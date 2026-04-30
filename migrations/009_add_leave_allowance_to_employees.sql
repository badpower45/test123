ALTER TABLE employees
  ADD COLUMN IF NOT EXISTS leave_allowance numeric DEFAULT 100;

UPDATE employees
SET leave_allowance = COALESCE(leave_allowance, 100)
WHERE leave_allowance IS NULL;