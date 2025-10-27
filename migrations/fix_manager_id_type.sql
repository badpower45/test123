-- Clear invalid manager_id values first
UPDATE branches SET manager_id = NULL WHERE manager_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

-- Fix manager_id type from text to uuid
ALTER TABLE branches 
ALTER COLUMN manager_id TYPE uuid USING manager_id::uuid;

-- Add shift times to employees table
ALTER TABLE employees 
ADD COLUMN IF NOT EXISTS shift_start_time TEXT,
ADD COLUMN IF NOT EXISTS shift_end_time TEXT,
ADD COLUMN IF NOT EXISTS shift_type TEXT;

-- Add comments
COMMENT ON COLUMN employees.shift_start_time IS 'Start time of employee shift (HH:mm format)';
COMMENT ON COLUMN employees.shift_end_time IS 'End time of employee shift (HH:mm format)';
COMMENT ON COLUMN employees.shift_type IS 'Type of shift: AM or PM';
