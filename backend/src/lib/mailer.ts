// Resend (resend.com) — plain HTTPS API, not SMTP. Switched from Gmail SMTP
// after confirming (from real production traffic on Render) that outbound
// SMTP connections to Gmail time out at the TCP handshake stage — code
// ETIMEDOUT, command CONN — a network-level block on Render's side, not a
// credentials problem. An HTTPS API call sidesteps that entirely.
const RESEND_API_KEY = process.env.RESEND_API_KEY;

// Resend's built-in sandbox sender — works with zero setup but can only
// deliver to the email address the Resend account itself was created with.
// Once a domain is verified in Resend, set RESEND_FROM_EMAIL to an address
// at that domain (e.g. otp@yourdomain.com) so mail can reach arbitrary
// recipients — required before this can serve real customer signups.
const RESEND_FROM_EMAIL = process.env.RESEND_FROM_EMAIL || 'onboarding@resend.dev';

if (RESEND_API_KEY) {
  console.log(`📧 Resend configured (from ${RESEND_FROM_EMAIL}) — email sending enabled`);
} else {
  console.warn(
    '⚠️  RESEND_API_KEY not set — email sending disabled (no-op). ' +
    'OTP/reset emails will not be delivered until it is set.',
  );
}

// No-op (logs a warning, does not throw) when the API key is missing, so
// local dev without credentials keeps working.
export async function sendMail(to: string, subject: string, html: string): Promise<void> {
  if (!RESEND_API_KEY) {
    console.warn(`⚠️  sendMail no-op (no RESEND_API_KEY): would have sent "${subject}" to ${to}`);
    return;
  }

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from: RESEND_FROM_EMAIL, to, subject, html }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Resend API error ${res.status}: ${body}`);
  }
}
