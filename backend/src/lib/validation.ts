import { z } from 'zod';

// Deliberately stricter than zod's built-in .email(): requires a dotted
// domain (rejects "a@b"), no leading/trailing/consecutive dots in either
// part, and a sane length cap — catches obviously-malformed addresses
// before they ever hit the DB or SMTP. Mirrored in Flutter (validators.dart)
// for client-side rejection.
const EMAIL_RE =
  /^[a-zA-Z0-9](?:[a-zA-Z0-9._%+-]*[a-zA-Z0-9])?@[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)+$/;

export const emailSchema = z
  .string()
  .trim()
  .toLowerCase()
  .max(254)
  .regex(EMAIL_RE, 'Enter a valid email address');
