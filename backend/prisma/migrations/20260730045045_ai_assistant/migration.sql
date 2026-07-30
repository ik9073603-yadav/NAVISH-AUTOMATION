-- CreateEnum
CREATE TYPE "public"."AiProvider" AS ENUM ('OPENAI', 'ANTHROPIC', 'GEMINI');

-- CreateEnum
CREATE TYPE "public"."AiFeature" AS ENUM ('OVERVIEW', 'ASSIST', 'INSIGHTS');

-- CreateTable
CREATE TABLE "public"."ai_configs" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "orgId" TEXT NOT NULL,
    "provider" "public"."AiProvider" NOT NULL,
    "model" TEXT NOT NULL,
    "encryptedApiKey" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ai_configs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ai_usage" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "orgId" TEXT NOT NULL,
    "provider" "public"."AiProvider" NOT NULL,
    "model" TEXT NOT NULL,
    "feature" "public"."AiFeature" NOT NULL,
    "inputTokens" INTEGER NOT NULL,
    "outputTokens" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ai_usage_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ai_configs_userId_key" ON "public"."ai_configs"("userId");

-- CreateIndex
CREATE INDEX "ai_configs_orgId_idx" ON "public"."ai_configs"("orgId");

-- CreateIndex
CREATE INDEX "ai_usage_userId_createdAt_idx" ON "public"."ai_usage"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "ai_usage_orgId_idx" ON "public"."ai_usage"("orgId");

-- AddForeignKey
ALTER TABLE "public"."ai_configs" ADD CONSTRAINT "ai_configs_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ai_usage" ADD CONSTRAINT "ai_usage_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

