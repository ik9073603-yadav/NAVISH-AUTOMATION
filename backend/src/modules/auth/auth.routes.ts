import { Router } from 'express';
import { z } from 'zod';
import * as authService from './auth.service';
import { requireAuth } from '../../middleware/auth';
import { prisma } from '../../lib/prisma';

export const authRouter = Router();

const signupSchema = z.object({
  companyName: z.string().min(2),
  ownerName: z.string().min(2),
  email: z.string().email(),
  password: z.string().min(8),
  phone: z.string().optional(),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

authRouter.post('/signup', async (req, res, next) => {
  try {
    const parsed = signupSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });
    }
    res.status(201).json(await authService.signup(parsed.data));
  } catch (err) {
    next(err);
  }
});

authRouter.post('/login', async (req, res, next) => {
  try {
    const parsed = loginSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'Validation failed' });
    }
    res.json(await authService.login(parsed.data));
  } catch (err) {
    next(err);
  }
});

// Proves the token works and shows what the server thinks you are.
authRouter.get('/me', requireAuth, async (req, res, next) => {
  try {
    const user = await prisma.user.findFirst({
      where: { id: req.user!.userId, orgId: req.user!.orgId },
      select: {
        id: true, name: true, email: true, phone: true, role: true,
        status: true, organization: { select: { id: true, name: true, slug: true } },
      },
    });
    if (!user) return res.status(404).json({ error: 'User not found' });
    res.json(user);
  } catch (err) {
    next(err);
  }
});