import { neon } from '@neondatabase/serverless';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Database connection
const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
  console.error('❌ DATABASE_URL environment variable is not set!');
  process.exit(1);
}

console.log('🚀 Starting BLV System Migration...\n');

const sql = neon(DATABASE_URL);

try {
  // Read migration file
  const migrationPath = join(__dirname, 'migrations', 'add_blv_system.sql');
  const migrationSQL = readFileSync(migrationPath, 'utf-8');
  
  console.log('📄 Migration file loaded successfully');
  console.log('🔄 Executing migration...\n');
  
  // Execute migration
  const result = await sql(migrationSQL);
  
  console.log('✅ Migration executed successfully!\n');
  console.log('📊 Results:', result);
  
  // Verify tables created
  console.log('\n🔍 Verifying BLV tables...');
  
  const tables = await sql`
    SELECT table_name 
    FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name IN (
      'branch_environment_baselines',
      'device_calibrations',
      'employee_device_baselines',
      'pulse_flags',
      'active_interaction_logs',
      'attendance_exemptions',
      'manual_overrides',
      'blv_system_config'
    )
    ORDER BY table_name;
  `;
  
  console.log('\n✅ BLV Tables Created:');
  tables.forEach(table => {
    console.log(`   ✓ ${table.table_name}`);
  });
  
  // Verify pulse table columns
  console.log('\n🔍 Verifying pulse table BLV columns...');
  
  const pulseColumns = await sql`
    SELECT column_name, data_type 
    FROM information_schema.columns 
    WHERE table_name = 'pulses' 
    AND column_name IN (
      'wifi_count', 'wifi_signal_strength', 'battery_level',
      'is_charging', 'accel_variance', 'sound_level',
      'presence_score', 'trust_score', 'verification_method'
    )
    ORDER BY column_name;
  `;
  
  console.log('\n✅ Pulse Table BLV Columns:');
  pulseColumns.forEach(col => {
    console.log(`   ✓ ${col.column_name} (${col.data_type})`);
  });
  
  // Check default config
  const config = await sql`SELECT COUNT(*) as count FROM blv_system_config`;
  console.log(`\n✅ Default BLV Config: ${config[0].count} record(s)`);
  
  // Check device calibrations
  const calibrations = await sql`SELECT COUNT(*) as count FROM device_calibrations`;
  console.log(`✅ Device Calibrations: ${calibrations[0].count} record(s)`);
  
  console.log('\n\n🎉 BLV System Migration Completed Successfully!');
  console.log('═══════════════════════════════════════════════\n');
  
} catch (error) {
  console.error('❌ Migration failed:', error);
  console.error('\nError details:', error.message);
  process.exit(1);
}
