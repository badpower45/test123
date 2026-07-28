-- Fix salary advance summary sync trigger to handle missing request_date safely.

CREATE OR REPLACE FUNCTION sync_daily_attendance_summary_for_approved_advance()
RETURNS TRIGGER AS $$
DECLARE
  v_request_date DATE;
  v_hourly_rate NUMERIC(10,2);
  v_advance_amount NUMERIC(10,2);
BEGIN
  IF NEW.status = 'approved' THEN
    IF TG_OP = 'UPDATE' AND OLD.status = 'approved' THEN
      RETURN NEW;
    END IF;

    SELECT COALESCE(hourly_rate::NUMERIC, 0)
      INTO v_hourly_rate
      FROM employees
     WHERE id = NEW.employee_id;

    v_request_date := COALESCE(
      NEW.request_date::DATE,
      NEW.created_at::DATE,
      CURRENT_DATE
    );
    v_advance_amount := COALESCE(NEW.amount::NUMERIC, 0);

    INSERT INTO daily_attendance_summary (
      employee_id,
      attendance_date,
      check_in_time,
      check_out_time,
      total_hours,
      hourly_rate,
      daily_salary,
      advance_amount,
      is_absent,
      is_on_leave,
      created_at,
      updated_at
    ) VALUES (
      NEW.employee_id,
      v_request_date,
      NULL,
      NULL,
      0,
      COALESCE(v_hourly_rate, 0),
      0,
      v_advance_amount,
      FALSE,
      FALSE,
      NOW(),
      NOW()
    )
    ON CONFLICT (employee_id, attendance_date)
    DO UPDATE SET
      advance_amount = COALESCE(daily_attendance_summary.advance_amount, 0) + EXCLUDED.advance_amount,
      updated_at = NOW();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;