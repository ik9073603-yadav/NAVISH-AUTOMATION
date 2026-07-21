import { prisma } from '../../lib/prisma';

export interface OrgHours {
  timezone: string;
  workingDays: number[]; // ISO weekday: 1=Mon ... 7=Sun
  shiftStart: string;    // "HH:mm"
  shiftEnd: string;      // "HH:mm"
  holidays: string[];    // "YYYY-MM-DD", org-local calendar date
}

interface LocalParts {
  year: number;
  month: number; // 1-12
  day: number;
  hour: number;
  minute: number;
  isoWeekday: number; // 1=Mon ... 7=Sun
  dateStr: string;    // "YYYY-MM-DD"
}

const WEEKDAY_TO_ISO: Record<string, number> = {
  Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7,
};

// Reads the wall-clock date/time an instant corresponds to in a given IANA
// timezone — dependency-free (Intl handles DST/offset rules correctly).
function getLocalParts(instant: Date, timezone: string): LocalParts {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hour12: false, weekday: 'short',
  });
  const map: Record<string, string> = {};
  for (const p of fmt.formatToParts(instant)) map[p.type] = p.value;

  const year = Number(map.year);
  const month = Number(map.month);
  const day = Number(map.day);
  const hour = Number(map.hour) % 24; // Intl can emit "24" for midnight
  const minute = Number(map.minute);

  return {
    year, month, day, hour, minute,
    isoWeekday: WEEKDAY_TO_ISO[map.weekday],
    dateStr: `${map.year}-${map.month}-${map.day}`,
  };
}

// Inverse of getLocalParts: what UTC instant corresponds to this wall-clock
// time in the given timezone. Standard "double conversion" trick so DST
// offsets resolve correctly without a date library.
function zonedTimeToUtc(year: number, month: number, day: number, hour: number, minute: number, timezone: string): Date {
  const guess = new Date(Date.UTC(year, month - 1, day, hour, minute, 0));
  const local = getLocalParts(guess, timezone);
  const localAsUtc = Date.UTC(local.year, local.month - 1, local.day, local.hour, local.minute, 0);
  const offsetMs = localAsUtc - guess.getTime();
  return new Date(guess.getTime() - offsetMs);
}

// Shift start of the next qualifying working, non-holiday day AFTER the given
// local calendar date (never the date itself) — shared by nextWorkingMoment's
// "push forward" fallback and addWorkingTime's day-rollover, so both walk the
// calendar identically. Noon-UTC anchor avoids midnight/DST edge cases; we
// only care about the resulting local calendar date.
function startOfNextWorkingDay(year: number, month: number, day: number, org: OrgHours): Date {
  const [startH, startM] = org.shiftStart.split(':').map(Number);
  for (let i = 1; i <= 14; i++) {
    const probe = new Date(Date.UTC(year, month - 1, day + i, 12, 0, 0));
    const parts = getLocalParts(probe, org.timezone);
    if (org.workingDays.includes(parts.isoWeekday) && !org.holidays.includes(parts.dateStr)) {
      return zonedTimeToUtc(parts.year, parts.month, parts.day, startH, startM, org.timezone);
    }
  }
  // 14 non-working days in a row shouldn't happen — fail open onto day+1's shift start.
  return zonedTimeToUtc(year, month, day + 1, startH, startM, org.timezone);
}

// If `candidate` falls inside the org's working hours, returns it unchanged.
// Otherwise pushes it forward to shiftStart of the next working, non-holiday day.
export function nextWorkingMoment(candidate: Date, org: OrgHours): Date {
  const [startH, startM] = org.shiftStart.split(':').map(Number);
  const [endH, endM] = org.shiftEnd.split(':').map(Number);
  const startMinutes = startH * 60 + startM;
  const endMinutes = endH * 60 + endM;

  const local = getLocalParts(candidate, org.timezone);
  const minutesNow = local.hour * 60 + local.minute;
  const isWorkingDay = org.workingDays.includes(local.isoWeekday);
  const isHoliday = org.holidays.includes(local.dateStr);

  if (isWorkingDay && !isHoliday && minutesNow >= startMinutes && minutesNow < endMinutes) {
    return candidate;
  }

  // Still before today's shift start, and today is a working day → land today.
  if (isWorkingDay && !isHoliday && minutesNow < startMinutes) {
    return zonedTimeToUtc(local.year, local.month, local.day, startH, startM, org.timezone);
  }

  return startOfNextWorkingDay(local.year, local.month, local.day, org);
}

