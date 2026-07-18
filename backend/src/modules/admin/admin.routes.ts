import { Router } from 'express';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireSuperAdmin } from '../../middleware/auth';
import { deleteOrganizationCascade, OrgNameMismatchError, OrgNotFoundError } from '../../lib/org-deletion';

// Cross-org, superadmin-only. This is the ONLY router in the codebase that
// deliberately does not scope by req.user.orgId — every query here spans
// every tenant on purpose. Never relax requireSuperAdmin below.
export const adminRouter = Router();
adminRouter.use(requireAuth, requireSuperAdmin);

const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;

async function orgIdsActiveSince(since: Date): Promise<Set<string>> {
  const rows = await prisma.activityLog.findMany({
    where: { createdAt: { gte: since } },
    distinct: ['orgId'],
    select: { orgId: true },
  });
  return new Set(rows.map(r => r.orgId));
}

adminRouter.get('/overview', async (_req, res, next) => {
  try {
    const since = new Date(Date.now() - SEVEN_DAYS_MS);

    const [totalCompanies, roleCounts, totalTasks, activeOrgIds] = await Promise.all([
      prisma.organization.count(),
      prisma.user.groupBy({ by: ['role'], where: { status: 'ACTIVE' }, _count: { _all: true } }),
      prisma.task.count(),
      orgIdsActiveSince(since),
    ]);

    res.json({
      totalCompanies,
      activeAccountsByRole: Object.fromEntries(roleCounts.map(r => [r.role, r._count._all])),
      totalTasks,
      orgsActiveLast7Days: activeOrgIds.size,
    });
  } catch (err) { next(err); }
});

adminRouter.get('/orgs', async (_req, res, next) => {
  try {
    const since = new Date(Date.now() - SEVEN_DAYS_MS);

    const [orgs, activeOrgIds] = await Promise.all([
      prisma.organization.findMany({ orderBy: { createdAt: 'desc' } }),
      orgIdsActiveSince(since),
    ]);

    const orgIds = orgs.map(o => o.id);
    const [accountCounts, taskCounts, lastActivity] = await Promise.all([
      prisma.user.groupBy({ by: ['orgId'], where: { orgId: { in: orgIds }, status: 'ACTIVE' }, _count: { _all: true } }),
      prisma.task.groupBy({ by: ['orgId'], where: { orgId: { in: orgIds } }, _count: { _all: true } }),
      prisma.activityLog.groupBy({ by: ['orgId'], where: { orgId: { in: orgIds } }, _max: { createdAt: true } }),
    ]);

    const accountsByOrg = Object.fromEntries(accountCounts.map(r => [r.orgId, r._count._all]));
    const tasksByOrg = Object.fromEntries(taskCounts.map(r => [r.orgId, r._count._all]));
    const lastActivityByOrg = Object.fromEntries(lastActivity.map(r => [r.orgId, r._max.createdAt]));

    res.json(orgs.map(o => ({
      id: o.id,
      name: o.name,
      slug: o.slug,
      createdAt: o.createdAt,
      enabled: o.enabled,
      accountCount: accountsByOrg[o.id] ?? 0,
      taskCount: tasksByOrg[o.id] ?? 0,
      lastActivityAt: lastActivityByOrg[o.id] ?? null,
      activeRecently: activeOrgIds.has(o.id),
    })));
  } catch (err) { next(err); }
});

// Health/usage counts only — deliberately no task titles, no user names/emails.
// Even as superadmin, we don't read into a tenant's private data.
adminRouter.get('/orgs/:id', async (req, res, next) => {
  try {
    const org = await prisma.organization.findUnique({ where: { id: req.params.id } });
    if (!org) return res.status(404).json({ error: 'Organization not found' });

    const since = new Date(Date.now() - SEVEN_DAYS_MS);
    const orgId = org.id;

    const [
      accountsByRole, taskStatusCounts, checklistCount, activeChecklistCount,
      flowCount, activeOrderCount, skuCount, lastActivity,
    ] = await Promise.all([
      prisma.user.groupBy({ by: ['role'], where: { orgId, status: 'ACTIVE' }, _count: { _all: true } }),
      prisma.task.groupBy({ by: ['status'], where: { orgId }, _count: { _all: true } }),
      prisma.checklistRule.count({ where: { orgId } }),
      prisma.checklistRule.count({ where: { orgId, active: true } }),
      prisma.flow.count({ where: { orgId } }),
      prisma.order.count({ where: { orgId, status: 'ACTIVE' } }),
      prisma.sku.count({ where: { orgId, active: true } }),
      prisma.activityLog.aggregate({ where: { orgId }, _max: { createdAt: true } }),
    ]);

    res.json({
      id: org.id,
      name: org.name,
      slug: org.slug,
      createdAt: org.createdAt,
      enabled: org.enabled,
      accountsByRole: Object.fromEntries(accountsByRole.map(r => [r.role, r._count._all])),
      tasksByStatus: Object.fromEntries(taskStatusCounts.map(r => [r.status, r._count._all])),
      checklists: { total: checklistCount, active: activeChecklistCount },
      fms: { flows: flowCount, activeOrders: activeOrderCount },
      inventory: { activeSkus: skuCount },
      lastActivityAt: lastActivity._max.createdAt,
      activeRecently: lastActivity._max.createdAt ? lastActivity._max.createdAt >= since : false,
    });
  } catch (err) { next(err); }
});

