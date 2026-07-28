import { prisma } from '../../lib/prisma';

export interface EmployeeMetric {
  userId: string;
  name: string;
  departmentId: string | null;
  completed: number;
  late: number;
  onTimePct: number;
  escalated: number;
  currentLoad: number;
  checklistTotal: number;
  checklistDone: number;
  checklistCompliancePct: number;
  avgCompletionMins: number;
}

// Single set of grouped/aggregate queries covering every active user at
// once — O(1) round trips regardless of headcount, never a per-user loop.
// Reused by both the employee-level and department-rollup analytics
// endpoints so the two screens' numbers can never drift apart.
export async function computeEmployeeMetrics(orgId: string, from: Date, to: Date): Promise<EmployeeMetric[]> {
  const users = await prisma.user.findMany({
    where: { orgId, status: 'ACTIVE' },
    select: { id: true, name: true, departmentId: true },
  });

  const [
    completedInRange,
    escalatedInRange,
    currentLoad,
    lateInRange,
    checklistTotalRows,
    checklistDoneRows,
    completedDurationRows,
  ] = await Promise.all([
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
    // "Late" among completed-in-range: escalated at some point before finishing.
    prisma.task.groupBy({
      by: ['assigneeId'],
      where: { orgId, status: 'DONE', completedAt: { gte: from, lte: to }, escalatedAt: { not: null } },
      _count: { _all: true },
    }),
    prisma.task.groupBy({
      by: ['assigneeId'],
      where: { orgId, source: 'CHECKLIST', createdAt: { gte: from, lte: to } },
      _count: { _all: true },
    }),
    prisma.task.groupBy({
      by: ['assigneeId'],
      where: { orgId, source: 'CHECKLIST', createdAt: { gte: from, lte: to }, status: 'DONE' },
      _count: { _all: true },
    }),
    // No stored task-duration column — one query fetching every completed
    // task's timestamps in range, reduced to a per-assignee average in JS
    // below. A single round trip, not a per-user loop.
    prisma.task.findMany({
      where: { orgId, status: 'DONE', completedAt: { gte: from, lte: to } },
      select: { assigneeId: true, createdAt: true, completedAt: true },
    }),
  ]);

  const toMap = (rows: { assigneeId: string; _count: { _all: number } }[]) =>
    new Map(rows.map(r => [r.assigneeId, r._count._all]));
  const doneBy = toMap(completedInRange);
  const escalatedBy = toMap(escalatedInRange);
  const loadBy = toMap(currentLoad);
  const lateBy = toMap(lateInRange);
  const checklistTotalBy = toMap(checklistTotalRows);
  const checklistDoneBy = toMap(checklistDoneRows);

  const durationSumByUser = new Map<string, number>();
  const durationCountByUser = new Map<string, number>();
  for (const t of completedDurationRows) {
    if (!t.completedAt) continue;
    const mins = (t.completedAt.getTime() - t.createdAt.getTime()) / 60_000;
    durationSumByUser.set(t.assigneeId, (durationSumByUser.get(t.assigneeId) ?? 0) + mins);
    durationCountByUser.set(t.assigneeId, (durationCountByUser.get(t.assigneeId) ?? 0) + 1);
  }

  return users.map(u => {
    const completed = doneBy.get(u.id) ?? 0;
    const late = lateBy.get(u.id) ?? 0;
    const checklistTotal = checklistTotalBy.get(u.id) ?? 0;
    const checklistDone = checklistDoneBy.get(u.id) ?? 0;
    const durationCount = durationCountByUser.get(u.id) ?? 0;
    const durationSum = durationSumByUser.get(u.id) ?? 0;

    return {
      userId: u.id,
      name: u.name,
      departmentId: u.departmentId,
      completed,
      late,
      onTimePct: completed > 0 ? Math.round(((completed - late) / completed) * 100) : 0,
      escalated: escalatedBy.get(u.id) ?? 0,
      currentLoad: loadBy.get(u.id) ?? 0,
      checklistTotal,
      checklistDone,
      checklistCompliancePct: checklistTotal > 0 ? Math.round((checklistDone / checklistTotal) * 100) : 0,
      avgCompletionMins: durationCount > 0 ? Math.round(durationSum / durationCount) : 0,
    };
  });
}
