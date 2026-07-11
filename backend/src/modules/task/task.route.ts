import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { computeFirstAction } from '../engine/engine.service';

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
        nextActionAt: computeFirstAction(dueAt),
      },
    });

    await prisma.notification.create({
      data: {
        orgId, userId: assignee.id, type: 'TASK_ASSIGNED',
        title: `New task: ${task.title}`, body: 'You have been assigned a new task.', taskId: task.id,
      },
    });

    res.status(201).json(task);
  } catch (err) { next(err); }
});

// Mere tasks
taskRouter.get('/my', async (req, res, next) => {
  try {
    const tasks = await prisma.task.findMany({
      where: { orgId: req.user!.orgId, assigneeId: req.user!.userId, status: { notIn: ['DONE', 'CANCELLED'] } },
      orderBy: { dueAt: 'asc' },
    });
    res.json(tasks);
  } catch (err) { next(err); }
});

// DONE — chasing turant band
taskRouter.post('/:id/done', async (req, res, next) => {
  try {
    const task = await prisma.task.findFirst({
      where: { id: req.params.id, orgId: req.user!.orgId, assigneeId: req.user!.userId },
    });
    if (!task) return res.status(404).json({ error: 'Task not found' });

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
      where: { id: req.params.id, orgId: req.user!.orgId, assigneeId: req.user!.userId },
    });
    if (!task) return res.status(404).json({ error: 'Task not found' });

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