import { supabase } from './config/supabase.js';

async function testRealtime() {
  console.log('📡 Testing Supabase Realtime Broadcast Channel...');

  const channel = supabase.channel('refqa-dispatch-test', {
    config: { broadcast: { self: true } }
  });

  channel.on('broadcast', { event: 'ride_requested' }, (payload) => {
    console.log('✅ RECEIVED REALTIME BROADCAST EVENT!', payload);
    process.exit(0);
  });

  channel.subscribe(async (status) => {
    console.log(`🔌 Channel Status: ${status}`);
    if (status === 'SUBSCRIBED') {
      console.log('🚀 Sending test broadcast event...');
      await channel.send({
        type: 'broadcast',
        event: 'ride_requested',
        payload: {
          rider_name: 'Salma',
          pickup: 'Zamalek',
          dropoff: 'New Cairo',
          fare_egp: 299.0,
          pin_code: '7429'
        }
      });
    }
  });

  // Timeout after 10s if not received
  setTimeout(() => {
    console.error('❌ Realtime test timed out');
    process.exit(1);
  }, 10000);
}

testRealtime();
