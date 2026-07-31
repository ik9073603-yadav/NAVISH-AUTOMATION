import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { recordMovement, checkStockAlertForSku, classifyLiquidVsDead, generateUniqueSkuCode, canRecordMovement, validateSkuCustomData } from './inventory.service';
import { suggestSkuFields, logUsage } from '../ai/ai.service';

export const inventoryRouter = Router();
inventoryRouter.use(requireAuth);

const skuCreateSchema = z.object({
  name: z.string().min(1),
  code: z.string().min(1).optional(),
  category: z.string().optional(),
  unit: z.string().min(1).optional(),
  imageUrl: z.string().optional(),
  currentStock: z.number().nonnegative().optional(),
  minStock: z.number().nonnegative().optional(),
  maxStock: z.number().nonnegative().optional(),
  unitCost: z.number().nonnegative().optional(),
  customData: z.record(z.string(), z.any()).optional(),
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
  customData: z.record(z.string(), z.any()).optional(),
});

// ---------- SKU CUSTOM FIELD DEFS (Owner/Manager decide their own SKU shape) ----------

const skuFieldSchema = z.object({
  label: z.string().min(1),
  type: z.enum(['TEXT', 'NUMBER', 'DROPDOWN', 'DATE', 'PHOTO', 'YESNO']),
  required: z.boolean().optional(),
  options: z.string().optional(),
});

inventoryRouter.get('/sku-fields', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const defs = await prisma.skuFieldDef.findMany({
      where: { orgId: req.user!.orgId },
      orderBy: { sequence: 'asc' },
    });
    res.json(defs);
  } catch (err) { next(err); }
});

inventoryRouter.post('/sku-fields', requireRole('OWNER', 'MANAGER'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = skuFieldSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId } = req.user!;
    const maxSeq = await prisma.skuFieldDef.aggregate({ where: { orgId }, _max: { sequence: true } });

    const def = await prisma.skuFieldDef.create({
      data: {
        orgId,
        label: parsed.data.label,
        type: parsed.data.type,
        required: parsed.data.required ?? false,
        options: parsed.data.options,
        sequence: (maxSeq._max.sequence ?? -1) + 1,
      },
    });

    res.status(201).json(def);
  } catch (err) { next(err); }
});

const skuFieldUpdateSchema = skuFieldSchema.partial();

inventoryRouter.patch('/sku-fields/:id', requireRole('OWNER', 'MANAGER'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = skuFieldUpdateSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId } = req.user!;
    const def = await prisma.skuFieldDef.findFirst({ where: { id: req.params.id as string, orgId } });
    if (!def) return res.status(404).json({ error: 'Field not found' });

    const updated = await prisma.skuFieldDef.update({ where: { id: def.id }, data: parsed.data });
    res.json(updated);
  } catch (err) { next(err); }
});

inventoryRouter.delete('/sku-fields/:id', requireRole('OWNER', 'MANAGER'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { orgId } = req.user!;
    const def = await prisma.skuFieldDef.findFirst({ where: { id: req.params.id as string, orgId } });
    if (!def) return res.status(404).json({ error: 'Field not found' });

    await prisma.skuFieldDef.delete({ where: { id: def.id } });
    res.json({ deleted: true });
  } catch (err) { next(err); }
});

const reorderSchema = z.object({ ids: z.array(z.string().uuid()).min(1) });

inventoryRouter.put('/sku-fields/reorder', requireRole('OWNER', 'MANAGER'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = reorderSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId } = req.user!;
    const owned = await prisma.skuFieldDef.findMany({ where: { orgId, id: { in: parsed.data.ids } }, select: { id: true } });
    if (owned.length !== parsed.data.ids.length) {
      return res.status(400).json({ error: 'One or more fields not found in your company' });
    }

    await prisma.$transaction(
      parsed.data.ids.map((id, i) => prisma.skuFieldDef.update({ where: { id }, data: { sequence: i } })),
    );

    res.json({ reordered: true });
  } catch (err) { next(err); }
});

// AI-assisted field setup — describe the business in plain language, get
// back suggestions in the exact shape POST /sku-fields already accepts.
// Reuses the caller's own configured AI key (ai.service.ts); never applies
// anything itself, just returns suggestions for the client to preview.
const suggestFieldsSchema = z.object({ description: z.string().min(2).max(500) });

inventoryRouter.post('/sku-fields/suggest', requireRole('OWNER', 'MANAGER'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = suggestFieldsSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId, userId } = req.user!;
    const outcome = await suggestSkuFields(userId, parsed.data.description);
    await logUsage(userId, orgId, outcome.provider, outcome.model, 'ASSIST', outcome.usage);

    res.json({ fields: outcome.fields });
  } catch (err) { next(err); }
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
inventoryRouter.get('/skus', async (req: Request, res: Response, next: NextFunction) => {
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

    // Safety cap, not real pagination — status (LIQUID/DEAD/SLOW/LOW) is
    // derived client-side below since it depends on business logic the DB
    // can't filter on, so this must stay generous enough for a real catalog.
    const skus = await prisma.sku.findMany({ where, orderBy: { name: 'asc' }, take: 500 });

    let mapped = skus.map(s => ({ ...s, ...skuView(s) }));

    if (status === 'LIQUID' || status === 'DEAD' || status === 'SLOW') {
      mapped = mapped.filter(s => s.liquidClass === status);
    } else if (status === 'LOW') {
      mapped = mapped.filter(s => s.isLow);
    }

    res.json(mapped);
  } catch (err) { next(err); }
});

