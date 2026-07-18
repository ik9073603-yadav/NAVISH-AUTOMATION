-- AlterTable
ALTER TABLE "public"."organizations" ADD COLUMN     "enabled" BOOLEAN NOT NULL DEFAULT true;

-- AlterTable
ALTER TABLE "public"."users" ADD COLUMN     "isSuperAdmin" BOOLEAN NOT NULL DEFAULT false;
