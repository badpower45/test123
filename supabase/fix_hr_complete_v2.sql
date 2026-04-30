-- Complete fix for HR access - Run in Supabase SQL Editor
-- This fixes 401 unauthorized errors

-- 1. First, disable RLS on all tables completely
ALTER TABLE IF EXISTS leave_requests DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS salary_advances DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS attendance_requests DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS breaks DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS pulses DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS absences DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS deductions DISABLE ROW LEVEL SECURITY;

-- 2. Create bonuses table if not exists
CREATE TABLE IF NOT EXISTS bonuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  reason TEXT NOT NULL,
  bonus_date DATE NOT NULL,
  created_by TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE IF EXISTS bonuses DISABLE ROW LEVEL SECURITY;

-- 3. Grant ALL permissions to anon and authenticated roles
GRANT ALL ON leave_requests TO anon, authenticated;
GRANT ALL ON salary_advances TO anon, authenticated;
GRANT ALL ON attendance_requests TO anon, authenticated;
GRANT ALL ON breaks TO anon, authenticated;
GRANT ALL ON pulses TO anon, authenticated;
GRANT ALL ON absences TO anon, authenticated;
GRANT ALL ON deductions TO anon, authenticated;
GRANT ALL ON bonuses TO anon, authenticated;

-- 4. Verify - show current RLS status
SELECT 
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables 
WHERE schemaname = 'public'
AND tablename IN (
  'leave_requests', 'salary_advances', 'attendance_requests', 
  'breaks', 'pulses', 'absences', 'deductions', 'bonuses'
);