-- Complete RLS fix for HR access
-- Run this entire file in Supabase SQL Editor

-- ============================================================
-- 1. CREATE BONUSES TABLE (if doesn't exist)
-- ============================================================
CREATE TABLE IF NOT EXISTS bonuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  reason TEXT NOT NULL,
  bonus_date DATE NOT NULL,
  created_by TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================
-- 2. DISABLE RLS ON ALL REQUEST TABLES (allow all access)
-- ============================================================
ALTER TABLE leave_requests DISABLE ROW LEVEL SECURITY;
ALTER TABLE salary_advances DISABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_requests DISABLE ROW LEVEL SECURITY;
ALTER TABLE breaks DISABLE ROW LEVEL SECURITY;
ALTER TABLE pulses DISABLE ROW LEVEL SECURITY;
ALTER TABLE absences DISABLE ROW LEVEL SECURITY;
ALTER TABLE deductions DISABLE ROW LEVEL SECURITY;
ALTER TABLE bonuses DISABLE ROW LEVEL SECURITY;

-- ============================================================
-- 3. GRANT PERMISSIONS
-- ============================================================
GRANT ALL ON leave_requests TO authenticated;
GRANT ALL ON salary_advances TO authenticated;
GRANT ALL ON attendance_requests TO authenticated;
GRANT ALL ON breaks TO authenticated;
GRANT ALL ON pulses TO authenticated;
GRANT ALL ON absences TO authenticated;
GRANT ALL ON deductions TO authenticated;
GRANT ALL ON bonuses TO authenticated;

-- ============================================================
-- 4. CHECK IF TABLES EXIST
-- ============================================================
SELECT 'Checking tables...' as status;

-- Show tables that exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_type = 'BASE TABLE'
ORDER BY table_name;