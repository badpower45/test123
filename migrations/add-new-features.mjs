import { neon } from '@neondatabase/serverless';
import { config } from 'dotenv';
import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load environment variables
config({ path: resolve(__dirname, '../.env') });

const sql = neon(process.env.DATABASE_URL);

async function migrate() {
  console.log('🚀 Starting migration: Add new features...\n');

  try {
    // 1. Create device_sessions table
    console.log('Creating device_sessions table...');
    await sql`
      CREATE TABLE IF NOT EXISTS device_sessions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
        device_id TEXT NOT NULL,
        device_name TEXT,
        device_model TEXT,
        os_version TEXT,
        app_version TEXT,
        last_active_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        is_active BOOLEAN NOT NULL DEFAULT true,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `;
    await sql`CREATE INDEX IF NOT EXISTS idx_device_sessions_employee_id ON device_sessions(employee_id)`;
    await sql`CREATE INDEX IF NOT EXISTS idx_device_sessions_device_id ON device_sessions(device_id)`;
    await sql`CREATE INDEX IF NOT EXISTS idx_device_sessions_is_active ON device_sessions(is_active)`;
    console.log('✅ device_sessions table created\n');

    // 2. Create notification_type enum and notifications table
    console.log('Creating notifications table...');
    await sql`
      DO $$ 
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_type') THEN
          CREATE TYPE notification_type AS ENUM (
            'CHECK_IN',
            'CHECK_OUT',
            'LEAVE_REQUEST',
            'ADVANCE_REQUEST',
            'ATTENDANCE_REQUEST',
            'ABSENCE_ALERT',
            'SALARY_PAID',
            'GENERAL'
          );
        END IF;
      END $$;
    `;
    
    await sql`
      CREATE TABLE IF NOT EXISTS notifications (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        recipient_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
        sender_id TEXT REFERENCES employees(id) ON DELETE SET NULL,
        type notification_type NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        related_id UUID,
        is_read BOOLEAN NOT NULL DEFAULT false,
        read_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `;
    await sql`CREATE INDEX IF NOT EXISTS idx_notifications_recipient_id ON notifications(recipient_id)`;
    await sql`CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type)`;
    await sql`CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON notifications(is_read)`;
    await sql`CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at)`;
    console.log('✅ notifications table created\n');

    // 3. Create salary_calculations table
    console.log('Creating salary_calculations table...');
    await sql`
      CREATE TABLE IF NOT EXISTS salary_calculations (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
        period_start DATE NOT NULL,
        period_end DATE NOT NULL,
        base_salary NUMERIC NOT NULL,
        total_work_hours NUMERIC NOT NULL DEFAULT 0,
        total_work_days INTEGER NOT NULL DEFAULT 0,
        overtime_hours NUMERIC DEFAULT 0,
        overtime_amount NUMERIC DEFAULT 0,
        advances_total NUMERIC DEFAULT 0,
        deductions_total NUMERIC DEFAULT 0,
        absence_deductions NUMERIC DEFAULT 0,
        net_salary NUMERIC NOT NULL,
        is_paid BOOLEAN NOT NULL DEFAULT false,
        paid_at TIMESTAMPTZ,
        notes TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `;
    await sql`CREATE INDEX IF NOT EXISTS idx_salary_calculations_employee_id ON salary_calculations(employee_id)`;
    await sql`CREATE INDEX IF NOT EXISTS idx_salary_calculations_period_start ON salary_calculations(period_start)`;
    await sql`CREATE INDEX IF NOT EXISTS idx_salary_calculations_is_paid ON salary_calculations(is_paid)`;
    console.log('✅ salary_calculations table created\n');

    // 4. Add new columns to attendance table
    console.log('Adding new columns to attendance table...');
    await sql`ALTER TABLE attendance ADD COLUMN IF NOT EXISTS actual_check_in_time TIMESTAMPTZ`;
    await sql`ALTER TABLE attendance ADD COLUMN IF NOT EXISTS modified_check_in_time TIMESTAMPTZ`;
    await sql`ALTER TABLE attendance ADD COLUMN IF NOT EXISTS modified_by TEXT REFERENCES employees(id)`;
    await sql`ALTER TABLE attendance ADD COLUMN IF NOT EXISTS modified_at TIMESTAMPTZ`;
    await sql`ALTER TABLE attendance ADD COLUMN IF NOT EXISTS modification_reason TEXT`;
    console.log('✅ attendance table updated\n');

    // 5. Add deducted flag to advances table
    console.log('Updating advances table...');
    await sql`ALTER TABLE advances ADD COLUMN IF NOT EXISTS is_deducted BOOLEAN DEFAULT false`;
    console.log('✅ advances table updated\n');

    console.log('🎉 Migration completed successfully!');
  } catch (error) {
    console.error('❌ Migration failed:', error);
    throw error;
  }
}

migrate()
  .then(() => process.exit(0))
  .catch(() => process.exit(1));
