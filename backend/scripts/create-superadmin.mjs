// One-off: creates the dedicated platform super-admin account, separate
// from any real company. The super-admin is Navish (the platform operator),
// not a company owner — this account is never meant to create flows,
// delegate tasks, or otherwise act as a normal org member. The frontend
// gates isSuperAdmin users to the oversight view only, regardless of the
// role stored here.
//
// The User model requires an orgId (every other route in the app scopes by
// it), so this creates one small, dedicated "Navish Platform" organization
// to hold the account — never a real tenant, never shown to anyone, and
// /api/admin/* (the only place isSuperAdmin matters) never scopes by orgId
// in the first place.
//
// Idempotent — safe to re-run any time you want to change the password:
//   node scripts/create-superadmin.mjs admin@navish.com '<your-password>'
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();
const email = process.argv[2];
const password = process.argv[3];

if (!email || !password) {
  console.error("Usage: node scripts/create-superadmin.mjs <email> '<password>'");
  process.exit(1);
}
if (password.length < 8) {
  console.error('Password must be at least 8 characters.');
  process.exit(1);
}

const PLATFORM_ORG_SLUG = 'navish-platform';
const normalizedEmail = email.toLowerCase().trim();
const passwordHash = await bcrypt.hash(password, 10);

const org = await prisma.organization.upsert({
  where: { slug: PLATFORM_ORG_SLUG },
  update: {},
  create: { name: 'Navish Platform (internal — not a customer)', slug: PLATFORM_ORG_SLUG },
});

// login() looks up users by email globally (not scoped to one org), so
// the same email existing under a different org would silently break it.
// The compound unique key below only protects against a collision within
// this specific org.
const existingElsewhere = await prisma.user.findFirst({
  where: { email: normalizedEmail, orgId: { not: org.id } },
  select: { id: true, orgId: true },
});
if (existingElsewhere) {
  console.error(`${normalizedEmail} already exists under a different org (${existingElsewhere.orgId}) — refusing to create a duplicate.`);
  process.exit(1);
}

const user = await prisma.user.upsert({
  where: { orgId_email: { orgId: org.id, email: normalizedEmail } },
  update: { passwordHash, isSuperAdmin: true, status: 'ACTIVE' },
  create: {
    orgId: org.id,
    name: 'Navish Admin',
    email: normalizedEmail,
    passwordHash,
    role: 'OWNER',
    status: 'ACTIVE',
    isSuperAdmin: true,
  },
});

console.log(`Super-admin ready: ${user.email} (isSuperAdmin=${user.isSuperAdmin}), platform org: ${org.slug}`);
console.log('They must log out and back in for it to take effect.');
await prisma.$disconnect();
