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

// ─────────────────────────── SKU custom-field suggestions ───────────────────────────
// AI-assisted setup for a company that doesn't know what SKU fields to
// define (see inventory's SkuFieldDef) — describe the business in plain
// language, get back suggestions in the exact shape the field-def CRUD
// already accepts. Never applied automatically; the caller always shows
// these as an editable preview first.

const SKU_FIELD_TYPES = ['TEXT', 'NUMBER', 'DATE', 'DROPDOWN', 'YESNO'] as const;
type SkuFieldTypeSuggestion = typeof SKU_FIELD_TYPES[number];

export interface SuggestedSkuField {
  label: string;
  type: SkuFieldTypeSuggestion;
  options?: string;
  required: boolean;
}

function buildSkuFieldsSystemPrompt(): string {
  return [
    'You set up custom inventory (SKU) fields for a small-business operations app.',
    'Given a short description of the business, suggest the SKU attributes it should track beyond the fixed core fields (name, code, quantity, min/max stock).',
    'Reply with ONLY a JSON array — no prose, no markdown code fences — of 3 to 7 items, each shaped exactly as:',
    '{"label": string, "type": "TEXT" | "NUMBER" | "DATE" | "DROPDOWN" | "YESNO", "options": string, "required": boolean}',
    '"options" is a comma-separated list of choices and must be present ONLY when type is "DROPDOWN"; omit it otherwise.',
    'Use only those five exact type values — nothing else. Keep labels short and practical (e.g. "Color", "Size", "Expiry Date", "Batch No").',
    'Labels may be in the same language as the business description (English or Hindi), but the JSON keys and type values must stay exactly as specified above.',
  ].join('\n');
}

// LLMs occasionally wrap JSON in prose or code fences despite instructions —
// pull out the first [...] block rather than trusting the whole reply to be
// bare JSON.
function extractJsonArray(text: string): unknown[] {
  const start = text.indexOf('[');
  const end = text.lastIndexOf(']');
  if (start === -1 || end === -1 || end < start) {
    throw Object.assign(new Error('AI response was not in the expected format — try rephrasing your description'), { status: 502 });
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text.slice(start, end + 1));
  } catch {
    throw Object.assign(new Error('AI response was not valid JSON — try rephrasing your description'), { status: 502 });
  }
  if (!Array.isArray(parsed)) {
    throw Object.assign(new Error('AI response was not in the expected format — try rephrasing your description'), { status: 502 });
  }
  return parsed;
}

const TYPE_ALIASES: Record<string, SkuFieldTypeSuggestion> = {
  TEXT: 'TEXT', STRING: 'TEXT',
  NUMBER: 'NUMBER', NUMERIC: 'NUMBER', INT: 'NUMBER', INTEGER: 'NUMBER', FLOAT: 'NUMBER', DECIMAL: 'NUMBER',
  DATE: 'DATE',
  DROPDOWN: 'DROPDOWN', SELECT: 'DROPDOWN', ENUM: 'DROPDOWN', CHOICE: 'DROPDOWN',
  YESNO: 'YESNO', YES_NO: 'YESNO', BOOLEAN: 'YESNO', BOOL: 'YESNO',
};

// Lenient by design — an LLM's minor deviations (a wrong key name, an
// unrecognized type) should drop that one suggestion, not fail the whole
// batch. The caller only errors out if nothing usable survives.
function normalizeSuggestions(raw: unknown[]): SuggestedSkuField[] {
  const out: SuggestedSkuField[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const obj = item as Record<string, unknown>;

    const label = typeof obj.label === 'string' ? obj.label.trim() : '';
    if (!label) continue;

    const typeKey = typeof obj.type === 'string' ? obj.type.trim().toUpperCase().replace(/[\s-]+/g, '_') : '';
    const type = TYPE_ALIASES[typeKey];
    if (!type) continue;

    let options: string | undefined;
    if (type === 'DROPDOWN') {
      if (Array.isArray(obj.options)) options = obj.options.map(String).join(',');
      else if (typeof obj.options === 'string') options = obj.options;
    }

    out.push({
      label: label.slice(0, 60),
      type,
      options: options?.slice(0, 300),
      required: obj.required === true,
    });
  }
  return out.slice(0, 10); // asked the model for 3-7; hard cap regardless of what comes back
}

