import { prisma } from '../../lib/prisma';
import { computeFirstAction, notify } from '../engine/engine.service';
import { nextWorkingMoment, loadOrgHours, getLocalParts, zonedTimeToUtc, type LocalParts } from '../engine/working-hours';

// Candidate WEEKLY fire date for one target weekday, built from the org-local
// calendar date of `from` (not the server's local date) — `timeOfDay` is an
// org-local wall-clock time, so "today" and "already passed" must be judged
// in the org's timezone, not the server's.
export function candidateForWeekday(
  fromLocal: LocalParts, target: number, from: Date, h: number, m: number, timezone: string,
): Date {
  let diff = target - fromLocal.isoWeekday; // 1=Mon ... 7=Sun
  if (diff < 0) diff += 7;
  let candidate = zonedTimeToUtc(fromLocal.year, fromLocal.month, fromLocal.day + diff, h, m, timezone);
  if (diff === 0 && candidate <= from) {
    candidate = zonedTimeToUtc(fromLocal.year, fromLocal.month, fromLocal.day + diff + 7, h, m, timezone);
  }
  return candidate;
}

// Agla occurrence kab? (sirf agla — infinite rows nahi banate)
// timeOfDay is an org-local wall-clock time ("09:00" means 9am in the org's
// own timezone, not the server's) — every candidate is built via
// zonedTimeToUtc/getLocalParts (see engine/working-hours.ts) so this is
// correct regardless of what timezone the server itself runs in. The naive
// next occurrence is then pushed off holidays/non-working days via the same
// working-hours gate the rest of the engine uses — a checklist due on a
// holiday skips forward to the next working day's shift start instead of
// firing off-hours.
export async function computeNextFire(rule: {
  orgId: string;
  recurrence: string;
  timeOfDay: string;
  weekdays: number[];
  dayOfMonth?: number | null;
}, from: Date = new Date()): Promise<Date> {
  const org = await loadOrgHours(rule.orgId);
  const timezone = org?.timezone ?? 'UTC'; // fail-open, same spirit as applyWorkingHours
  const [h, m] = rule.timeOfDay.split(':').map(Number);
  const fromLocal = getLocalParts(from, timezone);

  let candidate: Date;

  if (rule.recurrence === 'DAILY') {
    candidate = zonedTimeToUtc(fromLocal.year, fromLocal.month, fromLocal.day, h, m, timezone);
    if (candidate <= from) candidate = zonedTimeToUtc(fromLocal.year, fromLocal.month, fromLocal.day + 1, h, m, timezone);
  } else if (rule.recurrence === 'WEEKLY') {
    const targets = rule.weekdays.length ? rule.weekdays : [1]; // 1=Mon ... 7=Sun
    candidate = targets
      .map(target => candidateForWeekday(fromLocal, target, from, h, m, timezone))
      .sort((a, b) => a.getTime() - b.getTime())[0]!;
  } else {
    // MONTHLY
    const dom = rule.dayOfMonth ?? 1;
    candidate = zonedTimeToUtc(fromLocal.year, fromLocal.month, dom, h, m, timezone);
    if (candidate <= from) candidate = zonedTimeToUtc(fromLocal.year, fromLocal.month + 1, dom, h, m, timezone);
  }

  return org ? nextWorkingMoment(candidate, org) : candidate;
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
        nextFireAt: await computeNextFire(rule, new Date(dueAt.getTime() + 60_000)),
      },
    });

    console.log(`📋 Checklist fired: ${rule.title}`);
  }
}