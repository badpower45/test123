-- ============================================================================
-- Attendance System Improvements for HR Application Standards
-- ============================================================================
-- Created: 2025-11-30
-- Description: Add new columns and improve attendance table for HR standards
-- ============================================================================

-- ============================================================================
-- 1. Add new columns to attendance table
-- ============================================================================

-- Break duration field (in minutes)
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS break_duration_minutes INTEGER DEFAULT 0;

-- Late minutes field
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS late_minutes INTEGER DEFAULT 0;

-- Overtime minutes field
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS overtime_minutes INTEGER DEFAULT 0;

-- Net work hours field (after deducting breaks and out-of-zone time)
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS net_work_hours DECIMAL(5,2);

-- Attendance type field
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS attendance_type TEXT DEFAULT 'regular';

-- Pause duration field (in minutes) - from failed pulses
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS pause_duration_minutes INTEGER DEFAULT 0;

-- Scheduled shift start time
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS scheduled_start_time TIME;

-- Scheduled shift end time
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS scheduled_end_time TIME;

-- Overtime rate
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS overtime_rate DECIMAL(3,2) DEFAULT 1.5;

-- Notes field
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS notes TEXT;

-- Auto checkout flag
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS is_auto_checkout BOOLEAN DEFAULT false;

-- ============================================================================
-- 2. Add assigned_manager_id to missing tables
-- ============================================================================

-- Add to leave_requests if not exists
ALTER TABLE leave_requests 
ADD COLUMN IF NOT EXISTS assigned_manager_id TEXT;

-- Add to attendance_requests if not exists
ALTER TABLE attendance_requests 
ADD COLUMN IF NOT EXISTS assigned_manager_id TEXT;

-- Add to salary_advances if not exists
ALTER TABLE salary_advances 
ADD COLUMN IF NOT EXISTS assigned_manager_id TEXT;

-- ============================================================================
-- 3. Create View for daily attendance details
-- ============================================================================

DROP VIEW IF EXISTS v_daily_attendance_details;

CREATE OR REPLACE VIEW v_daily_attendance_details AS
SELECT 
  a.id,
  a.employee_id,
  e.full_name AS employee_name,
  e.branch,
  e.hourly_rate,
  a.date,
  a.check_in_time,
  a.check_out_time,
  a.scheduled_start_time,
  a.scheduled_end_time,
  e.shift_start_time AS employee_shift_start,
  e.shift_end_time AS employee_shift_end,
  a.status,
  a.attendance_type,
  
  -- Gross work hours
  COALESCE(a.work_hours, 0) AS gross_work_hours,
  
  -- Break minutes
  COALESCE(a.break_duration_minutes, 0) AS break_minutes,
  
  -- Pause minutes (out of zone)
  COALESCE(a.pause_duration_minutes, 0) AS pause_minutes,
  
  -- Net work hours
  COALESCE(a.net_work_hours, 
    GREATEST(0, COALESCE(a.work_hours, 0) - (COALESCE(a.break_duration_minutes, 0) + COALESCE(a.pause_duration_minutes, 0)) / 60.0)
  ) AS net_hours,
  
  -- Late minutes
  COALESCE(a.late_minutes, 0) AS late_minutes,
  
  -- Overtime minutes
  COALESCE(a.overtime_minutes, 0) AS overtime_minutes,
  
  -- Calculated late minutes
  CASE 
    WHEN a.check_in_time IS NOT NULL AND a.scheduled_start_time IS NOT NULL THEN
      GREATEST(0, EXTRACT(EPOCH FROM (a.check_in_time::time - a.scheduled_start_time)) / 60)::INTEGER
    WHEN a.check_in_time IS NOT NULL AND e.shift_start_time IS NOT NULL THEN
      GREATEST(0, EXTRACT(EPOCH FROM (a.check_in_time::time - e.shift_start_time::time)) / 60)::INTEGER
    ELSE 0
  END AS calculated_late_minutes,
  
  -- Daily salary
  ROUND(
    COALESCE(a.net_work_hours, 
      GREATEST(0, COALESCE(a.work_hours, 0) - (COALESCE(a.break_duration_minutes, 0) + COALESCE(a.pause_duration_minutes, 0)) / 60.0)
    ) * COALESCE(e.hourly_rate::DECIMAL, 0), 2
  ) AS daily_salary,
  
  -- Overtime salary
  ROUND(
    (COALESCE(a.overtime_minutes, 0) / 60.0) * COALESCE(e.hourly_rate::DECIMAL, 0) * COALESCE(a.overtime_rate, 1.5), 2
  ) AS overtime_salary,
  
  a.notes,
  a.is_auto_checkout,
  a.created_at,
  a.updated_at

