import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { computeNextFire } from './checklist.service';
import { parseListQuery, dateRangeFilter } from '../../lib/listFilters';
import { suggestChecklistItems, logUsage } from '../ai/ai.service';

export const checklistRouter = Router();
checklistRouter.use(requireAuth);

// AI-assisted setup — describe the business/routine in plain language, get
// back suggestions in the same shape POST / already accepts. Never applies
// anything itself, just returns suggestions for the client to preview.
const suggestItemsSchema = z.object({ description: z.string().min(2).max(500) });

checklistRouter.post('/suggest', requireRole('OWNER', 'MANAGER'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = suggestItemsSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId, userId } = req.user!;
    const outcome = await suggestChecklistItems(userId, parsed.data.description);
    await logUsage(userId, orgId, outcome.provider, outcome.model, 'ASSIST', outcome.usage);

    res.json({ items: outcome.items });
  } catch (err) { next(err); }
});

const schema = z.object({
  title: z.string().min(2),
  description: z.string().optional(),
  assigneeId: z.string().uuid(),
  recurrence: z.enum(['DAILY', 'WEEKLY', 'MONTHLY']),
  timeOfDay: z.string().regex(/^\d{2}:\d{2}$/),
  weekdays: z.array(z.number().min(1).max(7)).max(7).optional(),
  dayOfMonth: z.number().min(1).max(28).optional(),
  priority: z.enum(['HIGH', 'NORMAL', 'LOW']).optional(),
});

checklistRouter.post('/', requireRole('OWNER', 'MANAGER'), async (req: Request, res: Response, next: NextFunction) => {
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
        weekdays: parsed.data.weekdays ?? [],
        dayOfMonth: parsed.data.dayOfMonth,
        priority: parsed.data.priority ?? 'NORMAL',
        nextFireAt: await computeNextFire({ ...parsed.data, orgId, weekdays: parsed.data.weekdays ?? [] }),
      },
    });

    res.status(201).json(rule);
  } catch (err) { next(err); }
});

checklistRouter.get('/', async (req: Request, res: Response, next: NextFunction) => {
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
checklistRouter.get('/:id/compliance', requireRole('OWNER', 'MANAGER'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const orgId = req.user!.orgId;
    const [total, done] = await Promise.all([
      prisma.task.count({ where: { orgId, ruleId: req.params.id as string } }),
      prisma.task.count({ where: { orgId, ruleId: req.params.id as string, status: 'DONE' } }),
    ]);
    res.json({ total, done, compliancePct: total > 0 ? Math.round((done / total) * 100) : 0 });
  } catch (err) { next(err); }
});

const updateSchema = z.object({
  assigneeId: z.string().uuid().optional(),
  timeOfDay: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  weekdays: z.array(z.number().min(1).max(7)).max(7).optional(),
  dayOfMonth: z.number().min(1).max(28).optional(),
  priority: z.enum(['HIGH', 'NORMAL', 'LOW']).optional(),
  active: z.boolean().optional(),
});

// Used to finish setting up a template-applied rule — assign the real person
// and (optionally) activate it. Also usable as a general small-edit endpoint.
checklistRouter.patch('/:id', requireRole('OWNER', 'MANAGER'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = updateSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId } = req.user!;
    const rule = await prisma.checklistRule.findFirst({ where: { id: req.params.id as string, orgId } });
    if (!rule) return res.status(404).json({ error: 'Not found' });

    if (parsed.data.assigneeId) {
      const assignee = await prisma.user.findFirst({ where: { id: parsed.data.assigneeId, orgId } });
      if (!assignee) return res.status(404).json({ error: 'Assignee not found in your company' });
    }

    const merged = { ...rule, ...parsed.data };
    const willBeActive = parsed.data.active ?? rule.active;

    const updated = await prisma.checklistRule.update({
      where: { id: rule.id },
      data: {
        ...parsed.data,
        nextFireAt: willBeActive ? await computeNextFire(merged) : null,
      },
    });

    res.json(updated);
  } catch (err) { next(err); }
});

checklistRouter.post('/:id/toggle', requireRole('OWNER', 'MANAGER'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const rule = await prisma.checklistRule.findFirst({
      where: { id: req.params.id as string, orgId: req.user!.orgId },
    });
    if (!rule) return res.status(404).json({ error: 'Not found' });

    const updated = await prisma.checklistRule.update({
      where: { id: rule.id },
      data: {
        active: !rule.active,
        nextFireAt: !rule.active ? await computeNextFire(rule) : null,
      },
    });
    res.json(updated);
  } catch (err) { next(err); }
});