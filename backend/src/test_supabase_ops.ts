import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.resolve(__dirname, '../../.env') });

const supabaseUrl = process.env.SUPABASE_URL || '';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY || '';

const supabase = createClient(supabaseUrl, supabaseKey);

async function testInsertAndRead() {
  console.log('Testing Supabase REST API operations...');

  // Test 1: Query rides
  const rides = await supabase.from('rides').select('*');
  console.log('Rides select result:', rides);

  // Test 2: Query profiles
  const profiles = await supabase.from('profiles').select('*');
  console.log('Profiles select result:', profiles);

  // Test 3: Query drivers
  const drivers = await supabase.from('drivers').select('*');
  console.log('Drivers select result:', drivers);

  // Test 4: Check if we can insert a test profile or check RLS
  const testId = '00000000-0000-0000-0000-000000000001';
  const insertProf = await supabase.from('profiles').upsert({
    id: testId,
    phone: '+201000000001',
    full_name: 'Test Profile',
    role: 'driver',
    gender: 'female',
    gender_verified: true,
  });
  console.log('Insert profile result:', insertProf);

  // Test 5: Check if direct pooler connection works with db.xertkpwuovmfwwwmdjbe.supabase.co
}

testInsertAndRead();
