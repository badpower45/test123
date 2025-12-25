-- ============================================================================
-- Leave Integration with Attendance System
-- ============================================================================
-- Created: 2025-11-30
-- Description: Auto-mark approved leaves in daily attendance
-- ============================================================================

-- ============================================================================
-- 1. Add leave_request_id to attendance table
-- ============================================================================

ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS leave_request_id UUID REFERENCES leave_requests(id);

ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS is_leave_day BOOLEAN DEFAULT false;

-- ============================================================================
-- 2. Create function to auto-create attendance records for approved leaves
-- ============================================================================

CREATE OR REPLACE FUNCTION create_attendance_for_approved_leave()
RETURNS TRIGGER AS $$
DECLARE
  v_current_date DATE;
  v_employee RECORD;
BEGIN
  -- Only trigger when leave is approved
  IF NEW.status = 'approved' AND (OLD.status IS NULL OR OLD.status != 'approved') THEN
    
    -- Get employee info
    SELECT * INTO v_employee FROM employees WHERE id = NEW.employee_id;
    
    -- Loop through each day of the leave period
    v_current_date := NEW.start_date;
    
    WHILE v_current_date <= NEW.end_date LOOP
      -- Check if attendance record already exists for this day
      IF NOT EXISTS (
        SELECT 1 FROM attendance 
        WHERE employee_id = NEW.employee_id 
        AND date = v_current_date
      ) THEN
        -- Create attendance record for leave day
        INSERT INTO attendance (
          employee_id,
          date,
          status,
          attendance_type,
          leave_request_id,
          is_leave_day,
          notes,
          work_hours,
          net_work_hours,
          scheduled_start_time,
          scheduled_end_time
        ) VALUES (
          NEW.employee_id,
          v_current_date,
          'leave',
          CASE 
            WHEN NEW.leave_type = 'sick' THEN 'sick_leave'
            WHEN NEW.leave_type = 'annual' THEN 'annual_leave'
            WHEN NEW.leave_type = 'emergency' THEN 'emergency_leave'
            ELSE 'leave'
          END,
          NEW.id,
          true,
          'Leave: ' || COALESCE(NEW.leave_type, 'general') || ' - ' || COALESCE(NEW.reason, ''),
          0,
          0,
          v_employee.shift_start_time::TIME,
          v_employee.shift_end_time::TIME
        );
      ELSE
        -- Update existing record to mark as leave
        UPDATE attendance SET
          status = 'leave',
          attendance_type = CASE 
            WHEN NEW.leave_type = 'sick' THEN 'sick_leave'
            WHEN NEW.leave_type = 'annual' THEN 'annual_leave'
            WHEN NEW.leave_type = 'emergency' THEN 'emergency_leave'
            ELSE 'leave'
          END,
          leave_request_id = NEW.id,
          is_leave_day = true,
          notes = COALESCE(notes, '') || ' | Leave: ' || COALESCE(NEW.leave_type, 'general'),
          updated_at = NOW()
        WHERE employee_id = NEW.employee_id 
        AND date = v_current_date;
      END IF;
      
      v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop old trigger if exists
DROP TRIGGER IF EXISTS trigger_create_attendance_for_leave ON leave_requests;

-- Create trigger
CREATE TRIGGER trigger_create_attendance_for_leave
  AFTER INSERT OR UPDATE OF status
  ON leave_requests
  FOR EACH ROW
  EXECUTE FUNCTION create_attendance_for_approved_leave();

-- ============================================================================
-- 3. Create function to handle leave cancellation
-- ============================================================================

CREATE OR REPLACE FUNCTION handle_leave_cancellation()
RETURNS TRIGGER AS $$
BEGIN
  -- If leave is cancelled or rejected, remove leave marks from attendance
  IF NEW.status IN ('cancelled', 'rejected') AND OLD.status = 'approved' THEN
    
    -- Update attendance records to remove leave marking
    UPDATE attendance SET
      status = 'absent',
      attendance_type = 'none',
      leave_request_id = NULL,
      is_leave_day = false,
      notes = REPLACE(COALESCE(notes, ''), ' | Leave: ' || COALESCE(OLD.leave_type, 'general'), ''),
      updated_at = NOW()
    WHERE leave_request_id = OLD.id
    AND check_in_time IS NULL; -- Only update if no actual check-in happened
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop old trigger if exists
DROP TRIGGER IF EXISTS trigger_handle_leave_cancellation ON leave_requests;

-- Create trigger
CREATE TRIGGER trigger_handle_leave_cancellation
  AFTER UPDATE OF status
  ON leave_requests
  FOR EACH ROW
  EXECUTE FUNCTION handle_leave_cancellation();