FROM attendance a
JOIN employees e ON a.employee_id = e.id
WHERE e.is_active = true;

-- ============================================================================
-- 4. Function to calculate net work hours automatically
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_net_work_hours()
RETURNS TRIGGER AS $$
DECLARE
  v_break_minutes INTEGER;
  v_pause_minutes INTEGER;
  v_gross_hours DECIMAL;
  v_net_hours DECIMAL;
  v_late_minutes INTEGER;
  v_scheduled_start TIME;
  v_employee_shift_start TEXT;
BEGIN
  -- Get shift time from employee if not specified
  IF NEW.scheduled_start_time IS NULL THEN
    SELECT shift_start_time INTO v_employee_shift_start
    FROM employees WHERE id = NEW.employee_id;
    
    IF v_employee_shift_start IS NOT NULL THEN
      NEW.scheduled_start_time := v_employee_shift_start::TIME;
    END IF;
  END IF;
  
  -- Calculate total break time from breaks table
  SELECT COALESCE(SUM(
    CASE 
      WHEN break_end IS NOT NULL THEN
        EXTRACT(EPOCH FROM (break_end - break_start)) / 60
      ELSE 0
    END
  ), 0)::INTEGER INTO v_break_minutes
  FROM breaks
  WHERE employee_id = NEW.employee_id
    AND status = 'COMPLETED'
    AND DATE(break_start) = NEW.date;
  
  NEW.break_duration_minutes := v_break_minutes;
  
  -- Calculate out-of-zone time from failed pulses
  SELECT COALESCE(COUNT(*) * 5, 0)::INTEGER INTO v_pause_minutes
  FROM pulses
  WHERE employee_id = NEW.employee_id
    AND DATE(timestamp) = NEW.date
    AND (is_within_geofence = false OR inside_geofence = false);
  
  NEW.pause_duration_minutes := v_pause_minutes;
  
  -- Calculate gross work hours
  IF NEW.check_in_time IS NOT NULL AND NEW.check_out_time IS NOT NULL THEN
    v_gross_hours := EXTRACT(EPOCH FROM (NEW.check_out_time - NEW.check_in_time)) / 3600.0;
    NEW.work_hours := ROUND(v_gross_hours, 2);
  END IF;
  
  -- Calculate net work hours
  v_gross_hours := COALESCE(NEW.work_hours::DECIMAL, 0);
  v_net_hours := GREATEST(0, v_gross_hours - (v_break_minutes + v_pause_minutes) / 60.0);
  NEW.net_work_hours := ROUND(v_net_hours, 2);
  
  -- Calculate late minutes
  IF NEW.check_in_time IS NOT NULL AND NEW.scheduled_start_time IS NOT NULL THEN
    v_late_minutes := GREATEST(0, 
      EXTRACT(EPOCH FROM (NEW.check_in_time::TIME - NEW.scheduled_start_time)) / 60
    )::INTEGER;
    NEW.late_minutes := v_late_minutes;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Remove old trigger if exists
DROP TRIGGER IF EXISTS trigger_calculate_net_work_hours ON attendance;

-- Create new trigger
CREATE TRIGGER trigger_calculate_net_work_hours
  BEFORE INSERT OR UPDATE OF check_in_time, check_out_time, status
  ON attendance
  FOR EACH ROW
  EXECUTE FUNCTION calculate_net_work_hours();

-- ============================================================================
-- 5. Function to update break duration when break ends
-- ============================================================================

CREATE OR REPLACE FUNCTION update_attendance_break_duration()
RETURNS TRIGGER AS $$
DECLARE
  v_total_break_minutes INTEGER;
  v_attendance_date DATE;
