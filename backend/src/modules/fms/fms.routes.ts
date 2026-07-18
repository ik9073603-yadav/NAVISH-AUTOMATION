import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { advanceOrder } from './fms.service';
import { parseListQuery, dateRangeFilter } from '../../lib/listFilters';
import { cached } from '../../lib/cache';
import { classifyOrdersSla, deriveOrderDetailLabel } from './fms-analytics.service';

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

const stageUpdateSchema = z.object({
  responsibleId: z.string().uuid().nullable().optional(),
  plannedMins: z.number().int().positive().nullable().optional(),
});

// Used to finish setting up a template-applied flow — assign the real
// responsible person per stage (and optionally tweak the planned time).
fmsRouter.patch('/stages/:id', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const parsed = stageUpdateSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId } = req.user!;
    const stage = await prisma.stageDef.findFirst({ where: { id: req.params.id, orgId } });
    if (!stage) return res.status(404).json({ error: 'Stage not found' });

    if (parsed.data.responsibleId) {
      const person = await prisma.user.findFirst({ where: { id: parsed.data.responsibleId, orgId } });
      if (!person) return res.status(404).json({ error: 'Person not found in your company' });
    }

    const updated = await prisma.stageDef.update({
      where: { id: stage.id },
      data: parsed.data,
    });

    res.json(updated);
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
        plannedDeadline: os?.plannedDeadline ?? null,
        // Working-time deadline, not raw wall-clock — a stage sitting overnight
        // or across a week-off isn't "delayed" until its actual deadline passes.
        delayed: os?.plannedDeadline ? Date.now() > os.plannedDeadline.getTime() : false,
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

    // Delay is measured against the working-time deadline computed when this
    // stage was entered (os.plannedDeadline), not raw wall-clock elapsed —
    // sitting overnight or across a week-off must not count as "late".
    const completedAt = new Date();
    const delayMins = os.plannedDeadline
      ? Math.round((completedAt.getTime() - os.plannedDeadline.getTime()) / 60_000)
      : null;

    await prisma.orderStage.update({
      where: { id: os.id },
      data: { completedAt, completedById: userId, data, delayMins },
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
    const plannedMinsById = Object.fromEntries(order.flow.stages.map(s => [s.id, s.plannedMins]));

    const completedByIds = [...new Set(order.stages.map(s => s.completedById).filter((x): x is string => !!x))];
    const completedByUsers = completedByIds.length
      ? await prisma.user.findMany({ where: { id: { in: completedByIds } }, select: { id: true, name: true } })
      : [];
    const nameByUserId = Object.fromEntries(completedByUsers.map(u => [u.id, u.name]));

    // Same SLA rule as the analytics KPIs, computed inline since every stage
    // is already loaded here — no need for the org-wide batch query.
    const hasPlannedStage = order.flow.stages.some(s => s.plannedMins != null);
    const anyLate = order.stages.some(
      s => s.plannedDeadline && s.completedAt && s.completedAt.getTime() > s.plannedDeadline.getTime(),
    );
    const slaStatus = !hasPlannedStage ? 'NO_SLA' : (anyLate ? 'DELAYED' : 'ON_TIME');

    res.json({
      orderNumber: order.orderNumber,
      status: order.status,
      slaStatus,
      stages: order.stages.map(s => ({
        name: nameById[s.stageId] ?? '?',
        plannedMins: plannedMinsById[s.stageId] ?? null,
        enteredAt: s.enteredAt,
        completedAt: s.completedAt,
        plannedDeadline: s.plannedDeadline,
        delayMins: s.delayMins,
        completedByName: s.completedById ? (nameByUserId[s.completedById] ?? null) : null,
        data: s.data,
      })),
    });
  } catch (err) { next(err); }
});

// ---------- FLOW ANALYTICS (KPI cards + drill-down lists) ----------
const ANALYTICS_CACHE_TTL_MS = 60_000;

