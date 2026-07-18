import { prisma } from '../../lib/prisma';
import { computeFirstAction, notify } from '../engine/engine.service';
import { addWorkingTimeForOrg } from '../engine/working-hours';

// Order ko agle stage pe le jao (ya complete karo)
export async function advanceOrder(orderId: string, orgId: string) {
  const order = await prisma.order.findFirst({
    where: { id: orderId, orgId },
    include: { flow: { include: { stages: { orderBy: { sequence: 'asc' } } } } },
  });
  if (!order) throw new Error('Order not found');

  const done = await prisma.orderStage.findMany({
    where: { orderId, completedAt: { not: null } },
    select: { sequence: true, completedAt: true },
  });
  const doneSeqs = new Set(done.map(d => d.sequence));

  const next = order.flow.stages.find(s => !doneSeqs.has(s.sequence));

  // Saare stage ho gaye → order complete
  if (!next) {
    await prisma.order.update({
      where: { id: orderId },
      data: { status: 'COMPLETED', completedAt: new Date(), currentStageId: null },
    });
    return null;
  }

  // The clock for THIS stage starts at the PREVIOUS stage's actual completion
  // (order.startedAt for the very first stage) — never at "now", so a late
  // upstream stage correctly pushes every downstream deadline out with it.
  const previousStage = done.find(d => d.sequence === next.sequence - 1);
  const previousCompletion = previousStage?.completedAt ?? order.startedAt;

  // Unplanned stages (plannedMins == null) get no deadline and are never
  // chased — but previousCompletion above still flows into them and out the
  // other side via their own completedAt when the NEXT stage is computed.
  const plannedDeadline = next.plannedMins
    ? await addWorkingTimeForOrg(orgId, previousCompletion, next.plannedMins)
    : null;

  const task = next.responsibleId
    ? await prisma.task.create({
        data: {
          orgId,
          title: `${order.orderNumber} — ${next.name}`,
          source: 'FMS_STAGE',
          assigneeId: next.responsibleId,
          createdById: next.responsibleId,
          dueAt: plannedDeadline,
          nextActionAt: plannedDeadline ? await computeFirstAction(orgId, plannedDeadline) : null,
        },
      })
    : null;

  const os = await prisma.orderStage.create({
    data: {
      orgId,
      orderId,
      stageId: next.id,
      sequence: next.sequence,
      taskId: task?.id,
      enteredAt: new Date(),
      plannedDeadline,
    },
  });

  await prisma.order.update({
    where: { id: orderId },
    data: { currentStageId: next.id },
  });

  if (next.responsibleId) {
    await notify(orgId, next.responsibleId, 'FMS_STAGE', `${order.orderNumber} — ${next.name}`, 'An order has reached your stage.', task?.id);
  }

  console.log(`🏭 ${order.orderNumber} → ${next.name}`);
  return os;
}