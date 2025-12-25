-- Create table for daily salary calculations
CREATE TABLE IF NOT EXISTS daily_salary_calculations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  calculation_date DATE NOT NULL,
  
  -- Work details
  total_work_hours DECIMAL(10, 2) DEFAULT 0,
  hourly_rate DECIMAL(10, 2) DEFAULT 0,
  gross_salary DECIMAL(10, 2) DEFAULT 0, -- total_work_hours * hourly_rate
  
  -- Pulse violations
  false_pulses_count INTEGER DEFAULT 0,
  pulse_deduction_amount DECIMAL(10, 2) DEFAULT 0, -- false_pulses * 5 minutes * (hourly_rate/60)
  
  -- Other deductions
  other_deductions DECIMAL(10, 2) DEFAULT 0,
  total_deductions DECIMAL(10, 2) DEFAULT 0,
  
  -- Final calculation
  net_salary DECIMAL(10, 2) DEFAULT 0, -- gross_salary - total_deductions
  
  -- Metadata
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Unique constraint: one calculation per employee per day
  UNIQUE(employee_id, calculation_date)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_daily_salary_employee_date 
  ON daily_salary_calculations(employee_id, calculation_date DESC);

CREATE INDEX IF NOT EXISTS idx_daily_salary_date 
  ON daily_salary_calculations(calculation_date DESC);

-- Enable RLS
ALTER TABLE daily_salary_calculations ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Employees can view their own salary calculations"
  ON daily_salary_calculations FOR SELECT
  USING (employee_id = auth.jwt() ->> 'employee_id');

CREATE POLICY "Owners and admins can view all salary calculations"
  ON daily_salary_calculations FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM employees 
      WHERE employees.id = auth.jwt() ->> 'employee_id'
      AND employees.role IN ('owner', 'admin', 'hr', 'manager')
    )
  );

CREATE POLICY "Service role can do everything"
  ON daily_salary_calculations FOR ALL
  USING (auth.role() = 'service_role');

-- Allow authenticated users to read (simplified for now)
CREATE POLICY "Authenticated users can read salary calculations"
  ON daily_salary_calculations FOR SELECT
  TO authenticated
  USING (true);

-- Add comment
COMMENT ON TABLE daily_salary_calculations IS 'Stores daily salary calculations for each employee including work hours, deductions, and net pay';
