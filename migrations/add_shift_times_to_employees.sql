-- Add shift time columns to employees table
ALTER TABLE employees ADD COLUMN IF NOT EXISTS shift_start_time TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS shift_end_time TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS shift_type TEXT;

-- Add comments for documentation
COMMENT ON COLUMN employees.shift_start_time IS 'Shift start time in HH:MM format (e.g., 09:00, 21:00)';
COMMENT ON COLUMN employees.shift_end_time IS 'Shift end time in HH:MM format (e.g., 17:00, 05:00)';
COMMENT ON COLUMN employees.shift_type IS 'Shift type: AM or PM';
