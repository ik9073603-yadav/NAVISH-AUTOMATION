import { prisma } from '../../lib/prisma';
import { sendPush } from '../../lib/fcm';
import {
  CHASE_AFTER_MINUTES,
  CHASE_REPEAT_MINUTES,
  MAX_CHASES_BEFORE_ESCALATE,
  ESCALATE_AFTER_MINUTES,
} from './engine.config';
import { applyWorkingHours } from './working-hours';

const mins = (n: number) => new Date(Date.now() + n * 60_000);

// The ONE place every module funnels through to reach a user — in-app row +
// real push, together. Wire new alert types here, never call sendPush() directly.
export async function notify(orgId: string, userId: string, type: string, title: string, body: string, taskId?: string) {
  await prisma.notification.create({
    data: { orgId, userId, type, title, body, taskId },
  });
  console.log(`🔔 [${type}] → user ${userId}: ${title}`);
  await sendPush(userId, title, body, { type, taskId: taskId ?? '' });
}

// Overdue task → responsible person ko ping
export async function chaseTask(taskId: string) {
  const task = await prisma.task.findUnique({ where: { id: taskId } });
  if (!task || task.status === 'DONE' || task.status === 'CANCELLED') return;

  const chaseCount = task.chaseCount + 1;
  const shouldEscalateNext = chaseCount >= MAX_CHASES_BEFORE_ESCALATE;

  await notify(
    task.orgId,
    task.assigneeId,
    'CHASE',
    `Reminder: ${task.title}`,
    `This task is overdue. Reminder ${chaseCount}.`,
    task.id,
  );

  const naive = shouldEscalateNext ? mins(ESCALATE_AFTER_MINUTES) : mins(CHASE_REPEAT_MINUTES);

  await prisma.task.update({
    where: { id: task.id },
    data: {
      chaseCount,
      nextActionAt: await applyWorkingHours(task.orgId, naive),
    },
  });

  await prisma.activityLog.create({
    data: { orgId: task.orgId, action: 'TASK_CHASED', entity: 'Task', entityId: task.id, meta: { chaseCount } },
  });
}

// Jawab nahi mila → manager ko escalate (kabhi owner ko nahi — Feature 122)
export async function escalateTask(taskId: string) {
  const task = await prisma.task.findUnique({ where: { id: taskId } });
  if (!task || task.status === 'DONE' || task.status === 'CANCELLED') return;

  const assignee = await prisma.user.findUnique({ where: { id: task.assigneeId } });
  const managerId = assignee?.managerId;

  if (!managerId) {
    // Manager nahi hai → chasing band, warna infinite loop
    await prisma.task.update({ where: { id: task.id }, data: { nextActionAt: null } });
    return;
  }

  await notify(
    task.orgId,
    managerId,
    'ESCALATION',
    `Escalated: ${task.title}`,
    `${assignee?.name} has not completed this task after ${task.chaseCount} reminders.`,
    task.id,
  );

  await prisma.task.update({
    where: { id: task.id },
    data: { escalatedAt: new Date(), escalatedToId: managerId, nextActionAt: null },
  });

  await prisma.activityLog.create({
    data: { orgId: task.orgId, action: 'TASK_ESCALATED', entity: 'Task', entityId: task.id, meta: { managerId } },
  });
}

// Har task ka pehla nextActionAt set karna — pushed out of dead hours if needed.
export async function computeFirstAction(orgId: string, dueAt: Date | null): Promise<Date | null> {
  if (!dueAt) return null;
  const naive = new Date(dueAt.getTime() + CHASE_AFTER_MINUTES * 60_000);
  return applyWorkingHours(orgId, naive);
}