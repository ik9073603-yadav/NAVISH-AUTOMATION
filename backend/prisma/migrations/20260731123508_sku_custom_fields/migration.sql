-- Org-defined custom SKU attributes, mirroring FieldDef/FMS.
ALTER TABLE "skus" ADD COLUMN "customData" JSONB;

CREATE TABLE "sku_field_defs" (
    "id" TEXT NOT NULL,
    "orgId" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "type" "public"."FieldType" NOT NULL DEFAULT 'TEXT',
    "required" BOOLEAN NOT NULL DEFAULT false,
    "options" TEXT,
    "sequence" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "sku_field_defs_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "sku_field_defs_orgId_sequence_idx" ON "sku_field_defs"("orgId", "sequence");

ALTER TABLE "sku_field_defs" ADD CONSTRAINT "sku_field_defs_orgId_fkey" FOREIGN KEY ("orgId") REFERENCES "organizations"("id") ON DELETE CASCADE ON UPDATE CASCADE;
