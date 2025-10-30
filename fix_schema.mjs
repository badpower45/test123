import { neon } from '@neondatabase/serverless';
import dotenv from 'dotenv';

dotenv.config();

const sql = neon(process.env.DATABASE_URL);

async function fixSchema() {
  try {
    console.log('Starting schema fixes...\n');

    // 1. Fix notifications.related_id to TEXT
    console.log('1. Fixing notifications.related_id column type...');
    try {
      await sql`ALTER TABLE notifications ALTER COLUMN related_id TYPE TEXT USING related_id::TEXT`;
      console.log('✅ notifications.related_id changed to TEXT');
    } catch (err) {
      console.log('⚠️ related_id column:', err.message);
    }

    // 2. Fix bssid_1 and bssid_2 columns in branches
    console.log('\n2. Fixing bssid_1 and bssid_2 columns...');

    // Check if wifi_bssid exists
    const wifiBssidCheck = await sql`
      SELECT column_name
      FROM information_schema.columns
      WHERE table_name='branches' AND column_name='wifi_bssid'
    `;

    if (wifiBssidCheck.length > 0) {
      console.log('Found wifi_bssid column, renaming to bssid_1...');
      await sql`ALTER TABLE branches RENAME COLUMN wifi_bssid TO bssid_1`;
      console.log('✅ Renamed wifi_bssid to bssid_1');
    } else {
      // Check if bssid_1 exists
      const bssid1Check = await sql`
        SELECT column_name
        FROM information_schema.columns
        WHERE table_name='branches' AND column_name='bssid_1'
      `;

      if (bssid1Check.length === 0) {
        console.log('Creating bssid_1 column...');
        await sql`ALTER TABLE branches ADD COLUMN bssid_1 TEXT`;
        console.log('✅ Created bssid_1 column');
      } else {
        console.log('✅ bssid_1 column already exists');
      }
    }

    // Check if bssid_2 exists
    const bssid2Check = await sql`
      SELECT column_name
      FROM information_schema.columns
      WHERE table_name='branches' AND column_name='bssid_2'
    `;

    if (bssid2Check.length === 0) {
      console.log('Creating bssid_2 column...');
      await sql`ALTER TABLE branches ADD COLUMN bssid_2 TEXT DEFAULT NULL`;
      console.log('✅ Created bssid_2 column');
    } else {
      console.log('✅ bssid_2 column already exists');
    }

    // 3. Ensure hourly_rate exists
    console.log('\n3. Checking hourly_rate column...');
    const hourlyRateCheck = await sql`
      SELECT column_name
      FROM information_schema.columns
      WHERE table_name='employees' AND column_name='hourly_rate'
    `;

    if (hourlyRateCheck.length === 0) {
      console.log('Creating hourly_rate column...');
      await sql`ALTER TABLE employees ADD COLUMN hourly_rate NUMERIC`;
      console.log('✅ Created hourly_rate column');
    } else {
      console.log('✅ hourly_rate column already exists');
    }

    // 4. Fix reviewed_by columns to TEXT (drop foreign keys first)
    console.log('\n4. Fixing reviewed_by and applied_by columns to TEXT...');

    const reviewedByTables = [
      { table: 'attendance_requests', column: 'reviewed_by', fk: 'attendance_requests_reviewed_by_users_id_fk' },
      { table: 'leave_requests', column: 'reviewed_by', fk: 'leave_requests_reviewed_by_users_id_fk' },
      { table: 'advances', column: 'reviewed_by', fk: 'advances_reviewed_by_users_id_fk' },
      { table: 'absence_notifications', column: 'reviewed_by', fk: 'absence_notifications_reviewed_by_users_id_fk' }
    ];

    for (const { table, column, fk } of reviewedByTables) {
      try {
        // Drop foreign key constraint if exists
        await sql.query(`ALTER TABLE ${table} DROP CONSTRAINT IF EXISTS ${fk}`);
        // Change column type to TEXT
        await sql.query(`ALTER TABLE ${table} ALTER COLUMN ${column} TYPE TEXT USING ${column}::TEXT`);
        console.log(`✅ ${table}.${column} changed to TEXT`);
      } catch (err) {
        console.log(`⚠️ ${table}.${column}:`, err.message);
      }
    }

    // Fix deductions.applied_by
    try {
      await sql.query('ALTER TABLE deductions DROP CONSTRAINT IF EXISTS deductions_applied_by_users_id_fk');
      await sql.query('ALTER TABLE deductions ALTER COLUMN applied_by TYPE TEXT USING applied_by::TEXT');
      console.log('✅ deductions.applied_by changed to TEXT');
    } catch (err) {
      console.log('⚠️ deductions.applied_by:', err.message);
    }

    // 5. Fix attendance.modified_by (drop foreign key)
    console.log('\n5. Fixing attendance.modified_by foreign key...');
    try {
      await sql.query('ALTER TABLE attendance DROP CONSTRAINT IF EXISTS attendance_modified_by_employees_id_fk');
      console.log('✅ attendance.modified_by foreign key constraint removed');
    } catch (err) {
      console.log('⚠️ attendance.modified_by:', err.message);
    }

    console.log('\n✅ All schema fixes completed successfully!');
  } catch (error) {
    console.error('❌ Error fixing schema:', error);
    process.exit(1);
  }
}

fixSchema();
