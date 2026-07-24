import { Router } from 'express';
import { z } from 'zod';
import bcrypt from 'bcryptjs';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';

export const userRouter = Router();
userRouter.use(requireAuth);

// Company ke saare log (task assign karne ke liye)
userRouter.get('/', async (req, res, next) => {
  try {
    const users = await prisma.user.findMany({
      where: { orgId: req.user!.orgId, status: 'ACTIVE' },
      select: {
        id: true, name: true, email: true, phone: true, role: true, managerId: true,
        canStockIn: true, canStockOut: true,
      },
      orderBy: { name: 'asc' },
    });
    res.json(users);
  } catch (err) { next(err); }
});

const addSchema = z.object({
  name: z.string().min(2),
  email: z.string().email(),
  password: z.string().min(8),
  phone: z.string().optional(),
  role: z.enum(['MANAGER', 'EMPLOYEE']),
  managerId: z.string().uuid().optional(),
});

// Employee/Manager add karo (Owner only)
userRouter.post('/', requireRole('OWNER'), async (req, res, next) => {
  try {
    const parsed = addSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId, userId } = req.user!;

    // Manager na diya ho toh owner hi manager banega (escalation chain)
    const managerId = parsed.data.managerId ?? userId;

    const user = await prisma.user.create({
      data: {
        orgId,
        name: parsed.data.name,
        email: parsed.data.email.toLowerCase().trim(),
        phone: parsed.data.phone,
        passwordHash: await bcrypt.hash(parsed.data.password, 10),
        role: parsed.data.role,
        status: 'ACTIVE',
        managerId,
      },
      select: { id: true, name: true, email: true, role: true },
    });

    await prisma.activityLog.create({
      data: { orgId, actorId: userId, action: 'USER_ADDED', entity: 'User', entityId: user.id },
    });

    res.status(201).json(user);
  } catch (err) { next(err); }
});

const inventoryPermissionsSchema = z.object({
  canStockIn: z.boolean(),
  canStockOut: z.boolean(),
});

// Grants/revokes an employee's Stock IN / Stock OUT capability. OWNER and
// MANAGER always have both regardless of these flags (enforced in code, not
// stored) — this only matters for EMPLOYEE, but is harmless to set on anyone.
userRouter.patch('/:id/inventory-permissions', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const parsed = inventoryPermissionsSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId, userId: actorId } = req.user!;
    const target = await prisma.user.findFirst({ where: { id: req.params.id as string, orgId } });
    if (!target) return res.status(404).json({ error: 'Person not found in your company' });

    const updated = await prisma.user.update({
      where: { id: target.id },
      data: { canStockIn: parsed.data.canStockIn, canStockOut: parsed.data.canStockOut },
      select: { id: true, name: true, canStockIn: true, canStockOut: true },
    });

    await prisma.activityLog.create({
      data: {
        orgId, actorId, action: 'INVENTORY_PERMISSIONS_UPDATED', entity: 'User', entityId: target.id,
        meta: { canStockIn: updated.canStockIn, canStockOut: updated.canStockOut },
      },
    });

    res.json(updated);
  } catch (err) { next(err); }
});