-- Add manager assignment to all request tables

-- ==================== LEAVE REQUESTS ====================
-- Add assigned_manager column to leave_requests
ALTER TABLE leave_requests 
ADD COLUMN IF NOT EXISTS assigned_manager_id TEXT REFERENCES employees(id);

CREATE INDEX IF NOT EXISTS idx_leave_requests_manager 
  ON leave_requests(assigned_manager_id);

-- Function to auto-assign manager based on employee's branch
CREATE OR REPLACE FUNCTION assign_manager_to_leave_request()
RETURNS TRIGGER AS $$
DECLARE
  v_branch TEXT;
  v_manager_id TEXT;
BEGIN
  -- Get employee's branch
  SELECT branch INTO v_branch
  FROM employees
  WHERE id = NEW.employee_id;
  
  -- Find manager for that branch
  SELECT id INTO v_manager_id
  FROM employees
  WHERE branch = v_branch
    AND role = 'manager'
    AND is_active = true
  LIMIT 1;
  
  -- Assign manager (NULL if no manager found = goes to owner)
  NEW.assigned_manager_id := v_manager_id;
  
  RAISE NOTICE 'Leave request for %: assigned to manager %', NEW.employee_id, v_manager_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-assign manager on leave request creation
DROP TRIGGER IF EXISTS trigger_assign_manager_leave ON leave_requests;
CREATE TRIGGER trigger_assign_manager_leave
  BEFORE INSERT ON leave_requests
  FOR EACH ROW
  EXECUTE FUNCTION assign_manager_to_leave_request();

-- ==================== SALARY ADVANCES ====================
-- Add assigned_manager column to salary_advances
ALTER TABLE salary_advances 
ADD COLUMN IF NOT EXISTS assigned_manager_id TEXT REFERENCES employees(id);

CREATE INDEX IF NOT EXISTS idx_salary_advances_manager 
  ON salary_advances(assigned_manager_id);

-- Function to auto-assign manager based on employee's branch
CREATE OR REPLACE FUNCTION assign_manager_to_advance_request()
RETURNS TRIGGER AS $$
DECLARE
  v_branch TEXT;
  v_manager_id TEXT;
BEGIN
  -- Get employee's branch
  SELECT branch INTO v_branch
  FROM employees
  WHERE id = NEW.employee_id;
  
  -- Find manager for that branch
  SELECT id INTO v_manager_id
  FROM employees
  WHERE branch = v_branch
    AND role = 'manager'
    AND is_active = true
  LIMIT 1;
  
  -- Assign manager (NULL if no manager found = goes to owner)
  NEW.assigned_manager_id := v_manager_id;
  
  RAISE NOTICE 'Advance request for %: assigned to manager %', NEW.employee_id, v_manager_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-assign manager on advance request creation
DROP TRIGGER IF EXISTS trigger_assign_manager_advance ON salary_advances;
CREATE TRIGGER trigger_assign_manager_advance
  BEFORE INSERT ON salary_advances
  FOR EACH ROW
  EXECUTE FUNCTION assign_manager_to_advance_request();

-- ==================== ATTENDANCE REQUESTS ====================
-- Add assigned_manager column to attendance_requests
ALTER TABLE attendance_requests 
ADD COLUMN IF NOT EXISTS assigned_manager_id TEXT REFERENCES employees(id);

CREATE INDEX IF NOT EXISTS idx_attendance_requests_manager 
  ON attendance_requests(assigned_manager_id);

-- Function to auto-assign manager based on employee's branch
CREATE OR REPLACE FUNCTION assign_manager_to_attendance_request()
RETURNS TRIGGER AS $$
DECLARE
  v_branch TEXT;
  v_manager_id TEXT;
BEGIN
  -- Get employee's branch
  SELECT branch INTO v_branch
  FROM employees
  WHERE id = NEW.employee_id;
  
  -- Find manager for that branch
  SELECT id INTO v_manager_id
  FROM employees
  WHERE branch = v_branch
    AND role = 'manager'
    AND is_active = true
  LIMIT 1;
  
  -- Assign manager (NULL if no manager found = goes to owner)
  NEW.assigned_manager_id := v_manager_id;
  
  RAISE NOTICE 'Attendance request for %: assigned to manager %', NEW.employee_id, v_manager_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-assign manager on attendance request creation
DROP TRIGGER IF EXISTS trigger_assign_manager_attendance ON attendance_requests;
CREATE TRIGGER trigger_assign_manager_attendance
  BEFORE INSERT ON attendance_requests
  FOR EACH ROW
  EXECUTE FUNCTION assign_manager_to_attendance_request();

-- ==================== UPDATE EXISTING REQUESTS ====================
-- Update existing leave requests to assign managers
UPDATE leave_requests lr
SET assigned_manager_id = (
  SELECT e2.id
  FROM employees e1
  JOIN employees e2 ON e1.branch = e2.branch
  WHERE e1.id = lr.employee_id
    AND e2.role = 'manager'
    AND e2.is_active = true
  LIMIT 1
)
WHERE assigned_manager_id IS NULL;

-- Update existing salary advances to assign managers
UPDATE salary_advances sa
SET assigned_manager_id = (
  SELECT e2.id
  FROM employees e1
  JOIN employees e2 ON e1.branch = e2.branch
  WHERE e1.id = sa.employee_id
    AND e2.role = 'manager'
    AND e2.is_active = true
  LIMIT 1
)
WHERE assigned_manager_id IS NULL;

-- Update existing attendance requests to assign managers
UPDATE attendance_requests ar
SET assigned_manager_id = (
  SELECT e2.id
  FROM employees e1
  JOIN employees e2 ON e1.branch = e2.branch
  WHERE e1.id = ar.employee_id
    AND e2.role = 'manager'
    AND e2.is_active = true
  LIMIT 1
)
WHERE assigned_manager_id IS NULL;

COMMENT ON COLUMN leave_requests.assigned_manager_id IS 'Manager responsible for approving this request (NULL = goes to owner)';
COMMENT ON COLUMN salary_advances.assigned_manager_id IS 'Manager responsible for approving this request (NULL = goes to owner)';
COMMENT ON COLUMN attendance_requests.assigned_manager_id IS 'Manager responsible for approving this request (NULL = goes to owner)';
