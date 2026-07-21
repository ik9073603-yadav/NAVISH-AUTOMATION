import { Router } from 'express';
import { requireAuth, requireRole } from '../../middleware/auth';
import { getStuckItems } from './stuck.service';

export const stuckRouter = Router();
stuckRouter.use(requireAuth);

stuckRouter.get('/', requireRole('OWNER', 'MANAGER'), async (req, res, next) => {
  try {
    const items = await getStuckItems(req.user!.orgId);
    res.json(items);
  } catch (err) { next(err); }
});
