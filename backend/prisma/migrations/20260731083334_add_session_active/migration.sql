-- Separate from tokenVersion: whether a session is currently active
-- anywhere, so login() can warn about a takeover only when one actually is.
ALTER TABLE "users" ADD COLUMN "sessionActive" BOOLEAN NOT NULL DEFAULT false;
