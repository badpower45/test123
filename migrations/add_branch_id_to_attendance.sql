-- ============================================
-- Add branch_id column to attendance table
-- This is needed for tracking which branch 
-- the employee checked in from
-- ============================================

-- Add branch_id column to attendance table (if not exists)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'attendance' AND column_name = 'branch_id'
    ) THEN
        ALTER TABLE attendance ADD COLUMN branch_id UUID REFERENCES branches(id) ON DELETE SET NULL;
        RAISE NOTICE 'Added branch_id column to attendance table';
    ELSE
        RAISE NOTICE 'branch_id column already exists in attendance table';
    END IF;
END $$;

-- Add index on branch_id for faster queries
CREATE INDEX IF NOT EXISTS idx_attendance_branch_id ON attendance(branch_id);

-- Add latitude column if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'attendance' AND column_name = 'latitude'
    ) THEN
        ALTER TABLE attendance ADD COLUMN latitude NUMERIC(10, 7);
    END IF;
END $$;

-- Add longitude column if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'attendance' AND column_name = 'longitude'
    ) THEN
        ALTER TABLE attendance ADD COLUMN longitude NUMERIC(10, 7);
    END IF;
END $$;

-- Add is_within_geofence column if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'attendance' AND column_name = 'is_within_geofence'
    ) THEN
        ALTER TABLE attendance ADD COLUMN is_within_geofence BOOLEAN DEFAULT true;
    END IF;
END $$;

-- Add date column if not exists (for faster date-based queries)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'attendance' AND column_name = 'date'
    ) THEN
        ALTER TABLE attendance ADD COLUMN date DATE;
        -- Populate existing records
        UPDATE attendance SET date = (check_in_time AT TIME ZONE 'Africa/Cairo')::DATE WHERE date IS NULL;
        RAISE NOTICE 'Added date column to attendance table';
    END IF;
END $$;

-- Add work_hours column if not exists (computed total)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'attendance' AND column_name = 'work_hours'
    ) THEN
        ALTER TABLE attendance ADD COLUMN work_hours NUMERIC(10, 2);
    END IF;
END $$;

-- Add check_in_wifi_bssid column if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'attendance' AND column_name = 'check_in_wifi_bssid'
    ) THEN
        ALTER TABLE attendance ADD COLUMN check_in_wifi_bssid TEXT;
    END IF;
END $$;

-- Add check_out_wifi_bssid column if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'attendance' AND column_name = 'check_out_wifi_bssid'
    ) THEN
        ALTER TABLE attendance ADD COLUMN check_out_wifi_bssid TEXT;
    END IF;
END $$;

-- Create composite index for employee and date queries
CREATE INDEX IF NOT EXISTS idx_attendance_employee_date ON attendance(employee_id, date);

-- Create unique constraint to prevent duplicate check-ins on same day
-- (Optional - uncomment if you want to enforce one check-in per day)
-- CREATE UNIQUE INDEX IF NOT EXISTS attendance_employee_date_unique ON attendance(employee_id, date);

COMMENT ON COLUMN attendance.branch_id IS 'The branch where the employee checked in';
COMMENT ON COLUMN attendance.date IS 'Date of check-in in Cairo timezone';
COMMENT ON COLUMN attendance.is_within_geofence IS 'Whether the employee was inside the allowed area at check-in';
COMMENT ON COLUMN attendance.check_in_wifi_bssid IS 'WiFi BSSID used for check-in validation';
