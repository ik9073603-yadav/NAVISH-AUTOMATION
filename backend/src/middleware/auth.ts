import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../lib/env';
import { prisma } from '../lib/prisma';

export type Role = 'OWNER' | 'MANAGER' | 'EMPLOYEE';

export interface AuthUser {
  userId: string;
  orgId: string;
  role: Role;
  // Cross-org platform capability, set only at login time from the DB flag —
  // never settable through any request. See scripts/set-superadmin.mjs.
  isSuperAdmin: boolean;
  // Single-active-session enforcement — see requireAuth below.
  tokenVersion: number;
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export function signToken(payload: AuthUser): string {
  return jwt.sign(payload, env.JWT_SECRET, { expiresIn: env.JWT_EXPIRES_IN } as jwt.SignOptions);
}

export async function requireAuth(req: Request, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or malformed token' });
  }
  let payload: AuthUser;
  try {
    payload = jwt.verify(header.slice(7), env.JWT_SECRET) as AuthUser;
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
  try {
    // A newer login (this device or another) bumps tokenVersion, which
    // silently invalidates every JWT issued before it — single active
    // session per account, enforced without a server-side session store.
    const user = await prisma.user.findUnique({
      where: { id: payload.userId },
      select: { tokenVersion: true },
    });
    if (!user || user.tokenVersion !== payload.tokenVersion) {
      return res.status(401).json({ error: 'session ended' });
    }
    req.user = payload;
    next();
  } catch (err) {
    next(err);
  }
}

export function requireRole(...allowed: Role[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) return res.status(401).json({ error: 'Not authenticated' });
    if (!allowed.includes(req.user.role)) {
      return res.status(403).json({ error: 'Insufficient permissions' });
    }
    next();
  };
}

// Gate for /api/admin/* only — the sole place cross-org access is permitted.
export function requireSuperAdmin(req: Request, res: Response, next: NextFunction) {
  if (!req.user) return res.status(401).json({ error: 'Not authenticated' });
  if (!req.user.isSuperAdmin) {
    return res.status(403).json({ error: 'Insufficient permissions' });
  }
  next();
}