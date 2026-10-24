import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.resolve(__dirname, '../../.env') });

const supabaseUrl = process.env.SUPABASE_URL || '';
const supabaseKey = process.env.SUPABASE_ANON_KEY || '';

const supabase = createClient(supabaseUrl, supabaseKey);

async function testAuthSession() {
  const email = `driver_${Date.now()}@refqa.app`;
  const password = 'RefqaSecurePass123!';
  
  const { data: signUpData, error: signUpError } = await supabase.auth.signUp({
    email,
    password,
  });

  console.log('Session present?', Boolean(signUpData?.session));
  console.log('User id:', signUpData?.user?.id);
  console.log('Identities:', signUpData?.user?.identities);
  
  if (signUpData?.session) {
    const authClient = createClient(supabaseUrl, supabaseKey, {
      global: {
        headers: {
          Authorization: `Bearer ${signUpData.session.access_token}`
        }
      }
    });

    const res = await authClient.from('profiles').insert({
      id: signUpData.user?.id,
      phone: `+2010${Math.floor(10000000 + Math.random() * 90000000)}`,
      full_name: 'Captain Yasmine Test',
      role: 'driver',
      gender: 'female',
      gender_verified: true,
      verification_status: 'approved',
    }).select();

    console.log('Authenticated Profile Insert Result:', res);
  } else {
    console.log('No session returned. Probably email confirmation is required by Supabase Auth settings.');
  }
}

testAuthSession();
