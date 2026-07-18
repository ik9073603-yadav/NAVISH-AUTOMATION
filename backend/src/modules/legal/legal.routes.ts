import { Router } from 'express';

export const legalRouter = Router();

export const LEGAL_VERSION = '1.0';

const page = (title: string, bodyHtml: string) => `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} — Navish</title>
<style>
  body { font-family: -apple-system, Segoe UI, Roboto, Arial, sans-serif; max-width: 760px; margin: 0 auto; padding: 24px 20px 60px; line-height: 1.55; color: #1a1a1a; }
  h1 { font-size: 1.6rem; margin-bottom: 4px; }
  h2 { font-size: 1.15rem; margin-top: 2em; }
  .draft-banner { background: #fff3cd; border: 1px solid #ffe08a; color: #7a5b00; padding: 12px 16px; border-radius: 8px; font-weight: 600; margin: 16px 0 28px; }
  .meta { color: #666; font-size: 0.9rem; margin-bottom: 24px; }
  a { color: #0f5132; }
</style>
</head>
<body>
<div class="draft-banner">⚠️ DRAFT — must be reviewed by a lawyer before public launch. This is placeholder scaffolding text, not legal advice.</div>
${bodyHtml}
<p class="meta">Version ${LEGAL_VERSION} · Navish</p>
</body>
</html>`;

const termsBody = `
<h1>Terms &amp; Conditions</h1>
<p class="meta">Last updated: draft — date to be set on legal review.</p>

<p>These Terms &amp; Conditions ("Terms") govern access to and use of Navish (the "Service"),
a multi-tenant operations management application. By creating an account you agree to these Terms.</p>

<h2>1. The Service</h2>
<p>Navish helps a company ("Organization") manage delegation, checklists, production/order flows,
and inventory, including automated reminders and escalations during the Organization's configured
working hours.</p>

<h2>2. Accounts and roles</h2>
<p>An Organization's Owner may invite Managers and Employees. Each account belongs to exactly one
Organization. Owners are responsible for the accuracy of data entered and for managing who has
access within their Organization.</p>

<h2>3. Acceptable use</h2>
<p>You agree not to misuse the Service, attempt to access another Organization's data, or use the
Service for any unlawful purpose.</p>

<h2>4. Data ownership</h2>
<p>Data entered by an Organization (tasks, inventory, orders, checklists) belongs to that
Organization. Navish processes it to provide the Service as described in the
<a href="/legal/privacy">Privacy Policy</a>.</p>

<h2>5. Account deletion</h2>
<p>You may request deletion of your account and associated personal data at any time from within
the app. Requests are reviewed and actioned by your Organization's Owner (or, where applicable,
a Navish administrator).</p>

<h2>6. Termination</h2>
<p>Navish may suspend an Organization's access for violation of these Terms, non-payment (where
applicable), or extended inactivity, with notice where reasonably practicable.</p>

<h2>7. Disclaimer &amp; liability</h2>
<p>The Service is provided "as is." Navish is not liable for indirect or consequential losses
arising from use of the Service, to the maximum extent permitted by applicable law.</p>

<h2>8. Governing law</h2>
<p>These Terms are governed by the laws of India, without regard to conflict-of-law principles.</p>

<h2>9. Changes</h2>
<p>We may update these Terms from time to time. Material changes will be reflected by a new
version number and, where required, re-acceptance will be requested.</p>
`;

const privacyBody = `
<h1>Privacy Policy</h1>
<p class="meta">Last updated: draft — date to be set on legal review. Drafted with reference to
India's Digital Personal Data Protection Act, 2023 (DPDP Act) — final wording requires legal review.</p>

<p>This Privacy Policy explains how Navish collects, uses, and protects personal data processed
through the Service, in line with the principles of the DPDP Act (purpose limitation, data
minimisation, security safeguards, and grievance redressal).</p>

<h2>1. What we collect</h2>
<ul>
  <li>Account data: name, email, phone number (optional), role, organization.</li>
  <li>Operational data you or your Organization enters: tasks, checklists, orders, inventory
  movements, and related timestamps.</li>
  <li>Device data for push notifications: a device token, tied to your account.</li>
  <li>Usage/activity logs used for security, support, and the Organization's own analytics.</li>
</ul>

<h2>2. Why we collect it (purpose limitation)</h2>
<p>Personal data is processed only to provide the Service: authenticating you, running the
automation engine (reminders/escalations) for your Organization, and letting your Organization
manage its own operations. We do not sell personal data.</p>

<h2>3. Who can see it</h2>
<p>Data is scoped to your Organization. Other Organizations cannot see your Organization's data.
A small number of Navish platform administrators (superadmins) can see cross-organization usage
counts and health metrics for platform operation — never your Organization's task contents.</p>

<h2>4. Data retention</h2>
<p>We retain personal data for as long as your account is active, plus a reasonable period
afterward for legal/audit purposes, unless you request earlier deletion (see below).</p>

<h2>5. Your rights (Data Principal rights under the DPDP Act)</h2>
<p>Subject to applicable law, you may request access to, correction of, or erasure of your
personal data. You can file a deletion request directly from the app (Profile → Delete my
account); it is reviewed by your Organization's Owner (or a Navish administrator).</p>

<h2>6. Security</h2>
<p>Passwords are hashed, not stored in plain text. Access to the Service requires authentication,
and cross-organization access is restricted to a narrow, explicitly-gated administrative path.</p>

<h2>7. Grievance redressal</h2>
<p>Placeholder — a grievance officer contact (name/email) will be added here on legal review, as
required under the DPDP Act.</p>

<h2>8. Changes</h2>
<p>We may update this Policy from time to time. Material changes will be reflected by a new
version number.</p>
`;

legalRouter.get('/terms', (_req, res) => {
  res.type('html').send(page('Terms & Conditions', termsBody));
});

legalRouter.get('/privacy', (_req, res) => {
  res.type('html').send(page('Privacy Policy', privacyBody));
});
