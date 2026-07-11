-- CreateEnum
CREATE TYPE "public"."TaskStatus" AS ENUM ('PENDING', 'IN_PROGRESS', 'STUCK', 'DONE', 'CANCELLED');

-- CreateEnum
CREATE TYPE "public"."TaskSource" AS ENUM ('DELEGATION', 'CHECKLIST', 'FMS_STAGE', 'INVENTORY_ALERT');

-- CreateTable
CREATE TABLE "public"."tasks" (
    "id" TEXT NOT NULL,
    "orgId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "source" "public"."TaskSource" NOT NULL DEFAULT 'DELEGATION',
    "status" "public"."TaskStatus" NOT NULL DEFAULT 'PENDING',
    "priority" TEXT NOT NULL DEFAULT 'NORMAL',
    "assigneeId" TEXT NOT NULL,
    "createdById" TEXT NOT NULL,
    "dueAt" TIMESTAMP(3),
    "completedAt" TIMESTAMP(3),
    "stuckReason" TEXT,
    "nextActionAt" TIMESTAMP(3),
    "chaseCount" INTEGER NOT NULL DEFAULT 0,
    "escalatedAt" TIMESTAMP(3),
    "escalatedToId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "tasks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."notifications" (
    "id" TEXT NOT NULL,
    "orgId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "taskId" TEXT,
    "readAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "tasks_orgId_status_idx" ON "public"."tasks"("orgId", "status");

-- CreateIndex
CREATE INDEX "tasks_nextActionAt_idx" ON "public"."tasks"("nextActionAt");

-- CreateIndex
CREATE INDEX "tasks_assigneeId_status_idx" ON "public"."tasks"("assigneeId", "status");

-- CreateIndex
CREATE INDEX "notifications_orgId_userId_createdAt_idx" ON "public"."notifications"("orgId", "userId", "createdAt");
