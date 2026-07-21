import { Router } from 'express';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { cached } from '../../lib/cache';
import { computeHealthScore } from './health-score.service';

export const healthRouter = Router();
healthRouter.use(requireAuth, requireRole('OWNER', 'MANAGER'));

const CACHE_TTL_MS = 60_000;
const DEFAULT_WINDOW_DAYS = 7;

// Company Health Score — one 0-100 number summarising the org's operational
// state over a window (default last 7 days), built entirely from a
// transparent, documented weighted formula (see health-score.service.ts) —
// never a black box. Trend compares against the most recent daily snapshot
// strictly before today (see writeDailyHealthSnapshots, run by the
// scheduler), so this stays cheap even though the score itself is
// recomputed live.
healthRouter.get('/', async (req, res, next) => {
  try {
    const { orgId } = req.user!;
    const days = Math.max(1, Math.min(90, Number(req.query.days) || DEFAULT_WINDOW_DAYS));
    const key = `health:score:${orgId}:${days}`;

    const data = await cached(key, CACHE_TTL_MS, async () => {
      const to = new Date();
      const from = new Date(to.getTime() - days * 86_400_000);
      const result = await computeHealthScore(orgId, from, to);

      const today = to.toISOString().slice(0, 10);
      const previous = await prisma.healthSnapshot.findFirst({
        where: { orgId, date: { lt: today } },
        orderBy: { date: 'desc' },
        select: { date: true, score: true },
      });

      return {
        ...result,
        trend: previous && result.overall != null
          ? { previousScore: previous.score, previousDate: previous.date, delta: result.overall - previous.score }
          : null,
      };
    });

    res.json(data);
  } catch (err) { next(err); }
});
