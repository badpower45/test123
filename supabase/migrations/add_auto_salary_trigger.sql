-- Function to automatically calculate daily salary when attendance is completed
CREATE OR REPLACE FUNCTION auto_calculate_daily_salary()
RETURNS TRIGGER AS $$
DECLARE
  v_hourly_rate DECIMAL(10, 2);
  v_total_work_hours DECIMAL(10, 2);
  v_false_pulses_count INTEGER;
  v_gross_salary DECIMAL(10, 2);
  v_pulse_deduction DECIMAL(10, 2);
  v_per_minute_rate DECIMAL(10, 2);
  v_net_salary DECIMAL(10, 2);
BEGIN
  -- Only trigger when status changes to 'completed'
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    
    -- Get employee hourly rate
    SELECT COALESCE(hourly_rate, 60) INTO v_hourly_rate
    FROM employees
    WHERE id = NEW.employee_id;
    
    v_per_minute_rate := v_hourly_rate / 60.0;
    
    -- Calculate total work hours for this date
    SELECT COALESCE(SUM(COALESCE(work_hours, total_hours, 0)), 0) INTO v_total_work_hours
    FROM attendance
    WHERE employee_id = NEW.employee_id
      AND date = NEW.date
      AND status = 'completed';
    
    -- Count false pulses for this date
    SELECT COUNT(*) INTO v_false_pulses_count
    FROM pulses
    WHERE employee_id = NEW.employee_id
      AND is_within_geofence = false
      AND timestamp::date = NEW.date;
    
    -- Calculate salaries
    v_gross_salary := v_total_work_hours * v_hourly_rate;
    v_pulse_deduction := v_false_pulses_count * 5 * v_per_minute_rate; -- 5 minutes per false pulse
    v_net_salary := GREATEST(0, v_gross_salary - v_pulse_deduction);
    
    -- Upsert into daily_salary_calculations
    INSERT INTO daily_salary_calculations (
      employee_id,
      calculation_date,
      total_work_hours,
      hourly_rate,
      gross_salary,
      false_pulses_count,
      pulse_deduction_amount,
      other_deductions,
      total_deductions,
      net_salary,
      created_at,
      updated_at
    ) VALUES (
      NEW.employee_id,
      NEW.date,
      v_total_work_hours,
      v_hourly_rate,
      v_gross_salary,
      v_false_pulses_count,
      v_pulse_deduction,
      0,
      v_pulse_deduction,
      v_net_salary,
      NOW(),
      NOW()
    )
    ON CONFLICT (employee_id, calculation_date)
    DO UPDATE SET
      total_work_hours = EXCLUDED.total_work_hours,
      hourly_rate = EXCLUDED.hourly_rate,
      gross_salary = EXCLUDED.gross_salary,
      false_pulses_count = EXCLUDED.false_pulses_count,
      pulse_deduction_amount = EXCLUDED.pulse_deduction_amount,
      total_deductions = EXCLUDED.total_deductions,
      net_salary = EXCLUDED.net_salary,
      updated_at = NOW();
    
    RAISE NOTICE 'Daily salary calculated for % on %: % hours, % EGP net', 
      NEW.employee_id, NEW.date, v_total_work_hours, v_net_salary;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger on attendance table
DROP TRIGGER IF EXISTS trigger_auto_calculate_salary ON attendance;
CREATE TRIGGER trigger_auto_calculate_salary
  AFTER INSERT OR UPDATE ON attendance
  FOR EACH ROW
  EXECUTE FUNCTION auto_calculate_daily_salary();

-- Also create a function to recalculate for existing completed attendance records
CREATE OR REPLACE FUNCTION recalculate_all_daily_salaries()
RETURNS TABLE (
  out_employee_id TEXT,
  out_calculation_date DATE,
  out_net_salary DECIMAL(10, 2)
) AS $$
DECLARE
  v_record RECORD;
  v_hourly_rate DECIMAL(10, 2);
  v_total_work_hours DECIMAL(10, 2);
  v_false_pulses_count INTEGER;
  v_gross_salary DECIMAL(10, 2);
  v_pulse_deduction DECIMAL(10, 2);
  v_per_minute_rate DECIMAL(10, 2);
  v_net_salary DECIMAL(10, 2);
BEGIN
  -- Loop through all completed attendance records
  FOR v_record IN 
    SELECT DISTINCT a.employee_id, a.date
    FROM attendance a
    WHERE a.status = 'completed'
    ORDER BY a.date DESC, a.employee_id
  LOOP
    -- Get employee hourly rate
    SELECT COALESCE(e.hourly_rate, 60) INTO v_hourly_rate
    FROM employees e
    WHERE e.id = v_record.employee_id;
    
    v_per_minute_rate := v_hourly_rate / 60.0;
    
    -- Calculate total work hours for this date
    SELECT COALESCE(SUM(COALESCE(a.work_hours, a.total_hours, 0)), 0) INTO v_total_work_hours
    FROM attendance a
    WHERE a.employee_id = v_record.employee_id
      AND a.date = v_record.date
      AND a.status = 'completed';
    
    -- Count false pulses for this date
    SELECT COUNT(*) INTO v_false_pulses_count
    FROM pulses p
    WHERE p.employee_id = v_record.employee_id
      AND p.is_within_geofence = false
      AND p.timestamp::date = v_record.date;
    
    -- Calculate salaries
    v_gross_salary := v_total_work_hours * v_hourly_rate;
    v_pulse_deduction := v_false_pulses_count * 5 * v_per_minute_rate;
    v_net_salary := GREATEST(0, v_gross_salary - v_pulse_deduction);
    
    -- Upsert into daily_salary_calculations
    INSERT INTO daily_salary_calculations (
      employee_id,
      calculation_date,
      total_work_hours,
      hourly_rate,
      gross_salary,
      false_pulses_count,
      pulse_deduction_amount,
      other_deductions,
      total_deductions,
      net_salary,
      created_at,
      updated_at
    ) VALUES (
      v_record.employee_id,
      v_record.date,
      v_total_work_hours,
      v_hourly_rate,
      v_gross_salary,
      v_false_pulses_count,
      v_pulse_deduction,
      0,
      v_pulse_deduction,
      v_net_salary,
      NOW(),
      NOW()
    )
    ON CONFLICT (employee_id, calculation_date)
    DO UPDATE SET
      total_work_hours = EXCLUDED.total_work_hours,
      hourly_rate = EXCLUDED.hourly_rate,
      gross_salary = EXCLUDED.gross_salary,
      false_pulses_count = EXCLUDED.false_pulses_count,
      pulse_deduction_amount = EXCLUDED.pulse_deduction_amount,
      total_deductions = EXCLUDED.total_deductions,
      net_salary = EXCLUDED.net_salary,
      updated_at = NOW();
    
    -- Return this record
    out_employee_id := v_record.employee_id;
    out_calculation_date := v_record.date;
    out_net_salary := v_net_salary;
    RETURN NEXT;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Run the recalculation for all existing records
SELECT * FROM recalculate_all_daily_salaries();

COMMENT ON FUNCTION auto_calculate_daily_salary() IS 'Automatically calculates and stores daily salary when attendance status becomes completed';
COMMENT ON FUNCTION recalculate_all_daily_salaries() IS 'Recalculates daily salaries for all completed attendance records';
