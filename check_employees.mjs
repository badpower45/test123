import pkg from 'pg';
import dotenv from 'dotenv';
const { Client } = pkg;

dotenv.config({ path: '/home/ubuntu/oldies-server/.env' });

const client = new Client({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }
});

async function test() {
  try {
    await client.connect();
    console.log('✅ Connected to database');
    
    const result = await client.query('SELECT id, full_name, role FROM employees ORDER BY id LIMIT 10');
    console.log('\n📊 Total employees:', result.rowCount);
    console.log('\n👥 Employees:');
    result.rows.forEach(row => {
      console.log(`  - ID: ${row.id}, Name: ${row.full_name}, Role: ${row.role}`);
    });
    
    await client.end();
  } catch (err) {
    console.error('❌ Error:', err.message);
  }
}

test();
