-- Create view for up-to-date salary with advances deducted
CREATE OR REPLACE VIEW up_to_date_salary_with_advances AS
SELECT 
  u.employee_id,
  u.total_work_hours,
  u.total_gross_salary,
  u.total_deductions,
  u.total_net_salary,
  COALESCE(SUM(sa.amount), 0) AS total_advances_taken,
  u.total_net_salary - COALESCE(SUM(sa.amount), 0) AS remaining_balance,
  (u.total_net_salary - COALESCE(SUM(sa.amount), 0)) * 0.30 AS max_additional_advance,
  u.period_start_date,
  u.period_end_date,
  u.last_calculation_date
FROM up_to_date_salary u
LEFT JOIN salary_advances sa ON sa.employee_id = u.employee_id 
  AND sa.status = 'approved'
  AND sa.created_at >= u.period_start_date
GROUP BY 
  u.employee_id,
  u.total_work_hours,
  u.total_gross_salary,
  u.total_deductions,
  u.total_net_salary,
  u.period_start_date,
  u.period_end_date,
  u.last_calculation_date;

-- Update RPC function to use the new view
CREATE OR REPLACE FUNCTION get_employee_salary_info(p_employee_id TEXT)
RETURNS TABLE (
  total_net_salary DECIMAL(10, 2),
  total_work_hours DECIMAL(10, 2),
  total_advances_taken DECIMAL(10, 2),
  remaining_balance DECIMAL(10, 2),
  max_additional_advance DECIMAL(10, 2),
  last_advance_date TIMESTAMPTZ,
  days_since_last_advance INTEGER,
  can_request_advance BOOLEAN
) 
SECURITY DEFINER
AS $$
DECLARE
  v_last_advance_date TIMESTAMPTZ;
  v_days_since INTEGER;
BEGIN
  -- Get last approved advance date
  SELECT created_at INTO v_last_advance_date
  FROM salary_advances
  WHERE employee_id = p_employee_id
    AND status = 'approved'
  ORDER BY created_at DESC
  LIMIT 1;
  
  -- Calculate days since last advance
  IF v_last_advance_date IS NOT NULL THEN
    v_days_since := EXTRACT(DAY FROM (NOW() - v_last_advance_date));
  ELSE
    v_days_since := 999; -- No previous advance
  END IF;
  
  -- Return salary info with advance eligibility
  RETURN QUERY
  SELECT 
    u.total_net_salary,
    u.total_work_hours,
    u.total_advances_taken,
    u.remaining_balance,
    u.max_additional_advance,
    v_last_advance_date,
    v_days_since,
    (v_days_since >= 5 AND u.remaining_balance > 0) AS can_request_advance
  FROM up_to_date_salary_with_advances u
  WHERE u.employee_id = p_employee_id;
  
  -- If no record found, return zeros
  IF NOT FOUND THEN
    RETURN QUERY
    SELECT 
      0::DECIMAL(10, 2),
      0::DECIMAL(10, 2),
      0::DECIMAL(10, 2),
      0::DECIMAL(10, 2),
      0::DECIMAL(10, 2),
      v_last_advance_date,
      v_days_since,
      FALSE;
  END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON VIEW up_to_date_salary_with_advances IS 'Shows net salary with advances already taken, and remaining balance available';
COMMENT ON FUNCTION get_employee_salary_info IS 'Get employee salary info including advances and remaining balance (bypasses RLS)';
