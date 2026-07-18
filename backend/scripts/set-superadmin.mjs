// One-off: flip isSuperAdmin=true for a specific account. Never exposed via
// any API — this is the only way the flag is ever set. Run with:
//   node scripts/set-superadmin.mjs suraj@navish.com
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const email = process.argv[2];

if (!email) {
  console.error('Usage: node scripts/set-superadmin.mjs <email>');
  process.exit(1);
}

const result = await prisma.user.updateMany({
  where: { email: email.toLowerCase().trim() },
  data: { isSuperAdmin: true },
});

if (result.count === 0) {
  console.error(`No user found with email ${email}`);
  process.exit(1);
}

console.log(`isSuperAdmin=true set for ${email} (${result.count} account updated). They must log out and back in for it to take effect.`);
await prisma.$disconnect();
