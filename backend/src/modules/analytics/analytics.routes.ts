import { Router, Request, Response, NextFunction } from 'express';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { cached } from '../../lib/cache';
import { classifyLiquidVsDead } from '../inventory/inventory.service';
import { computeEmployeeMetrics } from './analytics.service';

export const analyticsRouter = Router();
analyticsRouter.use(requireAuth, requireRole('OWNER', 'MANAGER'));

// Short enough that a user who just completed something won't see stale
// numbers for long, long enough to absorb repeated tab-switches/reopens.
const CACHE_TTL_MS = 60_000;

function parseRange(req: Request): { from: Date; to: Date } {
  const now = new Date();
  const from = req.query.from ? new Date(req.query.from as string) : new Date(now.getTime() - 30 * 86_400_000);
  const to = req.query.to ? new Date(req.query.to as string) : now;
  return { from, to };
}

function dayKey(d: Date): string {
  return d.toISOString().slice(0, 10);
}

// Employee performance: on-time %, completed, late, escalated, current
// load, checklist compliance, avg completion time. One shared helper
// (analytics.service.ts) so this and /departments below can never drift.
analyticsRouter.get('/employees', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { orgId } = req.user!;
    const { from, to } = parseRange(req);
    const key = `analytics:employees:${orgId}:${dayKey(from)}:${dayKey(to)}`;
    const data = await cached(key, CACHE_TTL_MS, () => computeEmployeeMetrics(orgId, from, to));
    res.json(data);
  } catch (err) { next(err); }
});

// Department roll-up of the same per-employee metrics. Users with no
// departmentId are grouped under a single "Unassigned" bucket rather than
// being dropped. Departments with zero active employees still appear
// (all-zero row) instead of vanishing silently.
analyticsRouter.get('/departments', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { orgId } = req.user!;
    const { from, to } = parseRange(req);
    const key = `analytics:departments:${orgId}:${dayKey(from)}:${dayKey(to)}`;

    const data = await cached(key, CACHE_TTL_MS, async () => {
      const [departments, metrics] = await Promise.all([
        prisma.department.findMany({ where: { orgId }, select: { id: true, name: true } }),
        computeEmployeeMetrics(orgId, from, to),
      ]);
      const nameById = new Map(departments.map(d => [d.id, d.name]));

      type Bucket = {
        departmentId: string | null;
        name: string;
        employeeCount: number;
        completed: number;
        late: number;
        escalated: number;
        currentLoad: number;
        checklistTotal: number;
        checklistDone: number;
      };
      const buckets = new Map<string, Bucket>();

      for (const m of metrics) {
        const bucketKey = m.departmentId ?? 'UNASSIGNED';
        const name = m.departmentId ? (nameById.get(m.departmentId) ?? 'Unknown') : 'Unassigned';
        const bucket = buckets.get(bucketKey) ?? {
          departmentId: m.departmentId, name, employeeCount: 0,
          completed: 0, late: 0, escalated: 0, currentLoad: 0, checklistTotal: 0, checklistDone: 0,
        };
        bucket.employeeCount++;
        bucket.completed += m.completed;
        bucket.late += m.late;
        bucket.escalated += m.escalated;
        bucket.currentLoad += m.currentLoad;
        bucket.checklistTotal += m.checklistTotal;
        bucket.checklistDone += m.checklistDone;
        buckets.set(bucketKey, bucket);
      }

      // A department with no active members yet still shows up (all zeros)
      // instead of being invisible.
      for (const d of departments) {
        if (!buckets.has(d.id)) {
          buckets.set(d.id, {
            departmentId: d.id, name: d.name, employeeCount: 0,
            completed: 0, late: 0, escalated: 0, currentLoad: 0, checklistTotal: 0, checklistDone: 0,
          });
        }
      }

      return [...buckets.values()]
        .map(b => ({
          ...b,
          onTimePct: b.completed > 0 ? Math.round(((b.completed - b.late) / b.completed) * 100) : 0,
          checklistCompliancePct: b.checklistTotal > 0 ? Math.round((b.checklistDone / b.checklistTotal) * 100) : 0,
        }))
        .sort((a, b) => b.employeeCount - a.employeeCount);
    });

    res.json(data);
  } catch (err) { next(err); }
});

