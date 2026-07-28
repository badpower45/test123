-- Complete breaks table schema with all required columns
-- This migration ensures breaks table has all necessary fields for the employee-break function

-- 1. Add assigned_manager_id column if not exists
ALTER TABLE breaks 
ADD COLUMN IF NOT EXISTS assigned_manager_id TEXT REFERENCES employees(id) ON DELETE SET NULL;

-- 2. Add reason column if not exists
ALTER TABLE breaks 
ADD COLUMN IF NOT EXISTS reason TEXT;

-- 3. Create index for assigned_manager_id for faster queries
CREATE INDEX IF NOT EXISTS idx_breaks_assigned_manager ON breaks(assigned_manager_id);

-- 4. Update existing breaks to assign them to the branch manager (backfill)
UPDATE breaks b
SET assigned_manager_id = (
  SELECT m.id
  FROM employees e
  INNER JOIN employees m ON (
    (m.branch_id = e.branch_id AND m.branch_id IS NOT NULL) OR
    (m.branch = e.branch AND m.branch IS NOT NULL)
  )
  WHERE e.id = b.employee_id
    AND m.role = 'manager'
    AND m.is_active = true
  LIMIT 1
)
WHERE b.assigned_manager_id IS NULL
  AND b.employee_id IS NOT NULL;

-- 5. Add comment
COMMENT ON COLUMN breaks.assigned_manager_id IS 'The manager responsible for reviewing this break request';
COMMENT ON COLUMN breaks.reason IS 'Optional reason for the break request';
