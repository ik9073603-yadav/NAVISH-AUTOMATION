-- AlterTable
ALTER TABLE "public"."users" ADD COLUMN     "canStockIn" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "canStockOut" BOOLEAN NOT NULL DEFAULT false;
