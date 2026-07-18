import express, { NextFunction, Request, Response } from 'express';
import { env } from './lib/env';
import { authRouter } from './modules/auth/auth.routes';
import { taskRouter } from './modules/task/task.route';
import { startScheduler } from './modules/engine/engine.worker';
import cors from 'cors';
import { userRouter } from './modules/user/user.routes';
import { checklistRouter } from './modules/checklist/checklist.routes';
import { fmsRouter } from './modules/fms/fms.routes';
import { uploadsRouter } from './modules/uploads/uploads.routes';
import { inventoryRouter } from './modules/inventory/inventory.routes';
import { devicesRouter } from './modules/devices/devices.routes';
import { stuckRouter } from './modules/stuck/stuck.routes';
import { settingsRouter } from './modules/settings/settings.routes';
import { adminRouter } from './modules/admin/admin.routes';
import { analyticsRouter } from './modules/analytics/analytics.routes';
import { exportRouter } from './modules/export/export.routes';
import { templatesRouter } from './modules/templates/templates.routes';
import { legalRouter } from './modules/legal/legal.routes';

const app = express();
app.use(express.json());
app.use(cors());
app.use('/api/users', userRouter);
app.use('/api/checklists', checklistRouter);
app.use('/api/fms', fmsRouter);

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'navish-backend', time: new Date().toISOString() });
});

app.use('/api/auth', authRouter);
app.use('/api/tasks', taskRouter);
app.use('/api/uploads', uploadsRouter);
app.use('/api/inventory', inventoryRouter);
app.use('/api/devices', devicesRouter);
app.use('/api/stuck', stuckRouter);
app.use('/api/settings', settingsRouter);
app.use('/api/admin', adminRouter);
app.use('/api/analytics', analyticsRouter);
app.use('/api/export', exportRouter);
app.use('/api/templates', templatesRouter);
app.use('/legal', legalRouter);


app.use((_req, res) => res.status(404).json({ error: 'Route not found' }));

app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
  console.error(err?.stack ?? err);
  if (err?.code === 'P2002') {
    return res.status(409).json({ error: 'That email is already registered for this company' });
  }
  const status = err?.status ?? 500;
  const body: Record<string, unknown> = { error: err?.message ?? 'Internal server error' };
  if (process.env.NODE_ENV !== 'production') {
    body.name = err?.name;
    body.code = err?.code;
  }
  res.status(status).json(body);
});

app.listen(env.PORT, () => {
  console.log(`Navish backend running on http://localhost:${env.PORT}`);
  startScheduler();   // ← yeh add karo
});