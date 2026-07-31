import bcrypt from 'bcryptjs';
import { OtpPurpose } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { signToken } from '../../middleware/auth';
import { LEGAL_VERSION } from '../legal/legal.routes';
import { sendMail } from '../../lib/mailer';
import { issueOtp, verifyOtp, findPendingVerificationPurpose } from './otp.service';

function slugify(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40);
}

function otpEmailHtml(code: string, purpose: OtpPurpose, name?: string): { subject: string; html: string } {
  const subject = purpose === 'PASSWORD_RESET' ? 'Reset your Navish password' : 'Verify your email — Navish';
  const intro = purpose === 'PASSWORD_RESET'
    ? "Use this code to reset your Navish password."
    : "Use this code to verify your email and finish signing in to Navish.";
  const html = `
    <div style="font-family:sans-serif;max-width:480px;margin:auto">
      <h2 style="color:#111">Navish</h2>
      <p>Hi${name ? ` ${name}` : ''},</p>
      <p>${intro}</p>
      <p style="font-size:32px;font-weight:bold;letter-spacing:8px;text-align:center;background:#f4f4f5;padding:16px;border-radius:8px">${code}</p>
      <p style="color:#666;font-size:13px">This code expires in 10 minutes. If you didn't request this, you can safely ignore this email.</p>
    </div>`;
  return { subject, html };
}

async function sendOtpEmail(email: string, code: string, purpose: OtpPurpose, name?: string) {
  const { subject, html } = otpEmailHtml(code, purpose, name);
  await sendMail(email, subject, html);
}

// Bumps tokenVersion and signs a JWT carrying the new value — the one place
// a session actually gets issued, so rotation and signing can never drift
// apart. See requireAuth (single-active-session check) and login() below.
async function issueSessionToken(user: { id: string; orgId: string; role: 'OWNER' | 'MANAGER' | 'EMPLOYEE'; isSuperAdmin: boolean }) {
  const updated = await prisma.user.update({
    where: { id: user.id },
    data: { tokenVersion: { increment: 1 } },
    select: { tokenVersion: true },
  });
  return signToken({
    userId: user.id,
    orgId: user.orgId,
    role: user.role,
    isSuperAdmin: user.isSuperAdmin,
    tokenVersion: updated.tokenVersion,
  });
}

export async function signup(input: {
  companyName: string;
  ownerName: string;
  email: string;
  password: string;
  phone?: string;
}) {
  const email = input.email.toLowerCase().trim();
  const passwordHash = await bcrypt.hash(input.password, 10);

  let slug = slugify(input.companyName);
  if (await prisma.organization.findUnique({ where: { slug } })) {
    slug = `${slug}-${Date.now().toString(36).slice(-4)}`;
  }

  // Org + first Owner created atomically — one fails, both roll back.
  const result = await prisma.$transaction(async (tx) => {
    const org = await tx.organization.create({
      data: { name: input.companyName.trim(), slug },
    });

    const owner = await tx.user.create({
      data: {
        orgId: org.id,
        name: input.ownerName.trim(),
        email,
        phone: input.phone,
        passwordHash,
        role: 'OWNER',
        status: 'ACTIVE',
        termsAcceptedAt: new Date(),
        termsVersion: LEGAL_VERSION,
      },
    });

    await tx.activityLog.create({
      data: {
        orgId: org.id,
        actorId: owner.id,
        action: 'ORG_CREATED',
        entity: 'Organization',
        entityId: org.id,
        meta: { companyName: org.name },
      },
    });

    return { org, owner };
  });

  // Account exists but is unverified — no token yet. The client moves to
  // the OTP-entry screen and calls verify-otp to actually get logged in.
  const code = await issueOtp(email, 'SIGNUP', { enforceCooldown: false });
  await sendOtpEmail(email, code, 'SIGNUP', result.owner.name);

  return {
    message: 'Account created — enter the code we emailed you to verify.',
    email,
  };
}

// Completes SIGNUP or LOGIN_VERIFY (owner-added employee's first login) —
// verifies the code, flips emailVerified, and returns a normal login
// response. PASSWORD_RESET codes are deliberately excluded: they must go
// through resetPassword() instead, never grant a session on their own.
export async function verifyOtpAndLogin(email: string, code: string) {
  const normalized = email.toLowerCase().trim();
  await verifyOtp(normalized, ['SIGNUP', 'LOGIN_VERIFY'], code);

  const user = await prisma.user.findFirst({ where: { email: normalized }, include: { organization: true } });
  if (!user) throw Object.assign(new Error('Account not found'), { status: 404 });

  if (!user.emailVerified) {
    await prisma.user.update({ where: { id: user.id }, data: { emailVerified: true } });
  }

  if (!user.organization.enabled && !user.isSuperAdmin) {
    throw Object.assign(new Error('This company account has been suspended'), { status: 403 });
  }

  const token = await issueSessionToken({
    id: user.id,
    orgId: user.orgId,
    role: user.role as 'OWNER' | 'MANAGER' | 'EMPLOYEE',
    isSuperAdmin: user.isSuperAdmin,
  });

  await prisma.activityLog.create({
    data: { orgId: user.orgId, actorId: user.id, action: 'EMAIL_VERIFIED', entity: 'User', entityId: user.id },
  });

  return {
    token,
    user: { id: user.id, name: user.name, email: user.email, role: user.role, isSuperAdmin: user.isSuperAdmin },
    organization: { id: user.organization.id, name: user.organization.name },
  };
}

