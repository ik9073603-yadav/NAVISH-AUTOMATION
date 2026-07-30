import { prisma } from '../../lib/prisma';
import { encryptSecret, decryptSecret } from '../../lib/ai/encryption';
import { callAI, AiProviderName, DEFAULT_MODEL, ChatTurn } from '../../lib/ai/providers';
import { computeEmployeeMetrics } from '../analytics/analytics.service';
import { classifyOrdersSla } from '../fms/fms-analytics.service';
import { classifyLiquidVsDead } from '../inventory/inventory.service';

export type Role = 'OWNER' | 'MANAGER' | 'EMPLOYEE';

// ─────────────────────────── Config (per-user key) ───────────────────────────

export async function getConfigStatus(userId: string) {
  const config = await prisma.aiConfig.findUnique({ where: { userId } });
  if (!config) return { configured: false as const };
  return { configured: true as const, provider: config.provider, model: config.model };
}

export async function saveConfig(userId: string, orgId: string, provider: AiProviderName, apiKey: string, model?: string) {
  const encryptedApiKey = encryptSecret(apiKey);
  await prisma.aiConfig.upsert({
    where: { userId },
    create: { userId, orgId, provider, model: model || DEFAULT_MODEL[provider], encryptedApiKey },
    update: { provider, model: model || DEFAULT_MODEL[provider], encryptedApiKey },
  });
}

export async function deleteConfig(userId: string) {
  await prisma.aiConfig.deleteMany({ where: { userId } });
}

// Decrypted only in-process, for a single call — never returned to a client.
async function getDecryptedConfig(userId: string): Promise<{ provider: AiProviderName; model: string; apiKey: string } | null> {
  const config = await prisma.aiConfig.findUnique({ where: { userId } });
  if (!config) return null;
  return { provider: config.provider, model: config.model, apiKey: decryptSecret(config.encryptedApiKey) };
}

// ─────────────────────────── App knowledge (capability b) ───────────────────────────

// Compact, static feature/how-to reference — kept in the system prompt on
// every call so the assistant can answer "how do I..." questions without a
// retrieval step. Condensed from DOCUMENTATION.md §5.
export const APP_KNOWLEDGE = `
Navish is an operations-automation app for small businesses. Key features and how to use them:
- Tasks: Owner/Manager assigns a task (title, assignee, due date, priority) from the Tasks tab or the "Assign task" button. Overdue tasks are automatically chased (reminders) and escalate to the assignee's manager after repeated chases. Employees mark their own tasks "Done" or "Stuck" (with a reason) from their Tasks tab.
- Checklists: recurring daily/weekly/monthly routines. Owner/Manager creates a rule (title, recurrence, time, assignee) in the Checklists tab; it auto-creates a task each time it's due and flows through the same chase/escalate system.
- Flows (FMS): a configurable multi-stage pipeline (e.g. Order Received -> Cutting -> QC -> Dispatch). Owner/Manager builds a Flow with ordered stages in the Flows tab, then starts an Order against it. Completing a stage's form fields advances the order to the next stage automatically.
- Inventory: SKUs with optional min/max stock thresholds. Recording a stock IN/OUT/ADJUST movement updates the running stock level; the system automatically notifies the owner when a SKU crosses its threshold.
- Analytics tab: five cards — Flow, Employee, Department, Task, Inventory analysis — each with a Today/Week/Month/Custom date filter and charts.
- Company Health Score: a 0-100 score on the Home screen combining on-time %, stuck load, checklist compliance, inventory health, and escalation rate, with a drill-down showing what's dragging it down.
- Cost of Delay: optional org-wide Rupees/hour rate or per-order value, used to price delayed orders in Rupees on the Flow analysis screen.
- Settings (Owner only): working hours/days, holidays, Cost-of-Delay rate. Profile (any user): name, photo, language, and the AI Assistant setup.
- Offline: task completion, stock movements, and stage completion work offline and sync automatically when back online.
`.trim();

// ─────────────────────────── Business overview (capability a) ───────────────────────────

const RECENT_DAYS = 30;

