import nodemailer, { Transporter } from 'nodemailer';

// Gmail SMTP via an App Password. "from" is the Gmail address itself for
// now — swap for a custom-domain address later by pointing FROM at it once
// domain auth (SPF/DKIM) is set up; Gmail SMTP would still work as a relay
// or get replaced with a dedicated provider then.
const GMAIL_USER = process.env.GMAIL_USER;
const GMAIL_APP_PASSWORD = process.env.GMAIL_APP_PASSWORD;

let transporter: Transporter | null = null;

if (GMAIL_USER && GMAIL_APP_PASSWORD) {
  transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: { user: GMAIL_USER, pass: GMAIL_APP_PASSWORD },
  });
  console.log(`📧 Gmail SMTP configured (${GMAIL_USER}) — email sending enabled`);
} else {
  console.warn(
    '⚠️  GMAIL_USER / GMAIL_APP_PASSWORD not set — email sending disabled (no-op). ' +
    'OTP/reset emails will not be delivered until these are set.',
  );
}

// No-op (logs a warning, does not throw) when SMTP creds are missing, so
// local dev without credentials keeps working.
export async function sendMail(to: string, subject: string, html: string): Promise<void> {
  if (!transporter) {
    console.warn(`⚠️  sendMail no-op (no SMTP creds): would have sent "${subject}" to ${to}`);
    return;
  }
  await transporter.sendMail({ from: GMAIL_USER, to, subject, html });
}
