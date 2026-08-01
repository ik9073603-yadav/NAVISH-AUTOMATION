-- Multi-weekday checklist recurrence: weekday (single) -> weekdays (set)
ALTER TABLE "checklist_rules" ADD COLUMN "weekdays" INTEGER[] NOT NULL DEFAULT '{}';

UPDATE "checklist_rules" SET "weekdays" = ARRAY["weekday"] WHERE "weekday" IS NOT NULL;

ALTER TABLE "checklist_rules" DROP COLUMN "weekday";
