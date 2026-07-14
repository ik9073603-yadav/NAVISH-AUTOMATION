import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { advanceOrder } from './fms.service';
import { parseListQuery, dateRangeFilter } from '../../lib/listFilters';

export const fmsRouter = Router();
fmsRouter.use(requireAuth);

// ---------- FLOW BUILDER ----------
const flowSchema = z.object({
  name: z.string().min(2),
  prefix: z.string().min(1).max(6),
  itemLabel: z.string().min(1).max(20),
  stages: z.array(z.object({
    name: z.string().min(1),
    responsibleId: z.string().uuid().optional(),
    plannedMins: z.number().int().positive().optional(),
    fields: z.array(z.object({
      label: z.string().min(1),
      type: z.enum(['TEXT', 'NUMBER', 'DROPDOWN', 'DATE', 'PHOTO', 'YESNO']),
      required: z.boolean().optional(),
      options: z.string().optional(),
    })).optional(),
  })).min(1),
});

fmsRouter.post('/flows', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const parsed = flowSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId } = req.user!;

    const flow = await prisma.flow.create({
      data: {
        orgId,
        name: parsed.data.name,
        prefix: parsed.data.prefix.toUpperCase(),
        itemLabel: parsed.data.itemLabel,
      },
    });

    for (let i = 0; i < parsed.data.stages.length; i++) {
      const s = parsed.data.stages[i];
      const stage = await prisma.stageDef.create({
        data: {
          orgId, flowId: flow.id, name: s.name, sequence: i + 1,
          responsibleId: s.responsibleId, plannedMins: s.plannedMins,
        },
      });

      for (let j = 0; j < (s.fields ?? []).length; j++) {
        const f = s.fields![j];
        await prisma.fieldDef.create({
          data: {
            orgId, stageId: stage.id, label: f.label, type: f.type,
            required: f.required ?? false, options: f.options, sequence: j,
          },
        });
      }
    }

    res.status(201).json(flow);
  } catch (err) { next(err); }
});

fmsRouter.get('/flows', async (req, res, next) => {
  try {
    const flows = await prisma.flow.findMany({
      where: { orgId: req.user!.orgId },
      include: {
        stages: {
          orderBy: { sequence: 'asc' },
          include: { fields: { orderBy: { sequence: 'asc' } } },
        },
      },
      orderBy: { createdAt: 'desc' },
    });
    res.json(flows);
  } catch (err) { next(err); }
});

// ---------- ORDERS ----------
fmsRouter.post('/flows/:flowId/orders', async (req, res, next) => {
  try {
    const { orgId } = req.user!;

    const flow = await prisma.flow.findFirst({ where: { id: req.params.flowId, orgId } });
    if (!flow) return res.status(404).json({ error: 'Flow not found' });

    const count = flow.orderCount + 1;
    const orderNumber = `${flow.prefix}-${String(count).padStart(4, '0')}`;

    const order = await prisma.order.create({
      data: { orgId, flowId: flow.id, orderNumber },
    });

    await prisma.flow.update({ where: { id: flow.id }, data: { orderCount: count } });

    await advanceOrder(order.id, orgId);   // pehla stage shuru

    res.status(201).json(order);
  } catch (err) { next(err); }
});

// Live status board (Feature 92)
fmsRouter.get('/orders', async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const { status, from, to, assigneeId } = parseListQuery(req);

    const where: any = { orgId };
    if (status === 'ACTIVE') where.status = 'ACTIVE';
    else if (status === 'DONE') where.status = { in: ['COMPLETED', 'CANCELLED'] };
    const startedAt = dateRangeFilter(from, to);
    if (startedAt) where.startedAt = startedAt;

    const orders = await prisma.order.findMany({
      where,
      include: {
        flow: { include: { stages: { orderBy: { sequence: 'asc' } } } },
        stages: true,
      },
      orderBy: { startedAt: 'desc' },
      take: 100,
    });

    let mapped = orders.map(o => {
      const current = o.flow.stages.find(s => s.id === o.currentStageId);
      const os = o.stages.find(x => x.stageId === o.currentStageId && !x.completedAt);
      const sittingMins = os?.enteredAt
        ? Math.round((Date.now() - os.enteredAt.getTime()) / 60_000)
        : 0;
      return {
        id: o.id,
        orderNumber: o.orderNumber,
        flowName: o.flow.name,
        itemLabel: o.flow.itemLabel,
        status: o.status,
        currentStage: current?.name ?? '—',
        currentStageId: current?.id,
        responsibleId: current?.responsibleId ?? null,
        orderStageId: os?.id,
        totalStages: o.flow.stages.length,
        doneStages: o.stages.filter(s => s.completedAt).length,
        sittingMins,
        delayed: current?.plannedMins ? sittingMins > current.plannedMins : false,
      };
    });

    if (assigneeId) mapped = mapped.filter(o => o.responsibleId === assigneeId);

    res.json(mapped);
  } catch (err) { next(err); }
});

