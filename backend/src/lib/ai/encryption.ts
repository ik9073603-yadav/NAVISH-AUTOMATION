import crypto from 'crypto';

// Encrypts each user's own AI provider API key at rest. AES-256-GCM via
// Node's built-in crypto — no extra dependency for something this small.
// AI_ENCRYPTION_KEY is a base64-encoded 32-byte key; optional at startup
// (like BREVO_API_KEY) so a server without it configured yet keeps running —
// the AI routes themselves reject with a clear error until it's set.
const RAW_KEY = process.env.AI_ENCRYPTION_KEY;

if (RAW_KEY) {
  const bytes = Buffer.from(RAW_KEY, 'base64');
  if (bytes.length !== 32) {
    console.warn(`⚠️  AI_ENCRYPTION_KEY is set but not 32 bytes after base64 decode (got ${bytes.length}) — AI key storage disabled.`);
  } else {
    console.log('🔑 AI_ENCRYPTION_KEY configured — AI Assistant key storage enabled');
  }
} else {
  console.warn('⚠️  AI_ENCRYPTION_KEY not set — AI Assistant disabled until it is configured.');
}

function getKey(): Buffer {
  if (!RAW_KEY) throw Object.assign(new Error('AI Assistant is not configured on this server yet'), { status: 503 });
  const key = Buffer.from(RAW_KEY, 'base64');
  if (key.length !== 32) throw Object.assign(new Error('AI Assistant is misconfigured on this server'), { status: 503 });
  return key;
}

// Stored as "iv:authTag:ciphertext", each base64 — self-contained, no
// separate column needed for the IV/tag.
export function encryptSecret(plaintext: string): string {
  const key = getKey();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return [iv, authTag, ciphertext].map(b => b.toString('base64')).join(':');
}

export function decryptSecret(stored: string): string {
  const key = getKey();
  const [ivB64, authTagB64, ciphertextB64] = stored.split(':');
  if (!ivB64 || !authTagB64 || !ciphertextB64) {
    throw Object.assign(new Error('Stored AI key is corrupted'), { status: 500 });
  }
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(ivB64, 'base64'));
  decipher.setAuthTag(Buffer.from(authTagB64, 'base64'));
  const plaintext = Buffer.concat([decipher.update(Buffer.from(ciphertextB64, 'base64')), decipher.final()]);
  return plaintext.toString('utf8');
}