export async function suggestSkuFields(
  userId: string, description: string,
): Promise<AiCallOutcome & { fields: SuggestedSkuField[] }> {
  const config = await getDecryptedConfig(userId);
  if (!config) throw Object.assign(new Error('Connect an AI provider in your profile first'), { status: 400 });

  // Token-bounded on purpose — only the description goes out, never any real
  // inventory/business data.
  const trimmedDescription = description.trim().slice(0, 500);
  const result = await callAI({
    provider: config.provider, apiKey: config.apiKey, model: config.model,
    systemPrompt: buildSkuFieldsSystemPrompt(), userPrompt: trimmedDescription,
  });

  const fields = normalizeSuggestions(extractJsonArray(result.text));
  if (fields.length === 0) {
    throw Object.assign(
      new Error('AI could not suggest fields for that description — try rephrasing, or add fields manually'),
      { status: 502 },
    );
  }

  return { ...result, provider: config.provider, model: config.model, fields };
}

// ─────────────────────────── Checklist recurrence suggestions ───────────────────────────
// AI-assisted setup for a company that doesn't know what recurring routines
// to set up (see checklist.routes.ts POST /) — describe the business in
// plain language, get back suggestions in the exact shape checklist create
// already accepts. Never applied automatically; the caller always shows
// these as an editable preview first.

const CHECKLIST_RECURRENCES = ['DAILY', 'WEEKLY', 'MONTHLY'] as const;
type ChecklistRecurrenceSuggestion = typeof CHECKLIST_RECURRENCES[number];

export interface SuggestedChecklistItem {
  title: string;
  recurrence: ChecklistRecurrenceSuggestion;
  weekdays?: number[];
  dayOfMonth?: number;
  timeOfDay: string;
}

function buildChecklistItemsSystemPrompt(): string {
  return [
    'You set up recurring checklist routines for a small-business operations app.',
    'Given a short description of the business/routine, suggest 3 to 8 recurring checklist items it should track.',
    'Reply with ONLY a JSON array — no prose, no markdown code fences — each item shaped exactly as:',
    '{"title": string, "recurrence": "DAILY" | "WEEKLY" | "MONTHLY", "weekdays": number[], "dayOfMonth": number, "timeOfDay": "HH:mm"}',
    '"weekdays" is a list of ISO weekdays (1=Monday ... 7=Sunday) and must be present ONLY when recurrence is "WEEKLY" (may hold several days, e.g. every weekday = [1,2,3,4,5]); omit it otherwise.',
    '"dayOfMonth" is 1-28 and must be present ONLY when recurrence is "MONTHLY"; omit it otherwise.',
    '"timeOfDay" is a 24-hour "HH:mm" local time picked sensibly for that task (e.g. an opening checklist early, a closing checklist late).',
    'Use only those exact recurrence values — nothing else.',
    'Titles may be in the same language as the description (English or Hindi), but the JSON keys and recurrence values must stay exactly as specified above.',
  ].join('\n');
}

const TIME_OF_DAY_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

// Lenient by design, same spirit as normalizeSuggestions for SKU fields — an
// LLM's minor deviations should drop that one suggestion, not fail the batch.
function normalizeChecklistSuggestions(raw: unknown[]): SuggestedChecklistItem[] {
  const out: SuggestedChecklistItem[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const obj = item as Record<string, unknown>;

    const title = typeof obj.title === 'string' ? obj.title.trim() : '';
    if (!title) continue;

    const recurrenceKey = typeof obj.recurrence === 'string' ? obj.recurrence.trim().toUpperCase() : '';
    if (!CHECKLIST_RECURRENCES.includes(recurrenceKey as ChecklistRecurrenceSuggestion)) continue;
    const recurrence = recurrenceKey as ChecklistRecurrenceSuggestion;

    const timeOfDay = typeof obj.timeOfDay === 'string' && TIME_OF_DAY_RE.test(obj.timeOfDay) ? obj.timeOfDay : '09:00';

    let weekdays: number[] | undefined;
    if (recurrence === 'WEEKLY' && Array.isArray(obj.weekdays)) {
      weekdays = obj.weekdays
        .map(Number)
        .filter(d => Number.isInteger(d) && d >= 1 && d <= 7);
      if (weekdays.length === 0) weekdays = [1];
    }

    let dayOfMonth: number | undefined;
    if (recurrence === 'MONTHLY') {
      const d = Number(obj.dayOfMonth);
      dayOfMonth = Number.isInteger(d) && d >= 1 && d <= 28 ? d : 1;
    }

    out.push({ title: title.slice(0, 100), recurrence, weekdays, dayOfMonth, timeOfDay });
  }
  return out.slice(0, 10); // asked the model for 3-8; hard cap regardless of what comes back
}