// Delegation: totals, daily trend, and a by-person breakdown — all derived
// from a single findMany + JS reduce (one round trip, not a per-day or
// per-person loop).
analyticsRouter.get('/delegation', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { orgId } = req.user!;
    const { from, to } = parseRange(req);
    const key = `analytics:delegation:${orgId}:${dayKey(from)}:${dayKey(to)}`;

    const data = await cached(key, CACHE_TTL_MS, async () => {
      const [tasks, users] = await Promise.all([
        prisma.task.findMany({
          where: { orgId, source: 'DELEGATION', createdAt: { gte: from, lte: to } },
          select: { assigneeId: true, createdAt: true, completedAt: true, status: true, escalatedAt: true },
        }),
        prisma.user.findMany({ where: { orgId }, select: { id: true, name: true } }),
      ]);
      const nameById = new Map(users.map(u => [u.id, u.name]));

      const byDay: Record<string, { created: number; completed: number; stuck: number; escalated: number }> = {};
      const byPerson = new Map<string, {
        userId: string; name: string; created: number; completed: number; stuck: number; escalated: number;
        durationSum: number; durationCount: number;
      }>();

      let totalCreated = 0, totalCompleted = 0, totalStuck = 0, totalEscalated = 0;
      let durationSum = 0, durationCount = 0;

      for (const t of tasks) {
        const dayK = dayKey(t.createdAt);
        byDay[dayK] ??= { created: 0, completed: 0, stuck: 0, escalated: 0 };
        byDay[dayK].created++;
        totalCreated++;

        const person = byPerson.get(t.assigneeId) ?? {
          userId: t.assigneeId, name: nameById.get(t.assigneeId) ?? 'Unknown',
          created: 0, completed: 0, stuck: 0, escalated: 0, durationSum: 0, durationCount: 0,
        };
        person.created++;

        if (t.status === 'DONE') {
          byDay[dayK].completed++;
          totalCompleted++;
          person.completed++;
          if (t.completedAt) {
            const mins = (t.completedAt.getTime() - t.createdAt.getTime()) / 60_000;
            durationSum += mins; durationCount++;
            person.durationSum += mins; person.durationCount++;
          }
        }
        if (t.status === 'STUCK') {
          byDay[dayK].stuck++;
          totalStuck++;
          person.stuck++;
        }
        if (t.escalatedAt) {
          byDay[dayK].escalated++;
          totalEscalated++;
          person.escalated++;
        }

        byPerson.set(t.assigneeId, person);
      }

      const trend = Object.entries(byDay)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([date, v]) => ({
          date, ...v,
          completionPct: v.created > 0 ? Math.round((v.completed / v.created) * 100) : 0,
        }));

      const byPersonArr = [...byPerson.values()]
        .map(p => ({
          userId: p.userId, name: p.name, created: p.created, completed: p.completed,
          stuck: p.stuck, escalated: p.escalated,
          completionPct: p.created > 0 ? Math.round((p.completed / p.created) * 100) : 0,
          avgCompletionMins: p.durationCount > 0 ? Math.round(p.durationSum / p.durationCount) : 0,
        }))
        .sort((a, b) => b.created - a.created);

      return {
        totals: {
          created: totalCreated, completed: totalCompleted, stuck: totalStuck, escalated: totalEscalated,
          completionPct: totalCreated > 0 ? Math.round((totalCompleted / totalCreated) * 100) : 0,
          avgCompletionMins: durationCount > 0 ? Math.round(durationSum / durationCount) : 0,
        },
        trend,
        byPerson: byPersonArr,
      };
    });

    res.json(data);
  } catch (err) { next(err); }
});

