import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { requireAuth } from '../../middleware/auth';

export const devicesRouter = Router();
devicesRouter.use(requireAuth);

const tokenSchema = z.object({
  token: z.string().min(1),
  platform: z.enum(['android', 'ios', 'web']).optional(),
});

// Register/refresh this device's push token for the logged-in user.
devicesRouter.post('/', async (req, res, next) => {
  try {
    const parsed = tokenSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const { orgId, userId } = req.user!;

    await prisma.deviceToken.upsert({
      where: { token: parsed.data.token },
      create: {
        orgId,
        userId,
        token: parsed.data.token,
        platform: parsed.data.platform ?? 'android',
      },
      update: { orgId, userId, platform: parsed.data.platform ?? 'android' },
    });

    res.status(201).json({ registered: true });
  } catch (err) { next(err); }
});

// Called on logout — a shared device shouldn't keep chasing the previous user.
devicesRouter.delete('/', async (req, res, next) => {
  try {
    const parsed = z.object({ token: z.string().min(1) }).safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    await prisma.deviceToken.deleteMany({
      where: { token: parsed.data.token, userId: req.user!.userId },
    });

    res.json({ removed: true });
  } catch (err) { next(err); }
});
