import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { deleteOrganizationCascade, OrgNameMismatchError, OrgNotFoundError } from '../../lib/org-deletion';

export const settingsRouter = Router();
settingsRouter.use(requireAuth);

// Working-hours + org profile settings that gate the automation engine.
settingsRouter.get('/', requireRole('OWNER'), async (req, res, next) => {
  try {
    const org = await prisma.organization.findUnique({
      where: { id: req.user!.orgId },
      select: {
        id: true, name: true, timezone: true,
        workingDays: true, shiftStart: true, shiftEnd: true, holidays: true,
      },
    });
    if (!org) return res.status(404).json({ error: 'Organization not found' });
    res.json(org);
  } catch (err) { next(err); }
});

const timeRegex = /^([01]\d|2[0-3]):([0-5]\d)$/;
const dateRegex = /^\d{4}-\d{2}-\d{2}$/;

const updateSchema = z.object({
  timezone: z.string().min(1).optional(),
  workingDays: z.array(z.number().int().min(1).max(7)).optional(),
  shiftStart: z.string().regex(timeRegex, 'Expected HH:mm').optional(),
  shiftEnd: z.string().regex(timeRegex, 'Expected HH:mm').optional(),
  holidays: z.array(z.string().regex(dateRegex, 'Expected YYYY-MM-DD')).optional(),
});

settingsRouter.patch('/', requireRole('OWNER'), async (req, res, next) => {
  try {
    const parsed = updateSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const org = await prisma.organization.update({
      where: { id: req.user!.orgId },
      data: parsed.data,
      select: {
        id: true, name: true, timezone: true,
        workingDays: true, shiftStart: true, shiftEnd: true, holidays: true,
      },
    });

    await prisma.activityLog.create({
      data: { orgId: org.id, actorId: req.user!.userId, action: 'SETTINGS_UPDATED', entity: 'Organization', entityId: org.id, meta: parsed.data },
    });

    res.json(org);
  } catch (err) { next(err); }
});

const deleteOrgSchema = z.object({ confirmName: z.string().min(1) });

// Feature 13 — company delete + data retention (DPDP erasure). Owner-initiated,
// self-service equivalent of the superadmin path in admin.routes.ts. Irreversible:
// deletes the caller's own org and everything FK-cascaded from it, no undo.
settingsRouter.delete('/', requireRole('OWNER'), async (req, res, next) => {
  try {
    const parsed = deleteOrgSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });

    const deleted = await deleteOrganizationCascade(req.user!.orgId, parsed.data.confirmName);
    res.json({ deleted: true, id: deleted.id, name: deleted.name });
  } catch (err) {
    if (err instanceof OrgNotFoundError) return res.status(404).json({ error: err.message });
    if (err instanceof OrgNameMismatchError) return res.status(400).json({ error: err.message });
    next(err);
  }
});
