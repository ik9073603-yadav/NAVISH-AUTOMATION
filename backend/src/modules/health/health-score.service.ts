import { prisma } from '../../lib/prisma';
import { classifyLiquidVsDead } from '../inventory/inventory.service';
import { getStuckItems } from '../stuck/stuck.service';

export type Band = 'HEALTHY' | 'NEEDS_ATTENTION' | 'AT_RISK';

// Structured numbers behind each component's one-liner — the client builds
// its own (bilingual) sentence from these rather than parsing `reason`,
// which is kept only as an English fallback/debug string.
export interface HealthMetrics {
  [k: string]: number;
}

export interface HealthComponent {
  key: 'ON_TIME' | 'STUCK_LOAD' | 'CHECKLIST' | 'INVENTORY' | 'ESCALATIONS';
  label: string;
  score: number | null;   // 0-100, null when excluded (no data)
  weight: number;         // nominal documented weight (out of 100)
  effectiveWeight: number; // re-normalised weight actually used in the sum (0 if excluded)
  included: boolean;
  reason: string;
  metrics: HealthMetrics;
  module: 'TASKS' | 'FMS' | 'CHECKLISTS' | 'INVENTORY' | 'STUCK' | null;
}

export interface HealthDrag {
  key: string;
  reason: string;
  module: HealthComponent['module'];
  pointsLost: number;
}

export interface HealthScoreResult {
  overall: number | null;
  band: Band | null;
  windowFrom: string;
  windowTo: string;
  components: HealthComponent[];
  drags: HealthDrag[];
}

// ═══════════════════════════════════════════════════════════════════════
// Nominal weights (sum to 100). When a component has no data in the window
// it is EXCLUDED, not scored 0 — its weight is redistributed proportionally
// across the remaining included components so the score never gets
// unfairly tanked by "we just haven't used that module yet".
// ═══════════════════════════════════════════════════════════════════════
const WEIGHTS = {
  ON_TIME: 30,
  STUCK_LOAD: 25,
  CHECKLIST: 15,
  INVENTORY: 15,
  ESCALATIONS: 15,
} as const;

function round(n: number): number {
  return Math.round(n * 100) / 100;
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, n));
}

// ---- Component 1: On-time performance (tasks + PLANNED FMS stages) ----
// Late task = completed but was escalated at some point (same "late" rule
// analytics/employees already uses). Late FMS stage = completed after its
// plannedDeadline. UNPLANNED stages (plannedDeadline == null) never count.
async function computeOnTime(orgId: string, from: Date, to: Date): Promise<HealthComponent> {
  const [taskTotal, taskLate, stages] = await Promise.all([
    prisma.task.count({
      where: { orgId, source: { in: ['DELEGATION', 'CHECKLIST'] }, status: 'DONE', completedAt: { gte: from, lte: to } },
    }),
    prisma.task.count({
      where: {
        orgId, source: { in: ['DELEGATION', 'CHECKLIST'] }, status: 'DONE',
        completedAt: { gte: from, lte: to }, escalatedAt: { not: null },
      },
    }),
    prisma.orderStage.findMany({
      where: { orgId, plannedDeadline: { not: null }, completedAt: { gte: from, lte: to } },
      select: { completedAt: true, plannedDeadline: true },
    }),
  ]);

  const fmsTotal = stages.length;
  const fmsLate = stages.filter(s => s.completedAt!.getTime() > s.plannedDeadline!.getTime()).length;

  const total = taskTotal + fmsTotal;
  const late = taskLate + fmsLate;

  if (total === 0) {
    return {
      key: 'ON_TIME', label: 'On-time performance', score: null, weight: WEIGHTS.ON_TIME,
      effectiveWeight: 0, included: false, reason: 'No tasks or planned stages completed in this window',
      metrics: { total: 0, late: 0 },
      module: fmsLate >= taskLate ? 'FMS' : 'TASKS',
    };
  }

  const pct = round(((total - late) / total) * 100);
  return {
    key: 'ON_TIME',
    label: 'On-time performance',
    score: pct,
    weight: WEIGHTS.ON_TIME,
    effectiveWeight: 0,
    included: true,
    reason: `${pct}% on-time (${late} of ${total} finished late)`,
    metrics: { total, late, pct },
    module: fmsLate >= taskLate ? 'FMS' : 'TASKS',
  };
}

