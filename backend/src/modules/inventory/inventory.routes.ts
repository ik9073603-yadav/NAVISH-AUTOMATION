import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { recordMovement, checkStockAlertForSku, classifyLiquidVsDead } from './inventory.service';

export const inventoryRouter = Router();
inventoryRouter.use(requireAuth);

const skuCreateSchema = z.object({
  name: z.string().min(1),
  code: z.string().min(1),
  category: z.string().optional(),
  unit: z.string().min(1).optional(),
  imageUrl: z.string().optional(),
  currentStock: z.number().nonnegative().optional(),
  minStock: z.number().nonnegative().optional(),
  maxStock: z.number().nonnegative().optional(),
  unitCost: z.number().nonnegative().optional(),
});

const skuUpdateSchema = z.object({
  name: z.string().min(1).optional(),
  code: z.string().min(1).optional(),
  category: z.string().nullable().optional(),
  unit: z.string().min(1).optional(),
  imageUrl: z.string().nullable().optional(),
  minStock: z.number().nonnegative().nullable().optional(),
  maxStock: z.number().nonnegative().nullable().optional(),
  unitCost: z.number().nonnegative().nullable().optional(),
  active: z.boolean().optional(),
});

const movementSchema = z.object({
  type: z.enum(['IN', 'OUT', 'ADJUST']),
  quantity: z.number(),
  reason: z.string().optional(),
});

function skuView(s: {
  currentStock: number;
  unitCost: number | null;
  minStock: number | null;
  lastMovedAt: Date | null;
}) {
  return {
    liquidClass: classifyLiquidVsDead(s),
    stockValue: (s.unitCost ?? 0) * s.currentStock,
    isLow: s.minStock != null && s.currentStock <= s.minStock,
  };
}

// List SKUs — search/category/status(LIQUID|DEAD|SLOW|LOW|ALL). Active-by-default.
inventoryRouter.get('/skus', async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const search = (req.query.search as string | undefined)?.trim();
    const category = req.query.category as string | undefined;
    const status = ((req.query.status as string | undefined)?.toUpperCase()) || 'ALL';

    const where: any = { orgId, active: true };
    if (search) {
      where.OR = [
        { name: { contains: search, mode: 'insensitive' } },
        { code: { contains: search, mode: 'insensitive' } },
      ];
    }
    if (category) where.category = category;

    const skus = await prisma.sku.findMany({ where, orderBy: { name: 'asc' } });

    let mapped = skus.map(s => ({ ...s, ...skuView(s) }));

    if (status === 'LIQUID' || status === 'DEAD' || status === 'SLOW') {
      mapped = mapped.filter(s => s.liquidClass === status);
    } else if (status === 'LOW') {
      mapped = mapped.filter(s => s.isLow);
    }

    res.json(mapped);
  } catch (err) { next(err); }
});

inventoryRouter.post('/skus', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const parsed = skuCreateSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId } = req.user!;
    const opening = parsed.data.currentStock ?? 0;

    const sku = await prisma.sku.create({
      data: {
        orgId,
        name: parsed.data.name,
        code: parsed.data.code.trim(),
        category: parsed.data.category,
        unit: parsed.data.unit ?? 'pcs',
        imageUrl: parsed.data.imageUrl,
        currentStock: opening,
        minStock: parsed.data.minStock,
        maxStock: parsed.data.maxStock,
        unitCost: parsed.data.unitCost,
        lastMovedAt: opening > 0 ? new Date() : null,
      },
    });

    await checkStockAlertForSku(orgId, sku.id);

    res.status(201).json({ ...sku, ...skuView(sku) });
  } catch (err: any) {
    if (err?.code === 'P2002') return res.status(409).json({ error: 'A SKU with this code already exists' });
    next(err);
  }
});

inventoryRouter.patch('/skus/:id', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const parsed = skuUpdateSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId } = req.user!;
    const sku = await prisma.sku.findFirst({ where: { id: req.params.id, orgId } });
    if (!sku) return res.status(404).json({ error: 'SKU not found' });

    const updated = await prisma.sku.update({ where: { id: sku.id }, data: parsed.data });

    // Thresholds may have just changed — re-check whether an alert should fire/close.
    await checkStockAlertForSku(orgId, updated.id);

    res.json({ ...updated, ...skuView(updated) });
  } catch (err: any) {
    if (err?.code === 'P2002') return res.status(409).json({ error: 'A SKU with this code already exists' });
    next(err);
  }
});

// Shop-floor work — any authenticated org member can record a movement.
inventoryRouter.post('/skus/:id/movement', async (req, res, next) => {
  try {
    const parsed = movementSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });
    if (parsed.data.type !== 'ADJUST' && parsed.data.quantity <= 0) {
      return res.status(400).json({ error: 'Quantity must be positive' });
    }

    const { orgId, userId } = req.user!;
    const movement = await recordMovement(
      orgId, req.params.id, parsed.data.type, parsed.data.quantity, parsed.data.reason, userId,
    );

    await checkStockAlertForSku(orgId, req.params.id);

    res.status(201).json(movement);
  } catch (err: any) {
    if (err?.message === 'SKU not found') return res.status(404).json({ error: err.message });
    if (err?.status === 400) return res.status(400).json({ error: err.message });
    next(err);
  }
});

inventoryRouter.get('/skus/:id/history', async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const sku = await prisma.sku.findFirst({ where: { id: req.params.id, orgId } });
    if (!sku) return res.status(404).json({ error: 'SKU not found' });

    const movements = await prisma.stockMovement.findMany({
      where: { skuId: sku.id, orgId },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });

    const userIds = [...new Set(movements.map(m => m.doneById))];
    const users = await prisma.user.findMany({ where: { id: { in: userIds } }, select: { id: true, name: true } });
    const nameById = Object.fromEntries(users.map(u => [u.id, u.name]));

    res.json({
      sku: { id: sku.id, name: sku.name, code: sku.code, unit: sku.unit, currentStock: sku.currentStock },
      movements: movements.map(m => ({ ...m, doneByName: nameById[m.doneById] ?? 'Unknown' })),
    });
  } catch (err) { next(err); }
});

inventoryRouter.get('/summary', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const skus = await prisma.sku.findMany({ where: { orgId, active: true } });

    let totalStockValue = 0;
    let lowStockCount = 0;
    let deadStockCount = 0;
    let deadStockValue = 0;
    const reorderList: any[] = [];

    for (const s of skus) {
      const value = (s.unitCost ?? 0) * s.currentStock;
      totalStockValue += value;

      if (classifyLiquidVsDead(s) === 'DEAD') {
        deadStockCount++;
        deadStockValue += value;
      }

      const isLow = s.minStock != null && s.currentStock <= s.minStock;
      if (isLow) {
        lowStockCount++;
        const reorderQty = s.maxStock != null
          ? s.maxStock - s.currentStock
          : s.minStock! * 2 - s.currentStock;
        reorderList.push({
          id: s.id,
          name: s.name,
          code: s.code,
          unit: s.unit,
          currentStock: s.currentStock,
          minStock: s.minStock,
          maxStock: s.maxStock,
          suggestedReorderQty: Math.max(reorderQty, 0),
        });
      }
    }

    res.json({ totalStockValue, lowStockCount, deadStockCount, deadStockValue, reorderList });
  } catch (err) { next(err); }
});
