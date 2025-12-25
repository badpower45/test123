-- Create table for up-to-date cumulative salary
CREATE TABLE IF NOT EXISTS up_to_date_salary (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL UNIQUE REFERENCES employees(id) ON DELETE CASCADE,
  
  -- Cumulative totals
  total_work_hours DECIMAL(10, 2) DEFAULT 0,
  total_gross_salary DECIMAL(10, 2) DEFAULT 0,
  total_deductions DECIMAL(10, 2) DEFAULT 0,
  total_net_salary DECIMAL(10, 2) DEFAULT 0,
  
  -- Period info
  period_start_date DATE,
  period_end_date DATE,
  last_calculation_date DATE,
  
  -- Metadata
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index
CREATE INDEX IF NOT EXISTS idx_up_to_date_salary_employee 
  ON up_to_date_salary(employee_id);

-- Enable RLS
ALTER TABLE up_to_date_salary ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Employees can view their own up-to-date salary"
  ON up_to_date_salary FOR SELECT
  USING (employee_id = auth.jwt() ->> 'employee_id');

CREATE POLICY "Owners and admins can view all up-to-date salaries"
  ON up_to_date_salary FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM employees 
      WHERE employees.id = auth.jwt() ->> 'employee_id'
      AND employees.role IN ('owner', 'admin', 'hr', 'manager')
    )
  );

CREATE POLICY "Service role can do everything"
  ON up_to_date_salary FOR ALL
  USING (auth.role() = 'service_role');

CREATE POLICY "Authenticated users can read up-to-date salaries"
  ON up_to_date_salary FOR SELECT
  TO authenticated
  USING (true);

-- Function to update up_to_date_salary when daily_salary_calculations changes
CREATE OR REPLACE FUNCTION update_up_to_date_salary()
RETURNS TRIGGER AS $$
DECLARE
  v_total_hours DECIMAL(10, 2);
  v_total_gross DECIMAL(10, 2);
  v_total_deductions DECIMAL(10, 2);
  v_total_net DECIMAL(10, 2);
  v_period_start DATE;
  v_period_end DATE;
  v_last_calc_date DATE;
BEGIN
  -- Determine which employee_id to update
  DECLARE
    v_employee_id TEXT;
  BEGIN
    IF TG_OP = 'DELETE' THEN
      v_employee_id := OLD.employee_id;
    ELSE
      v_employee_id := NEW.employee_id;
    END IF;
    
    -- Calculate cumulative totals for this employee
    SELECT 
      COALESCE(SUM(total_work_hours), 0),
      COALESCE(SUM(gross_salary), 0),
      COALESCE(SUM(total_deductions), 0),
      COALESCE(SUM(net_salary), 0),
      MIN(calculation_date),
      MAX(calculation_date),
      MAX(calculation_date)
    INTO 
      v_total_hours,
      v_total_gross,
      v_total_deductions,
      v_total_net,
      v_period_start,
      v_period_end,
      v_last_calc_date
    FROM daily_salary_calculations
    WHERE employee_id = v_employee_id;
    
    -- Upsert into up_to_date_salary
    INSERT INTO up_to_date_salary (
      employee_id,
      total_work_hours,
      total_gross_salary,
      total_deductions,
      total_net_salary,
      period_start_date,
      period_end_date,
      last_calculation_date,
      created_at,
      updated_at
    ) VALUES (
      v_employee_id,
      v_total_hours,
      v_total_gross,
      v_total_deductions,
      v_total_net,
      v_period_start,
      v_period_end,
      v_last_calc_date,
      NOW(),
      NOW()
    )
    ON CONFLICT (employee_id)
    DO UPDATE SET
      total_work_hours = EXCLUDED.total_work_hours,
      total_gross_salary = EXCLUDED.total_gross_salary,
      total_deductions = EXCLUDED.total_deductions,
      total_net_salary = EXCLUDED.total_net_salary,
      period_start_date = EXCLUDED.period_start_date,
      period_end_date = EXCLUDED.period_end_date,
      last_calculation_date = EXCLUDED.last_calculation_date,
      updated_at = NOW();
    
    RAISE NOTICE 'Updated up-to-date salary for %: % EGP (% hours)', 
      v_employee_id, v_total_net, v_total_hours;
  END;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Create trigger on daily_salary_calculations
DROP TRIGGER IF EXISTS trigger_update_up_to_date_salary ON daily_salary_calculations;
CREATE TRIGGER trigger_update_up_to_date_salary
  AFTER INSERT OR UPDATE OR DELETE ON daily_salary_calculations
  FOR EACH ROW
  EXECUTE FUNCTION update_up_to_date_salary();

-- Function to initialize up_to_date_salary for all employees with existing calculations
CREATE OR REPLACE FUNCTION initialize_up_to_date_salary()
RETURNS TABLE (
  out_employee_id TEXT,
  out_total_net_salary DECIMAL(10, 2)
) AS $$
BEGIN
  RETURN QUERY
  INSERT INTO up_to_date_salary (
    employee_id,
    total_work_hours,
    total_gross_salary,
    total_deductions,
    total_net_salary,
    period_start_date,
    period_end_date,
    last_calculation_date,
    created_at,
    updated_at
  )
  SELECT 
    dsc.employee_id,
    SUM(dsc.total_work_hours),
    SUM(dsc.gross_salary),
    SUM(dsc.total_deductions),
    SUM(dsc.net_salary),
    MIN(dsc.calculation_date),
    MAX(dsc.calculation_date),
    MAX(dsc.calculation_date),
    NOW(),
    NOW()
  FROM daily_salary_calculations dsc
  GROUP BY dsc.employee_id
  ON CONFLICT (employee_id)
  DO UPDATE SET
    total_work_hours = EXCLUDED.total_work_hours,
    total_gross_salary = EXCLUDED.total_gross_salary,
    total_deductions = EXCLUDED.total_deductions,
    total_net_salary = EXCLUDED.total_net_salary,
    period_start_date = EXCLUDED.period_start_date,
    period_end_date = EXCLUDED.period_end_date,
    last_calculation_date = EXCLUDED.last_calculation_date,
    updated_at = NOW()
  RETURNING up_to_date_salary.employee_id, up_to_date_salary.total_net_salary;
END;
$$ LANGUAGE plpgsql;

-- Initialize up_to_date_salary with existing data
SELECT * FROM initialize_up_to_date_salary();

COMMENT ON TABLE up_to_date_salary IS 'Stores cumulative up-to-date salary totals for each employee, automatically updated when daily calculations change';
COMMENT ON FUNCTION update_up_to_date_salary() IS 'Automatically updates cumulative salary when daily_salary_calculations changes';
COMMENT ON FUNCTION initialize_up_to_date_salary() IS 'Initializes up_to_date_salary for all employees with existing daily calculations';
