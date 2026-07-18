import { Router } from 'express';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { TEMPLATES } from './template-data';

export const templatesRouter = Router();
templatesRouter.use(requireAuth);

// Library is static and org-agnostic — safe to show summaries to anyone in the org.
templatesRouter.get('/', (_req, res) => {
  res.json(TEMPLATES.map(t => {
    if (t.type === 'FMS') {
      return {
        id: t.id, type: t.type, name: t.name, description: t.description,
        stageNames: t.stages.map(s => s.name),
      };
    }
    return {
      id: t.id, type: t.type, name: t.name, description: t.description,
      recurrence: t.recurrence,
    };
  }));
});

// Clones a template into the caller's org. Never guesses a responsible
// person / checklist assignee — that's for the owner to fill in after.
templatesRouter.post('/:id/apply', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const { orgId, userId } = req.user!;
    const template = TEMPLATES.find(t => t.id === req.params.id);
    if (!template) return res.status(404).json({ error: 'Template not found' });

    if (template.type === 'FMS') {
      const flow = await prisma.flow.create({
        data: {
          orgId,
          name: template.name,
          prefix: template.prefix,
          itemLabel: template.itemLabel,
        },
      });

      for (let i = 0; i < template.stages.length; i++) {
        const s = template.stages[i];
        const stage = await prisma.stageDef.create({
          data: {
            orgId, flowId: flow.id, name: s.name, sequence: i + 1,
            plannedMins: s.plannedMins, // omitted in template = unplanned
          },
        });

        for (let j = 0; j < (s.fields ?? []).length; j++) {
          const f = s.fields![j];
          await prisma.fieldDef.create({
            data: {
              orgId, stageId: stage.id, label: f.label, type: f.type,
              required: f.required ?? false, options: f.options, sequence: j,
            },
          });
        }
      }

      await prisma.activityLog.create({
        data: { orgId, actorId: userId, action: 'TEMPLATE_APPLIED', entity: 'Flow', entityId: flow.id, meta: { templateId: template.id } },
      });

      return res.status(201).json({ type: 'FMS', flowId: flow.id });
    }

    // CHECKLIST — created inactive, assigned to the applying user as a safe
    // placeholder (never a guessed employee). Owner reassigns + activates
    // via the existing PATCH-toggle flow once they've picked the right person.
    const rule = await prisma.checklistRule.create({
      data: {
        orgId,
        title: template.title,
        description: template.description,
        assigneeId: userId,
        createdById: userId,
        recurrence: template.recurrence,
        timeOfDay: template.timeOfDay,
        weekday: template.weekday,
        dayOfMonth: template.dayOfMonth,
        priority: template.priority,
        active: false,
      },
    });

    await prisma.activityLog.create({
      data: { orgId, actorId: userId, action: 'TEMPLATE_APPLIED', entity: 'ChecklistRule', entityId: rule.id, meta: { templateId: template.id } },
    });

    res.status(201).json({ type: 'CHECKLIST', ruleId: rule.id });
  } catch (err) { next(err); }
});