adminRouter.post('/orgs/:id/toggle', async (req, res, next) => {
  try {
    const org = await prisma.organization.findUnique({ where: { id: req.params.id } });
    if (!org) return res.status(404).json({ error: 'Organization not found' });

    const updated = await prisma.organization.update({
      where: { id: org.id },
      data: { enabled: !org.enabled },
    });

    await prisma.activityLog.create({
      data: {
        orgId: org.id,
        actorId: req.user!.userId,
        action: updated.enabled ? 'ORG_ENABLED_BY_ADMIN' : 'ORG_DISABLED_BY_ADMIN',
        entity: 'Organization',
        entityId: org.id,
      },
    });

    res.json({ id: updated.id, enabled: updated.enabled });
  } catch (err) { next(err); }
});

// Feature 13 — company delete + data retention (DPDP erasure). Irreversible,
// so the caller must echo the org's exact current name back as confirmName.
// The org row (and everything FK-cascaded from it) is gone after this call;
// no soft-delete, no undo.
adminRouter.delete('/orgs/:id', async (req, res, next) => {
  try {
    const { confirmName } = req.body ?? {};
    if (typeof confirmName !== 'string' || confirmName.length === 0) {
      return res.status(400).json({ error: 'confirmName is required' });
    }

    const deleted = await deleteOrganizationCascade(req.params.id, confirmName);
    res.json({ deleted: true, id: deleted.id, name: deleted.name });
  } catch (err) {
    if (err instanceof OrgNotFoundError) return res.status(404).json({ error: err.message });
    if (err instanceof OrgNameMismatchError) return res.status(400).json({ error: err.message });
    next(err);
  }
});

// Cross-org fallback for account-deletion requests (Feature 176) — the org
// owner is the normal actioner (see /api/auth/deletion-requests); this exists
// for cases where a superadmin needs to step in.
adminRouter.get('/deletion-requests', async (_req, res, next) => {
  try {
    const requests = await prisma.deletionRequest.findMany({
      where: { status: 'PENDING' },
      orderBy: { requestedAt: 'asc' },
    });

    const userIds = requests.map(r => r.userId);
    const orgIds = [...new Set(requests.map(r => r.orgId))];
    const [users, orgs] = await Promise.all([
      userIds.length
        ? prisma.user.findMany({ where: { id: { in: userIds } }, select: { id: true, name: true, email: true } })
        : Promise.resolve([]),
      orgIds.length
        ? prisma.organization.findMany({ where: { id: { in: orgIds } }, select: { id: true, name: true } })
        : Promise.resolve([]),
    ]);
    const userById = Object.fromEntries(users.map(u => [u.id, u]));
    const orgById = Object.fromEntries(orgs.map(o => [o.id, o]));

    res.json(requests.map(r => ({
      id: r.id,
      requestedAt: r.requestedAt,
      user: userById[r.userId] ?? null,
      organization: orgById[r.orgId] ?? null,
    })));
  } catch (err) { next(err); }
});

adminRouter.post('/deletion-requests/:id/complete', async (req, res, next) => {
  try {
    const request = await prisma.deletionRequest.findFirst({
      where: { id: req.params.id, status: 'PENDING' },
    });
    if (!request) return res.status(404).json({ error: 'Deletion request not found' });

    await prisma.user.update({
      where: { id: request.userId },
      data: { status: 'DEACTIVATED' },
    });

    await prisma.deletionRequest.update({
      where: { id: request.id },
      data: { status: 'COMPLETED', resolvedAt: new Date(), resolvedById: req.user!.userId },
    });

    await prisma.activityLog.create({
      data: { orgId: request.orgId, actorId: req.user!.userId, action: 'DELETION_COMPLETED_BY_ADMIN', entity: 'User', entityId: request.userId },
    });

    res.json({ completed: true });
  } catch (err) { next(err); }
});
