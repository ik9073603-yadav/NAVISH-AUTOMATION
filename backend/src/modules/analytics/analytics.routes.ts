import { Router } from 'express';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { cached } from '../../lib/cache';
import { classifyLiquidVsDead } from '../inventory/inventory.service';

export const analyticsRouter = Router();
analyticsRouter.use(requireAuth, requireRole('OWNER', 'MANAGER'));

// Short enough that a user who just completed something won't see stale
// numbers for long, long enough to absorb repeated tab-switches/reopens.
const CACHE_TTL_MS = 60_000;

function parseRange(req: any): { from: Date; to: Date } {
  const now = new Date();
  const from = req.query.from ? new Date(req.query.from as string) : new Date(now.getTime() - 30 * 86_400_000);
  const to = req.query.to ? new Date(req.query.to as string) : now;
  return { from, to };
}

function dayKey(d: Date): string {
  return d.toISOString().slice(0, 10);
}

// Employee performance: on-time %, completed, late, escalated, current load.
analyticsRouter.get('/employees', async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const { from, to } = parseRange(req);
    const key = `analytics:employees:${orgId}:${dayKey(from)}:${dayKey(to)}`;

    const data = await cached(key, CACHE_TTL_MS, async () => {
      const users = await prisma.user.findMany({
        where: { orgId, status: 'ACTIVE' },
        select: { id: true, name: true },
      });

      const [completedInRange, escalatedInRange, currentLoad] = await Promise.all([
        prisma.task.groupBy({
          by: ['assigneeId'],
          where: { orgId, status: 'DONE', completedAt: { gte: from, lte: to } },
          _count: { _all: true },
        }),
        prisma.task.groupBy({
          by: ['assigneeId'],
          where: { orgId, escalatedAt: { gte: from, lte: to } },
          _count: { _all: true },
        }),
        prisma.task.groupBy({
          by: ['assigneeId'],
          where: { orgId, status: { in: ['PENDING', 'IN_PROGRESS', 'STUCK'] } },
          _count: { _all: true },
        }),
      ]);

      // "Late" among completed-in-range: escalated at some point before finishing.
      const lateInRange = await prisma.task.groupBy({
        by: ['assigneeId'],
        where: { orgId, status: 'DONE', completedAt: { gte: from, lte: to }, escalatedAt: { not: null } },
        _count: { _all: true },
      });

      const doneBy = Object.fromEntries(completedInRange.map(r => [r.assigneeId, r._count._all]));
      const escalatedBy = Object.fromEntries(escalatedInRange.map(r => [r.assigneeId, r._count._all]));
      const lateBy = Object.fromEntries(lateInRange.map(r => [r.assigneeId, r._count._all]));
      const loadBy = Object.fromEntries(currentLoad.map(r => [r.assigneeId, r._count._all]));

      return users.map(u => {
        const completed = doneBy[u.id] ?? 0;
        const late = lateBy[u.id] ?? 0;
        return {
          userId: u.id,
          name: u.name,
          completed,
          late,
          onTimePct: completed > 0 ? Math.round(((completed - late) / completed) * 100) : 0,
          escalated: escalatedBy[u.id] ?? 0,
          currentLoad: loadBy[u.id] ?? 0,
        };
      });
    });

    res.json(data);
  } catch (err) { next(err); }
});

// Delegation completion rate over time — one point per day in range.
analyticsRouter.get('/delegation', async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const { from, to } = parseRange(req);
    const key = `analytics:delegation:${orgId}:${dayKey(from)}:${dayKey(to)}`;

    const data = await cached(key, CACHE_TTL_MS, async () => {
      const tasks = await prisma.task.findMany({
        where: { orgId, source: 'DELEGATION', createdAt: { gte: from, lte: to } },
        select: { createdAt: true, status: true },
      });

      const byDay: Record<string, { created: number; completed: number }> = {};
      for (const t of tasks) {
        const k = dayKey(t.createdAt);
        byDay[k] ??= { created: 0, completed: 0 };
        byDay[k].created++;
        if (t.status === 'DONE') byDay[k].completed++;
      }

      return Object.entries(byDay)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([date, v]) => ({
          date,
          created: v.created,
          completed: v.completed,
          completionPct: v.created > 0 ? Math.round((v.completed / v.created) * 100) : 0,
        }));
    });

    res.json(data);
  } catch (err) { next(err); }
});

