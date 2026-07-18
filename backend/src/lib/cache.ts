// Small in-process TTL cache. Good enough for a single-instance deployment —
// analytics aggregates are bounded by the caller's date range already, this
// just avoids recomputing them on every tab open within the same few minutes.
interface Entry {
  data: unknown;
  expiresAt: number;
}

const store = new Map<string, Entry>();

export async function cached<T>(key: string, ttlMs: number, compute: () => Promise<T>): Promise<T> {
  const hit = store.get(key);
  if (hit && hit.expiresAt > Date.now()) return hit.data as T;

  const data = await compute();
  store.set(key, { data, expiresAt: Date.now() + ttlMs });
  return data;
}

// Used after a write that would make a cached read stale (e.g. an org's data changing).
export function invalidate(prefix: string) {
  for (const key of store.keys()) {
    if (key.startsWith(prefix)) store.delete(key);
  }
}