// ---- Component 2: Currently stuck/overdue load (point-in-time, not windowed) ----
// Flat penalty per item, weighted double for HIGH severity (escalated/flagged
// STUCK) since those are the ones actively hurting the business right now.
// 8 points per weighted unit, floored at 0 — i.e. ~13 weighted stuck items
// is already "as unhealthy as this component can get".
async function computeStuckLoad(orgId: string): Promise<HealthComponent> {
  const items = await getStuckItems(orgId);
  const weighted = items.reduce((sum, i) => sum + (i.severity === 'HIGH' ? 2 : 1), 0);
  const score = round(clamp(100 - weighted * 8, 0, 100));

  return {
    key: 'STUCK_LOAD',
    label: 'Stuck / overdue load',
    score,
    weight: WEIGHTS.STUCK_LOAD,
    effectiveWeight: 0,
    included: true, // absence of stuck items IS meaningful data (a perfect 100)
    reason: items.length === 0 ? 'Nothing stuck or overdue right now' : `${items.length} item(s) stuck or overdue right now`,
    metrics: { itemCount: items.length, highCount: items.filter(i => i.severity === 'HIGH').length },
    module: 'STUCK',
  };
}

// ---- Component 3: Checklist compliance % ----
async function computeChecklist(orgId: string, from: Date, to: Date): Promise<HealthComponent> {
  const [total, done] = await Promise.all([
    prisma.task.count({ where: { orgId, source: 'CHECKLIST', createdAt: { gte: from, lte: to } } }),
    prisma.task.count({ where: { orgId, source: 'CHECKLIST', createdAt: { gte: from, lte: to }, status: 'DONE' } }),
  ]);

  if (total === 0) {
    return {
      key: 'CHECKLIST', label: 'Checklist compliance', score: null, weight: WEIGHTS.CHECKLIST,
      effectiveWeight: 0, included: false, reason: 'No checklist items due in this window',
      metrics: { total: 0, done: 0 }, module: 'CHECKLISTS',
    };
  }

  const pct = round((done / total) * 100);
  return {
    key: 'CHECKLIST', label: 'Checklist compliance', score: pct, weight: WEIGHTS.CHECKLIST,
    effectiveWeight: 0, included: true, reason: `Checklist compliance ${pct}% (${done} of ${total})`,
    metrics: { total, done, pct }, module: 'CHECKLISTS',
  };
}

// ---- Component 4: Inventory health (current state, not windowed) ----
// Half the penalty budget goes to how many active SKUs are low/over stock,
// half to how much of total stock value is sitting DEAD (90+ days unmoved).
async function computeInventory(orgId: string): Promise<HealthComponent> {
  const skus = await prisma.sku.findMany({ where: { orgId, active: true } });

  if (skus.length === 0) {
    return {
      key: 'INVENTORY', label: 'Inventory health', score: null, weight: WEIGHTS.INVENTORY,
      effectiveWeight: 0, included: false, reason: 'No inventory configured',
      metrics: { skuCount: 0, alertCount: 0 }, module: 'INVENTORY',
    };
  }

  let totalValue = 0;
  let deadValue = 0;
  let alertCount = 0;
  for (const s of skus) {
    const value = (s.unitCost ?? 0) * s.currentStock;
    totalValue += value;
    if (classifyLiquidVsDead(s) === 'DEAD') deadValue += value;
    const isLow = s.minStock != null && s.currentStock <= s.minStock;
    const isOver = s.maxStock != null && s.currentStock >= s.maxStock;
    if (isLow || isOver) alertCount++;
  }

  const alertRatio = alertCount / skus.length;
  const deadRatio = totalValue > 0 ? deadValue / totalValue : 0;
  const score = round(clamp(100 - (alertRatio * 50 + deadRatio * 50), 0, 100));

  return {
    key: 'INVENTORY',
    label: 'Inventory health',
    score,
    weight: WEIGHTS.INVENTORY,
    effectiveWeight: 0,
    included: true,
    reason: `${alertCount} low/over-stock SKU(s), ${round(deadRatio * 100)}% of stock value is dead`,
    metrics: { skuCount: skus.length, alertCount, deadPct: round(deadRatio * 100) },
    module: 'INVENTORY',
  };
}