BEGIN
  -- Only when break is completed
  IF NEW.status = 'COMPLETED' AND NEW.break_end IS NOT NULL THEN
    v_attendance_date := DATE(NEW.break_start);
    
    -- Calculate total breaks for this day
    SELECT COALESCE(SUM(
      EXTRACT(EPOCH FROM (break_end - break_start)) / 60
    ), 0)::INTEGER INTO v_total_break_minutes
    FROM breaks
    WHERE employee_id = NEW.employee_id
      AND status = 'COMPLETED'
      AND DATE(break_start) = v_attendance_date;
    
    -- Update attendance record
    UPDATE attendance
    SET break_duration_minutes = v_total_break_minutes,
        net_work_hours = GREATEST(0, COALESCE(work_hours, 0) - (v_total_break_minutes + COALESCE(pause_duration_minutes, 0)) / 60.0)
    WHERE employee_id = NEW.employee_id
      AND date = v_attendance_date;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Remove old trigger if exists
DROP TRIGGER IF EXISTS trigger_update_attendance_break_duration ON breaks;

-- Create new trigger
CREATE TRIGGER trigger_update_attendance_break_duration
  AFTER UPDATE OF status, break_end
  ON breaks
  FOR EACH ROW
  EXECUTE FUNCTION update_attendance_break_duration();

-- ============================================================================
-- 6. Function to update pause duration from pulses
-- ============================================================================

CREATE OR REPLACE FUNCTION update_attendance_pause_duration()
RETURNS TRIGGER AS $$
DECLARE
  v_total_pause_minutes INTEGER;
  v_attendance_date DATE;
BEGIN
  v_attendance_date := DATE(NEW.timestamp);
  
  -- Calculate total out-of-zone time (each pulse = 5 minutes)
  SELECT COALESCE(COUNT(*) * 5, 0)::INTEGER INTO v_total_pause_minutes
  FROM pulses
  WHERE employee_id = NEW.employee_id
    AND DATE(timestamp) = v_attendance_date
    AND (is_within_geofence = false OR inside_geofence = false);
  
  -- Update attendance record
  UPDATE attendance
  SET pause_duration_minutes = v_total_pause_minutes,
      net_work_hours = GREATEST(0, COALESCE(work_hours, 0) - (COALESCE(break_duration_minutes, 0) + v_total_pause_minutes) / 60.0)
  WHERE employee_id = NEW.employee_id
    AND date = v_attendance_date;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Remove old trigger if exists
DROP TRIGGER IF EXISTS trigger_update_attendance_pause_duration ON pulses;

-- Create new trigger
CREATE TRIGGER trigger_update_attendance_pause_duration
  AFTER INSERT
  ON pulses
  FOR EACH ROW
  WHEN (NEW.is_within_geofence = false OR NEW.inside_geofence = false)
  EXECUTE FUNCTION update_attendance_pause_duration();

-- ============================================================================
-- 7. Monthly attendance summary view
-- ============================================================================

DROP VIEW IF EXISTS v_monthly_attendance_summary;

CREATE OR REPLACE VIEW v_monthly_attendance_summary AS
SELECT 
  e.id AS employee_id,
  e.full_name,
  e.branch,
  DATE_TRUNC('month', a.date) AS month,
  
  -- Days present
  COUNT(DISTINCT a.date) AS total_days_present,
  
  -- Total gross hours
  ROUND(SUM(COALESCE(a.work_hours::DECIMAL, 0)), 2) AS total_gross_hours,
  
  -- Total net hours
  ROUND(SUM(COALESCE(a.net_work_hours, 0)), 2) AS total_net_hours,
  
  -- Total break minutes
  SUM(COALESCE(a.break_duration_minutes, 0)) AS total_break_minutes,
  
  -- Total pause minutes
  SUM(COALESCE(a.pause_duration_minutes, 0)) AS total_pause_minutes,
  
  -- Total late minutes
  SUM(COALESCE(a.late_minutes, 0)) AS total_late_minutes,
  
  -- Total overtime minutes
  SUM(COALESCE(a.overtime_minutes, 0)) AS total_overtime_minutes,
  
  -- Auto checkout count
  COUNT(CASE WHEN a.is_auto_checkout = true THEN 1 END) AS auto_checkout_count,
  
  -- Monthly salary (net)
  ROUND(SUM(COALESCE(a.net_work_hours, 0)) * COALESCE(e.hourly_rate::DECIMAL, 0), 2) AS monthly_salary,
  
  -- Overtime salary
  ROUND(SUM((COALESCE(a.overtime_minutes, 0) / 60.0) * COALESCE(e.hourly_rate::DECIMAL, 0) * COALESCE(a.overtime_rate, 1.5)), 2) AS monthly_overtime_salary

