-- CreateEnum
CREATE TYPE "public"."OtpPurpose" AS ENUM ('SIGNUP', 'LOGIN_VERIFY', 'PASSWORD_RESET');

-- AlterTable
ALTER TABLE "public"."users" ADD COLUMN     "emailVerified" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "public"."otp_codes" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "purpose" "public"."OtpPurpose" NOT NULL,
    "codeHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "consumed" BOOLEAN NOT NULL DEFAULT false,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "otp_codes_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "otp_codes_email_purpose_idx" ON "public"."otp_codes"("email", "purpose");

-- Backfill: accounts created before email verification existed (e.g. the
-- super-admin) are grandfathered in as already verified.
UPDATE "public"."users" SET "emailVerified" = true WHERE "isSuperAdmin" = true;
