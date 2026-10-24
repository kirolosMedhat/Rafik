import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.resolve(__dirname, '../../.env') });

const supabaseUrl = process.env.SUPABASE_URL || '';
const supabaseKey = process.env.SUPABASE_ANON_KEY || '';

const supabase = createClient(supabaseUrl, supabaseKey);

async function testAuth() {
  console.log('Testing Supabase Auth...');
  
  // Test signing up a user
  const email = `driver_${Date.now()}@refqa.app`;
  const password = 'RefqaSecurePass123!';
  
  const { data: signUpData, error: signUpError } = await supabase.auth.signUp({
    email,
    password,
  });

  if (signUpError) {
    console.log('Sign up error:', signUpError.message);
  } else {
    console.log('✅ Sign up success! User ID:', signUpData.user?.id);
    const userClient = createClient(supabaseUrl, supabaseKey);
    // Now with this user, try inserting into profiles!
    const { data: profData, error: profError } = await supabase.from('profiles').insert({
      id: signUpData.user?.id,
      phone: '+201099998888',
      full_name: 'Captain Nourhan Ali',
      role: 'driver',
      gender: 'female',
      gender_verified: true,
      verification_status: 'approved',
    }).select();
    
    if (profError) {
      console.log('Profile insert error:', profError.message);
    } else {
      console.log('✅ Profile inserted successfully:', profData);
    }
  }
}

testAuth();
