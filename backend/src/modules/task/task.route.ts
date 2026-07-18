import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { computeFirstAction, notify } from '../engine/engine.service';
import { parseListQuery, dateRangeFilter } from '../../lib/listFilters';

export const taskRouter = Router();
taskRouter.use(requireAuth);

const createSchema = z.object({
  title: z.string().min(2),
  description: z.string().optional(),
  assigneeId: z.string().uuid(),
  dueAt: z.string().datetime().optional(),
  priority: z.enum(['HIGH', 'NORMAL', 'LOW']).optional(),
});

// Task assign karo (Owner/Manager only)
taskRouter.post('/', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const parsed = createSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId, userId } = req.user!;

    // Assignee usi company ka hona chahiye
    const assignee = await prisma.user.findFirst({ where: { id: parsed.data.assigneeId, orgId } });
    if (!assignee) return res.status(404).json({ error: 'Assignee not found in your company' });

    const dueAt = parsed.data.dueAt ? new Date(parsed.data.dueAt) : null;

    const task = await prisma.task.create({
      data: {
        orgId,
        title: parsed.data.title,
        description: parsed.data.description,
        assigneeId: parsed.data.assigneeId,
        createdById: userId,
        dueAt,
        priority: parsed.data.priority ?? 'NORMAL',
        nextActionAt: await computeFirstAction(orgId, dueAt),
      },
    });

    await notify(orgId, assignee.id, 'TASK_ASSIGNED', `New task: ${task.title}`, 'You have been assigned a new task.', task.id);

    res.status(201).json(task);
  } catch (err) { next(err); }
});

// Mere tasks
taskRouter.get('/my', async (req, res, next) => {
  try {
    const { status, from, to } = parseListQuery(req);
    const where: any = { orgId: req.user!.orgId, assigneeId: req.user!.userId };
    if (status === 'ACTIVE') where.status = { in: ['PENDING', 'IN_PROGRESS', 'STUCK'] };
    else if (status === 'DONE') where.status = { in: ['DONE', 'CANCELLED'] };
    const createdAt = dateRangeFilter(from, to);
    if (createdAt) where.createdAt = createdAt;

    const tasks = await prisma.task.findMany({ where, orderBy: { dueAt: 'asc' } });
    res.json(tasks);
  } catch (err) { next(err); }
});

// DONE — chasing turant band
taskRouter.post('/:id/done', async (req, res, next) => {
  try {
    const task = await prisma.task.findFirst({
      where: { id: req.params.id, orgId: req.user!.orgId },
    });
    if (!task) return res.status(404).json({ error: 'Task not found' });

    // Owner is read-only everywhere EXCEPT inventory alerts — those are assigned
    // to him by design since there's no one else below him for stock decisions.
    const ownerExempt = req.user!.role === 'OWNER' && task.source === 'INVENTORY_ALERT';
    if (task.assigneeId !== req.user!.userId || (req.user!.role === 'OWNER' && !ownerExempt)) {
      return res.status(403).json({ error: 'Only the assignee can complete this task' });
    }

    const updated = await prisma.task.update({
      where: { id: task.id },
      data: { status: 'DONE', completedAt: new Date(), nextActionAt: null },  // ← chasing stops
    });

    await prisma.activityLog.create({
      data: { orgId: task.orgId, actorId: req.user!.userId, action: 'TASK_DONE', entity: 'Task', entityId: task.id },
    });

    res.json(updated);
  } catch (err) { next(err); }
});

// STUCK — reason ke saath
taskRouter.post('/:id/stuck', async (req, res, next) => {
  try {
    const reason = z.object({ reason: z.string().min(2) }).safeParse(req.body);
    if (!reason.success) return res.status(400).json({ error: 'Reason required' });

    const task = await prisma.task.findFirst({
      where: { id: req.params.id, orgId: req.user!.orgId },
    });
    if (!task) return res.status(404).json({ error: 'Task not found' });

    const ownerExempt = req.user!.role === 'OWNER' && task.source === 'INVENTORY_ALERT';
    if (task.assigneeId !== req.user!.userId || (req.user!.role === 'OWNER' && !ownerExempt)) {
      return res.status(403).json({ error: 'Only the assignee can mark this task stuck' });
    }

    const updated = await prisma.task.update({
      where: { id: task.id },
      data: { status: 'STUCK', stuckReason: reason.data.reason },
    });

    res.json(updated);
  } catch (err) { next(err); }
});

