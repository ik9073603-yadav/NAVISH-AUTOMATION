import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { computeNextFire } from './checklist.service';
import { parseListQuery, dateRangeFilter } from '../../lib/listFilters';

export const checklistRouter = Router();
checklistRouter.use(requireAuth);

const schema = z.object({
  title: z.string().min(2),
  description: z.string().optional(),
  assigneeId: z.string().uuid(),
  recurrence: z.enum(['DAILY', 'WEEKLY', 'MONTHLY']),
  timeOfDay: z.string().regex(/^\d{2}:\d{2}$/),
  weekday: z.number().min(1).max(7).optional(),
  dayOfMonth: z.number().min(1).max(28).optional(),
  priority: z.enum(['HIGH', 'NORMAL', 'LOW']).optional(),
});

checklistRouter.post('/', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId, userId } = req.user!;

    const assignee = await prisma.user.findFirst({ where: { id: parsed.data.assigneeId, orgId } });
    if (!assignee) return res.status(404).json({ error: 'Assignee not found in your company' });

    const rule = await prisma.checklistRule.create({
      data: {
        orgId,
        title: parsed.data.title,
        description: parsed.data.description,
        assigneeId: parsed.data.assigneeId,
        createdById: userId,
        recurrence: parsed.data.recurrence,
        timeOfDay: parsed.data.timeOfDay,
        weekday: parsed.data.weekday,
        dayOfMonth: parsed.data.dayOfMonth,
        priority: parsed.data.priority ?? 'NORMAL',
        nextFireAt: computeNextFire(parsed.data as any),
      },
    });

    res.status(201).json(rule);
  } catch (err) { next(err); }
});

checklistRouter.get('/', async (req, res, next) => {
  try {
    const { status, from, to, assigneeId } = parseListQuery(req);
    const where: any = { orgId: req.user!.orgId };
    if (status === 'ACTIVE') where.active = true;
    else if (status === 'DONE') where.active = false;
    if (assigneeId) where.assigneeId = assigneeId;
    const createdAt = dateRangeFilter(from, to);
    if (createdAt) where.createdAt = createdAt;

    const rules = await prisma.checklistRule.findMany({
      where,
      orderBy: { createdAt: 'desc' },
    });

    const users = await prisma.user.findMany({
      where: { orgId: req.user!.orgId },
      select: { id: true, name: true },
    });
    const nameById = Object.fromEntries(users.map(u => [u.id, u.name]));

    res.json(rules.map(r => ({ ...r, assigneeName: nameById[r.assigneeId] ?? 'Unknown' })));
  } catch (err) { next(err); }
});

// Compliance % (Feature 81)
checklistRouter.get('/:id/compliance', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const orgId = req.user!.orgId;
    const [total, done] = await Promise.all([
      prisma.task.count({ where: { orgId, ruleId: req.params.id } }),
      prisma.task.count({ where: { orgId, ruleId: req.params.id, status: 'DONE' } }),
    ]);
    res.json({ total, done, compliancePct: total > 0 ? Math.round((done / total) * 100) : 0 });
  } catch (err) { next(err); }
});

checklistRouter.post('/:id/toggle', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const rule = await prisma.checklistRule.findFirst({
      where: { id: req.params.id, orgId: req.user!.orgId },
    });
    if (!rule) return res.status(404).json({ error: 'Not found' });

    const updated = await prisma.checklistRule.update({
      where: { id: rule.id },
      data: {
        active: !rule.active,
        nextFireAt: !rule.active ? computeNextFire(rule as any) : null,
      },
    });
    res.json(updated);
  } catch (err) { next(err); }
});