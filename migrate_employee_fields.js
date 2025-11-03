require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }
});

async function runMigration() {
  try {
    console.log('🔄 Starting migration...\n');
    
    await pool.query('ALTER TABLE employees ADD COLUMN IF NOT EXISTS address TEXT');
    console.log('✓ address column added');
    
    await pool.query('ALTER TABLE employees ADD COLUMN IF NOT EXISTS birth_date DATE');
    console.log('✓ birth_date column added');
    
    await pool.query('ALTER TABLE employees ADD COLUMN IF NOT EXISTS email TEXT');
    console.log('✓ email column added');
    
    await pool.query('ALTER TABLE employees ADD COLUMN IF NOT EXISTS phone TEXT');
    console.log('✓ phone column added');
    
    console.log('\n📋 Verifying columns...');
    const result = await pool.query(
      "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'employees' AND column_name IN ('address', 'birth_date', 'email', 'phone') ORDER BY column_name"
    );
    
    console.log('\nNew columns:');
    result.rows.forEach(row => {
      console.log(`  ✓ ${row.column_name} (${row.data_type})`);
    });
    
    await pool.end();
    console.log('\n✅ Migration completed successfully!');
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Migration failed:', error.message);
    await pool.end();
    process.exit(1);
  }
}

runMigration();
