-- Add assigned_manager_id to breaks table to track which manager should approve
-- This ensures break requests are properly filtered by manager/branch

ALTER TABLE breaks 
ADD COLUMN IF NOT EXISTS assigned_manager_id TEXT REFERENCES employees(id) ON DELETE SET NULL;

-- Update existing breaks to assign them to the branch manager
-- Find the manager for each employee's branch
UPDATE breaks b
SET assigned_manager_id = (
  SELECT m.id
  FROM employees e
  JOIN employees m ON m.branch = e.branch AND m.role = 'manager' AND m.is_active = true
  WHERE e.id = b.employee_id
  LIMIT 1
)
WHERE b.assigned_manager_id IS NULL;

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_breaks_assigned_manager ON breaks(assigned_manager_id);

-- Add comment
COMMENT ON COLUMN breaks.assigned_manager_id IS 'The manager responsible for reviewing this break request';
