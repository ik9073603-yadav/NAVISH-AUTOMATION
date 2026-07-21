import { prisma } from '../../lib/prisma';
import { workingMinutesBetween, OrgHours } from '../engine/working-hours';

export interface DelayCostOrg extends OrgHours {
  delayCostPerHour: number | null;
}

export async function loadOrgForCost(orgId: string): Promise<DelayCostOrg | null> {
  return prisma.organization.findUnique({
    where: { id: orgId },
    select: { timezone: true, workingDays: true, shiftStart: true, shiftEnd: true, holidays: true, delayCostPerHour: true },
  });
}

// A stage only ever costs money when it was PLANNED (has a plannedDeadline)
// AND finished after that deadline — unplanned stages never incur delay
// cost. delayHours counts only WORKING hours (working-hours.ts) between the
// deadline and completion, so a stage that goes late overnight or across a
// week-off/holiday isn't inflated by dead time.
export function stageDelayHours(plannedDeadline: Date | null, completedAt: Date | null, org: OrgHours): number {
  if (!plannedDeadline || !completedAt) return 0;
  if (completedAt.getTime() <= plannedDeadline.getTime()) return 0;
  return workingMinutesBetween(plannedDeadline, completedAt, org) / 60;
}

// Sum of a flow's PLANNED stages' plannedMins, in hours. Used as the
// denominator for the value-based cost formula below.
export function totalPlannedHoursForStages(stages: Array<{ plannedMins: number | null }>): number {
  return stages.reduce((sum, s) => sum + (s.plannedMins ?? 0), 0) / 60;
}

// Cost formula, in priority order:
//  1. Org has a ₹/hr delay rate set → delayHours * rate. Most accurate,
//     since the owner told us what an idle hour actually costs.
//  2. Else, if this order has a captured value → derive an implied hourly
//     value from the order's flow: orderValue / totalPlannedHours (the
//     flow's whole planned duration in working hours), then multiply by
//     delayHours. i.e. "this order is worth ₹X spread over Y planned
//     working hours end-to-end, so an hour of delay costs roughly ₹X/Y".
//  3. Else → null. Never fabricate a number when neither is configured.
export function stageDelayCost(
  delayHours: number,
  delayCostPerHour: number | null,
  orderValue: number | null,
  totalPlannedHours: number,
): number | null {
  if (delayHours <= 0) return 0;
  if (delayCostPerHour != null) return delayHours * delayCostPerHour;
  if (orderValue != null && totalPlannedHours > 0) return delayHours * (orderValue / totalPlannedHours);
  return null;
}

export function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
