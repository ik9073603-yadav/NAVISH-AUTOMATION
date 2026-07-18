import { Router } from 'express';
import { z } from 'zod';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import * as authService from './auth.service';
import { requireAuth, requireRole } from '../../middleware/auth';
import { prisma } from '../../lib/prisma';
import { notify } from '../engine/engine.service';

export const authRouter = Router();

// Unambiguous alphabet (no 0/O/1/I/l) — this gets read aloud over a phone call.
const TEMP_PASSWORD_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
function generateTempPassword(length = 10): string {
  let out = '';
  for (let i = 0; i < length; i++) {
    out += TEMP_PASSWORD_ALPHABET[crypto.randomInt(TEMP_PASSWORD_ALPHABET.length)];
  }
  return out;
}

const signupSchema = z.object({
  companyName: z.string().min(2),
  ownerName: z.string().min(2),
  email: z.string().email(),
  password: z.string().min(8),
  phone: z.string().optional(),
  acceptedTerms: z.literal(true, { message: 'You must accept the Terms & Conditions and Privacy Policy' }),
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
        status: true, isSuperAdmin: true, canStockIn: true, canStockOut: true,
        organization: { select: { id: true, name: true, slug: true } },
      },
    });
    if (!user) return res.status(404).json({ error: 'User not found' });
    res.json(user);
  } catch (err) {
    next(err);
  }
});

const updateMeSchema = z.object({
  phone: z.string().min(1).max(20).nullable(),
});

// Self-service: edit your own phone number (used for Call/WhatsApp buttons).
authRouter.patch('/me', requireAuth, async (req, res, next) => {
  try {
    const parsed = updateMeSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const user = await prisma.user.update({
      where: { id: req.user!.userId },
      data: { phone: parsed.data.phone },
      select: { id: true, name: true, email: true, phone: true, role: true },
    });
    res.json(user);
  } catch (err) {
    next(err);
  }
});

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(8),
});

// You know your password, you just want a new one — distinct from the
// logged-out reset-request/approve flow below.
authRouter.post('/change-password', requireAuth, async (req, res, next) => {
  try {
    const parsed = changePasswordSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const user = await prisma.user.findUnique({ where: { id: req.user!.userId } });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const ok = await bcrypt.compare(parsed.data.currentPassword, user.passwordHash);
    if (!ok) return res.status(401).json({ error: 'Current password is incorrect' });

    await prisma.user.update({
      where: { id: user.id },
      data: { passwordHash: await bcrypt.hash(parsed.data.newPassword, 10) },
    });

    await prisma.activityLog.create({
      data: { orgId: user.orgId, actorId: user.id, action: 'PASSWORD_CHANGED', entity: 'User', entityId: user.id },
    });

    res.json({ changed: true });
  } catch (err) {
    next(err);
  }
});

// ---------------- Forgot-password approval flow (Features 28-29) ----------------
// Employee is logged out and doesn't know their password → asks their org's
// owner/manager to reset it. Distinct from change-password above.

const requestResetSchema = z.object({ email: z.string().email() });

// Public — the whole point is the caller isn't logged in. Never reveals
// whether the email exists (same non-committal response either way).
authRouter.post('/request-reset', async (req, res, next) => {
  try {
    const parsed = requestResetSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const email = parsed.data.email.toLowerCase().trim();
    const user = await prisma.user.findFirst({ where: { email } });

    if (user) {
      const existing = await prisma.resetRequest.findFirst({
        where: { userId: user.id, status: 'PENDING' },
      });

      if (!existing) {
        const request = await prisma.resetRequest.create({
          data: { orgId: user.orgId, userId: user.id },
        });

        const approvers = await prisma.user.findMany({
          where: { orgId: user.orgId, role: { in: ['OWNER', 'MANAGER'] }, status: 'ACTIVE' },
        });
        for (const approver of approvers) {
          await notify(
            user.orgId,
            approver.id,
            'RESET_REQUESTED',
            `Password reset requested: ${user.name}`,
            `${user.name} (${user.email}) forgot their password and needs it reset.`,
          );
        }

        await prisma.activityLog.create({
          data: { orgId: user.orgId, action: 'RESET_REQUESTED', entity: 'User', entityId: user.id, meta: { requestId: request.id } },
        });
      }
    }

    res.json({ message: 'If an account exists for that email, your manager has been notified.' });
  } catch (err) {
    next(err);
  }
});

// Owner/Manager: pending reset requests for their org.
authRouter.get('/reset-requests', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const requests = await prisma.resetRequest.findMany({
      where: { orgId: req.user!.orgId, status: 'PENDING' },
      orderBy: { requestedAt: 'asc' },
    });

    const userIds = requests.map(r => r.userId);
    const users = userIds.length
      ? await prisma.user.findMany({ where: { id: { in: userIds } }, select: { id: true, name: true, email: true, phone: true } })
      : [];
    const userById = Object.fromEntries(users.map(u => [u.id, u]));

    res.json(requests.map(r => ({
      id: r.id,
      requestedAt: r.requestedAt,
      user: userById[r.userId] ?? null,
    })));
  } catch (err) {
    next(err);
  }
});

