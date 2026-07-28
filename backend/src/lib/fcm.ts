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

// Must match the channel created client-side (MainApplication.kt) AND the
// default_notification_channel_id meta-data in AndroidManifest.xml — Android
// silently drops a notification whose channel doesn't exist on the device,
// so all three must stay in sync if this ever changes.
const ANDROID_CHANNEL_ID = 'high_importance_channel';

// Fans a notification out to every device this user is logged in on.
// No-op if Firebase isn't configured or the user has no registered devices.
//
// Never throws — this is called synchronously from notify() on the hot path
// of business actions (task assign, FMS stage complete, ...). A push/FCM
// failure must never fail the request that already succeeded (task created,
// order advanced, etc.), so every failure mode here is caught and logged,
// not propagated.
export async function sendPush(
  userId: string,
  title: string,
  body: string,
  data?: Record<string, string>,
) {
  if (!app) return;

  let devices;
  try {
    devices = await prisma.deviceToken.findMany({ where: { userId } });
  } catch (err) {
    console.error(`🔔❌ sendPush: failed to load device tokens for user ${userId}:`, err);
    return;
  }
  if (devices.length === 0) {
    console.warn(`🔔⚠️  sendPush: user ${userId} has no registered devices — nothing to send`);
    return;
  }

  let res;
  try {
    // priority: 'high' bypasses Doze/App Standby batching so the message is
    // delivered immediately instead of on the next maintenance window — the
    // single biggest lever for "arrives late" on Android. channelId must
    // point at a channel that already exists on the device (see comment above).
    res = await getMessaging(app).sendEachForMulticast({
      tokens: devices.map(d => d.token),
      notification: { title, body },
      data,
      android: {
        priority: 'high',
        notification: {
          channelId: ANDROID_CHANNEL_ID,
          priority: 'max',
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
      apns: {
        payload: { aps: { sound: 'default', contentAvailable: true } },
      },
    });
  } catch (err) {
    console.error(`🔔❌ sendPush: FCM send failed for user ${userId} (${devices.length} device(s)):`, err);
    return;
  }

  const staleTokens: string[] = [];
  res.responses.forEach((r, i) => {
    if (r.success) return;
    const device = devices[i];
    const code = r.error?.code;
    if (
      code === 'messaging/invalid-registration-token' ||
      code === 'messaging/registration-token-not-registered'
    ) {
      staleTokens.push(device.token);
    } else {
      // Any other failure (quota, auth, mismatched-credential, internal...)
      // must be visible — silently ignoring it is how a real delivery
      // failure ends up looking like a successful send.
      console.error(
        `🔔❌ sendPush: delivery failed for user ${userId} (platform=${device.platform}, code=${code ?? 'unknown'}):`,
        r.error?.message ?? r.error,
      );
    }
  });

  const delivered = res.responses.length - res.responses.filter(r => !r.success).length;
  console.log(`🔔 sendPush: ${delivered}/${devices.length} device(s) delivered for user ${userId} (type=${data?.type ?? 'n/a'})`);

  if (staleTokens.length > 0) {
    try {
      await prisma.deviceToken.deleteMany({ where: { token: { in: staleTokens } } });
      console.log(`🧹 Pruned ${staleTokens.length} stale device token(s) for user ${userId}`);
    } catch (err) {
      console.error(`🔔❌ sendPush: failed to prune stale tokens for user ${userId}:`, err);
    }
  }
}
