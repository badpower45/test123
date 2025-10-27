import { neon } from '@neondatabase/serverless';
import * as dotenv from 'dotenv';
import { readFileSync } from 'fs';

dotenv.config();

const sql = neon(process.env.DATABASE_URL);

async function runMigration() {
  try {
    console.log('Running migration: add_branch_id_to_pulses.sql');
    
    const migrationSQL = readFileSync('./migrations/add_branch_id_to_pulses.sql', 'utf-8');
    
    await sql(migrationSQL);
    
    console.log('✅ Migration completed successfully!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Migration failed:', error);
    process.exit(1);
  }
}

runMigration();
