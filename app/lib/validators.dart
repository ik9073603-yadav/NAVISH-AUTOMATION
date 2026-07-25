// Mirrors backend/src/lib/validation.ts's EMAIL_RE — deliberately stricter
// than a bare "contains @" check: requires a dotted domain, no leading/
// trailing/consecutive dots. Kept in sync manually since it's a single
// small regex on each side.
final RegExp _emailRegex = RegExp(
  r'^[a-zA-Z0-9](?:[a-zA-Z0-9._%+-]*[a-zA-Z0-9])?@[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)+$',
);

bool isValidEmail(String email) => _emailRegex.hasMatch(email.trim());
