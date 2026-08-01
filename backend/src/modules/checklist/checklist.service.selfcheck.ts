// Assert-based self-check for computeNextFire's two composed pieces —
// multi-weekday selection and the holiday/working-hours skip. No DB, no
// framework: `npx tsx src/modules/checklist/checklist.service.selfcheck.ts`.
import assert from 'node:assert';
import { prisma } from '../../lib/prisma';
import { candidateForWeekday, computeNextFire } from './checklist.service';
import { nextWorkingMoment, getLocalParts, type OrgHours } from '../engine/working-hours';

const TZ = 'Asia/Kolkata';

async function main() {
  // Mon/Wed/Fri, "now" = Wed 08:00 IST, target time-of-day = Wed 09:00 IST
  // (same day, still ahead of "now") → nearest pick is today, not next Wednesday.
  {
    const from = new Date('2026-08-05T02:30:00Z'); // Wed 2026-08-05, 08:00 IST
    const fromLocal = getLocalParts(from, TZ);
    const targets = [1, 3, 5];
    const picked = targets
      .map(t => candidateForWeekday(fromLocal, t, from, 9, 0, TZ))
      .sort((a, b) => a.getTime() - b.getTime())[0]!;
    const pickedLocal = getLocalParts(picked, TZ);
    assert.strictEqual(pickedLocal.isoWeekday, 3, 'nearest of Mon/Wed/Fri from Wednesday morning should land on Wednesday');
    assert.strictEqual(pickedLocal.day, 5, 'and specifically today (2026-08-05), not next week');
    assert.strictEqual(pickedLocal.hour, 9, 'must land at 09:00 IST regardless of server timezone');
  }

  // "Every weekday" (Mon-Fri) from a Saturday should land on the next Monday.
  {
    const saturday = new Date('2026-08-08T03:30:00Z'); // Sat 2026-08-08, 09:00 IST
    const saturdayLocal = getLocalParts(saturday, TZ);
    const targets = [1, 2, 3, 4, 5];
    const picked = targets
      .map(t => candidateForWeekday(saturdayLocal, t, saturday, 9, 0, TZ))
      .sort((a, b) => a.getTime() - b.getTime())[0]!;
    const pickedLocal = getLocalParts(picked, TZ);
    assert.strictEqual(pickedLocal.isoWeekday, 1, 'every-weekday set from a Saturday should land on the next Monday');
    assert.strictEqual(pickedLocal.day, 10, 'that Monday should be 2026-08-10');
  }

  // Holiday skip: a candidate landing on an org holiday pushes to the next
  // working, non-holiday day's shift start (mirrors the working-hours gate).
  {
    const org: OrgHours = {
      timezone: 'Asia/Kolkata',
      workingDays: [1, 2, 3, 4, 5, 6],
      shiftStart: '09:00',
      shiftEnd: '18:00',
      holidays: ['2026-08-10'], // the Monday landed on above
    };
    const candidate = new Date('2026-08-10T03:30:00Z'); // 09:00 IST on the holiday
    const pushed = nextWorkingMoment(candidate, org);
    assert.strictEqual(pushed.getTime() === candidate.getTime(), false, 'a holiday candidate must be pushed forward');
    const iso = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata' }).format(pushed);
    assert.strictEqual(iso, '2026-08-11', 'should skip the 8/10 holiday and land on 8/11 (Tuesday)');
  }

  // Off-hours candidate on a normal working day lands at that day's shift start.
  {
    const org: OrgHours = {
      timezone: 'Asia/Kolkata',
      workingDays: [1, 2, 3, 4, 5, 6],
      shiftStart: '09:00',
      shiftEnd: '18:00',
      holidays: [],
    };
    const earlyCandidate = new Date('2026-08-11T01:00:00Z'); // 06:30 IST, before shift start
    const pushed = nextWorkingMoment(earlyCandidate, org);
    const hhmm = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Asia/Kolkata', hour: '2-digit', minute: '2-digit', hour12: false,
    }).format(pushed);
    assert.strictEqual(hhmm, '09:00', 'an off-hours candidate should push to that same day\'s shift start');
  }

  // computeNextFire must honor the ORG's timezone regardless of what timezone
  // the Node process itself runs in — this was the actual production bug: the
  // old code used Date.setHours() to set the wall-clock hour in the SERVER's
  // local timezone (UTC on Render), so a "09:00" checklist could fire at
  // 09:00 UTC (2:30pm IST) instead of 09:00 IST. Uses a real org row since
  // computeNextFire loads org hours from the DB.
  {
    const org = await prisma.organization.findFirst();
    if (org) {
      const from = new Date('2026-08-05T02:30:00Z'); // 08:00 IST, well before 09:00

      const daily = await computeNextFire(
        { orgId: org.id, recurrence: 'DAILY', timeOfDay: '09:00', weekdays: [] }, from,
      );
      assert.strictEqual(getLocalParts(daily, org.timezone).hour, 9, `DAILY "09:00" must land at 09:00 in ${org.timezone}, not the server's timezone`);

      const weekly = await computeNextFire(
        { orgId: org.id, recurrence: 'WEEKLY', timeOfDay: '09:00', weekdays: [3, 5] }, from,
      );
      assert.strictEqual(getLocalParts(weekly, org.timezone).hour, 9, `WEEKLY "09:00" must land at 09:00 in ${org.timezone}`);

      const monthly = await computeNextFire(
        { orgId: org.id, recurrence: 'MONTHLY', timeOfDay: '09:00', weekdays: [], dayOfMonth: 15 }, from,
      );
      assert.strictEqual(getLocalParts(monthly, org.timezone).hour, 9, `MONTHLY "09:00" must land at 09:00 in ${org.timezone}`);
    }
  }

  console.log('checklist.service self-check: all assertions passed');
}

main()
  .catch(err => { console.error(err); process.exitCode = 1; })
  .finally(() => prisma.$disconnect());