// Structured, bounded org snapshot for "how's my business doing?" — an
// employee only sees their own work; an owner/manager sees an org-wide
// rollup capped to the most active people/departments so the payload stays
// small regardless of company size.
export async function gatherOverviewData(orgId: string, userId: string, role: Role) {
  const to = new Date();
  const from = new Date(to.getTime() - RECENT_DAYS * 86_400_000);

  if (role === 'EMPLOYEE') {
    const [assigned, done, stuck, escalated] = await Promise.all([
      prisma.task.count({ where: { orgId, assigneeId: userId, createdAt: { gte: from, lte: to } } }),
      prisma.task.count({ where: { orgId, assigneeId: userId, status: 'DONE', completedAt: { gte: from, lte: to } } }),
      prisma.task.count({ where: { orgId, assigneeId: userId, status: 'STUCK' } }),
      prisma.task.count({ where: { orgId, assigneeId: userId, escalatedAt: { gte: from, lte: to } } }),
    ]);
    return { scope: 'own-work', period: { from, to }, myTasks: { assigned, done, stuck, escalated } };
  }

  const [employeeMetrics, orders, skus, checklistTasks] = await Promise.all([
    computeEmployeeMetrics(orgId, from, to),
    prisma.order.findMany({ where: { orgId }, select: { id: true, flowId: true, status: true } }),
    prisma.sku.findMany({ where: { orgId, active: true } }),
    prisma.task.findMany({
      where: { orgId, source: 'CHECKLIST', createdAt: { gte: from, lte: to } },
      select: { status: true },
    }),
  ]);

  const slaMap = await classifyOrdersSla(orgId, orders);
  let pending = 0, completed = 0, delayed = 0, onTime = 0;
  for (const o of orders) {
    if (o.status === 'ACTIVE') pending++;
    if (o.status === 'COMPLETED') completed++;
    const sla = slaMap.get(o.id);
    if (sla === 'DELAYED') delayed++;
    else if (sla === 'ON_TIME') onTime++;
  }

  let totalStockValue = 0, lowStockCount = 0, deadStockCount = 0, deadStockValue = 0;
  for (const s of skus) {
    const value = (s.unitCost ?? 0) * s.currentStock;
    totalStockValue += value;
    if (s.minStock != null && s.currentStock <= s.minStock) lowStockCount++;
    if (classifyLiquidVsDead(s) === 'DEAD') { deadStockCount++; deadStockValue += value; }
  }

  const checklistDone = checklistTasks.filter(t => t.status === 'DONE').length;

  const topEmployees = [...employeeMetrics]
    .sort((a, b) => (b.completed + b.escalated) - (a.completed + a.escalated))
    .slice(0, 12)
    .map(e => ({ name: e.name, completed: e.completed, onTimePct: e.onTimePct, escalated: e.escalated, currentLoad: e.currentLoad }));

  return {
    scope: 'org-wide',
    period: { from, to },
    tasks: {
      activeEmployees: employeeMetrics.length,
      totalCompleted: employeeMetrics.reduce((a, e) => a + e.completed, 0),
      totalEscalated: employeeMetrics.reduce((a, e) => a + e.escalated, 0),
      currentLoad: employeeMetrics.reduce((a, e) => a + e.currentLoad, 0),
    },
    topEmployees,
    fms: { totalOrders: orders.length, pending, completed, delayed, onTime },
    inventory: { totalStockValue, lowStockCount, deadStockCount, deadStockValue },
    checklist: { total: checklistTasks.length, done: checklistDone },
  };
}

// ─────────────────────────── Orchestration ───────────────────────────

function buildChatSystemPrompt(overview: unknown): string {
  return [
    'You are Navish\'s in-app AI assistant: a sharp, concise operations analyst and product guide for a small business.',
    'Answer in the same language the user writes in (English or Hindi).',
    'Keep answers short and concrete — prefer specific numbers and names over generalities.',
    '',
    'App feature/how-to knowledge:',
    APP_KNOWLEDGE,
    '',
    'The current user\'s org data snapshot (use this for business questions; ignore it for pure how-to questions):',
    JSON.stringify(overview),
  ].join('\n');
}

