/**
 * Run employee personal info migration
 * This script adds address, birth_date, email, and phone columns to employees table
 */

import postgres from 'postgres';
import dotenv from 'dotenv';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load environment variables
dotenv.config({ path: join(__dirname, 'server', '.env') });

const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
  console.error('❌ DATABASE_URL not found in environment variables');
  process.exit(1);
}

console.log('🔄 Connecting to database...');

const sql = postgres(DATABASE_URL, {
  ssl: 'require',
  max: 1,
});

async function runMigration() {
  try {
    console.log('📋 Running migration: Add employee personal information fields');
    
    // Add address field
    console.log('  - Adding address column...');
    await sql`
      ALTER TABLE employees
      ADD COLUMN IF NOT EXISTS address TEXT
    `;
    
    // Add birth_date field
    console.log('  - Adding birth_date column...');
    await sql`
      ALTER TABLE employees
      ADD COLUMN IF NOT EXISTS birth_date DATE
    `;
    
    // Add email field
    console.log('  - Adding email column...');
    await sql`
      ALTER TABLE employees
      ADD COLUMN IF NOT EXISTS email TEXT
    `;
    
    // Add phone field
    console.log('  - Adding phone column...');
    await sql`
      ALTER TABLE employees
      ADD COLUMN IF NOT EXISTS phone TEXT
    `;
    
    console.log('\n✅ Migration completed successfully!');
    
    // Verify the changes
    console.log('\n📊 Verifying columns...');
    const columns = await sql`
      SELECT column_name, data_type, is_nullable
      FROM information_schema.columns
      WHERE table_name = 'employees'
      AND column_name IN ('address', 'birth_date', 'email', 'phone')
      ORDER BY column_name
    `;
    
    console.log('\nNew columns added:');
    columns.forEach(col => {
      console.log(`  ✓ ${col.column_name} (${col.data_type}) - Nullable: ${col.is_nullable}`);
    });
    
  } catch (error) {
    console.error('\n❌ Migration failed:', error);
    throw error;
  } finally {
    await sql.end();
    console.log('\n🔌 Database connection closed');
  }
}

// Run the migration
runMigration()
  .then(() => {
    console.log('\n✨ All done!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n💥 Fatal error:', error);
    process.exit(1);
  });
