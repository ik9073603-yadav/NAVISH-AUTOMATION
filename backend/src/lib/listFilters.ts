import { Request } from 'express';

export type ListStatus = 'ACTIVE' | 'DONE' | 'ALL';

export interface ListQuery {
  status: ListStatus;
  from?: Date;
  to?: Date;
  assigneeId?: string;
}

// Shared ?status=&from=&to=&assigneeId= parsing for list endpoints.
// status defaults to ACTIVE — silent-by-default, pull for history via ALL/DONE.
export function parseListQuery(req: Request): ListQuery {
  const raw = (req.query.status as string | undefined)?.toUpperCase();
  const status: ListStatus = raw === 'DONE' || raw === 'ALL' ? raw : 'ACTIVE';
  const from = req.query.from ? new Date(req.query.from as string) : undefined;
  const to = req.query.to ? new Date(req.query.to as string) : undefined;
  const assigneeId = (req.query.assigneeId as string | undefined) || undefined;
  return { status, from, to, assigneeId };
}

export function dateRangeFilter(from?: Date, to?: Date) {
  if (!from && !to) return undefined;
  return { ...(from && { gte: from }), ...(to && { lte: to }) };
}
