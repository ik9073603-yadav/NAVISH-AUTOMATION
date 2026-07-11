import bcrypt from 'bcryptjs';
import { prisma } from '../../lib/prisma';
import { signToken } from '../../middleware/auth';

function slugify(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40);
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

  const token = signToken({
    userId: result.owner.id,
    orgId: result.org.id,
    role: 'OWNER',
  });

  return {
    token,
    user: {
      id: result.owner.id,
      name: result.owner.name,
      email: result.owner.email,
      role: result.owner.role,
    },
    organization: { id: result.org.id, name: result.org.name, slug: result.org.slug },
  };
}

export async function login(input: { email: string; password: string }) {
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

  const token = signToken({
    userId: user.id,
    orgId: user.orgId,
    role: user.role as 'OWNER' | 'MANAGER' | 'EMPLOYEE',
  });

  await prisma.activityLog.create({
    data: { orgId: user.orgId, actorId: user.id, action: 'LOGIN', entity: 'User', entityId: user.id },
  });

  return {
    token,
    user: { id: user.id, name: user.name, email: user.email, role: user.role },
    organization: { id: user.organization.id, name: user.organization.name },
  };
}