export async function suggestChecklistItems(
  userId: string, description: string,
): Promise<AiCallOutcome & { items: SuggestedChecklistItem[] }> {
  const config = await getDecryptedConfig(userId);
  if (!config) throw Object.assign(new Error('Connect an AI provider in your profile first'), { status: 400 });

  // Token-bounded on purpose — only the description goes out, never any real
  // company data.
  const trimmedDescription = description.trim().slice(0, 500);
  const result = await callAI({
    provider: config.provider, apiKey: config.apiKey, model: config.model,
    systemPrompt: buildChecklistItemsSystemPrompt(), userPrompt: trimmedDescription,
  });

  const items = normalizeChecklistSuggestions(extractJsonArray(result.text));
  if (items.length === 0) {
    throw Object.assign(
      new Error('AI could not suggest checklist items for that description — try rephrasing, or add them manually'),
      { status: 502 },
    );
  }

  return { ...result, provider: config.provider, model: config.model, items };
}

// ─────────────────────────── FMS flow-stage suggestions ───────────────────────────
// AI-assisted setup for a company that doesn't know how to break its process
// into stages (see fms.routes.ts POST /flows) — describe the process in
// plain language, get back suggestions in the exact shape flow create already
// accepts. Never applied automatically; the caller always shows these as an
// editable preview first.

const FLOW_FIELD_TYPES = ['TEXT', 'NUMBER', 'DROPDOWN', 'DATE', 'PHOTO', 'YESNO'] as const;
type FlowFieldTypeSuggestion = typeof FLOW_FIELD_TYPES[number];

export interface SuggestedFlowField {
  label: string;
  type: FlowFieldTypeSuggestion;
  options?: string;
  required: boolean;
}

export interface SuggestedFlowStage {
  name: string;
  plannedMins: number | null;
  fields: SuggestedFlowField[];
}

function buildFlowStagesSystemPrompt(): string {
  return [
    'You set up a multi-stage process flow (FMS) for a small-business operations app.',
    'Given a short description of a business process, suggest 2 to 8 stages it goes through, in order from start to finish.',
    'Reply with ONLY a JSON array — no prose, no markdown code fences — in stage order, each item shaped exactly as:',
    '{"name": string, "plannedMins": number | null, "fields": [{"label": string, "type": "TEXT" | "NUMBER" | "DROPDOWN" | "DATE" | "PHOTO" | "YESNO", "options": string, "required": boolean}]}',
    'CRITICAL RULE for "plannedMins": the FIRST stage in the array is the entry point — an item can enter it at any time, so it has no deadline and must be plannedMins: null. EVERY stage AFTER the first has its deadline computed from the previous stage\'s completion time, so it MUST have plannedMins set to a realistic positive integer number of minutes for that step.',
    '"fields" is optional per stage — 0 to 4 fields, only for data genuinely worth recording at that stage; omit it or use an empty array if none.',
    '"options" is a comma-separated list of choices and must be present ONLY when a field\'s type is "DROPDOWN"; omit it otherwise.',
    'Use only those exact type values. Stage/field names may be in the same language as the description (English or Hindi), but the JSON keys and type values must stay exactly as specified above.',
  ].join('\n');
}

