-- Fix leave summary sync trigger to avoid referencing a non-existent leave_requests.allowance_amount column.

CREATE OR REPLACE FUNCTION sync_daily_attendance_summary_for_approved_leave()
RETURNS TRIGGER AS $$
DECLARE
  v_current_date DATE;
  v_hourly_rate NUMERIC(10,2);
  v_leave_allowance NUMERIC(10,2);
BEGIN
  IF NEW.status = 'approved' THEN
    IF TG_OP = 'UPDATE' AND OLD.status = 'approved' THEN
      RETURN NEW;
    END IF;

    SELECT
      COALESCE(hourly_rate::NUMERIC, 0),
      COALESCE(leave_allowance::NUMERIC, 0)
      INTO v_hourly_rate, v_leave_allowance
      FROM employees
     WHERE id = NEW.employee_id;

    v_current_date := NEW.start_date;

    WHILE v_current_date <= NEW.end_date LOOP
      INSERT INTO daily_attendance_summary (
        employee_id,
        attendance_date,
        check_in_time,
        check_out_time,
        total_hours,
        hourly_rate,
        daily_salary,
        deduction_amount,
        leave_allowance,
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
        COALESCE(v_hourly_rate, 0),
        0,
        0,
        v_leave_allowance,
        FALSE,
        TRUE,
        NOW(),
        NOW()
      )
      ON CONFLICT (employee_id, attendance_date)
      DO UPDATE SET
        check_in_time = EXCLUDED.check_in_time,
        check_out_time = EXCLUDED.check_out_time,
        total_hours = EXCLUDED.total_hours,
        hourly_rate = EXCLUDED.hourly_rate,
        daily_salary = EXCLUDED.daily_salary,
        deduction_amount = 0,
        leave_allowance = EXCLUDED.leave_allowance,
        is_absent = FALSE,
        is_on_leave = TRUE,
        updated_at = NOW();

      v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;