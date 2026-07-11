require('dotenv').config();
const { Client } = require('pg');

const client = new Client({
  host: 'aws-0-ap-southeast-2.pooler.supabase.com',
  port: 5432,
  user: 'postgres.cbssytamdnmixittlitv',
  password: 'NavishOps2026Secure',
  database: 'postgres',
  ssl: { rejectUnauthorized: false },
});

client
  .connect()
  .then(() => client.query('select version()'))
  .then((r) => { console.log('✅ CONNECTED:', r.rows[0].version); return client.end(); })
  .catch((e) => { console.error('❌ FAILED:', e.message, e.code); });