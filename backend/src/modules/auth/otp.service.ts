import crypto from 'crypto';
import bcrypt from 'bcryptjs';
import { OtpPurpose } from '@prisma/client';
import { prisma } from '../../lib/prisma';

const OTP_EXPIRY_MS = 10 * 60 * 1000;   // 10 minutes
const RESEND_COOLDOWN_MS = 60 * 1000;   // 60 seconds
const MAX_ATTEMPTS = 5;

function generateCode(): string {
  return crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');
}

// Issues a fresh 6-digit code for (email, purpose), hashed at rest. Enforces
// the resend cooldown by default — callers that already know they're the
// very first send for this attempt (fresh signup) can skip it.
export async function issueOtp(
  email: string,
  purpose: OtpPurpose,
  opts: { enforceCooldown?: boolean } = {},
): Promise<string> {
  const normalized = email.toLowerCase().trim();
  const enforceCooldown = opts.enforceCooldown ?? true;

  if (enforceCooldown) {
    const latest = await prisma.otpCode.findFirst({
      where: { email: normalized, purpose },
      orderBy: { createdAt: 'desc' },
    });
    if (latest && !latest.consumed) {
      const elapsed = Date.now() - latest.createdAt.getTime();
      if (elapsed < RESEND_COOLDOWN_MS) {
        const secondsRemaining = Math.ceil((RESEND_COOLDOWN_MS - elapsed) / 1000);
        throw Object.assign(
          new Error(`Please wait ${secondsRemaining}s before requesting another code`),
          { status: 429 },
        );
      }
    }
  }

  const code = generateCode();
  const codeHash = await bcrypt.hash(code, 10);
  await prisma.otpCode.create({
    data: { email: normalized, purpose, codeHash, expiresAt: new Date(Date.now() + OTP_EXPIRY_MS) },
  });
  return code;
}

// Verifies a code against the newest unconsumed row for (email, purpose).
// Throws (400) on missing/expired/wrong/too-many-attempts; marks the row
// consumed on success so it can never be reused.
export async function verifyOtp(
  email: string,
  purpose: OtpPurpose | OtpPurpose[],
  code: string,
): Promise<void> {
  const normalized = email.toLowerCase().trim();
  const purposes = Array.isArray(purpose) ? purpose : [purpose];

  const row = await prisma.otpCode.findFirst({
    where: { email: normalized, purpose: { in: purposes }, consumed: false },
    orderBy: { createdAt: 'desc' },
  });
  const invalid = () => Object.assign(new Error('Invalid or expired code'), { status: 400 });
  if (!row) throw invalid();
  if (row.expiresAt < new Date()) throw invalid();
  if (row.attempts >= MAX_ATTEMPTS) {
    throw Object.assign(new Error('Too many attempts — request a new code'), { status: 400 });
  }

  const ok = await bcrypt.compare(code, row.codeHash);
  if (!ok) {
    await prisma.otpCode.update({ where: { id: row.id }, data: { attempts: { increment: 1 } } });
    throw invalid();
  }

  await prisma.otpCode.update({ where: { id: row.id }, data: { consumed: true } });
}

// Finds the purpose of whatever SIGNUP/LOGIN_VERIFY code is currently
// pending for this email, for resend-otp (which doesn't know the purpose
// up front — the client only supplies the email).
export async function findPendingVerificationPurpose(email: string): Promise<OtpPurpose | null> {
  const normalized = email.toLowerCase().trim();
  const pending = await prisma.otpCode.findFirst({
    where: { email: normalized, purpose: { in: ['SIGNUP', 'LOGIN_VERIFY'] }, consumed: false },
    orderBy: { createdAt: 'desc' },
  });
  return pending?.purpose ?? null;
}
