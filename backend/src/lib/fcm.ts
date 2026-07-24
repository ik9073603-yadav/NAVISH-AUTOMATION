import { initializeApp, cert, App, ServiceAccount } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import path from 'path';
import fs from 'fs';
import { prisma } from './prisma';

const KEY_PATH = path.join(__dirname, '..', '..', 'firebase-key.json');

// Production (Render etc.) has no local file — firebase-key.json is
// gitignored on purpose — so the service account JSON can be pasted into
// FIREBASE_SERVICE_ACCOUNT as an env var instead. Local dev keeps working
// unchanged via the file. Env var takes priority when both are present.
function loadCredential(): string | ServiceAccount | null {
  const fromEnv = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (fromEnv) {
    try {
      return JSON.parse(fromEnv) as ServiceAccount;
    } catch (err) {
      console.warn('⚠️  FIREBASE_SERVICE_ACCOUNT is not valid JSON, ignoring it:', err);
    }
  }
  if (fs.existsSync(KEY_PATH)) return KEY_PATH;
  return null;
}

let app: App | null = null;

const credentialSource = loadCredential();
if (credentialSource) {
  try {
    app = initializeApp({ credential: cert(credentialSource) });
    console.log('🔥 Firebase Admin initialised — push notifications enabled');
  } catch (err) {
    console.warn('⚠️  Failed to initialise Firebase Admin, push notifications disabled:', err);
  }
} else {
  console.warn(
    '⚠️  No Firebase credentials found (FIREBASE_SERVICE_ACCOUNT env var or backend/firebase-key.json) — push notifications disabled (no-op)',
  );
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
