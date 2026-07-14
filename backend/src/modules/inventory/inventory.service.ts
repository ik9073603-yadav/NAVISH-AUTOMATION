import { Sku, MovementType } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { computeFirstAction } from '../engine/engine.service';

export type LiquidClass = 'LIQUID' | 'SLOW' | 'DEAD';

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
        nextActionAt: computeFirstAction(dueAt),
      },
    });

    await prisma.notification.create({
      data: {
        orgId: sku.orgId,
        userId: owner.id,
        type: 'INVENTORY_ALERT',
        title,
        body: isLow
          ? 'Stock has dropped to or below the minimum level.'
          : 'Stock has risen to or above the maximum level.',
        taskId: task.id,
      },
    });

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
