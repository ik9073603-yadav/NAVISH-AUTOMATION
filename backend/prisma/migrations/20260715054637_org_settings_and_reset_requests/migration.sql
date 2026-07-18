-- CreateEnum
CREATE TYPE "public"."ResetRequestStatus" AS ENUM ('PENDING', 'APPROVED', 'DENIED');

-- AlterTable
ALTER TABLE "public"."organizations" ADD COLUMN     "holidays" TEXT[] DEFAULT ARRAY[]::TEXT[],
ADD COLUMN     "shiftEnd" TEXT NOT NULL DEFAULT '18:00',
ADD COLUMN     "shiftStart" TEXT NOT NULL DEFAULT '09:00',
ADD COLUMN     "workingDays" INTEGER[] DEFAULT ARRAY[1, 2, 3, 4, 5, 6]::INTEGER[];

-- CreateTable
CREATE TABLE "public"."reset_requests" (
    "id" TEXT NOT NULL,
    "orgId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" "public"."ResetRequestStatus" NOT NULL DEFAULT 'PENDING',
    "requestedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMP(3),
    "resolvedById" TEXT,

    CONSTRAINT "reset_requests_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "reset_requests_orgId_status_idx" ON "public"."reset_requests"("orgId", "status");
