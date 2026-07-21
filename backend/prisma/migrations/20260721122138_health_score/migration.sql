-- CreateTable
CREATE TABLE "public"."health_snapshots" (
    "id" TEXT NOT NULL,
    "orgId" TEXT NOT NULL,
    "date" TEXT NOT NULL,
    "score" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "health_snapshots_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "health_snapshots_orgId_date_idx" ON "public"."health_snapshots"("orgId", "date");

-- CreateIndex
CREATE UNIQUE INDEX "health_snapshots_orgId_date_key" ON "public"."health_snapshots"("orgId", "date");

-- AddForeignKey
ALTER TABLE "public"."health_snapshots" ADD CONSTRAINT "health_snapshots_orgId_fkey" FOREIGN KEY ("orgId") REFERENCES "public"."organizations"("id") ON DELETE CASCADE ON UPDATE CASCADE;
