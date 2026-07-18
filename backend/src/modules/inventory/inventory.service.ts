import { Sku, MovementType } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { computeFirstAction, notify } from '../engine/engine.service';

export type LiquidClass = 'LIQUID' | 'SLOW' | 'DEAD';

// OWNER/MANAGER can always move stock. An EMPLOYEE needs the matching flag —
// ADJUST is treated as an inbound-style reconciliation action (setting the
// record straight, closer in spirit to a stock-IN correction than a removal),
// so it's gated by canStockIn, not a separate capability.
export function canRecordMovement(
  role: 'OWNER' | 'MANAGER' | 'EMPLOYEE',
  flags: { canStockIn: boolean; canStockOut: boolean },
  type: 'IN' | 'OUT' | 'ADJUST',
): boolean {
  if (role === 'OWNER' || role === 'MANAGER') return true;
  return type === 'OUT' ? flags.canStockOut : flags.canStockIn;
}

// Used when a SKU is created without a code — a scannable Code128/QR value
// needs SOME code, so we can't just leave it blank. Random, not sequential,
// so two people creating SKUs at the same moment never race on the same value.
function randomSkuCode(): string {
  return 'SKU' + Math.random().toString(36).slice(2, 8).toUpperCase();
}

export async function generateUniqueSkuCode(orgId: string): Promise<string> {
  for (let i = 0; i < 5; i++) {
    const code = randomSkuCode();
    const clash = await prisma.sku.findFirst({ where: { orgId, code } });
    if (!clash) return code;
  }
  // Astronomically unlikely to still be colliding after 5 tries — fall back
  // to a timestamp-suffixed value that's unique by construction.
  return `${randomSkuCode()}${Date.now().toString(36).toUpperCase()}`;
}

// LIQUID: moved in the last 30 days. DEAD: 90+ days (or never moved). SLOW: in between.
export function classifyLiquidVsDead(sku: { lastMovedAt: Date | null }): LiquidClass {
  if (!sku.lastMovedAt) return 'DEAD';
  const daysSinceMove = (Date.now() - sku.lastMovedAt.getTime()) / 86_400_000;
  if (daysSinceMove <= 30) return 'LIQUID';
  if (daysSinceMove >= 90) return 'DEAD';
  return 'SLOW';
}

// IN/OUT/ADJUST all move the same signed delta — OUT is just a negative delta,
// which is what makes the negative-stock guard a single check below.
export async function recordMovement(
  orgId: string,
  skuId: string,
  type: MovementType,
  quantity: number,
  reason: string | undefined,
  userId: string,
) {
  return prisma.$transaction(async (tx) => {
    const sku = await tx.sku.findFirst({ where: { id: skuId, orgId } });
    if (!sku) throw new Error('SKU not found');

    const delta = type === 'OUT' ? -quantity : quantity;
    const newBalance = sku.currentStock + delta;

    if (newBalance < 0) {
      throw Object.assign(
        new Error(`Not enough stock: only ${sku.currentStock} ${sku.unit} available`),
        { status: 400 },
      );
    }

    const movement = await tx.stockMovement.create({
      data: { orgId, skuId, type, quantity, reason, doneById: userId, balance: newBalance },
    });

    await tx.sku.update({
      where: { id: sku.id },
      data: { currentStock: newBalance, lastMovedAt: new Date() },
    });

    return movement;
  });
}

// One SKU's alert task is keyed via Task.ruleId (same generic "source record id"
// role that field already plays for ChecklistRule) — no schema change needed.
async function checkSkuAlert(sku: Sku) {
  const isLow = sku.minStock != null && sku.currentStock <= sku.minStock;
  const isOver = sku.maxStock != null && sku.currentStock >= sku.maxStock;

  const openAlert = await prisma.task.findFirst({
    where: {
      orgId: sku.orgId,
      source: 'INVENTORY_ALERT',
      ruleId: sku.id,
      status: { notIn: ['DONE', 'CANCELLED'] },
    },
  });

  if (isLow || isOver) {
    if (openAlert) return; // already alerted — dedupe

    const owner = await prisma.user.findFirst({ where: { orgId: sku.orgId, role: 'OWNER' } });
    if (!owner) return;

    const title = isLow
      ? `Low stock: ${sku.name} (${sku.currentStock} ${sku.unit} left)`
      : `Over-stock: ${sku.name} (${sku.currentStock} ${sku.unit}, max ${sku.maxStock})`;

    const dueAt = new Date();
    const task = await prisma.task.create({
      data: {
        orgId: sku.orgId,
        title,
        source: 'INVENTORY_ALERT',
        assigneeId: owner.id,
        createdById: owner.id,
        ruleId: sku.id,
        dueAt,
        priority: 'HIGH',
        nextActionAt: await computeFirstAction(sku.orgId, dueAt),
      },
    });

    await notify(
      sku.orgId,
      owner.id,
      'INVENTORY_ALERT',
      title,
      isLow
        ? 'Stock has dropped to or below the minimum level.'
        : 'Stock has risen to or above the maximum level.',
      task.id,
    );

    console.log(`📦 Inventory alert: ${title}`);
  } else if (openAlert) {
    // Back in the healthy range — auto-close, chasing stops by itself.
    await prisma.task.update({
      where: { id: openAlert.id },
      data: { status: 'DONE', completedAt: new Date(), nextActionAt: null },
    });
    console.log(`📦 Inventory alert auto-closed: ${sku.name} back in healthy range`);
  }
}

export async function checkStockAlerts() {
  const skus = await prisma.sku.findMany({ where: { active: true } });
  for (const sku of skus) await checkSkuAlert(sku);
}

export async function checkStockAlertForSku(orgId: string, skuId: string) {
  const sku = await prisma.sku.findFirst({ where: { id: skuId, orgId } });
  if (sku) await checkSkuAlert(sku);
}