inventoryRouter.post('/skus', requireRole('OWNER', 'MANAGER'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = skuCreateSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId } = req.user!;

    const fieldDefs = await prisma.skuFieldDef.findMany({ where: { orgId } });
    const customDataError = validateSkuCustomData(fieldDefs, parsed.data.customData ?? {});
    if (customDataError) return res.status(400).json({ error: customDataError });

    const opening = parsed.data.currentStock ?? 0;
    const code = parsed.data.code?.trim() || await generateUniqueSkuCode(orgId);

    const sku = await prisma.sku.create({
      data: {
        orgId,
        name: parsed.data.name,
        code,
        category: parsed.data.category,
        unit: parsed.data.unit ?? 'pcs',
        imageUrl: parsed.data.imageUrl,
        currentStock: opening,
        minStock: parsed.data.minStock,
        maxStock: parsed.data.maxStock,
        unitCost: parsed.data.unitCost,
        lastMovedAt: opening > 0 ? new Date() : null,
        customData: parsed.data.customData ?? undefined,
      },
    });

    await checkStockAlertForSku(orgId, sku.id);

    res.status(201).json({ ...sku, ...skuView(sku) });
  } catch (err: any) {
    if (err?.code === 'P2002') return res.status(409).json({ error: 'A SKU with this code already exists' });
    next(err);
  }
});

inventoryRouter.patch('/skus/:id', requireRole('OWNER', 'MANAGER'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = skuUpdateSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId } = req.user!;
    const sku = await prisma.sku.findFirst({ where: { id: req.params.id as string, orgId } });
    if (!sku) return res.status(404).json({ error: 'SKU not found' });

    // customData, when sent, is a wholesale replacement (the edit form always
    // sends every field's current value) — validated against every def, same
    // as create. Omitted entirely = leave whatever's already stored alone.
    if (parsed.data.customData !== undefined) {
      const fieldDefs = await prisma.skuFieldDef.findMany({ where: { orgId } });
      const customDataError = validateSkuCustomData(fieldDefs, parsed.data.customData);
      if (customDataError) return res.status(400).json({ error: customDataError });
    }

    const updated = await prisma.sku.update({ where: { id: sku.id }, data: parsed.data });

    // Thresholds may have just changed — re-check whether an alert should fire/close.
    await checkStockAlertForSku(orgId, updated.id);

    res.json({ ...updated, ...skuView(updated) });
  } catch (err: any) {
    if (err?.code === 'P2002') return res.status(409).json({ error: 'A SKU with this code already exists' });
    next(err);
  }
});

// Exact-match lookup for the camera barcode scan — the scanned code IS the
// SKU code, so this is a single indexed lookup, not the fuzzy /skus search.
inventoryRouter.get('/skus/by-code/:code', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { orgId } = req.user!;
    const sku = await prisma.sku.findFirst({
      where: { orgId, code: { equals: req.params.code as string, mode: 'insensitive' } },
    });
    if (!sku) return res.status(404).json({ error: 'No SKU found for this code' });
    res.json({ ...sku, ...skuView(sku) });
  } catch (err) { next(err); }
});

// Shop-floor work — gated per-person. Owner/manager always allowed; an
// employee needs canStockIn/canStockOut granted (see PATCH /users/:id/inventory-permissions).
// Never trust the UI to have hidden the button — flags are re-read from the
// DB here, not from the JWT, so a permission change takes effect immediately.
inventoryRouter.post('/skus/:id/movement', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = movementSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });
    if (parsed.data.type !== 'ADJUST' && parsed.data.quantity <= 0) {
      return res.status(400).json({ error: 'Quantity must be positive' });
    }

    const { orgId, userId, role } = req.user!;

    if (role !== 'OWNER' && role !== 'MANAGER') {
      const actor = await prisma.user.findFirst({
        where: { id: userId, orgId },
        select: { canStockIn: true, canStockOut: true },
      });
      if (!actor || !canRecordMovement(role, actor, parsed.data.type)) {
        return res.status(403).json({ error: `You don't have permission to record ${parsed.data.type} stock movements` });
      }
    }

    const movement = await recordMovement(
      orgId, req.params.id as string, parsed.data.type, parsed.data.quantity, parsed.data.reason, userId,
    );

    await checkStockAlertForSku(orgId, req.params.id as string);

    res.status(201).json(movement);
  } catch (err: any) {
    if (err?.message === 'SKU not found') return res.status(404).json({ error: err.message });
    if (err?.status === 400) return res.status(400).json({ error: err.message });
    next(err);
  }
});

inventoryRouter.get('/skus/:id/history', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { orgId } = req.user!;
    const sku = await prisma.sku.findFirst({ where: { id: req.params.id as string, orgId } });
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

inventoryRouter.get('/summary', requireRole('OWNER', 'MANAGER'), async (req: Request, res: Response, next: NextFunction) => {
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