-- ============================================================================
-- 4. Update daily attendance view to include leave info
-- ============================================================================

DROP VIEW IF EXISTS v_daily_attendance_with_leaves;

CREATE OR REPLACE VIEW v_daily_attendance_with_leaves AS
SELECT 
  a.id,
  a.employee_id,
  e.full_name AS employee_name,
  e.branch,
  a.date,
  a.check_in_time,
  a.check_out_time,
  a.status,
  a.attendance_type,
  a.is_leave_day,
  a.leave_request_id,
  lr.leave_type,
  lr.reason AS leave_reason,
  lr.start_date AS leave_start,
  lr.end_date AS leave_end,
  COALESCE(a.work_hours, 0) AS work_hours,
  COALESCE(a.net_work_hours, 0) AS net_work_hours,
  a.late_minutes,
  a.notes,
  CASE 
    WHEN a.is_leave_day = true THEN 'On Leave'
    WHEN a.check_in_time IS NOT NULL AND a.check_out_time IS NOT NULL THEN 'Present'
    WHEN a.check_in_time IS NOT NULL THEN 'Checked In'
    ELSE 'Absent'
  END AS attendance_status_display,
  a.created_at
FROM attendance a
JOIN employees e ON a.employee_id = e.id
LEFT JOIN leave_requests lr ON a.leave_request_id = lr.id
WHERE e.is_active = true;

-- ============================================================================
-- 5. Function to get employee attendance including leaves for date range
-- ============================================================================

CREATE OR REPLACE FUNCTION get_employee_attendance_with_leaves(
  p_employee_id TEXT,
  p_start_date DATE,
  p_end_date DATE
)
RETURNS TABLE (
  date DATE,
  status TEXT,
  attendance_type TEXT,
  is_leave BOOLEAN,
  leave_type TEXT,
  check_in_time TIMESTAMPTZ,
  check_out_time TIMESTAMPTZ,
  work_hours DECIMAL,
  net_work_hours DECIMAL,
  late_minutes INTEGER
) AS $$
BEGIN
  RETURN QUERY
  WITH date_series AS (
    SELECT generate_series(p_start_date, p_end_date, '1 day'::interval)::DATE AS day
  ),
  attendance_data AS (
    SELECT 
      a.date,
      a.status,
      a.attendance_type,
      a.is_leave_day,
      lr.leave_type,
      a.check_in_time,
      a.check_out_time,
      COALESCE(a.work_hours::DECIMAL, 0) AS work_hours,
      COALESCE(a.net_work_hours, 0) AS net_work_hours,
      COALESCE(a.late_minutes, 0) AS late_minutes
    FROM attendance a
    LEFT JOIN leave_requests lr ON a.leave_request_id = lr.id
    WHERE a.employee_id = p_employee_id
    AND a.date BETWEEN p_start_date AND p_end_date
  ),
  approved_leaves AS (
    SELECT 
      d.day AS date,
      'leave' AS status,
      lr.leave_type || '_leave' AS attendance_type,
      true AS is_leave_day,
      lr.leave_type
    FROM date_series d
    JOIN leave_requests lr ON d.day BETWEEN lr.start_date AND lr.end_date
    WHERE lr.employee_id = p_employee_id
    AND lr.status = 'approved'
  )
  SELECT 
    ds.day,
    COALESCE(ad.status, al.status, 'absent') AS status,
    COALESCE(ad.attendance_type, al.attendance_type, 'none') AS attendance_type,
    COALESCE(ad.is_leave_day, al.is_leave_day, false) AS is_leave,
    COALESCE(ad.leave_type, al.leave_type) AS leave_type,
    ad.check_in_time,
    ad.check_out_time,
    COALESCE(ad.work_hours, 0),
    COALESCE(ad.net_work_hours, 0),
    COALESCE(ad.late_minutes, 0)
  FROM date_series ds
  LEFT JOIN attendance_data ad ON ds.day = ad.date
  LEFT JOIN approved_leaves al ON ds.day = al.date AND ad.date IS NULL
  ORDER BY ds.day;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 6. Monthly summary including leaves
-- ============================================================================

DROP VIEW IF EXISTS v_monthly_summary_with_leaves;