// Walks forward from `start`, consuming ONLY working minutes — time outside
// the shift, on a week-off day, or on a holiday doesn't count and is skipped.
// This is the single shared implementation for any "deadline N working-minutes
// from now" calculation; do not duplicate this calendar logic elsewhere.
export function addWorkingTime(start: Date, durationMinutes: number, org: OrgHours): Date {
  const [endH, endM] = org.shiftEnd.split(':').map(Number);
  const endMinutes = endH * 60 + endM;

  let cursor = nextWorkingMoment(start, org);
  let remaining = durationMinutes;

  while (remaining > 0) {
    const local = getLocalParts(cursor, org.timezone);
    const minutesNow = local.hour * 60 + local.minute;
    const availableToday = endMinutes - minutesNow;

    if (remaining <= availableToday) {
      return new Date(cursor.getTime() + remaining * 60_000);
    }

    remaining -= availableToday;
    cursor = startOfNextWorkingDay(local.year, local.month, local.day, org);
  }

  return cursor;
}

// Inverse of addWorkingTime: how many WORKING minutes elapse between two
// instants — time outside the shift, on a week-off day, or on a holiday
// doesn't count. Mirrors addWorkingTime's day-walking loop exactly (same
// nextWorkingMoment/startOfNextWorkingDay helpers) so the two stay in sync.
export function workingMinutesBetween(start: Date, end: Date, org: OrgHours): number {
  if (end.getTime() <= start.getTime()) return 0;

  const [endH, endM] = org.shiftEnd.split(':').map(Number);

  let cursor = nextWorkingMoment(start, org);
  if (cursor.getTime() >= end.getTime()) return 0;

  let totalMinutes = 0;
  while (cursor.getTime() < end.getTime()) {
    const local = getLocalParts(cursor, org.timezone);
    const dayEnd = zonedTimeToUtc(local.year, local.month, local.day, endH, endM, org.timezone);
    const segmentEnd = dayEnd.getTime() < end.getTime() ? dayEnd : end;

    totalMinutes += (segmentEnd.getTime() - cursor.getTime()) / 60_000;

    if (end.getTime() <= dayEnd.getTime()) break;
    cursor = startOfNextWorkingDay(local.year, local.month, local.day, org);
  }

  return totalMinutes;
}

async function loadOrgHours(orgId: string): Promise<OrgHours | null> {
  return prisma.organization.findUnique({
    where: { id: orgId },
    select: { timezone: true, workingDays: true, shiftStart: true, shiftEnd: true, holidays: true },
  });
}

// Loads the org's hours and pushes `candidate` out of dead time if needed.
// Falls back to returning `candidate` unchanged if the org can't be found.
export async function applyWorkingHours(orgId: string, candidate: Date): Promise<Date> {
  const org = await loadOrgHours(orgId);
  if (!org) return candidate;
  return nextWorkingMoment(candidate, org);
}

// Loads the org's hours and adds `durationMinutes` of WORKING time to `start`
// (see addWorkingTime). Falls back to raw wall-clock addition if the org
// can't be found — same fail-open spirit as applyWorkingHours.
export async function addWorkingTimeForOrg(orgId: string, start: Date, durationMinutes: number): Promise<Date> {
  const org = await loadOrgHours(orgId);
  if (!org) return new Date(start.getTime() + durationMinutes * 60_000);
  return addWorkingTime(start, durationMinutes, org);
}