// Notifications dekho
taskRouter.get('/notifications', async (req, res, next) => {
  try {
    const items = await prisma.notification.findMany({
      where: { orgId: req.user!.orgId, userId: req.user!.userId },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    res.json(items);
  } catch (err) { next(err); }
});

// Owner/Manager: company ke saare tasks
taskRouter.get('/all', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const { status, from, to, assigneeId } = parseListQuery(req);
    const where: any = { orgId: req.user!.orgId };
    if (status === 'ACTIVE') where.status = { in: ['PENDING', 'IN_PROGRESS', 'STUCK'] };
    else if (status === 'DONE') where.status = { in: ['DONE', 'CANCELLED'] };
    if (assigneeId) where.assigneeId = assigneeId;
    const createdAt = dateRangeFilter(from, to);
    if (createdAt) where.createdAt = createdAt;

    const tasks = await prisma.task.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: 100,
    });

    // Assignee ke naam bhi bhejo
    const users = await prisma.user.findMany({
      where: { orgId: req.user!.orgId },
      select: { id: true, name: true },
    });
    const nameById = Object.fromEntries(users.map(u => [u.id, u.name]));

    res.json(tasks.map(t => ({ ...t, assigneeName: nameById[t.assigneeId] ?? 'Unknown' })));
  } catch (err) { next(err); }
});

// Bulk assign — ek command, kai log (Feature 124)
taskRouter.post('/bulk', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const schema = z.object({
      title: z.string().min(2),
      description: z.string().optional(),
      assigneeIds: z.array(z.string().uuid()).min(1),
      dueAt: z.string().datetime().optional(),
      priority: z.enum(['HIGH', 'NORMAL', 'LOW']).optional(),
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed' });

    const { orgId, userId } = req.user!;
    const dueAt = parsed.data.dueAt ? new Date(parsed.data.dueAt) : null;

    const valid = await prisma.user.findMany({
      where: { id: { in: parsed.data.assigneeIds }, orgId },
      select: { id: true },
    });

    const nextActionAt = await computeFirstAction(orgId, dueAt);

    const created = await Promise.all(valid.map(u =>
      prisma.task.create({
        data: {
          orgId,
          title: parsed.data.title,
          description: parsed.data.description,
          assigneeId: u.id,
          createdById: userId,
          dueAt,
          priority: parsed.data.priority ?? 'NORMAL',
          nextActionAt,
        },
      })
    ));

    res.status(201).json({ created: created.length, tasks: created });
  } catch (err) { next(err); }
});

// Employee performance (Feature 69)
taskRouter.get('/stats', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const orgId = req.user!.orgId;
    const users = await prisma.user.findMany({
      where: { orgId, status: 'ACTIVE' },
      select: { id: true, name: true },
    });

    const stats = await Promise.all(users.map(async (u) => {
      const [total, done, escalated] = await Promise.all([
        prisma.task.count({ where: { orgId, assigneeId: u.id } }),
        prisma.task.count({ where: { orgId, assigneeId: u.id, status: 'DONE' } }),
        prisma.task.count({ where: { orgId, assigneeId: u.id, escalatedAt: { not: null } } }),
      ]);
      const onTime = await prisma.task.count({
        where: { orgId, assigneeId: u.id, status: 'DONE', escalatedAt: null },
      });
      return {
        userId: u.id,
        name: u.name,
        total,
        done,
        pending: total - done,
        escalated,
        onTimePct: done > 0 ? Math.round((onTime / done) * 100) : 0,
      };
    }));

    res.json(stats.filter(s => s.total > 0));
  } catch (err) { next(err); }
});