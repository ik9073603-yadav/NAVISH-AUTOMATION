import { prisma } from './prisma';

// Every model that carries an orgId column, checked post-delete as a
// belt-and-suspenders proof the FK cascades actually fired — not just the
// ones with a direct Organization relation, but the ones that cascade
// transitively (StageDef/FieldDef via Flow, Order/OrderStage via Flow,
// StockMovement via Sku) so a broken link anywhere in the chain surfaces here.
const ORG_SCOPED_MODELS: Array<{ name: string; count: (orgId: string) => Promise<number> }> = [
  { name: 'user', count: (orgId) => prisma.user.count({ where: { orgId } }) },
  { name: 'department', count: (orgId) => prisma.department.count({ where: { orgId } }) },
  { name: 'activityLog', count: (orgId) => prisma.activityLog.count({ where: { orgId } }) },
  { name: 'resetRequest', count: (orgId) => prisma.resetRequest.count({ where: { orgId } }) },
  { name: 'deletionRequest', count: (orgId) => prisma.deletionRequest.count({ where: { orgId } }) },
  { name: 'task', count: (orgId) => prisma.task.count({ where: { orgId } }) },
  { name: 'notification', count: (orgId) => prisma.notification.count({ where: { orgId } }) },
  { name: 'deviceToken', count: (orgId) => prisma.deviceToken.count({ where: { orgId } }) },
  { name: 'checklistRule', count: (orgId) => prisma.checklistRule.count({ where: { orgId } }) },
  { name: 'flow', count: (orgId) => prisma.flow.count({ where: { orgId } }) },
  { name: 'stageDef', count: (orgId) => prisma.stageDef.count({ where: { orgId } }) },
  { name: 'fieldDef', count: (orgId) => prisma.fieldDef.count({ where: { orgId } }) },
  { name: 'order', count: (orgId) => prisma.order.count({ where: { orgId } }) },
  { name: 'orderStage', count: (orgId) => prisma.orderStage.count({ where: { orgId } }) },
  { name: 'sku', count: (orgId) => prisma.sku.count({ where: { orgId } }) },
  { name: 'stockMovement', count: (orgId) => prisma.stockMovement.count({ where: { orgId } }) },
];

export class OrgNotFoundError extends Error {}
export class OrgNameMismatchError extends Error {}

// Deletes an Organization and everything scoped to it, then proves zero
// orphan rows remain. The actual removal is a single DB-level cascade
// (see the org_cascade_delete migration) — the scan below is verification,
// not the mechanism.
export async function deleteOrganizationCascade(orgId: string, confirmName: string) {
  const org = await prisma.organization.findUnique({ where: { id: orgId } });
  if (!org) throw new OrgNotFoundError('Organization not found');
  if (confirmName !== org.name) {
    throw new OrgNameMismatchError('confirmName must exactly match the organization name');
  }

  await prisma.organization.delete({ where: { id: orgId } });

  const remaining: Record<string, number> = {};
  for (const { name, count: countFor } of ORG_SCOPED_MODELS) {
    const count = await countFor(orgId);
    if (count > 0) remaining[name] = count;
  }
  if (Object.keys(remaining).length > 0) {
    // Should be structurally impossible given the cascade FKs, but never
    // silently report success if it somehow isn't true.
    throw new Error(`Orphan rows remain after deleting org ${orgId}: ${JSON.stringify(remaining)}`);
  }

  return org;
}