// Four clickable KPI counts + a small summary. All-time (the drill-down
// lists carry the date-range filter, not the headline counts).
fmsRouter.get('/analytics/summary', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const key = `fms:analytics:summary:${orgId}`;

    const data = await cached(key, ANALYTICS_CACHE_TTL_MS, async () => {
      const orders = await prisma.order.findMany({
        where: { orgId },
        select: { id: true, flowId: true, status: true, startedAt: true, completedAt: true },
      });
      const slaMap = await classifyOrdersSla(orgId, orders);

      let pending = 0, completed = 0, delayed = 0, onTime = 0, noSla = 0;
      for (const o of orders) {
        if (o.status === 'ACTIVE') pending++;
        if (o.status === 'COMPLETED') completed++;
        const sla = slaMap.get(o.id);
        if (sla === 'DELAYED') delayed++;
        else if (sla === 'ON_TIME') onTime++;
        else noSla++;
      }

      const completedWithDuration = orders.filter(o => o.status === 'COMPLETED' && o.completedAt);
      const avgCycleTimeMins = completedWithDuration.length > 0
        ? Math.round(
            completedWithDuration.reduce((a, o) => a + (o.completedAt!.getTime() - o.startedAt.getTime()) / 60_000, 0)
            / completedWithDuration.length,
          )
        : 0;

      return { totalOrders: orders.length, pending, completed, delayed, onTime, noSla, avgCycleTimeMins };
    });

    res.json(data);
  } catch (err) { next(err); }
});

const KPI_CATEGORIES = ['PENDING', 'COMPLETED', 'DELAYED', 'ONTIME'] as const;

// Drill-down list behind a KPI card. Same common columns regardless of
// category: order number, start date, current status, best-effort item label.
fmsRouter.get('/analytics/orders', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const category = ((req.query.category as string) || '').toUpperCase();
    if (!(KPI_CATEGORIES as readonly string[]).includes(category)) {
      return res.status(400).json({ error: 'category must be one of PENDING, COMPLETED, DELAYED, ONTIME' });
    }
    const search = (req.query.search as string | undefined)?.trim();
    const from = req.query.from ? new Date(req.query.from as string) : undefined;
    const to = req.query.to ? new Date(req.query.to as string) : undefined;

    const where: any = { orgId };
    if (category === 'PENDING') where.status = 'ACTIVE';
    if (category === 'COMPLETED') where.status = 'COMPLETED';
    if (search) where.orderNumber = { contains: search, mode: 'insensitive' };
    const startedAt = dateRangeFilter(from, to);
    if (startedAt) where.startedAt = startedAt;

    const orders = await prisma.order.findMany({
      where,
      include: { flow: { select: { name: true, stages: { select: { id: true, name: true } } } } },
      orderBy: { startedAt: 'desc' },
      take: 300,
    });

    let scoped = orders;
    if (category === 'DELAYED' || category === 'ONTIME') {
      const slaMap = await classifyOrdersSla(orgId, orders.map(o => ({ id: o.id, flowId: o.flowId })));
      const want = category === 'DELAYED' ? 'DELAYED' : 'ON_TIME';
      scoped = orders.filter(o => slaMap.get(o.id) === want);
    }

    const orderIds = scoped.map(o => o.id);
    const orderStages = orderIds.length
      ? await prisma.orderStage.findMany({
          where: { orgId, orderId: { in: orderIds } },
          select: { orderId: true, sequence: true, data: true },
        })
      : [];
    const stagesByOrder = new Map<string, typeof orderStages>();
    for (const s of orderStages) {
      const arr = stagesByOrder.get(s.orderId) ?? [];
      arr.push(s);
      stagesByOrder.set(s.orderId, arr);
    }

    const result = scoped.map(o => {
      const stageName = o.currentStageId
        ? (o.flow.stages.find(s => s.id === o.currentStageId)?.name ?? '—')
        : '—';
      const status = o.status === 'COMPLETED' ? 'Completed'
        : o.status === 'CANCELLED' ? 'Cancelled'
        : `At: ${stageName}`;
      const detailLabel = deriveOrderDetailLabel(stagesByOrder.get(o.id) ?? [], o.flow.name);

      return {
        id: o.id,
        orderNumber: o.orderNumber,
        startedAt: o.startedAt,
        status,
        detailLabel,
      };
    });

    res.json(result);
  } catch (err) { next(err); }
});