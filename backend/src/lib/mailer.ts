// Brevo (brevo.com) — plain HTTPS transactional email API, not SMTP.
// Gmail SMTP failed on Render (ETIMEDOUT / command CONN — the TCP handshake
// never completes, a network-level egress block), and the same is true of
// most SMTP-based providers on Render. Brevo's API runs over HTTPS (443),
// which Render allows. Uses fetch directly rather than the @getbrevo/brevo
// SDK to avoid another dependencies-vs-devDependencies footgun for zero gain.
const BREVO_API_KEY = process.env.BREVO_API_KEY;
const MAIL_FROM = process.env.MAIL_FROM || 'no-reply@navish.app';
const MAIL_FROM_NAME = process.env.MAIL_FROM_NAME || 'Navish';

// A send must never hang the caller (that's exactly the failure mode this
// replaced) — bounded by AbortSignal.timeout below.
const SEND_TIMEOUT_MS = 15_000;

if (BREVO_API_KEY) {
  // First 8 chars + length only — enough to confirm the right key loaded
  // (and that it isn't empty/truncated) without ever exposing the secret.
  console.log(
    `📧 Brevo configured (from "${MAIL_FROM_NAME}" <${MAIL_FROM}>) — email sending enabled ` +
    `[BREVO_API_KEY: ${BREVO_API_KEY.slice(0, 8)}... length=${BREVO_API_KEY.length}]`,
  );
} else {
  console.warn(
    '⚠️  BREVO_API_KEY not set — email sending disabled (no-op). ' +
    'OTP/reset emails will not be delivered until it is set.',
  );
}

// No-op (logs a warning, does not throw) when the API key is missing, so
// local dev without credentials keeps working.
export async function sendMail(to: string, subject: string, html: string): Promise<void> {
  if (!BREVO_API_KEY) {
    console.warn(`⚠️  sendMail no-op (no BREVO_API_KEY): would have sent "${subject}" to ${to}`);
    return;
  }

  let res: Response;
  try {
    res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: {
        'api-key': BREVO_API_KEY,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        sender: { name: MAIL_FROM_NAME, email: MAIL_FROM },
        to: [{ email: to }],
        subject,
        htmlContent: html,
      }),
      signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
    });
  } catch (err: any) {
    if (err?.name === 'TimeoutError' || err?.name === 'AbortError') {
      throw new Error(`Brevo API request timed out after ${SEND_TIMEOUT_MS}ms`);
    }
    throw new Error(`Brevo API request failed: ${err?.message ?? err}`);
  }

  const responseText = await res.text().catch(() => '');

  if (!res.ok) {
    throw new Error(`Brevo API error ${res.status}: ${responseText}`);
  }

  console.log(`📧 Brevo accepted send to ${to} (status ${res.status}): ${responseText}`);
}
