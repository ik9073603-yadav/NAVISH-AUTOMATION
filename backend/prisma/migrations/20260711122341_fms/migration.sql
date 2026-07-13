-- CreateEnum
CREATE TYPE "public"."FieldType" AS ENUM ('TEXT', 'NUMBER', 'DROPDOWN', 'DATE', 'PHOTO', 'YESNO');

-- CreateEnum
CREATE TYPE "public"."OrderStatus" AS ENUM ('ACTIVE', 'COMPLETED', 'CANCELLED');

-- CreateTable
CREATE TABLE "public"."flows" (
    "id" TEXT NOT NULL,
    "orgId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "prefix" TEXT NOT NULL DEFAULT 'ORD',
    "active" BOOLEAN NOT NULL DEFAULT true,
    "orderCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "flows_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."stage_defs" (
    "id" TEXT NOT NULL,
    "orgId" TEXT NOT NULL,
    "flowId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "sequence" INTEGER NOT NULL,
    "responsibleId" TEXT,
    "plannedMins" INTEGER,

    CONSTRAINT "stage_defs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."field_defs" (
    "id" TEXT NOT NULL,
    "orgId" TEXT NOT NULL,
    "stageId" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "type" "public"."FieldType" NOT NULL DEFAULT 'TEXT',
    "required" BOOLEAN NOT NULL DEFAULT false,
    "options" TEXT,
    "sequence" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "field_defs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."orders" (
    "id" TEXT NOT NULL,
    "orgId" TEXT NOT NULL,
    "flowId" TEXT NOT NULL,
    "orderNumber" TEXT NOT NULL,
    "status" "public"."OrderStatus" NOT NULL DEFAULT 'ACTIVE',
    "currentStageId" TEXT,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),

    CONSTRAINT "orders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."order_stages" (
    "id" TEXT NOT NULL,
    "orgId" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "stageId" TEXT NOT NULL,
    "sequence" INTEGER NOT NULL,
    "taskId" TEXT,
    "enteredAt" TIMESTAMP(3),
    "completedAt" TIMESTAMP(3),
    "completedById" TEXT,
    "data" JSONB,
    "delayMins" INTEGER,

    CONSTRAINT "order_stages_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "flows_orgId_idx" ON "public"."flows"("orgId");

-- CreateIndex
CREATE INDEX "stage_defs_flowId_sequence_idx" ON "public"."stage_defs"("flowId", "sequence");

-- CreateIndex
CREATE INDEX "field_defs_stageId_idx" ON "public"."field_defs"("stageId");

-- CreateIndex
CREATE INDEX "orders_orgId_status_idx" ON "public"."orders"("orgId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "orders_orgId_orderNumber_key" ON "public"."orders"("orgId", "orderNumber");

-- CreateIndex
CREATE INDEX "order_stages_orgId_orderId_idx" ON "public"."order_stages"("orgId", "orderId");

-- CreateIndex
CREATE INDEX "order_stages_stageId_idx" ON "public"."order_stages"("stageId");

-- AddForeignKey
ALTER TABLE "public"."stage_defs" ADD CONSTRAINT "stage_defs_flowId_fkey" FOREIGN KEY ("flowId") REFERENCES "public"."flows"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."field_defs" ADD CONSTRAINT "field_defs_stageId_fkey" FOREIGN KEY ("stageId") REFERENCES "public"."stage_defs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."orders" ADD CONSTRAINT "orders_flowId_fkey" FOREIGN KEY ("flowId") REFERENCES "public"."flows"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."order_stages" ADD CONSTRAINT "order_stages_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "public"."orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;
