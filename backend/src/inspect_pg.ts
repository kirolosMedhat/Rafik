import { Client } from 'pg';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.resolve(__dirname, '../../.env') });

const connectionString = process.env.DATABASE_URL;

async function checkPostgres() {
  console.log('Connecting to PostgreSQL directly via pooler...');
  const client = new Client({
    connectionString,
    ssl: { rejectUnauthorized: false }
  });

  try {
    await client.connect();
    console.log('✅ Connected to Supabase PostgreSQL!');

    // 1. Check all tables in public schema
    const tablesRes = await client.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      ORDER BY table_name;
    `);
    console.log('Tables in public schema:', tablesRes.rows.map(r => r.table_name));

    // 2. Check counts for each table
    for (const r of tablesRes.rows) {
      try {
        const countRes = await client.query(`SELECT COUNT(*) FROM public."${r.table_name}";`);
        console.log(`Table ${r.table_name}: ${countRes.rows[0].count} rows`);
      } catch (err: any) {
        console.log(`Table ${r.table_name} count error:`, err.message);
      }
    }

    // 3. Inspect columns of drivers, profiles, driver_documents, rides
    for (const t of ['drivers', 'profiles', 'driver_documents', 'rides']) {
      const colRes = await client.query(`
        SELECT column_name, data_type, is_nullable 
        FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = $1
        ORDER BY ordinal_position;
      `, [t]);
      console.log(`\nColumns of ${t}:`, colRes.rows.map(c => `${c.column_name} (${c.data_type})`).join(', '));
    }

  } catch (err: any) {
    console.error('PostgreSQL connection error:', err.message);
  } finally {
    await client.end();
  }
}

checkPostgres();
