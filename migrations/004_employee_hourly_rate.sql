-- Add hourly_rate column to employees table for owner dashboards and payroll adjustments
ALTER TABLE employees
  ADD COLUMN IF NOT EXISTS hourly_rate numeric;

-- Optional: keep timestamps for consistency
UPDATE employees
SET updated_at = NOW()
WHERE hourly_rate IS NULL;
