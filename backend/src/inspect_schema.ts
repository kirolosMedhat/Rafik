import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.resolve(__dirname, '../../.env') });

const supabaseUrl = process.env.SUPABASE_URL || '';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY || '';

const supabase = createClient(supabaseUrl, supabaseKey);

async function inspectSchema() {
  const tables = ['profiles', 'drivers', 'driver_documents', 'rides'];
  for (const table of tables) {
    console.log(`\n=== Table: ${table} ===`);
    const { data, error } = await supabase.from(table).select().limit(1);
    if (error) {
      console.log(`Error querying ${table}:`, error);
    } else {
      console.log(`Columns inferred from select:`, data);
    }
  }
}

inspectSchema();
