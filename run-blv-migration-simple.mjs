import { neon } from '@neondatabase/serverless';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
  console.error('❌ DATABASE_URL is missing!');
  process.exit(1);
}

const sql = neon(DATABASE_URL);

console.log('🚀 Running BLV Migration...\n');

const migrationSQL = readFileSync(join(__dirname, 'migrations', 'add_blv_system.sql'), 'utf-8');

// Split by semicolons and filter empty statements
const statements = migrationSQL
  .split(';')
  .map(s => s.trim())
  .filter(s => s.length > 0 && !s.startsWith('--') && !s.startsWith('/*'));

console.log(`📝 Found ${statements.length} SQL statements\n`);

let successCount = 0;
let errorCount = 0;

for (let i = 0; i < statements.length; i++) {
  const statement = statements[i];
  try {
    if (statement.length < 10) continue; // Skip very short statements
    
    console.log(`⏳ [${i + 1}/${statements.length}] Executing...`);
    await sql(statement);
    console.log(`✅ Success\n`);
    successCount++;
  } catch (error) {
    console.error(`❌ Error:`, error.message);
    console.error(`Statement: ${statement.substring(0, 100)}...\n`);
    errorCount++;
  }
}

console.log('\n════════════════════════════════════');
console.log(`✅ Successful: ${successCount}`);
console.log(`❌ Errors: ${errorCount}`);
console.log('════════════════════════════════════\n');

if (errorCount === 0) {
  console.log('🎉 BLV Migration Completed Successfully!\n');
} else {
  console.log('⚠️  Migration completed with some errors\n');
}
