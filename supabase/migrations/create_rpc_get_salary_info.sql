-- RPC function to get employee salary info (bypasses RLS)
CREATE OR REPLACE FUNCTION get_employee_salary_info(p_employee_id TEXT)
RETURNS TABLE (
  total_net_salary DECIMAL(10, 2),
  total_work_hours DECIMAL(10, 2),
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
    COALESCE(u.total_net_salary, 0::DECIMAL(10, 2)),
    COALESCE(u.total_work_hours, 0::DECIMAL(10, 2)),
    v_last_advance_date,
    v_days_since,
    (v_days_since >= 5) AS can_request_advance
  FROM up_to_date_salary u
  WHERE u.employee_id = p_employee_id;
  
  -- If no record found, return zeros
  IF NOT FOUND THEN
    RETURN QUERY
    SELECT 
      0::DECIMAL(10, 2),
      0::DECIMAL(10, 2),
      v_last_advance_date,
      v_days_since,
      (v_days_since >= 5) AS can_request_advance;
  END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_employee_salary_info IS 'Get employee salary info including advance eligibility (bypasses RLS)';
