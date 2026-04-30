-- HR Management System - Database Migrations
-- Create bonuses table and update deductions

-- 1. Create bonuses table (for rewards/bonuses)
CREATE TABLE IF NOT EXISTS bonuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  amount DECIMAL(10,2) NOT NULL,
  reason TEXT NOT NULL,
  bonus_date DATE NOT NULL,
  created_by TEXT REFERENCES employees(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Add created_by column to deductions table (to track who created the penalty)
ALTER TABLE deductions ADD COLUMN IF NOT EXISTS created_by TEXT REFERENCES employees(id);

-- 3. Create indexes for bonuses table
CREATE INDEX IF NOT EXISTS idx_bonuses_employee ON bonuses(employee_id);
CREATE INDEX IF NOT EXISTS idx_bonuses_date ON bonuses(bonus_date);

-- 4. Comments
COMMENT ON TABLE bonuses IS 'Employee bonuses and rewards';
COMMENT ON COLUMN bonuses.amount IS 'Bonus amount (always positive)';
COMMENT ON COLUMN bonuses.created_by IS 'Employee ID who created the bonus';