// ---- Component 5: Escalations (rate within the window) ----
// Each 1% of the org's in-window tasks that escalated costs 2 health
// points, floored at 0 (so a 50%+ escalation rate is already the floor).
async function computeEscalations(orgId: string, from: Date, to: Date): Promise<HealthComponent> {
  const [total, escalated] = await Promise.all([
    prisma.task.count({ where: { orgId, createdAt: { gte: from, lte: to } } }),
    prisma.task.count({ where: { orgId, escalatedAt: { gte: from, lte: to } } }),
  ]);

  if (total === 0) {
    return {
      key: 'ESCALATIONS', label: 'Escalations', score: null, weight: WEIGHTS.ESCALATIONS,
      effectiveWeight: 0, included: false, reason: 'No task activity in this window',
      metrics: { total: 0, escalated: 0 }, module: 'STUCK',
    };
  }

  const rate = escalated / total;
  const score = round(clamp(100 - rate * 100 * 2, 0, 100));
  return {
    key: 'ESCALATIONS',
    label: 'Escalations',
    score,
    weight: WEIGHTS.ESCALATIONS,
    effectiveWeight: 0,
    included: true,
    reason: `${escalated} escalation(s) out of ${total} task(s) this window`,
    metrics: { total, escalated },
    module: 'STUCK',
  };
}

function bandFor(score: number): Band {
  if (score >= 85) return 'HEALTHY';
  if (score >= 60) return 'NEEDS_ATTENTION';
  return 'AT_RISK';
}

export async function computeHealthScore(orgId: string, from: Date, to: Date): Promise<HealthScoreResult> {
  const components = await Promise.all([
    computeOnTime(orgId, from, to),
    computeStuckLoad(orgId),
    computeChecklist(orgId, from, to),
    computeInventory(orgId),
    computeEscalations(orgId, from, to),
  ]);

  const includedWeightSum = components.filter(c => c.included).reduce((s, c) => s + c.weight, 0);

  let overall: number | null = null;
  if (includedWeightSum > 0) {
    let weightedSum = 0;
    for (const c of components) {
      if (!c.included || c.score == null) continue;
      c.effectiveWeight = round((c.weight / includedWeightSum) * 100);
      weightedSum += (c.effectiveWeight / 100) * c.score;
    }
    overall = Math.round(clamp(weightedSum, 0, 100));
  }

  const drags: HealthDrag[] = components
    .filter(c => c.included && c.score != null && c.score < 100)
    .map(c => ({
      key: c.key,
      reason: c.reason,
      module: c.module,
      pointsLost: round((c.effectiveWeight / 100) * (100 - (c.score as number))),
    }))
    .sort((a, b) => b.pointsLost - a.pointsLost)
    .slice(0, 3);

  return {
    overall,
    band: overall == null ? null : bandFor(overall),
    windowFrom: from.toISOString(),
    windowTo: to.toISOString(),
    components,
    drags,
  };
}

// Called once a day per org by the scheduler (see engine.worker.ts). Writes
// a HealthSnapshot for "today" (UTC calendar date) if one doesn't already
// exist — self-healing across restarts/missed ticks, race-safe via the
// unique(orgId, date) constraint.
export async function writeDailyHealthSnapshots(): Promise<void> {
  const today = new Date().toISOString().slice(0, 10);
  const orgs = await prisma.organization.findMany({ where: { enabled: true }, select: { id: true } });

  for (const org of orgs) {
    const exists = await prisma.healthSnapshot.findUnique({
      where: { orgId_date: { orgId: org.id, date: today } },
    });
    if (exists) continue;

    const to = new Date();
    const from = new Date(to.getTime() - 7 * 86_400_000);
    const result = await computeHealthScore(org.id, from, to);
    if (result.overall == null) continue; // not enough data anywhere yet — nothing meaningful to snapshot

    await prisma.healthSnapshot
      .create({ data: { orgId: org.id, date: today, score: result.overall } })
      .catch(() => {}); // benign race against another tick/instance — unique constraint wins
  }
}