// Approve: generates a temp password, sets it on the employee's account, and
// returns it in the response so the approver can relay it (Call/WhatsApp).
// We do not persist the plaintext password anywhere.
authRouter.post('/reset-requests/:id/approve', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const request = await prisma.resetRequest.findFirst({
      where: { id: req.params.id, orgId: req.user!.orgId, status: 'PENDING' },
    });
    if (!request) return res.status(404).json({ error: 'Reset request not found' });

    const tempPassword = generateTempPassword();

    const user = await prisma.user.update({
      where: { id: request.userId },
      data: { passwordHash: await bcrypt.hash(tempPassword, 10) },
      select: { id: true, name: true, email: true, phone: true },
    });

    await prisma.resetRequest.update({
      where: { id: request.id },
      data: { status: 'APPROVED', resolvedAt: new Date(), resolvedById: req.user!.userId },
    });

    // Best-effort — the employee is logged out so this usually won't reach a
    // device, but costs nothing to try. The temp password itself is relayed
    // out-of-band (Call/WhatsApp), never persisted in a notification body.
    await notify(
      req.user!.orgId,
      user.id,
      'RESET_APPROVED',
      'Your password has been reset',
      'Contact your manager for your new temporary password.',
    );

    await prisma.activityLog.create({
      data: { orgId: req.user!.orgId, actorId: req.user!.userId, action: 'RESET_APPROVED', entity: 'User', entityId: user.id },
    });

    res.json({ user, tempPassword });
  } catch (err) {
    next(err);
  }
});

authRouter.post('/reset-requests/:id/deny', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const request = await prisma.resetRequest.findFirst({
      where: { id: req.params.id, orgId: req.user!.orgId, status: 'PENDING' },
    });
    if (!request) return res.status(404).json({ error: 'Reset request not found' });

    await prisma.resetRequest.update({
      where: { id: request.id },
      data: { status: 'DENIED', resolvedAt: new Date(), resolvedById: req.user!.userId },
    });

    await prisma.activityLog.create({
      data: { orgId: req.user!.orgId, actorId: req.user!.userId, action: 'RESET_DENIED', entity: 'User', entityId: request.userId },
    });

    res.json({ denied: true });
  } catch (err) {
    next(err);
  }
});

// ---------------- Account deletion request (Feature 176) ----------------
// Files a request; actioning it (deactivating the account) is a manual step
// for the org owner (or a superadmin) — this is scaffolding, not an
// automated data-erasure pipeline.

// Self-service — any authenticated account can ask for its own account to be deleted.
authRouter.post('/request-deletion', requireAuth, async (req, res, next) => {
  try {
    const { orgId, userId } = req.user!;

    const existing = await prisma.deletionRequest.findFirst({
      where: { userId, status: 'PENDING' },
    });
    if (existing) return res.json({ requestId: existing.id, alreadyPending: true });

    const request = await prisma.deletionRequest.create({
      data: { orgId, userId },
    });

    const owners = await prisma.user.findMany({
      where: { orgId, role: 'OWNER', status: 'ACTIVE' },
    });
    const requester = await prisma.user.findUnique({ where: { id: userId } });
    for (const owner of owners) {
      await notify(
        orgId,
        owner.id,
        'DELETION_REQUESTED',
        `Account deletion requested: ${requester?.name}`,
        `${requester?.name} (${requester?.email}) has requested their account and data be deleted.`,
      );
    }

    await prisma.activityLog.create({
      data: { orgId, actorId: userId, action: 'DELETION_REQUESTED', entity: 'User', entityId: userId, meta: { requestId: request.id } },
    });

    res.status(201).json({ requestId: request.id, alreadyPending: false });
  } catch (err) {
    next(err);
  }
});

// Owner: pending deletion requests for their org.
authRouter.get('/deletion-requests', requireAuth, requireRole('OWNER'), async (req, res, next) => {
  try {
    const requests = await prisma.deletionRequest.findMany({
      where: { orgId: req.user!.orgId, status: 'PENDING' },
      orderBy: { requestedAt: 'asc' },
    });

    const userIds = requests.map(r => r.userId);
    const users = userIds.length
      ? await prisma.user.findMany({ where: { id: { in: userIds } }, select: { id: true, name: true, email: true, role: true } })
      : [];
    const userById = Object.fromEntries(users.map(u => [u.id, u]));

    res.json(requests.map(r => ({
      id: r.id,
      requestedAt: r.requestedAt,
      user: userById[r.userId] ?? null,
    })));
  } catch (err) {
    next(err);
  }
});

// Approve: deactivates the account (soft — not a hard data wipe) and resolves the request.
authRouter.post('/deletion-requests/:id/complete', requireAuth, requireRole('OWNER'), async (req, res, next) => {
  try {
    const request = await prisma.deletionRequest.findFirst({
      where: { id: req.params.id, orgId: req.user!.orgId, status: 'PENDING' },
    });
    if (!request) return res.status(404).json({ error: 'Deletion request not found' });

    await prisma.user.update({
      where: { id: request.userId },
      data: { status: 'DEACTIVATED' },
    });

    await prisma.deletionRequest.update({
      where: { id: request.id },
      data: { status: 'COMPLETED', resolvedAt: new Date(), resolvedById: req.user!.userId },
    });

    await prisma.activityLog.create({
      data: { orgId: req.user!.orgId, actorId: req.user!.userId, action: 'DELETION_COMPLETED', entity: 'User', entityId: request.userId },
    });

    res.json({ completed: true });
  } catch (err) {
    next(err);
  }
});

authRouter.post('/deletion-requests/:id/deny', requireAuth, requireRole('OWNER'), async (req, res, next) => {
  try {
    const request = await prisma.deletionRequest.findFirst({
      where: { id: req.params.id, orgId: req.user!.orgId, status: 'PENDING' },
    });
    if (!request) return res.status(404).json({ error: 'Deletion request not found' });

    await prisma.deletionRequest.update({
      where: { id: request.id },
      data: { status: 'DENIED', resolvedAt: new Date(), resolvedById: req.user!.userId },
    });

    res.json({ denied: true });
  } catch (err) {
    next(err);
  }
});