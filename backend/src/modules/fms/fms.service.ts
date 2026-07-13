import { prisma } from '../../lib/prisma';
import { computeFirstAction } from '../engine/engine.service';

// Order ko agle stage pe le jao (ya complete karo)
export async function advanceOrder(orderId: string, orgId: string) {
  const order = await prisma.order.findFirst({
    where: { id: orderId, orgId },
    include: { flow: { include: { stages: { orderBy: { sequence: 'asc' } } } } },
  });
  if (!order) throw new Error('Order not found');

  const done = await prisma.orderStage.findMany({
    where: { orderId, completedAt: { not: null } },
    select: { sequence: true },
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

  // Agle stage ka task banao — engine isko chase karega
  const dueAt = next.plannedMins
    ? new Date(Date.now() + next.plannedMins * 60_000)
    : null;

  const task = next.responsibleId
    ? await prisma.task.create({
        data: {
          orgId,
          title: `${order.orderNumber} — ${next.name}`,
          source: 'FMS_STAGE',
          assigneeId: next.responsibleId,
          createdById: next.responsibleId,
          dueAt,
          nextActionAt: computeFirstAction(dueAt),
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
    },
  });

  await prisma.order.update({
    where: { id: orderId },
    data: { currentStageId: next.id },
  });

  if (next.responsibleId) {
    await prisma.notification.create({
      data: {
        orgId,
        userId: next.responsibleId,
        type: 'FMS_STAGE',
        title: `${order.orderNumber} — ${next.name}`,
        body: 'An order has reached your stage.',
        taskId: task?.id,
      },
    });
  }

  console.log(`🏭 ${order.orderNumber} → ${next.name}`);
  return os;
}