// Checklist compliance % per checklist rule.
analyticsRouter.get('/checklists', async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const { from, to } = parseRange(req);
    const key = `analytics:checklists:${orgId}:${dayKey(from)}:${dayKey(to)}`;

    const data = await cached(key, CACHE_TTL_MS, async () => {
      const rules = await prisma.checklistRule.findMany({ where: { orgId }, select: { id: true, title: true } });

      const [totals, dones] = await Promise.all([
        prisma.task.groupBy({
          by: ['ruleId'],
          where: { orgId, source: 'CHECKLIST', createdAt: { gte: from, lte: to } },
          _count: { _all: true },
        }),
        prisma.task.groupBy({
          by: ['ruleId'],
          where: { orgId, source: 'CHECKLIST', createdAt: { gte: from, lte: to }, status: 'DONE' },
          _count: { _all: true },
        }),
      ]);

      const totalBy = Object.fromEntries(totals.map(r => [r.ruleId, r._count._all]));
      const doneBy = Object.fromEntries(dones.map(r => [r.ruleId, r._count._all]));

      return rules
        .map(r => {
          const total = totalBy[r.id] ?? 0;
          const done = doneBy[r.id] ?? 0;
          return { ruleId: r.id, title: r.title, total, done, compliancePct: total > 0 ? Math.round((done / total) * 100) : 0 };
        })
        .filter(r => r.total > 0);
    });

    res.json(data);
  } catch (err) { next(err); }
});

// FMS: avg time per stage, throughput, bottlenecks (bounded to range).
analyticsRouter.get('/fms', async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const { from, to } = parseRange(req);
    const key = `analytics:fms:${orgId}:${dayKey(from)}:${dayKey(to)}`;

    const data = await cached(key, CACHE_TTL_MS, async () => {
      const stages = await prisma.stageDef.findMany({
        where: { orgId },
        include: { flow: { select: { name: true } } },
      });

      const avgPerStage = await Promise.all(stages.map(async (s) => {
        const completed = await prisma.orderStage.findMany({
          where: { orgId, stageId: s.id, completedAt: { gte: from, lte: to } },
          select: { enteredAt: true, completedAt: true, delayMins: true },
        });
        const withDuration = completed.filter(c => c.enteredAt && c.completedAt);
        const avgMins = withDuration.length > 0
          ? Math.round(withDuration.reduce((a, c) => a + (c.completedAt!.getTime() - c.enteredAt!.getTime()) / 60_000, 0) / withDuration.length)
          : 0;
        const delayed = completed.filter(c => c.delayMins != null);
        const avgDelayMins = delayed.length > 0
          ? Math.round(delayed.reduce((a, c) => a + (c.delayMins ?? 0), 0) / delayed.length)
          : 0;
        const stuckNow = await prisma.orderStage.count({ where: { orgId, stageId: s.id, completedAt: null } });

        return {
          stageId: s.id,
          stageName: s.name,
          flowName: s.flow.name,
          plannedMins: s.plannedMins,
          avgMins,
          avgDelayMins,
          ordersStuckNow: stuckNow,
          completedInRange: completed.length,
        };
      }));

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
        stages: avgPerStage.sort((a, b) => b.ordersStuckNow - a.ordersStuckNow),
      };
    });

    res.json(data);
  } catch (err) { next(err); }
});

// Inventory: dead-stock value, low-stock count, total stock value, movement trend.
analyticsRouter.get('/inventory', async (req, res, next) => {
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