const FLOW_FIELD_TYPE_ALIASES: Record<string, FlowFieldTypeSuggestion> = {
  TEXT: 'TEXT', STRING: 'TEXT',
  NUMBER: 'NUMBER', NUMERIC: 'NUMBER', INT: 'NUMBER', INTEGER: 'NUMBER', FLOAT: 'NUMBER', DECIMAL: 'NUMBER',
  DATE: 'DATE',
  DROPDOWN: 'DROPDOWN', SELECT: 'DROPDOWN', ENUM: 'DROPDOWN', CHOICE: 'DROPDOWN',
  YESNO: 'YESNO', YES_NO: 'YESNO', BOOLEAN: 'YESNO', BOOL: 'YESNO',
  PHOTO: 'PHOTO', IMAGE: 'PHOTO', PICTURE: 'PHOTO',
};

function normalizeFlowFields(raw: unknown): SuggestedFlowField[] {
  if (!Array.isArray(raw)) return [];
  const out: SuggestedFlowField[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const obj = item as Record<string, unknown>;

    const label = typeof obj.label === 'string' ? obj.label.trim() : '';
    if (!label) continue;

    const typeKey = typeof obj.type === 'string' ? obj.type.trim().toUpperCase().replace(/[\s-]+/g, '_') : '';
    const type = FLOW_FIELD_TYPE_ALIASES[typeKey];
    if (!type) continue;

    let options: string | undefined;
    if (type === 'DROPDOWN') {
      if (Array.isArray(obj.options)) options = obj.options.map(String).join(',');
      else if (typeof obj.options === 'string') options = obj.options;
    }

    out.push({
      label: label.slice(0, 60),
      type,
      options: options?.slice(0, 300),
      required: obj.required === true,
    });
  }
  return out.slice(0, 4); // asked the model for 0-4 per stage; hard cap regardless
}

// Lenient by design, same spirit as normalizeSuggestions for SKU fields — an
// LLM's minor deviations should drop that one suggestion, not fail the batch.
// The plannedMins rule, however, is enforced regardless of what the model
// returned (see comment at the bottom): the FMS deadline cascade depends on
// exactly this nullability shape.
export function normalizeFlowStageSuggestions(raw: unknown[]): SuggestedFlowStage[] {
  const out: SuggestedFlowStage[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const obj = item as Record<string, unknown>;

    const name = typeof obj.name === 'string' ? obj.name.trim() : '';
    if (!name) continue;

    const plannedMinsRaw = Number(obj.plannedMins);
    const plannedMins = Number.isFinite(plannedMinsRaw) && plannedMinsRaw > 0 ? Math.round(plannedMinsRaw) : null;

    out.push({ name: name.slice(0, 60), plannedMins, fields: normalizeFlowFields(obj.fields) });
  }
  const capped = out.slice(0, 10); // asked the model for 2-8; hard cap regardless of what comes back

  // The FMS rule (see StageDef.plannedMins / advanceOrder's working-time
  // cascade): the first stage is the unplanned entry point — no deadline, no
  // chasing, never stuck. Every later stage's deadline is computed from the
  // previous stage's actual completion time, so it needs a real duration —
  // a stray null there would silently disable chasing for that step.
  return capped.map((s, i) => (
    i === 0 ? { ...s, plannedMins: null } : { ...s, plannedMins: s.plannedMins ?? 60 }
  ));
}

export async function suggestFlowStages(
  userId: string, description: string,
): Promise<AiCallOutcome & { stages: SuggestedFlowStage[] }> {
  const config = await getDecryptedConfig(userId);
  if (!config) throw Object.assign(new Error('Connect an AI provider in your profile first'), { status: 400 });

  // Token-bounded on purpose — only the description goes out, never any real
  // company data.
  const trimmedDescription = description.trim().slice(0, 500);
  const result = await callAI({
    provider: config.provider, apiKey: config.apiKey, model: config.model,
    systemPrompt: buildFlowStagesSystemPrompt(), userPrompt: trimmedDescription,
  });

  const stages = normalizeFlowStageSuggestions(extractJsonArray(result.text));
  if (stages.length === 0) {
    throw Object.assign(
      new Error('AI could not suggest a flow for that description — try rephrasing, or build it manually'),
      { status: 502 },
    );
  }

  return { ...result, provider: config.provider, model: config.model, stages };
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
