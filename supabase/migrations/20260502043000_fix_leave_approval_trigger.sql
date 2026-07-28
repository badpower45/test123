-- Fix leave approval flow when attendance.check_in_time is NOT NULL.
-- Keep leave state in daily_attendance_summary and annotate only existing
-- attendance rows instead of inserting synthetic rows without check-in values.

CREATE OR REPLACE FUNCTION create_attendance_for_approved_leave()
RETURNS TRIGGER AS $$
DECLARE
  v_current_date DATE;
  v_employee RECORD;
  v_attendance_type TEXT;
BEGIN
  IF NEW.status = 'approved' AND (OLD.status IS NULL OR OLD.status != 'approved') THEN
    SELECT * INTO v_employee FROM employees WHERE id = NEW.employee_id;

    v_attendance_type := CASE
      WHEN NEW.leave_type = 'sick' THEN 'sick_leave'
      WHEN NEW.leave_type = 'annual' THEN 'annual_leave'
      WHEN NEW.leave_type = 'emergency' THEN 'emergency_leave'
      ELSE 'leave'
    END;

    v_current_date := NEW.start_date;

    WHILE v_current_date <= NEW.end_date LOOP
      UPDATE attendance
      SET
        status = 'leave',
        attendance_type = v_attendance_type,
        leave_request_id = NEW.id,
        is_leave_day = true,
        notes = COALESCE(notes, '') ||
          CASE WHEN COALESCE(notes, '') = '' THEN '' ELSE ' | ' END ||
          'Leave: ' || COALESCE(NEW.leave_type, 'general'),
        updated_at = NOW()
      WHERE employee_id = NEW.employee_id
        AND date = v_current_date
        AND check_in_time IS NOT NULL;

      INSERT INTO daily_attendance_summary (
        employee_id,
        attendance_date,
        check_in_time,
        check_out_time,
        total_hours,
        hourly_rate,
        daily_salary,
        advance_amount,
        leave_allowance,
        deduction_amount,
        is_absent,
        is_on_leave,
        created_at,
        updated_at
      ) VALUES (
        NEW.employee_id,
        v_current_date,
        NULL,
        NULL,
        0,
        COALESCE(v_employee.hourly_rate, 0),
        0,
        0,
        0,
        0,
        false,
        true,
        NOW(),
        NOW()
      )
      ON CONFLICT (employee_id, attendance_date)
      DO UPDATE SET
        is_on_leave = true,
        is_absent = false,
        updated_at = NOW();

      v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION handle_leave_cancellation()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status IN ('cancelled', 'rejected') AND OLD.status = 'approved' THEN
    UPDATE attendance
    SET
      status = 'absent',
      attendance_type = 'none',
      leave_request_id = NULL,
      is_leave_day = false,
      notes = REPLACE(COALESCE(notes, ''), ' | Leave: ' || COALESCE(OLD.leave_type, 'general'), ''),
      updated_at = NOW()
    WHERE leave_request_id = OLD.id
      AND check_in_time IS NOT NULL;

    UPDATE daily_attendance_summary
    SET
      is_on_leave = false,
      updated_at = NOW()
    WHERE employee_id = OLD.employee_id
      AND attendance_date BETWEEN OLD.start_date AND OLD.end_date
      AND check_in_time IS NULL
      AND COALESCE(total_hours, 0) = 0;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