FROM employees e
LEFT JOIN attendance a ON e.id = a.employee_id
WHERE e.is_active = true
  AND a.date IS NOT NULL
GROUP BY e.id, e.full_name, e.branch, e.hourly_rate, DATE_TRUNC('month', a.date);

-- ============================================================================
-- 8. Function to get branch daily attendance report
-- ============================================================================

CREATE OR REPLACE FUNCTION get_branch_daily_attendance(
  p_branch_name TEXT,
  p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
  employee_id TEXT,
  employee_name TEXT,
  check_in_time TIMESTAMPTZ,
  check_out_time TIMESTAMPTZ,
  gross_hours DECIMAL,
  break_minutes INTEGER,
  pause_minutes INTEGER,
  net_hours DECIMAL,
  late_minutes INTEGER,
  overtime_minutes INTEGER,
  daily_salary DECIMAL,
  status TEXT,
  attendance_type TEXT,
  is_present BOOLEAN
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    e.id,
    e.full_name,
    a.check_in_time,
    a.check_out_time,
    COALESCE(a.work_hours::DECIMAL, 0),
    COALESCE(a.break_duration_minutes, 0),
    COALESCE(a.pause_duration_minutes, 0),
    COALESCE(a.net_work_hours, 0),
    COALESCE(a.late_minutes, 0),
    COALESCE(a.overtime_minutes, 0),
    ROUND(COALESCE(a.net_work_hours, 0) * COALESCE(e.hourly_rate::DECIMAL, 0), 2),
    COALESCE(a.status, 'absent'),
    COALESCE(a.attendance_type, 'none'),
    (a.id IS NOT NULL)
  FROM employees e
  LEFT JOIN attendance a ON e.id = a.employee_id AND a.date = p_date
  WHERE e.branch = p_branch_name
    AND e.is_active = true
  ORDER BY e.full_name;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 9. Add indexes for better performance
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_attendance_date_employee 
  ON attendance(date, employee_id);

CREATE INDEX IF NOT EXISTS idx_attendance_status_date 
  ON attendance(status, date);

CREATE INDEX IF NOT EXISTS idx_breaks_employee_status 
  ON breaks(employee_id, status);

CREATE INDEX IF NOT EXISTS idx_breaks_break_start 
  ON breaks(break_start);

CREATE INDEX IF NOT EXISTS idx_pulses_employee_geofence 
  ON pulses(employee_id, is_within_geofence);

CREATE INDEX IF NOT EXISTS idx_pulses_timestamp 
  ON pulses(timestamp);

-- ============================================================================
-- 10. Update existing records
-- ============================================================================

-- Update scheduled_start_time from employee data for existing records
UPDATE attendance a
SET scheduled_start_time = e.shift_start_time::TIME
FROM employees e
WHERE a.employee_id = e.id
  AND a.scheduled_start_time IS NULL
  AND e.shift_start_time IS NOT NULL;

-- Update scheduled_end_time from employee data for existing records
UPDATE attendance a
SET scheduled_end_time = e.shift_end_time::TIME
FROM employees e
WHERE a.employee_id = e.id
  AND a.scheduled_end_time IS NULL
  AND e.shift_end_time IS NOT NULL;

-- Recalculate net work hours for existing records
UPDATE attendance
SET net_work_hours = GREATEST(0, COALESCE(work_hours::DECIMAL, 0) - (COALESCE(break_duration_minutes, 0) + COALESCE(pause_duration_minutes, 0)) / 60.0)
WHERE status = 'completed';

-- ============================================================================
-- Migration Complete
-- ============================================================================
