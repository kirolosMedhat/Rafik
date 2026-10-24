import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.resolve(__dirname, '../../.env') });

const supabaseUrl = process.env.SUPABASE_URL || '';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY || '';

const supabase = createClient(supabaseUrl, supabaseKey);

async function checkDatabase() {
  const tables = ['profiles', 'drivers', 'driver_documents', 'rides', 'emergency_contacts'];
  for (const table of tables) {
    try {
      const { data, count, error } = await supabase.from(table).select('*', { count: 'exact' });
      if (error) {
        console.log(`Table '${table}': ERROR - ${error.message} (code: ${error.code})`);
      } else {
        console.log(`Table '${table}': Count = ${count}, Rows = ${data?.length}`);
        if (data && data.length > 0) {
          console.log(` Sample:`, JSON.stringify(data.slice(0, 2), null, 2));
        }
      }
    } catch (e: any) {
      console.log(`Table '${table}': Exception - ${e.message}`);
    }
  }
}

checkDatabase();
