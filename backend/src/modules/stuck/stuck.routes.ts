import { Router } from 'express';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';

export const stuckRouter = Router();
stuckRouter.use(requireAuth);

type Severity = 'HIGH' | 'MEDIUM' | 'LOW';

interface StuckItem {
  type: string;
  title: string;
  who: string;
  whoId: string | null;
  stuckSince: string;
  stuckForMins: number;
  severity: Severity;
  module: string;
  deepLinkId: string;
}

// A task can be flagged STUCK before its deadline even passes — fall back to
// when it was last touched rather than producing a negative duration.
function stuckSinceFor(t: { dueAt: Date | null; escalatedAt: Date | null; updatedAt: Date; createdAt: Date }, now: Date): Date {
  if (t.dueAt && t.dueAt <= now) return t.dueAt;
  if (t.escalatedAt) return t.escalatedAt;
  return t.updatedAt ?? t.createdAt;
}

function severityFor(t: { status: string; escalatedAt: Date | null }): Severity {
  if (t.escalatedAt || t.status === 'STUCK') return 'HIGH';
  return 'MEDIUM';
}

stuckRouter.get('/', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const now = new Date();
    const items: StuckItem[] = [];

    const users = await prisma.user.findMany({ where: { orgId }, select: { id: true, name: true } });
    const nameById = Object.fromEntries(users.map(u => [u.id, u.name]));

    // 1. Delegation tasks — overdue, STUCK, or escalated.
    const delegationTasks = await prisma.task.findMany({
      where: {
        orgId,
        source: 'DELEGATION',
        status: { notIn: ['DONE', 'CANCELLED'] },
        OR: [{ status: 'STUCK' }, { escalatedAt: { not: null } }, { dueAt: { lt: now } }],
      },
    });
    for (const t of delegationTasks) {
      const stuckSince = stuckSinceFor(t, now);
      items.push({
        type: t.escalatedAt ? 'ESCALATED' : t.status === 'STUCK' ? 'STUCK' : 'OVERDUE',
        title: t.title,
        who: nameById[t.assigneeId] ?? 'Unknown',
        whoId: t.assigneeId,
        stuckSince: stuckSince.toISOString(),
        stuckForMins: Math.round((now.getTime() - stuckSince.getTime()) / 60_000),
        severity: severityFor(t),
        module: 'TASKS',
        deepLinkId: t.id,
      });
    }

    // 2. Checklist items missed — overdue, not done.
    const checklistTasks = await prisma.task.findMany({
      where: {
        orgId,
        source: 'CHECKLIST',
        status: { notIn: ['DONE', 'CANCELLED'] },
        OR: [{ status: 'STUCK' }, { escalatedAt: { not: null } }, { dueAt: { lt: now } }],
      },
    });
    for (const t of checklistTasks) {
      const stuckSince = stuckSinceFor(t, now);
      items.push({
        type: t.escalatedAt ? 'ESCALATED' : t.status === 'STUCK' ? 'STUCK' : 'OVERDUE',
        title: t.title,
        who: nameById[t.assigneeId] ?? 'Unknown',
        whoId: t.assigneeId,
        stuckSince: stuckSince.toISOString(),
        stuckForMins: Math.round((now.getTime() - stuckSince.getTime()) / 60_000),
        severity: severityFor(t),
        module: 'CHECKLISTS',
        deepLinkId: t.id,
      });
    }

    // 3. FMS orders sitting past a PLANNED stage's time — mirrors the exact
    // delayed-computation used on the live board. Unplanned stages
    // (plannedMins == null) have no deadline and can NEVER appear here.
    const orders = await prisma.order.findMany({
      where: { orgId, status: 'ACTIVE', currentStageId: { not: null } },
      include: { flow: { include: { stages: true } }, stages: true },
    });

    const linkedTaskIds = orders
      .flatMap(o => o.stages)
      .map(s => s.taskId)
      .filter((id): id is string => !!id);
    const linkedTasks = linkedTaskIds.length
      ? await prisma.task.findMany({ where: { id: { in: linkedTaskIds } }, select: { id: true, escalatedAt: true, status: true } })
      : [];
    const taskById = Object.fromEntries(linkedTasks.map(t => [t.id, t]));

    for (const o of orders) {
      const current = o.flow.stages.find(s => s.id === o.currentStageId);
      if (!current || current.plannedMins == null) continue; // unplanned — never stuck

      const os = o.stages.find(x => x.stageId === o.currentStageId && !x.completedAt);
      if (!os?.plannedDeadline) continue;
      if (now < os.plannedDeadline) continue; // within the working-time plan — not stuck

      const stuckSince = os.plannedDeadline;
      const linkedTask = os.taskId ? taskById[os.taskId] : undefined;
      const escalated = !!linkedTask?.escalatedAt;
      const flaggedStuck = linkedTask?.status === 'STUCK';

      items.push({
        type: escalated ? 'ESCALATED' : flaggedStuck ? 'STUCK' : 'DELAYED',
        title: `${o.orderNumber} — ${current.name}`,
        who: current.responsibleId ? (nameById[current.responsibleId] ?? 'Unknown') : 'Unassigned',
        whoId: current.responsibleId ?? null,
        stuckSince: stuckSince.toISOString(),
        stuckForMins: Math.round((now.getTime() - stuckSince.getTime()) / 60_000),
        severity: (escalated || flaggedStuck) ? 'HIGH' : 'MEDIUM',
        module: 'FMS',
        deepLinkId: o.id,
      });
    }

    // 4. Inventory alerts — open (not DONE/CANCELLED) INVENTORY_ALERT tasks.
    const invTasks = await prisma.task.findMany({
      where: { orgId, source: 'INVENTORY_ALERT', status: { notIn: ['DONE', 'CANCELLED'] } },
    });
    for (const t of invTasks) {
      const stuckSince = stuckSinceFor(t, now);
      items.push({
        type: t.title.startsWith('Over-stock') ? 'OVER_STOCK' : 'LOW_STOCK',
        title: t.title,
        who: nameById[t.assigneeId] ?? 'Unknown',
        whoId: t.assigneeId,
        stuckSince: stuckSince.toISOString(),
        stuckForMins: Math.round((now.getTime() - stuckSince.getTime()) / 60_000),
        severity: severityFor(t),
        module: 'INVENTORY',
        deepLinkId: t.ruleId ?? t.id,
      });
    }

    const severityRank: Record<Severity, number> = { HIGH: 0, MEDIUM: 1, LOW: 2 };
    items.sort((a, b) => {
      const rankDiff = severityRank[a.severity] - severityRank[b.severity];
      if (rankDiff !== 0) return rankDiff;
      return b.stuckForMins - a.stuckForMins;
    });

    res.json(items);
  } catch (err) { next(err); }
});