// Checklist compliance: per-rule totals, org-wide totals, and a compliance-
// over-time trend. Single findMany + JS reduce, no per-rule/per-day loop.
analyticsRouter.get('/checklists', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { orgId } = req.user!;
    const { from, to } = parseRange(req);
    const key = `analytics:checklists:${orgId}:${dayKey(from)}:${dayKey(to)}`;

    const data = await cached(key, CACHE_TTL_MS, async () => {
      const [rules, tasks] = await Promise.all([
        prisma.checklistRule.findMany({ where: { orgId }, select: { id: true, title: true } }),
        prisma.task.findMany({
          where: { orgId, source: 'CHECKLIST', createdAt: { gte: from, lte: to } },
          select: { ruleId: true, createdAt: true, status: true },
        }),
      ]);

      const byRule = new Map<string, { total: number; done: number }>();
      const byDay: Record<string, { total: number; done: number }> = {};

      for (const t of tasks) {
        if (t.ruleId) {
          const r = byRule.get(t.ruleId) ?? { total: 0, done: 0 };
          r.total++;
          if (t.status === 'DONE') r.done++;
          byRule.set(t.ruleId, r);
        }
        const dayK = dayKey(t.createdAt);
        byDay[dayK] ??= { total: 0, done: 0 };
        byDay[dayK].total++;
        if (t.status === 'DONE') byDay[dayK].done++;
      }

      const perRule = rules
        .map(r => {
          const agg = byRule.get(r.id) ?? { total: 0, done: 0 };
          return {
            ruleId: r.id, title: r.title, total: agg.total, done: agg.done,
            missed: agg.total - agg.done,
            compliancePct: agg.total > 0 ? Math.round((agg.done / agg.total) * 100) : 0,
          };
        })
        .filter(r => r.total > 0)
        .sort((a, b) => a.compliancePct - b.compliancePct);

      const trend = Object.entries(byDay)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([date, v]) => ({
          date, total: v.total, done: v.done, missed: v.total - v.done,
          compliancePct: v.total > 0 ? Math.round((v.done / v.total) * 100) : 0,
        }));

      const totalAll = perRule.reduce((a, r) => a + r.total, 0);
      const doneAll = perRule.reduce((a, r) => a + r.done, 0);

      return {
        totals: {
          total: totalAll, done: doneAll, missed: totalAll - doneAll,
          compliancePct: totalAll > 0 ? Math.round((doneAll / totalAll) * 100) : 0,
        },
        perRule,
        trend,
      };
    });

    res.json(data);
  } catch (err) { next(err); }
});

