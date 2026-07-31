-- Single-active-session enforcement: bumped on every login, embedded in the
-- JWT, checked by requireAuth.
ALTER TABLE "users" ADD COLUMN "tokenVersion" INTEGER NOT NULL DEFAULT 0;
