import IORedis from 'ioredis';

const url = process.env.REDIS_URL;
if (!url) throw new Error('Missing REDIS_URL');

export const redis = new IORedis(url, {
  maxRetriesPerRequest: null,
});