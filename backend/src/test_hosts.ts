import { Client } from 'pg';
import dns from 'dns';

async function testHosts() {
  const hosts = [
    { host: 'db.xertkpwuovmfwwwmdjbe.supabase.co', port: 5432, user: 'postgres' },
    { host: 'aws-0-eu-central-1.pooler.supabase.com', port: 6543, user: 'postgres.xertkpwuovmfwwwmdjbe' },
    { host: 'aws-0-eu-central-1.pooler.supabase.com', port: 5432, user: 'postgres.xertkpwuovmfwwwmdjbe' },
    { host: 'aws-0-eu-west-1.pooler.supabase.com', port: 6543, user: 'postgres.xertkpwuovmfwwwmdjbe' },
    { host: 'aws-0-eu-west-3.pooler.supabase.com', port: 6543, user: 'postgres.xertkpwuovmfwwwmdjbe' },
    { host: 'aws-0-us-east-1.pooler.supabase.com', port: 6543, user: 'postgres.xertkpwuovmfwwwmdjbe' },
  ];

  for (const h of hosts) {
    try {
      console.log(`\nTesting ${h.host}:${h.port} (${h.user})...`);
      const client = new Client({
        host: h.host,
        port: h.port,
        user: h.user,
        password: 'UperGirl@123',
        database: 'postgres',
        ssl: { rejectUnauthorized: false },
        connectionTimeoutMillis: 5000,
      });
      await client.connect();
      console.log(`✅ SUCCESS connecting to ${h.host}!`);
      const res = await client.query('SELECT version();');
      console.log('PostgreSQL version:', res.rows[0].version);
      await client.end();
      return h;
    } catch (e: any) {
      console.log(`Failed ${h.host}:${h.port}:`, e.message);
    }
  }
}

testHosts();