function buildInsightsSystemPrompt(screen: string): string {
  return [
    `You are a sharp operations analyst reviewing the "${screen}" analytics screen of a small business ops app.`,
    'Given the structured data below, write ONE short paragraph (2-4 sentences) of plain-language insight:',
    'what stands out, what is likely causing it, and (if relevant) who/what is most responsible.',
    'Be specific — cite real numbers and names from the data. No preamble, no headings, just the insight.',
  ].join('\n');
}

export interface AiCallOutcome {
  text: string;
  usage: { inputTokens: number; outputTokens: number };
  provider: AiProviderName;
  model: string;
}

export async function runChat(
  userId: string, orgId: string, role: Role, message: string, history: ChatTurn[] | undefined,
): Promise<AiCallOutcome> {
  const config = await getDecryptedConfig(userId);
  if (!config) throw Object.assign(new Error('Connect an AI provider in your profile first'), { status: 400 });

  const overview = await gatherOverviewData(orgId, userId, role);
  const systemPrompt = buildChatSystemPrompt(overview);
  const result = await callAI({
    provider: config.provider, apiKey: config.apiKey, model: config.model,
    systemPrompt, userPrompt: message, history,
  });
  return { ...result, provider: config.provider, model: config.model };
}

export async function runInsights(
  userId: string, screen: string, data: unknown,
): Promise<AiCallOutcome> {
  const config = await getDecryptedConfig(userId);
  if (!config) throw Object.assign(new Error('Connect an AI provider in your profile first'), { status: 400 });

  // Bounded — a screen's already-fetched analytics payload is small by
  // construction (capped list lengths), but guard against pathological input.
  const json = JSON.stringify(data).slice(0, 20_000);
  const result = await callAI({
    provider: config.provider, apiKey: config.apiKey, model: config.model,
    systemPrompt: buildInsightsSystemPrompt(screen), userPrompt: json,
  });
  return { ...result, provider: config.provider, model: config.model };
}

export async function testConnection(provider: AiProviderName, apiKey: string, model: string): Promise<void> {
  await callAI({
    provider, apiKey, model: model || DEFAULT_MODEL[provider],
    systemPrompt: 'Reply with only the single word: OK',
    userPrompt: 'OK?',
  });
}

// ─────────────────────────── Usage ───────────────────────────

export async function logUsage(
  userId: string, orgId: string, provider: AiProviderName, model: string,
  feature: 'OVERVIEW' | 'ASSIST' | 'INSIGHTS', usage: { inputTokens: number; outputTokens: number },
) {
  await prisma.aiUsage.create({
    data: { userId, orgId, provider, model, feature, inputTokens: usage.inputTokens, outputTokens: usage.outputTokens },
  });
}

export async function getUsageSummary(userId: string) {
  const since = new Date(Date.now() - 90 * 86_400_000);
  const rows = await prisma.aiUsage.findMany({
    where: { userId, createdAt: { gte: since } },
    select: { feature: true, inputTokens: true, outputTokens: true, createdAt: true },
    orderBy: { createdAt: 'asc' },
  });

  const byFeature: Record<string, { calls: number; inputTokens: number; outputTokens: number }> = {};
  const byDay: Record<string, { calls: number; inputTokens: number; outputTokens: number }> = {};
  let totalCalls = 0, totalInput = 0, totalOutput = 0;

  for (const r of rows) {
    totalCalls++; totalInput += r.inputTokens; totalOutput += r.outputTokens;
    byFeature[r.feature] ??= { calls: 0, inputTokens: 0, outputTokens: 0 };
    byFeature[r.feature].calls++;
    byFeature[r.feature].inputTokens += r.inputTokens;
    byFeature[r.feature].outputTokens += r.outputTokens;

    const dayKey = r.createdAt.toISOString().slice(0, 10);
    byDay[dayKey] ??= { calls: 0, inputTokens: 0, outputTokens: 0 };
    byDay[dayKey].calls++;
    byDay[dayKey].inputTokens += r.inputTokens;
    byDay[dayKey].outputTokens += r.outputTokens;
  }

  return {
    totals: { calls: totalCalls, inputTokens: totalInput, outputTokens: totalOutput },
    byFeature,
    trend: Object.entries(byDay).sort(([a], [b]) => a.localeCompare(b)).map(([date, v]) => ({ date, ...v })),
  };
}
