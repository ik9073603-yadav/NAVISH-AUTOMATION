import { prisma } from '../../lib/prisma';
import { computeFirstAction, notify } from '../engine/engine.service';

// Agla occurrence kab? (sirf agla — infinite rows nahi banate)
export function computeNextFire(rule: {
  recurrence: string;
  timeOfDay: string;
  weekday: number | null;
  dayOfMonth: number | null;
}, from: Date = new Date()): Date {
  const [h, m] = rule.timeOfDay.split(':').map(Number);
  const next = new Date(from);
  next.setSeconds(0, 0);
  next.setHours(h, m);

  if (rule.recurrence === 'DAILY') {
    if (next <= from) next.setDate(next.getDate() + 1);
    return next;
  }

  if (rule.recurrence === 'WEEKLY') {
    const target = rule.weekday ?? 1;            // 1=Mon ... 7=Sun
    const current = next.getDay() === 0 ? 7 : next.getDay();
    let diff = target - current;
    if (diff < 0 || (diff === 0 && next <= from)) diff += 7;
    next.setDate(next.getDate() + diff);
    return next;
  }

  // MONTHLY
  const dom = rule.dayOfMonth ?? 1;
  next.setDate(dom);
  if (next <= from) next.setMonth(next.getMonth() + 1);
  return next;
}

// Scheduler yeh har minute chalayega
export async function fireDueChecklists() {
  const due = await prisma.checklistRule.findMany({
    where: { active: true, nextFireAt: { lte: new Date() } },
    take: 50,
  });

  for (const rule of due) {
    const dueAt = rule.nextFireAt!;

    const task = await prisma.task.create({
      data: {
        orgId: rule.orgId,
        title: rule.title,
        description: rule.description,
        source: 'CHECKLIST',
        assigneeId: rule.assigneeId,
        createdById: rule.createdById,
        dueAt,
        priority: rule.priority,
        ruleId: rule.id,
        nextActionAt: await computeFirstAction(rule.orgId, dueAt),   // engine yahan se chase karega
      },
    });

    await notify(rule.orgId, rule.assigneeId, 'CHECKLIST_DUE', rule.title, 'Your recurring checklist is due.', task.id);

    // Agla occurrence set karo
    await prisma.checklistRule.update({
      where: { id: rule.id },
      data: {
        lastFiredAt: new Date(),
        nextFireAt: computeNextFire(rule, new Date(dueAt.getTime() + 60_000)),
      },
    });

    console.log(`📋 Checklist fired: ${rule.title}`);
  }
}