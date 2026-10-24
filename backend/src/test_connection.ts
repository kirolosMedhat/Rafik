import { supabase } from './config/supabase.js';

async function testConnection() {
  console.log('🔄 Testing connection to Supabase Cloud (Refqa)...');
  console.log(`📡 URL: ${process.env.SUPABASE_URL}`);
  console.log(`🔑 Key: ${process.env.SUPABASE_ANON_KEY?.substring(0, 18)}...`);

  // 1. Test profiles table query
  try {
    const { count, error } = await supabase
      .from('profiles')
      .select('*', { count: 'exact', head: true });

    if (error) {
      console.error('❌ Profiles Table Query Error:', error.message);
    } else {
      console.log('✅ Profiles Table Accessible! Total Profiles in Cloud:', count ?? 0);
    }
  } catch (err: any) {
    console.error('❌ Query Exception:', err.message);
  }

  // 2. Test PostGIS stored procedure find_nearby_female_drivers
  try {
    const { data: drivers, error: rpcError } = await supabase.rpc('find_nearby_female_drivers', {
      rider_lat: 30.0444, // Downtown Cairo
      rider_lng: 31.2357,
      radius_meters: 5000,
    });

    if (rpcError) {
      console.error('❌ PostGIS Stored Procedure Error:', rpcError.message);
    } else {
      console.log('✅ PostGIS Stored Procedure Working! Nearby Drivers Returned:', drivers ? drivers.length : 0);
    }
  } catch (err: any) {
    console.error('❌ RPC Exception:', err.message);
  }

  // 3. Ensure Storage Bucket driver-documents exists
  try {
    const { data: bucket, error: bucketError } = await supabase.storage.getBucket('driver-documents');
    if (bucketError) {
      console.log('📦 Attempting to create bucket "driver-documents"...');
      const { data: newBucket, error: createError } = await supabase.storage.createBucket('driver-documents', {
        public: true,
      });
      if (createError) {
        console.warn('⚠️ Bucket notice:', createError.message);
        console.log('💡 Note: You can create the bucket "driver-documents" in the Supabase Dashboard under Storage -> New Bucket (Make it Public).');
      } else {
        console.log('✅ Storage Bucket "driver-documents" created successfully!');
      }
    } else {
      console.log(`✅ Storage Bucket 'driver-documents' Accessible! Public: ${bucket.public}`);
    }
  } catch (err: any) {
    console.warn('⚠️ Storage Exception:', err.message);
  }

  console.log('🎉 Cloud Handshake Verification Complete!');
}

testConnection();
