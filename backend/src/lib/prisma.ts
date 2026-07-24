import { PrismaClient } from '@prisma/client';

// TEMP PERF DIAGNOSTIC — set PERF_LOG=1 to log every query's duration.
// Remove this block once the diagnostic pass is done.
const perfLog = process.env.PERF_LOG === '1';

export const prisma = new PrismaClient({
  log: perfLog ? [{ level: 'query', emit: 'event' }, 'warn', 'error'] : ['warn', 'error'],
});

if (perfLog) {
  (prisma as any).$on('query', (e: { query: string; duration: number }) => {
    if (e.duration >= 5) {
      console.log(`[prisma] ${e.duration}ms  ${e.query.slice(0, 140)}`);
    }
  });
}