-- ============================================
-- QUICK FIX: Disable RLS for testing
-- Run this in Supabase SQL Editor NOW
-- ============================================

ALTER TABLE branches DISABLE ROW LEVEL SECURITY;
ALTER TABLE employees DISABLE ROW LEVEL SECURITY;
ALTER TABLE attendance DISABLE ROW LEVEL SECURITY;
ALTER TABLE pulses DISABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_requests DISABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests DISABLE ROW LEVEL SECURITY;
ALTER TABLE salary_advances DISABLE ROW LEVEL SECURITY;

SELECT '✅ RLS Disabled - Try adding branch again!' AS result;