CREATE OR REPLACE VIEW v_monthly_summary_with_leaves AS
SELECT 
  e.id AS employee_id,
  e.full_name,
  e.branch,
  DATE_TRUNC('month', a.date) AS month,
  
  -- Days present (actual attendance)
  COUNT(DISTINCT CASE WHEN a.check_in_time IS NOT NULL AND a.is_leave_day = false THEN a.date END) AS days_present,
  
  -- Leave days
  COUNT(DISTINCT CASE WHEN a.is_leave_day = true THEN a.date END) AS leave_days,
  
  -- Sick leave days
  COUNT(DISTINCT CASE WHEN a.attendance_type = 'sick_leave' THEN a.date END) AS sick_leave_days,
  
  -- Annual leave days
  COUNT(DISTINCT CASE WHEN a.attendance_type = 'annual_leave' THEN a.date END) AS annual_leave_days,
  
  -- Absent days (no attendance and no approved leave)
  COUNT(DISTINCT CASE WHEN a.check_in_time IS NULL AND a.is_leave_day = false THEN a.date END) AS absent_days,
  
  -- Total work hours
  ROUND(SUM(CASE WHEN a.is_leave_day = false THEN COALESCE(a.work_hours::DECIMAL, 0) ELSE 0 END), 2) AS total_work_hours,
  
  -- Net work hours
  ROUND(SUM(CASE WHEN a.is_leave_day = false THEN COALESCE(a.net_work_hours, 0) ELSE 0 END), 2) AS total_net_hours,
  
  -- Late minutes
  SUM(CASE WHEN a.is_leave_day = false THEN COALESCE(a.late_minutes, 0) ELSE 0 END) AS total_late_minutes,
  
  -- Calculated salary (only for actual work days)
  ROUND(SUM(CASE WHEN a.is_leave_day = false THEN COALESCE(a.net_work_hours, 0) ELSE 0 END) * COALESCE(e.hourly_rate::DECIMAL, 0), 2) AS monthly_salary

FROM employees e
LEFT JOIN attendance a ON e.id = a.employee_id
WHERE e.is_active = true
  AND a.date IS NOT NULL
GROUP BY e.id, e.full_name, e.branch, e.hourly_rate, DATE_TRUNC('month', a.date);

-- ============================================================================
-- 7. Backfill existing approved leaves
-- ============================================================================

DO $$
DECLARE
  v_leave RECORD;
  v_current_date DATE;
  v_employee RECORD;
BEGIN
  -- Loop through all approved leaves
  FOR v_leave IN 
    SELECT * FROM leave_requests WHERE status = 'approved'
  LOOP
    -- Get employee info
    SELECT * INTO v_employee FROM employees WHERE id = v_leave.employee_id;
    
    -- Loop through each day
    v_current_date := v_leave.start_date;
    
    WHILE v_current_date <= v_leave.end_date LOOP
      -- Insert or update attendance record
      INSERT INTO attendance (
        employee_id,
        date,
        status,
        attendance_type,
        leave_request_id,
        is_leave_day,
        notes,
        work_hours,
        net_work_hours
      ) VALUES (
        v_leave.employee_id,
        v_current_date,
        'leave',
        CASE 
          WHEN v_leave.leave_type = 'sick' THEN 'sick_leave'
          WHEN v_leave.leave_type = 'annual' THEN 'annual_leave'
          WHEN v_leave.leave_type = 'emergency' THEN 'emergency_leave'
          ELSE 'leave'
        END,
        v_leave.id,
        true,
        'Backfilled Leave: ' || COALESCE(v_leave.leave_type, 'general'),
        0,
        0
      )
      ON CONFLICT (employee_id, date) 
      DO UPDATE SET
        leave_request_id = v_leave.id,
        is_leave_day = true,
        attendance_type = CASE 
          WHEN v_leave.leave_type = 'sick' THEN 'sick_leave'
          WHEN v_leave.leave_type = 'annual' THEN 'annual_leave'
          ELSE 'leave'
        END
      WHERE attendance.check_in_time IS NULL;
      
      v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;
  END LOOP;
  
  RAISE NOTICE 'Backfilled attendance records for existing approved leaves';
END $$;

-- ============================================================================
-- 8. Add unique constraint for employee + date (if not exists)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'attendance_employee_date_unique'
  ) THEN
    -- First, handle duplicates by keeping the most recent record
    DELETE FROM attendance a1
    USING attendance a2
    WHERE a1.employee_id = a2.employee_id 
    AND a1.date = a2.date 
    AND a1.created_at < a2.created_at;
    
    -- Now add the unique constraint
    ALTER TABLE attendance 
    ADD CONSTRAINT attendance_employee_date_unique UNIQUE (employee_id, date);
  END IF;
EXCEPTION
  WHEN others THEN
    RAISE NOTICE 'Could not add unique constraint: %', SQLERRM;
END $$;

-- ============================================================================
-- Migration Complete
-- ============================================================================
