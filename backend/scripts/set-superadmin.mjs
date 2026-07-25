// One-off: flip isSuperAdmin for a specific account. Never exposed via any
// API — this is the only way the flag is ever set. Run with:
//   node scripts/set-superadmin.mjs suraj@navish.com true
//   node scripts/set-superadmin.mjs suraj@navish.com false
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const email = process.argv[2];
const flagArg = process.argv[3] ?? 'true';

if (!email || !['true', 'false'].includes(flagArg)) {
  console.error('Usage: node scripts/set-superadmin.mjs <email> <true|false>');
  process.exit(1);
}
const isSuperAdmin = flagArg === 'true';

const result = await prisma.user.updateMany({
  where: { email: email.toLowerCase().trim() },
  data: { isSuperAdmin },
});

if (result.count === 0) {
  console.error(`No user found with email ${email}`);
  process.exit(1);
}

console.log(`isSuperAdmin=${isSuperAdmin} set for ${email} (${result.count} account updated). They must log out and back in for it to take effect.`);
await prisma.$disconnect();
