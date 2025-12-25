-- Create table for current salary (after deducting approved advances)
CREATE TABLE IF NOT EXISTS up_to_date_salary_with_advances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL UNIQUE REFERENCES employees(id) ON DELETE CASCADE,
  
  -- Salary components
  total_net_salary DECIMAL(10, 2) DEFAULT 0, -- From up_to_date_salary
  total_approved_advances DECIMAL(10, 2) DEFAULT 0, -- Sum of approved advances
  current_salary DECIMAL(10, 2) DEFAULT 0, -- Net - Advances
  available_advance_30_percent DECIMAL(10, 2) DEFAULT 0, -- Current × 30%
  
  -- Metadata
  last_updated TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index
CREATE INDEX IF NOT EXISTS idx_up_to_date_salary_with_advances_employee 
  ON up_to_date_salary_with_advances(employee_id);

-- Enable RLS
ALTER TABLE up_to_date_salary_with_advances ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Service role can do everything"
  ON up_to_date_salary_with_advances FOR ALL
  USING (auth.role() = 'service_role');

CREATE POLICY "Authenticated users can read"
  ON up_to_date_salary_with_advances FOR SELECT
  TO authenticated
  USING (true);

-- Function to update current salary when advances change
CREATE OR REPLACE FUNCTION update_current_salary()
RETURNS TRIGGER AS $$
DECLARE
  v_employee_id TEXT;
  v_total_net DECIMAL(10, 2);
  v_total_advances DECIMAL(10, 2);
  v_current DECIMAL(10, 2);
  v_available DECIMAL(10, 2);
  v_should_update BOOLEAN := FALSE;
BEGIN
  -- Check if we should update (only for approved advances)
  IF TG_OP = 'INSERT' AND NEW.status = 'approved' THEN
    v_should_update := TRUE;
    v_employee_id := NEW.employee_id;
  ELSIF TG_OP = 'UPDATE' AND NEW.status = 'approved' AND OLD.status != 'approved' THEN
    v_should_update := TRUE;
    v_employee_id := NEW.employee_id;
  ELSIF TG_OP = 'DELETE' AND OLD.status = 'approved' THEN
    v_should_update := TRUE;
    v_employee_id := OLD.employee_id;
  END IF;

  -- If not relevant, skip
  IF NOT v_should_update THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  
  -- Get total net salary
  SELECT COALESCE(total_net_salary, 0)
  INTO v_total_net
  FROM up_to_date_salary
  WHERE employee_id = v_employee_id;
  
  -- Calculate total approved advances
  SELECT COALESCE(SUM(amount), 0)
  INTO v_total_advances
  FROM salary_advances
  WHERE employee_id = v_employee_id
    AND status = 'approved';
  
  -- Calculate current salary and available advance
  v_current := v_total_net - v_total_advances;
  v_available := ROUND(v_current * 0.30, 2);
  
  -- Upsert into up_to_date_salary_with_advances
  INSERT INTO up_to_date_salary_with_advances (
    employee_id,
    total_net_salary,
    total_approved_advances,
    current_salary,
    available_advance_30_percent,
    last_updated,
    created_at
  ) VALUES (
    v_employee_id,
    v_total_net,
    v_total_advances,
    v_current,
    v_available,
    NOW(),
    NOW()
  )
  ON CONFLICT (employee_id)
  DO UPDATE SET
    total_net_salary = EXCLUDED.total_net_salary,
    total_approved_advances = EXCLUDED.total_approved_advances,
    current_salary = EXCLUDED.current_salary,
    available_advance_30_percent = EXCLUDED.available_advance_30_percent,
    last_updated = NOW();
  
  RAISE NOTICE 'Updated current salary for %: Current=% EGP, Available=% EGP', 
    v_employee_id, v_current, v_available;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Trigger on salary_advances when status changes to approved
DROP TRIGGER IF EXISTS trigger_update_current_salary ON salary_advances;
CREATE TRIGGER trigger_update_current_salary
  AFTER INSERT OR UPDATE OR DELETE ON salary_advances
  FOR EACH ROW
  EXECUTE FUNCTION update_current_salary();

-- Trigger on up_to_date_salary when net salary changes
DROP TRIGGER IF EXISTS trigger_update_current_salary_on_net_change ON up_to_date_salary;
CREATE TRIGGER trigger_update_current_salary_on_net_change
  AFTER INSERT OR UPDATE ON up_to_date_salary
  FOR EACH ROW
  EXECUTE FUNCTION update_current_salary();

-- Function to initialize current salary for all employees
CREATE OR REPLACE FUNCTION initialize_current_salary()
RETURNS TABLE (
  out_employee_id TEXT,
  out_current_salary DECIMAL(10, 2)
) AS $$
BEGIN
  RETURN QUERY
  INSERT INTO up_to_date_salary_with_advances (
    employee_id,
    total_net_salary,
    total_approved_advances,
    current_salary,
    available_advance_30_percent,
    last_updated,
    created_at
  )
  SELECT 
    u.employee_id,
    COALESCE(u.total_net_salary, 0),
    COALESCE(adv.total_advances, 0),
    COALESCE(u.total_net_salary, 0) - COALESCE(adv.total_advances, 0),
    ROUND((COALESCE(u.total_net_salary, 0) - COALESCE(adv.total_advances, 0)) * 0.30, 2),
    NOW(),
    NOW()
  FROM up_to_date_salary u
  LEFT JOIN (
    SELECT 
      employee_id,
      SUM(amount) as total_advances
    FROM salary_advances
    WHERE status = 'approved'
    GROUP BY employee_id
  ) adv ON u.employee_id = adv.employee_id
  ON CONFLICT (employee_id)
  DO UPDATE SET
    total_net_salary = EXCLUDED.total_net_salary,
    total_approved_advances = EXCLUDED.total_approved_advances,
    current_salary = EXCLUDED.current_salary,
    available_advance_30_percent = EXCLUDED.available_advance_30_percent,
    last_updated = NOW()
  RETURNING up_to_date_salary_with_advances.employee_id, up_to_date_salary_with_advances.current_salary;
END;
$$ LANGUAGE plpgsql;

-- RPC function to get current salary info (bypasses RLS)
CREATE OR REPLACE FUNCTION get_current_salary_info(p_employee_id TEXT)
RETURNS TABLE (
  current_salary DECIMAL(10, 2),
  available_advance DECIMAL(10, 2),
  total_net_salary DECIMAL(10, 2),
  total_approved_advances DECIMAL(10, 2)
) 
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(c.current_salary, 0::DECIMAL(10, 2)),
    COALESCE(c.available_advance_30_percent, 0::DECIMAL(10, 2)),
    COALESCE(c.total_net_salary, 0::DECIMAL(10, 2)),
    COALESCE(c.total_approved_advances, 0::DECIMAL(10, 2))
  FROM up_to_date_salary_with_advances c
  WHERE c.employee_id = p_employee_id;
  
  -- If no record found, return zeros
  IF NOT FOUND THEN
    RETURN QUERY
    SELECT 
      0::DECIMAL(10, 2),
      0::DECIMAL(10, 2),
      0::DECIMAL(10, 2),
      0::DECIMAL(10, 2);
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Initialize current salary for all employees
SELECT * FROM initialize_current_salary();

COMMENT ON TABLE up_to_date_salary_with_advances IS 'Current salary after deducting approved advances, updated automatically';
COMMENT ON FUNCTION update_current_salary() IS 'Updates current salary when advances are approved or net salary changes';
COMMENT ON FUNCTION get_current_salary_info IS 'Get current salary info including available advance (bypasses RLS)';
