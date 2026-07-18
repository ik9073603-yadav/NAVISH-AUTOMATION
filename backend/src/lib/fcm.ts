import { initializeApp, cert, App } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import path from 'path';
import fs from 'fs';
import { prisma } from './prisma';

const KEY_PATH = path.join(__dirname, '..', '..', 'firebase-key.json');

let app: App | null = null;

if (fs.existsSync(KEY_PATH)) {
  try {
    app = initializeApp({ credential: cert(KEY_PATH) });
    console.log('🔥 Firebase Admin initialised — push notifications enabled');
  } catch (err) {
    console.warn('⚠️  Failed to initialise Firebase Admin, push notifications disabled:', err);
  }
} else {
  console.warn('⚠️  backend/firebase-key.json not found — push notifications disabled (no-op)');
}

// Fans a notification out to every device this user is logged in on.
// No-op if Firebase isn't configured or the user has no registered devices.
export async function sendPush(
  userId: string,
  title: string,
  body: string,
  data?: Record<string, string>,
) {
  if (!app) return;

  const devices = await prisma.deviceToken.findMany({ where: { userId } });
  if (devices.length === 0) return;

  const res = await getMessaging(app).sendEachForMulticast({
    tokens: devices.map(d => d.token),
    notification: { title, body },
    data,
  });

  const staleTokens: string[] = [];
  res.responses.forEach((r, i) => {
    if (!r.success) {
      const code = r.error?.code;
      if (
        code === 'messaging/invalid-registration-token' ||
        code === 'messaging/registration-token-not-registered'
      ) {
        staleTokens.push(devices[i].token);
      }
    }
  });

  if (staleTokens.length > 0) {
    await prisma.deviceToken.deleteMany({ where: { token: { in: staleTokens } } });
    console.log(`🧹 Pruned ${staleTokens.length} stale device token(s)`);
  }
}