// FMS: avg time per stage, throughput, current stuck count per stage, and
// a funnel of how many orders reached each stage position in range. Two
// findMany calls (stage defs, completed-in-range order stages) reduced in
// JS, plus two grouped aggregates — no per-stage loop (the previous version
// ran a query pair per stage; fixed here).
analyticsRouter.get('/fms', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { orgId } = req.user!;
    const { from, to } = parseRange(req);
    const key = `analytics:fms:${orgId}:${dayKey(from)}:${dayKey(to)}`;

    const data = await cached(key, CACHE_TTL_MS, async () => {
      const stages = await prisma.stageDef.findMany({
        where: { orgId },
        select: { id: true, name: true, sequence: true, plannedMins: true, flow: { select: { name: true } } },
      });

      const completedStages = await prisma.orderStage.findMany({
        where: { orgId, completedAt: { gte: from, lte: to } },
        select: { stageId: true, enteredAt: true, completedAt: true, delayMins: true },
      });

      const stuckNowRows = await prisma.orderStage.groupBy({
        by: ['stageId'], where: { orgId, completedAt: null }, _count: { _all: true },
      });
      const stuckByStage = new Map(stuckNowRows.map(r => [r.stageId, r._count._all]));

      const acc = new Map<string, { durationSum: number; durationCount: number; delaySum: number; delayCount: number; completedInRange: number }>();
      for (const s of completedStages) {
        const bucket = acc.get(s.stageId) ?? { durationSum: 0, durationCount: 0, delaySum: 0, delayCount: 0, completedInRange: 0 };
        bucket.completedInRange++;
        if (s.enteredAt && s.completedAt) {
          bucket.durationSum += (s.completedAt.getTime() - s.enteredAt.getTime()) / 60_000;
          bucket.durationCount++;
        }
        if (s.delayMins != null) {
          bucket.delaySum += s.delayMins;
          bucket.delayCount++;
        }
        acc.set(s.stageId, bucket);
      }

      const stageMetrics = stages.map(s => {
        const bucket = acc.get(s.id);
        return {
          stageId: s.id,
          stageName: s.name,
          flowName: s.flow.name,
          plannedMins: s.plannedMins,
          avgMins: bucket && bucket.durationCount > 0 ? Math.round(bucket.durationSum / bucket.durationCount) : 0,
          avgDelayMins: bucket && bucket.delayCount > 0 ? Math.round(bucket.delaySum / bucket.delayCount) : 0,
          ordersStuckNow: stuckByStage.get(s.id) ?? 0,
          completedInRange: bucket?.completedInRange ?? 0,
        };
      });

      // Funnel: how many orders reached each stage-sequence position within
      // the range (i.e. entered that position) — naturally non-increasing
      // as position increases, one grouped query across every flow.
      const reachedRows = await prisma.orderStage.groupBy({
        by: ['sequence'],
        where: { orgId, enteredAt: { gte: from, lte: to } },
        _count: { _all: true },
      });
      const funnel = reachedRows
        .map(r => ({ sequence: r.sequence, count: r._count._all }))
        .sort((a, b) => a.sequence - b.sequence);

      const [completedOrders, allCompleted] = await Promise.all([
        prisma.order.count({ where: { orgId, status: 'COMPLETED', completedAt: { gte: from, lte: to } } }),
        prisma.order.findMany({
          where: { orgId, status: 'COMPLETED', completedAt: { gte: from, lte: to } },
          select: { startedAt: true, completedAt: true },
        }),
      ]);
      const avgCycleTimeMins = allCompleted.length > 0
        ? Math.round(allCompleted.reduce((a, o) => a + (o.completedAt!.getTime() - o.startedAt.getTime()) / 60_000, 0) / allCompleted.length)
        : 0;

      return {
        throughput: { completedOrders, avgCycleTimeMins },
        stages: stageMetrics.sort((a, b) => b.ordersStuckNow - a.ordersStuckNow),
        funnel,
      };
    });

    res.json(data);
  } catch (err) { next(err); }
});

// Inventory: dead-stock value, low-stock count, total stock value, movement trend.
analyticsRouter.get('/inventory', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { orgId } = req.user!;
    const { from, to } = parseRange(req);
    const key = `analytics:inventory:${orgId}:${dayKey(from)}:${dayKey(to)}`;

    const data = await cached(key, CACHE_TTL_MS, async () => {
      const skus = await prisma.sku.findMany({ where: { orgId, active: true } });

      let totalStockValue = 0;
      let lowStockCount = 0;
      let deadStockValue = 0;
      for (const s of skus) {
        const value = (s.unitCost ?? 0) * s.currentStock;
        totalStockValue += value;
        if (s.minStock != null && s.currentStock <= s.minStock) lowStockCount++;
        if (classifyLiquidVsDead(s) === 'DEAD') deadStockValue += value;
      }

      const movements = await prisma.stockMovement.findMany({
        where: { orgId, createdAt: { gte: from, lte: to } },
        select: { createdAt: true, type: true, quantity: true },
      });

      const byDay: Record<string, { inQty: number; outQty: number }> = {};
      for (const m of movements) {
        const k = dayKey(m.createdAt);
        byDay[k] ??= { inQty: 0, outQty: 0 };
        if (m.type === 'IN') byDay[k].inQty += m.quantity;
        else if (m.type === 'OUT') byDay[k].outQty += m.quantity;
      }
      const movementTrend = Object.entries(byDay)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([date, v]) => ({ date, ...v }));

      return { totalStockValue, lowStockCount, deadStockValue, movementTrend };
    });

    res.json(data);
  } catch (err) { next(err); }
});