// Re-sends whatever SIGNUP/LOGIN_VERIFY code is currently pending for this
// email, at the same purpose. Cooldown is enforced inside issueOtp.
export async function resendOtp(email: string) {
  const normalized = email.toLowerCase().trim();
  const purpose = await findPendingVerificationPurpose(normalized);
  if (!purpose) {
    throw Object.assign(new Error('No pending verification for this email'), { status: 400 });
  }

  const user = await prisma.user.findFirst({ where: { email: normalized } });
  const code = await issueOtp(normalized, purpose);
  await sendOtpEmail(normalized, code, purpose, user?.name);
}

// Self-service — always resolves, never reveals whether the email exists.
export async function forgotPassword(email: string) {
  const normalized = email.toLowerCase().trim();
  try {
    const user = await prisma.user.findFirst({ where: { email: normalized } });
    if (user) {
      const code = await issueOtp(normalized, 'PASSWORD_RESET');
      await sendOtpEmail(normalized, code, 'PASSWORD_RESET', user.name);
    }
  } catch (err) {
    // Cooldown (already sent recently) or a transient mail failure — never
    // let this change the response the caller sees.
    console.warn('forgotPassword: OTP issue/send failed (response unaffected):', err);
  }
}

export async function resetPassword(email: string, code: string, newPassword: string) {
  const normalized = email.toLowerCase().trim();
  await verifyOtp(normalized, 'PASSWORD_RESET', code);

  const user = await prisma.user.findFirst({ where: { email: normalized } });
  if (!user) throw Object.assign(new Error('Invalid or expired code'), { status: 400 });

  await prisma.user.update({
    where: { id: user.id },
    data: { passwordHash: await bcrypt.hash(newPassword, 10) },
  });

  await prisma.activityLog.create({
    data: { orgId: user.orgId, actorId: user.id, action: 'PASSWORD_RESET_SELF_SERVICE', entity: 'User', entityId: user.id },
  });
}

export async function login(input: { email: string; password: string; confirm?: boolean }) {
  const email = input.email.toLowerCase().trim();

  const user = await prisma.user.findFirst({
    where: { email },
    include: { organization: true },
  });

  // Same message either way — never reveal whether an email exists.
  if (!user) throw Object.assign(new Error('Invalid credentials'), { status: 401 });

  const ok = await bcrypt.compare(input.password, user.passwordHash);
  if (!ok) throw Object.assign(new Error('Invalid credentials'), { status: 401 });

  if (user.status !== 'ACTIVE') {
    throw Object.assign(new Error('Account is not active'), { status: 403 });
  }

  // Unverified — either mid-signup or an owner-added employee logging in
  // for the first time. Fire off (or resend, cooldown-permitting) a
  // LOGIN_VERIFY code and block the session; the client routes to the same
  // OTP-entry screen used after signup. Password is already proven above,
  // so this can't be used to spam an arbitrary inbox without knowing it.
  if (!user.emailVerified) {
    try {
      const code = await issueOtp(email, 'LOGIN_VERIFY');
      await sendOtpEmail(email, code, 'LOGIN_VERIFY', user.name);
    } catch (err: any) {
      if (err?.status !== 429) throw err; // 429 = code already pending, fine
    }
    throw Object.assign(new Error('Verify your email to continue — we sent you a code'), {
      status: 403,
      emailNotVerified: true,
      email,
    });
  }

  // Suspended org — blocks new logins. Superadmins bypass this so they can
  // still investigate a suspended org if ever needed.
  if (!user.organization.enabled && !user.isSuperAdmin) {
    throw Object.assign(new Error('This company account has been suspended'), { status: 403 });
  }

  // tokenVersion > 0 means a previous login already issued a session that
  // nothing has since superseded — warn before silently kicking it out.
  // The client re-calls with confirm:true to proceed anyway.
  if (user.tokenVersion > 0 && !input.confirm) {
    throw Object.assign(
      new Error('Already active on another device. Log in here and sign out there?'),
      { status: 409, sessionActive: true },
    );
  }

  const token = await issueSessionToken({
    id: user.id,
    orgId: user.orgId,
    role: user.role as 'OWNER' | 'MANAGER' | 'EMPLOYEE',
    isSuperAdmin: user.isSuperAdmin,
  });

  await prisma.activityLog.create({
    data: { orgId: user.orgId, actorId: user.id, action: 'LOGIN', entity: 'User', entityId: user.id },
  });

  return {
    token,
    user: { id: user.id, name: user.name, email: user.email, role: user.role, isSuperAdmin: user.isSuperAdmin },
    organization: { id: user.organization.id, name: user.organization.name },
  };
}
