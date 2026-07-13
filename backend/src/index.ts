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