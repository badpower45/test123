import dotenv from 'dotenv';
import pg from 'pg';
const { Pool } = pg;

// Load environment variables
dotenv.config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL
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
    console.error('\n❌ Migration failed:');
    console.error('Error message:', error.message);
    console.error('Error stack:', error.stack);
    await pool.end();
    process.exit(1);
  }
}

runMigration();
