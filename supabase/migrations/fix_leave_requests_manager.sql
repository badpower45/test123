-- Fix leave_requests to ensure assigned_manager_id is properly set

-- 1. First, verify the column exists (should already exist from previous migration)
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'leave_requests' 
    AND column_name = 'assigned_manager_id'
  ) THEN
    ALTER TABLE leave_requests 
    ADD COLUMN assigned_manager_id TEXT REFERENCES employees(id);
    RAISE NOTICE '✅ Added assigned_manager_id column to leave_requests';
  ELSE
    RAISE NOTICE 'ℹ️ Column assigned_manager_id already exists in leave_requests';
  END IF;
END $$;

-- 2. Verify the trigger function exists
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
  
  RAISE NOTICE 'Leave request for employee %: assigned to manager %', NEW.employee_id, COALESCE(v_manager_id, 'NULL (owner)');
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Re-create the trigger (drop first to ensure it's fresh)
DROP TRIGGER IF EXISTS trigger_assign_manager_leave ON leave_requests;
CREATE TRIGGER trigger_assign_manager_leave
  BEFORE INSERT ON leave_requests
  FOR EACH ROW
  EXECUTE FUNCTION assign_manager_to_leave_request();

DO $$
BEGIN
  RAISE NOTICE '✅ Trigger trigger_assign_manager_leave created successfully';
END $$;

-- 4. Update existing leave_requests that don't have assigned_manager_id
DO $$
DECLARE
  v_updated_count INTEGER := 0;
  v_record RECORD;
BEGIN
  FOR v_record IN 
    SELECT lr.id, lr.employee_id, e.branch
    FROM leave_requests lr
    JOIN employees e ON lr.employee_id = e.id
    WHERE lr.assigned_manager_id IS NULL
  LOOP
    UPDATE leave_requests
    SET assigned_manager_id = (
      SELECT id 
      FROM employees 
      WHERE branch = v_record.branch 
        AND role = 'manager' 
        AND is_active = true 
      LIMIT 1
    )
    WHERE id = v_record.id;
    
    v_updated_count := v_updated_count + 1;
  END LOOP;
  
  RAISE NOTICE '✅ Updated % existing leave_requests with assigned_manager_id', v_updated_count;
END $$;

-- 5. Create index if not exists
CREATE INDEX IF NOT EXISTS idx_leave_requests_manager 
  ON leave_requests(assigned_manager_id);

DO $$
BEGIN
  RAISE NOTICE '✅ Index created on assigned_manager_id';
END $$;

-- 6. Verify the fix by showing sample data
DO $$
DECLARE
  v_total INTEGER;
  v_with_manager INTEGER;
  v_without_manager INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_total FROM leave_requests;
  SELECT COUNT(*) INTO v_with_manager FROM leave_requests WHERE assigned_manager_id IS NOT NULL;
  SELECT COUNT(*) INTO v_without_manager FROM leave_requests WHERE assigned_manager_id IS NULL;
  
  RAISE NOTICE '================================';
  RAISE NOTICE '📊 Leave Requests Summary:';
  RAISE NOTICE '   Total requests: %', v_total;
  RAISE NOTICE '   With manager: %', v_with_manager;
  RAISE NOTICE '   Without manager (owner): %', v_without_manager;
  RAISE NOTICE '================================';
END $$;

-- 7. Show a sample of leave_requests with their assigned managers
SELECT 
  lr.id,
  lr.employee_id,
  e.full_name AS employee_name,
  e.branch,
  lr.assigned_manager_id,
  m.full_name AS manager_name,
  lr.status,
  lr.created_at
FROM leave_requests lr
LEFT JOIN employees e ON lr.employee_id = e.id
LEFT JOIN employees m ON lr.assigned_manager_id = m.id
ORDER BY lr.created_at DESC
LIMIT 10;