// Stage complete karo + custom fields bharo
fmsRouter.post('/orderstages/:id/complete', async (req, res, next) => {
  try {
    const { orgId, userId, role } = req.user!;

    const os = await prisma.orderStage.findFirst({
      where: { id: req.params.id, orgId, completedAt: null },
    });
    if (!os) return res.status(404).json({ error: 'Stage not found or already done' });

    const stageDef = await prisma.stageDef.findUnique({
      where: { id: os.stageId },
      include: { fields: true },
    });

    // Only the doer acts — owner never executes, and if a specific person is
    // responsible for this stage, only that person may complete it.
    if (role === 'OWNER' || (stageDef?.responsibleId && stageDef.responsibleId !== userId)) {
      return res.status(403).json({ error: 'Only the responsible person can complete this stage' });
    }

    const data = (req.body?.data ?? {}) as Record<string, any>;
    const remarks = req.body?.remarks as string | undefined;
    if (remarks) data.__remarks = remarks;

    // Required fields check
    for (const f of stageDef?.fields ?? []) {
      if (f.required && (data[f.label] === undefined || data[f.label] === '')) {
        return res.status(400).json({ error: `Field required: ${f.label}` });
      }
    }

    const actualMins = os.enteredAt
      ? Math.round((Date.now() - os.enteredAt.getTime()) / 60_000)
      : 0;
    const delayMins = stageDef?.plannedMins ? actualMins - stageDef.plannedMins : null;

    await prisma.orderStage.update({
      where: { id: os.id },
      data: { completedAt: new Date(), completedById: userId, data, delayMins },
    });

    // Us stage ka task band karo → chasing rukegi
    if (os.taskId) {
      await prisma.task.update({
        where: { id: os.taskId },
        data: { status: 'DONE', completedAt: new Date(), nextActionAt: null },
      });
    }

    const next = await advanceOrder(os.orderId, orgId);

    res.json({ completed: true, nextStage: next?.stageId ?? null, delayMins });
  } catch (err) { next(err); }
});

// Bottleneck view (Feature 97)
fmsRouter.get('/bottlenecks', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const { orgId } = req.user!;

    const stages = await prisma.stageDef.findMany({
      where: { orgId },
      include: { flow: { select: { name: true } } },
    });

    const result = await Promise.all(stages.map(async (s) => {
      const stuck = await prisma.orderStage.count({
        where: { orgId, stageId: s.id, completedAt: null },
      });
      const completed = await prisma.orderStage.findMany({
        where: { orgId, stageId: s.id, completedAt: { not: null }, delayMins: { not: null } },
        select: { delayMins: true },
      });
      const avgDelay = completed.length > 0
        ? Math.round(completed.reduce((a, c) => a + (c.delayMins ?? 0), 0) / completed.length)
        : 0;

      return {
        stageName: s.name,
        flowName: s.flow.name,
        ordersStuck: stuck,
        avgDelayMins: avgDelay,
        plannedMins: s.plannedMins,
      };
    }));

    res.json(result.sort((a, b) => b.ordersStuck - a.ordersStuck));
  } catch (err) { next(err); }
});

// Order ka poora safar (Feature 99)
fmsRouter.get('/orders/:id/history', async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const order = await prisma.order.findFirst({
      where: { id: req.params.id, orgId },
      include: { flow: { include: { stages: true } }, stages: { orderBy: { sequence: 'asc' } } },
    });
    if (!order) return res.status(404).json({ error: 'Not found' });

    const nameById = Object.fromEntries(order.flow.stages.map(s => [s.id, s.name]));

    res.json({
      orderNumber: order.orderNumber,
      status: order.status,
      stages: order.stages.map(s => ({
        name: nameById[s.stageId] ?? '?',
        enteredAt: s.enteredAt,
        completedAt: s.completedAt,
        delayMins: s.delayMins,
        data: s.data,
      })),
    });
  } catch (err) { next(err); }
});