import { Queue, Worker } from 'bullmq';
import { redis } from '../../lib/redis';
import { prisma } from '../../lib/prisma';
import { chaseTask, escalateTask } from './engine.service';
import { MAX_CHASES_BEFORE_ESCALATE } from './engine.config';
import { fireDueChecklists } from '../checklist/checklist.service';
import { checkStockAlerts } from '../inventory/inventory.service';
import { writeDailyHealthSnapshots } from '../health/health-score.service';

// bullmq bundles its own ioredis copy (a different install than the app's
// top-level ioredis), so its own .d.ts sees two structurally-similar but
// nominally distinct `Redis` classes and rejects ours. Same runtime package,
// same client — this is a type-only mismatch, not a real incompatibility.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const connection: any = redis;

export const taskQueue = new Queue('task-actions', { connection });

// WORKER: queue se job uthao aur kaam karo
//
// Redis-chattiness tuning (Upstash bills per command, so an idle queue
// shouldn't be expensive):
//  - drainDelay: how long the worker's blocking read waits for a new job
//    before looping and re-issuing it. A newly-added job wakes the blocked
//    read immediately regardless of this value (BullMQ pushes to the
//    blocking list on add()) — this only governs the idle-poll rate, so
//    raising it is free from a latency standpoint. Jobs here are only ever
//    added by the 2-minute scheduler tick, so 60s is still far tighter than
//    needed and cuts idle polling 12x versus the 5s default.
//  - stalledInterval: how often the worker scans for jobs whose lock
//    expired without completing (i.e. a crashed worker mid-job). Our jobs
//    (chase/escalate) finish in well under a second, so this is a rare-crash
//    safety net, not something that needs checking every 30s — 5 minutes is
//    still a fast recovery time for that scenario.
//  - removeOnComplete/removeOnFail: without these, BullMQ keeps every
//    completed/failed job in Redis forever. Bounding them keeps key counts
//    (and Upstash storage) from growing unbounded.
new Worker(
  'task-actions',
  async (job) => {
    const { taskId, action } = job.data as { taskId: string; action: 'CHASE' | 'ESCALATE' };
    if (action === 'CHASE') await chaseTask(taskId);
    else await escalateTask(taskId);
  },
  {
    connection,
    drainDelay: 60,
    stalledInterval: 300_000,
    removeOnComplete: { count: 100 },
    removeOnFail: { count: 500 },
  },
);

// Health snapshots are a once-a-day write, guarded by a unique(orgId, date)
// constraint — but there's no point re-checking "does today's row exist"
// on every tick across every org, so this throttles the check itself to
// once per 10 minutes. Self-healing: a missed tick, restart, or slow day
// just means the check (and the write, if still missing) happens on the
// next one.
const HEALTH_SNAPSHOT_CHECK_INTERVAL_MS = 10 * 60_000;
let lastHealthSnapshotCheck = 0;

// SCHEDULER: har 2 minute — "kiska time aa gaya?"
// Chases/escalates only fire 1+ minutes (30+ in production, per
// engine.config.ts) after a task's nextActionAt, so 2-minute polling
// granularity is still far tighter than needed — this was 30s purely out
// of caution, not because anything needs sub-2-minute precision.
export function startScheduler() {
  setInterval(async () => {
    // A transient DB/network blip must skip this tick, not crash the whole
    // process — the scheduler just tries again next tick either way.
    try {
      await fireDueChecklists();
      await checkStockAlerts();

      if (Date.now() - lastHealthSnapshotCheck >= HEALTH_SNAPSHOT_CHECK_INTERVAL_MS) {
        lastHealthSnapshotCheck = Date.now();
        await writeDailyHealthSnapshots();
      }
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
      console.error('⚠️  Scheduler tick failed, will retry in 2 min:', err);
    }
  }, 120_000);

  console.log('⚙️  Scheduler started (every 2 min)');
}