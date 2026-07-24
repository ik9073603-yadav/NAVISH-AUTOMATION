import { createClient } from '@supabase/supabase-js';
import { env } from './env';

// Service key stays server-side only — never send this client or its key to the Flutter app.
export const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY);

export const ATTACHMENTS_BUCKET = 'attachments';
