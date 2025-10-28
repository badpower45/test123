import { neon } from '@neondatabase/serverless';
import dotenv from 'dotenv';

dotenv.config();

const sql = neon(process.env.DATABASE_URL);

(async () => {
  try {
    console.log('Adding branch_id column to pulses table...');
    await sql`ALTER TABLE pulses ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES branches(id) ON DELETE CASCADE`;
    console.log('✅ Column branch_id added successfully');
    
    console.log('Adding bssid_address column to pulses table...');
    await sql`ALTER TABLE pulses ADD COLUMN IF NOT EXISTS bssid_address TEXT`;
    console.log('✅ Column bssid_address added successfully');
    
    console.log('Creating index on branch_id...');
    await sql`CREATE INDEX IF NOT EXISTS idx_pulses_branch_id ON pulses(branch_id)`;
    console.log('✅ Index created successfully');
    
    console.log('🎉 Migration completed successfully!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Migration failed:', error.message);
    process.exit(1);
  }
})();
