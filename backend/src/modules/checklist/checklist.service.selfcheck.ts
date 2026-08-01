// Assert-based self-check for computeNextFire's two composed pieces —
// multi-weekday selection and the holiday/working-hours skip. No DB, no
// framework: `npx tsx src/modules/checklist/checklist.service.selfcheck.ts`.
import assert from 'node:assert';
import { candidateForWeekday } from './checklist.service';
import { nextWorkingMoment, type OrgHours } from '../engine/working-hours';

// candidateForWeekday works in server-local time (like the pre-existing
// single-weekday code it replaces) — dates below use local components so
// the "today, before the target time" edge case is unambiguous.

// Mon/Wed/Fri, "now" = Wed 08:00, target time-of-day = Wed 09:00 (same day,
// still ahead of "now") → nearest pick is today, not next Wednesday.
{
  const from = new Date(2026, 7, 5, 8, 0, 0); // Wed 2026-08-05, 08:00 local
  const base = new Date(2026, 7, 5, 9, 0, 0); // same day, candidate time-of-day
  const targets = [1, 3, 5];
  const picked = targets
    .map(t => candidateForWeekday(base, t, from))
    .sort((a, b) => a.getTime() - b.getTime())[0]!;
  assert.strictEqual(picked.getDay(), 3, 'nearest of Mon/Wed/Fri from Wednesday morning should land on Wednesday');
  assert.strictEqual(picked.getDate(), 5, 'and specifically today (2026-08-05), not next week');
}

// "Every weekday" (Mon-Fri) from a Saturday should land on the next Monday.
{
  const saturday = new Date(2026, 7, 8, 9, 0, 0); // Sat 2026-08-08
  const targets = [1, 2, 3, 4, 5];
  const picked = targets
    .map(t => candidateForWeekday(saturday, t, saturday))
    .sort((a, b) => a.getTime() - b.getTime())[0]!;
  assert.strictEqual(picked.getDay(), 1, 'every-weekday set from a Saturday should land on the next Monday');
  assert.strictEqual(picked.getDate(), 10, 'that Monday should be 2026-08-10');
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

console.log('checklist.service self-check: all assertions passed');
