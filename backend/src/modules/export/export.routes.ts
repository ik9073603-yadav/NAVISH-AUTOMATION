import { Router } from 'express';
import { ZipArchive } from 'archiver';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { dateRangeFilter } from '../../lib/listFilters';
import { rowsToCsv, rowsToXlsxBuffer } from '../../lib/exportUtils';

export const exportRouter = Router();
exportRouter.use(requireAuth, requireRole('OWNER', 'MANAGER'));

function parseRange(req: any): { from?: Date; to?: Date } {
  return {
    from: req.query.from ? new Date(req.query.from as string) : undefined,
    to: req.query.to ? new Date(req.query.to as string) : undefined,
  };
}

async function sendTable(res: any, format: string, filenameBase: string, sheetName: string, headers: string[], rows: unknown[][]) {
  if (format === 'xlsx') {
    const buffer = await rowsToXlsxBuffer(sheetName, headers, rows);
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', `attachment; filename="${filenameBase}.xlsx"`);
    res.send(buffer);
  } else {
    const csv = rowsToCsv(headers, rows);
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename="${filenameBase}.csv"`);
    res.send(csv);
  }
}

// FMS orders for one flow, in a date range.
exportRouter.get('/fms/:flowId', async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const format = (req.query.format as string) === 'xlsx' ? 'xlsx' : 'csv';
    const { from, to } = parseRange(req);

    const flow = await prisma.flow.findFirst({
      where: { id: req.params.flowId, orgId },
      include: { stages: { orderBy: { sequence: 'asc' } } },
    });
    if (!flow) return res.status(404).json({ error: 'Flow not found' });

    const startedAt = dateRangeFilter(from, to);
    const orders = await prisma.order.findMany({
      where: { orgId, flowId: flow.id, ...(startedAt && { startedAt }) },
      include: { stages: true },
      orderBy: { startedAt: 'desc' },
    });

    const stageNameById = Object.fromEntries(flow.stages.map(s => [s.id, s.name]));

    const headers = ['Order #', 'Status', 'Started', 'Completed', 'Cycle time (mins)', 'Current stage', 'Stages done', 'Total stages'];
    const rows = orders.map(o => {
      const current = flow.stages.find(s => s.id === o.currentStageId);
      const cycleMins = o.completedAt ? Math.round((o.completedAt.getTime() - o.startedAt.getTime()) / 60_000) : '';
      return [
        o.orderNumber,
        o.status,
        o.startedAt.toISOString(),
        o.completedAt ? o.completedAt.toISOString() : '',
        cycleMins,
        current ? stageNameById[current.id] ?? '' : '',
        o.stages.filter(s => s.completedAt).length,
        flow.stages.length,
      ];
    });

    await sendTable(res, format, `flow-${flow.name.replace(/\s+/g, '-').toLowerCase()}`, 'Orders', headers, rows);
  } catch (err) { next(err); }
});

// Inventory stock movements in a date range (optionally one SKU).
exportRouter.get('/inventory/movements', async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const format = (req.query.format as string) === 'xlsx' ? 'xlsx' : 'csv';
    const { from, to } = parseRange(req);
    const skuId = req.query.skuId as string | undefined;

    const createdAt = dateRangeFilter(from, to);
    const movements = await prisma.stockMovement.findMany({
      where: { orgId, ...(skuId && { skuId }), ...(createdAt && { createdAt }) },
      include: { sku: { select: { name: true, code: true, unit: true } } },
      orderBy: { createdAt: 'desc' },
    });

    const userIds = [...new Set(movements.map(m => m.doneById))];
    const users = await prisma.user.findMany({ where: { id: { in: userIds } }, select: { id: true, name: true } });
    const nameById = Object.fromEntries(users.map(u => [u.id, u.name]));

    const headers = ['Date', 'SKU', 'Code', 'Type', 'Quantity', 'Unit', 'Balance after', 'Reason', 'Done by'];
    const rows = movements.map(m => [
      m.createdAt.toISOString(),
      m.sku.name,
      m.sku.code,
      m.type,
      m.quantity,
      m.sku.unit,
      m.balance,
      m.reason ?? '',
      nameById[m.doneById] ?? 'Unknown',
    ]);

    await sendTable(res, format, 'inventory-movements', 'Movements', headers, rows);
  } catch (err) { next(err); }
});

// Task / analytics report in a date range (optionally one source).
exportRouter.get('/tasks', async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const format = (req.query.format as string) === 'xlsx' ? 'xlsx' : 'csv';
    const { from, to } = parseRange(req);
    const source = req.query.source as string | undefined;

    const createdAt = dateRangeFilter(from, to);
    const tasks = await prisma.task.findMany({
      where: { orgId, ...(source && { source: source as any }), ...(createdAt && { createdAt }) },
      orderBy: { createdAt: 'desc' },
      take: 5000,
    });

    const userIds = [...new Set(tasks.map(t => t.assigneeId))];
    const users = await prisma.user.findMany({ where: { id: { in: userIds } }, select: { id: true, name: true } });
    const nameById = Object.fromEntries(users.map(u => [u.id, u.name]));

    const headers = ['Title', 'Source', 'Status', 'Priority', 'Assignee', 'Due', 'Completed', 'Escalated', 'Chase count', 'Created'];
    const rows = tasks.map(t => [
      t.title,
      t.source,
      t.status,
      t.priority,
      nameById[t.assigneeId] ?? 'Unknown',
      t.dueAt ? t.dueAt.toISOString() : '',
      t.completedAt ? t.completedAt.toISOString() : '',
      t.escalatedAt ? 'Yes' : 'No',
      t.chaseCount,
      t.createdAt.toISOString(),
    ]);

    await sendTable(res, format, 'tasks-report', 'Tasks', headers, rows);
  } catch (err) { next(err); }
});

// Full company backup (Feature 12) — a zip of JSON files, one per entity.
// OWNER only, always the caller's own org (orgId from JWT).
exportRouter.get('/backup', requireRole('OWNER'), async (req, res, next) => {
  try {
    const { orgId } = req.user!;

    const [org, users, tasks, checklistRules, flows, orders, orderStages, skus, movements] = await Promise.all([
      prisma.organization.findUnique({ where: { id: orgId } }),
      prisma.user.findMany({ where: { orgId }, select: { id: true, name: true, email: true, phone: true, role: true, status: true, managerId: true, createdAt: true } }),
      prisma.task.findMany({ where: { orgId } }),
      prisma.checklistRule.findMany({ where: { orgId } }),
      prisma.flow.findMany({ where: { orgId }, include: { stages: { include: { fields: true } } } }),
      prisma.order.findMany({ where: { orgId } }),
      prisma.orderStage.findMany({ where: { orgId } }),
      prisma.sku.findMany({ where: { orgId } }),
      prisma.stockMovement.findMany({ where: { orgId } }),
    ]);

    res.setHeader('Content-Type', 'application/zip');
    res.setHeader('Content-Disposition', `attachment; filename="navish-backup-${orgId}.zip"`);

    const archive = new ZipArchive({ zlib: { level: 9 } });
    archive.on('error', (err: Error) => next(err));
    archive.pipe(res);

    archive.append(JSON.stringify(org, null, 2), { name: 'organization.json' });
    archive.append(JSON.stringify(users, null, 2), { name: 'users.json' });
    archive.append(JSON.stringify(tasks, null, 2), { name: 'tasks.json' });
    archive.append(JSON.stringify(checklistRules, null, 2), { name: 'checklist_rules.json' });
    archive.append(JSON.stringify(flows, null, 2), { name: 'flows.json' });
    archive.append(JSON.stringify(orders, null, 2), { name: 'flow_orders.json' });
    archive.append(JSON.stringify(orderStages, null, 2), { name: 'flow_order_stages.json' });
    archive.append(JSON.stringify(skus, null, 2), { name: 'inventory_skus.json' });
    archive.append(JSON.stringify(movements, null, 2), { name: 'inventory_movements.json' });

    await archive.finalize();
  } catch (err) { next(err); }
});
