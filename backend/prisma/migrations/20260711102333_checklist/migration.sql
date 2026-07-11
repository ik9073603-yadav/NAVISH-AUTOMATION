-- CreateEnum
CREATE TYPE "public"."Recurrence" AS ENUM ('DAILY', 'WEEKLY', 'MONTHLY');

-- AlterTable
ALTER TABLE "public"."tasks" ADD COLUMN     "ruleId" TEXT;

-- CreateTable
CREATE TABLE "public"."checklist_rules" (
    "id" TEXT NOT NULL,
    "orgId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "assigneeId" TEXT NOT NULL,
    "createdById" TEXT NOT NULL,
    "recurrence" "public"."Recurrence" NOT NULL,
    "timeOfDay" TEXT NOT NULL,
    "weekday" INTEGER,
    "dayOfMonth" INTEGER,
    "priority" TEXT NOT NULL DEFAULT 'NORMAL',
    "active" BOOLEAN NOT NULL DEFAULT true,
    "nextFireAt" TIMESTAMP(3),
    "lastFiredAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "checklist_rules_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "checklist_rules_orgId_active_idx" ON "public"."checklist_rules"("orgId", "active");

-- CreateIndex
CREATE INDEX "checklist_rules_nextFireAt_idx" ON "public"."checklist_rules"("nextFireAt");
