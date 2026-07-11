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
      select: { id: true, name: true, email: true, role: true, managerId: true },
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