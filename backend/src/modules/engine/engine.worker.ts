import { Queue, Worker } from 'bullmq';
import { redis } from '../../lib/redis';
import { prisma } from '../../lib/prisma';
import { chaseTask, escalateTask } from './engine.service';
import { MAX_CHASES_BEFORE_ESCALATE } from './engine.config';
import { fireDueChecklists } from '../checklist/checklist.service';
import { checkStockAlerts } from '../inventory/inventory.service';

export const taskQueue = new Queue('task-actions', { connection: redis });

// WORKER: queue se job uthao aur kaam karo
new Worker(
  'task-actions',
  async (job) => {
    const { taskId, action } = job.data as { taskId: string; action: 'CHASE' | 'ESCALATE' };
    if (action === 'CHASE') await chaseTask(taskId);
    else await escalateTask(taskId);
  },
  { connection: redis },
);

// SCHEDULER: har 30 sec — "kiska time aa gaya?"
export function startScheduler() {
  setInterval(async () => {
    // A transient DB/network blip must skip this tick, not crash the whole
    // process — the scheduler just tries again in 30s either way.
    try {
      await fireDueChecklists();
      await checkStockAlerts();
      const due = await prisma.task.findMany({
        where: {
          nextActionAt: { lte: new Date() },
          status: { in: ['PENDING', 'IN_PROGRESS', 'STUCK'] },
        },
        take: 100,
      });

      for (const task of due) {
        const action = task.chaseCount >= MAX_CHASES_BEFORE_ESCALATE ? 'ESCALATE' : 'CHASE';

        // Lock: turant nextActionAt aage badha do, taaki dobara na uthe
        await prisma.task.update({
          where: { id: task.id },
          data: { nextActionAt: new Date(Date.now() + 5 * 60_000) },
        });

        await taskQueue.add(action, { taskId: task.id, action });
        console.log(`⚙️  Queued ${action} for task ${task.id}`);
      }
    } catch (err) {
      console.error('⚠️  Scheduler tick failed, will retry in 30s:', err);
    }
  }, 30_000);

  console.log('⚙️  Scheduler started (every 30s)');
}