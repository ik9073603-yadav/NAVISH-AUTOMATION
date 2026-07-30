import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/auth';
import { AiProviderName } from '../../lib/ai/providers';
import {
  getConfigStatus, saveConfig, deleteConfig, testConnection,
  runChat, runInsights, logUsage, getUsageSummary,
} from './ai.service';

export const aiRouter = Router();
// Any authenticated user — owner, manager, or employee — can bring their
// own AI key. This is deliberately NOT requireRole-gated.
aiRouter.use(requireAuth);

const providerSchema = z.enum(['OPENAI', 'ANTHROPIC', 'GEMINI']);

const configSchema = z.object({
  provider: providerSchema,
  apiKey: z.string().min(10),
  model: z.string().min(1).optional(),
});

aiRouter.get('/config', async (req: Request, res: Response, next: NextFunction) => {
  try {
    res.json(await getConfigStatus(req.user!.userId));
  } catch (err) { next(err); }
});

aiRouter.post('/config', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = configSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });
    const { orgId, userId } = req.user!;
    await saveConfig(userId, orgId, parsed.data.provider as AiProviderName, parsed.data.apiKey, parsed.data.model);
    res.json(await getConfigStatus(userId));
  } catch (err) { next(err); }
});

aiRouter.delete('/config', async (req: Request, res: Response, next: NextFunction) => {
  try {
    await deleteConfig(req.user!.userId);
    res.json({ configured: false });
  } catch (err) { next(err); }
});

aiRouter.post('/config/test', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = configSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });
    await testConnection(parsed.data.provider as AiProviderName, parsed.data.apiKey, parsed.data.model ?? '');
    res.json({ ok: true, message: 'Connection successful' });
  } catch (err) { next(err); }
});

const chatSchema = z.object({
  message: z.string().min(1),
  history: z.array(z.object({ role: z.enum(['user', 'assistant']), content: z.string() })).optional(),
  feature: z.enum(['OVERVIEW', 'ASSIST']).optional(),
});

aiRouter.post('/chat', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = chatSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });
    const { orgId, userId, role } = req.user!;

    const outcome = await runChat(userId, orgId, role, parsed.data.message, parsed.data.history);
    await logUsage(userId, orgId, outcome.provider, outcome.model, parsed.data.feature ?? 'ASSIST', outcome.usage);
    res.json({ reply: outcome.text });
  } catch (err) { next(err); }
});

const insightsSchema = z.object({
  screen: z.string().min(1),
  data: z.unknown(),
});

aiRouter.post('/insights', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = insightsSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Validation failed', details: parsed.error.issues });
    const { orgId, userId } = req.user!;

    const outcome = await runInsights(userId, parsed.data.screen, parsed.data.data);
    await logUsage(userId, orgId, outcome.provider, outcome.model, 'INSIGHTS', outcome.usage);
    res.json({ insight: outcome.text });
  } catch (err) { next(err); }
});

aiRouter.get('/usage', async (req: Request, res: Response, next: NextFunction) => {
  try {
    res.json(await getUsageSummary(req.user!.userId));
  } catch (err) { next(err); }
});
