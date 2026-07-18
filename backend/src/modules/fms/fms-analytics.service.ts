import { prisma } from '../../lib/prisma';

export type SlaStatus = 'DELAYED' | 'ON_TIME' | 'NO_SLA';

interface OrderSlaInput {
  id: string;
  flowId: string;
}

// Classifies each order's SLA outcome against the working-time deadlines
// already stored on its OrderStage rows (see plannedDeadline). Two queries
// total regardless of how many orders are passed in:
//   1. which of these orders' FLOWS have any planned stage at all — a flow
//      with zero planned stages makes every one of its orders "NO_SLA",
//      never falsely on-time.
//   2. every planned-AND-completed OrderStage among these orders, compared
//      in application code since Prisma can't compare two columns in `where`.
// A stage only counts once it has actually completed; an order with planned
// stages that simply hasn't reached/finished one yet is ON_TIME so far —
// matches "every PLANNED stage [that has] finished on or before its deadline".
export async function classifyOrdersSla(orgId: string, orders: OrderSlaInput[]): Promise<Map<string, SlaStatus>> {
  const result = new Map<string, SlaStatus>();
  if (orders.length === 0) return result;

  const flowIds = [...new Set(orders.map(o => o.flowId))];
  const plannedFlows = await prisma.stageDef.findMany({
    where: { orgId, flowId: { in: flowIds }, plannedMins: { not: null } },
    select: { flowId: true },
    distinct: ['flowId'],
  });
  const plannedFlowIds = new Set(plannedFlows.map(f => f.flowId));

  const orderIds = orders.map(o => o.id);
  const plannedCompletedStages = await prisma.orderStage.findMany({
    where: { orgId, orderId: { in: orderIds }, plannedDeadline: { not: null }, completedAt: { not: null } },
    select: { orderId: true, completedAt: true, plannedDeadline: true },
  });
  const lateOrderIds = new Set(
    plannedCompletedStages
      .filter(s => s.completedAt!.getTime() > s.plannedDeadline!.getTime())
      .map(s => s.orderId),
  );

  for (const o of orders) {
    if (!plannedFlowIds.has(o.flowId)) result.set(o.id, 'NO_SLA');
    else if (lateOrderIds.has(o.id)) result.set(o.id, 'DELAYED');
    else result.set(o.id, 'ON_TIME');
  }
  return result;
}

// Best-effort human label for a drill-down row: the first custom-field value
// that looks like an item/product/name field (across the order's stages, in
// stage order), else the flow's name. Never blank.
const LABEL_KEY_PATTERN = /item|product|name/i;

export function deriveOrderDetailLabel(
  stagesData: Array<{ sequence: number; data: unknown }>,
  flowName: string,
): string {
  const sorted = [...stagesData].sort((a, b) => a.sequence - b.sequence);
  for (const s of sorted) {
    const data = s.data as Record<string, unknown> | null;
    if (!data) continue;
    for (const [key, value] of Object.entries(data)) {
      if (key === '__remarks') continue;
      if (LABEL_KEY_PATTERN.test(key) && typeof value === 'string' && value.trim().length > 0) {
        return value.trim();
      }
    }
  }
  return flowName;
}
