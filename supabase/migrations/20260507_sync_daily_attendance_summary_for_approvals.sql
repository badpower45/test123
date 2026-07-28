-- Sync approved leave and salary advance requests into daily_attendance_summary

-- ----------------------------------------------------------------------------
-- Leave approvals: mark each approved leave day in the daily summary
-- ----------------------------------------------------------------------------

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

    SELECT COALESCE(hourly_rate::NUMERIC, 0)
      INTO v_hourly_rate
      FROM employees
     WHERE id = NEW.employee_id;

    v_leave_allowance := COALESCE(NEW.allowance_amount::NUMERIC, 0);
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

DROP TRIGGER IF EXISTS trigger_sync_daily_summary_for_leave ON leave_requests;

CREATE TRIGGER trigger_sync_daily_summary_for_leave
  AFTER INSERT OR UPDATE OF status
  ON leave_requests
  FOR EACH ROW
  EXECUTE FUNCTION sync_daily_attendance_summary_for_approved_leave();


-- ----------------------------------------------------------------------------
-- Salary advances: write the approved advance into the request date summary row
-- ----------------------------------------------------------------------------

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

    v_request_date := NEW.request_date::DATE;
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

DROP TRIGGER IF EXISTS trigger_sync_daily_summary_for_advance ON salary_advances;

CREATE TRIGGER trigger_sync_daily_summary_for_advance
  AFTER INSERT OR UPDATE OF status
  ON salary_advances
  FOR EACH ROW
  EXECUTE FUNCTION sync_daily_attendance_summary_for_approved_advance();

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'advances'
  ) THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trigger_sync_daily_summary_for_advance_legacy ON advances';
    EXECUTE '
      CREATE TRIGGER trigger_sync_daily_summary_for_advance_legacy
        AFTER INSERT OR UPDATE OF status
        ON advances
        FOR EACH ROW
        EXECUTE FUNCTION sync_daily_attendance_summary_for_approved_advance()';
  END IF;
END;
$$;