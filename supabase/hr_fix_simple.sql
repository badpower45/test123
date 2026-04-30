-- HR Access Fix - Simple Version
-- Run directly in Supabase SQL Editor

-- 1. Check current tables (for info only)
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';

-- 2. Disable all RLS on these tables
ALTER TABLE leave_requests DISABLE ROW LEVEL SECURITY;
ALTER TABLE salary_advances DISABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_requests DISABLE ROW LEVEL SECURITY;
ALTER TABLE breaks DISABLE ROW LEVEL SECURITY;

-- 3. Grant permissions  
GRANT ALL ON leave_requests TO public;
GRANT ALL ON salary_advances TO public;
GRANT ALL ON attendance_requests TO public;
GRANT ALL ON breaks TO public;

-- 4. Create bonuses if needed
CREATE TABLE IF NOT EXISTS bonuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  reason TEXT NOT NULL,
  bonus_date DATE NOT NULL,
  created_by TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE bonuses DISABLE ROW LEVEL SECURITY;
GRANT ALL ON bonuses TO public;

-- Done
SELECT 'RLS Fixed!' as status;