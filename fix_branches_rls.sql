-- ============================================
-- FIX: Row Level Security for branches table
-- ============================================
-- This allows all operations on branches table
-- Run this in Supabase SQL Editor

-- Drop existing policies if any
DROP POLICY IF EXISTS "Allow all operations" ON branches;
DROP POLICY IF EXISTS "Enable read access for all users" ON branches;
DROP POLICY IF EXISTS "Enable insert for all users" ON branches;
DROP POLICY IF EXISTS "Enable update for all users" ON branches;
DROP POLICY IF EXISTS "Enable delete for all users" ON branches;

-- Disable RLS temporarily OR create permissive policies
-- Option 1: Disable RLS (for development/testing)
ALTER TABLE branches DISABLE ROW LEVEL SECURITY;

-- Option 2: OR keep RLS enabled with permissive policies (recommended for production)
-- Uncomment these lines if you want to keep RLS enabled:
/*
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Enable read for all" ON branches
    FOR SELECT USING (true);

CREATE POLICY "Enable insert for all" ON branches
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable update for all" ON branches
    FOR UPDATE USING (true);

CREATE POLICY "Enable delete for all" ON branches
    FOR DELETE USING (true);
*/

-- Also fix for other tables if needed
ALTER TABLE employees DISABLE ROW LEVEL SECURITY;
ALTER TABLE attendance DISABLE ROW LEVEL SECURITY;
ALTER TABLE pulses DISABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_requests DISABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests DISABLE ROW LEVEL SECURITY;
ALTER TABLE salary_advances DISABLE ROW LEVEL SECURITY;
ALTER TABLE breaks DISABLE ROW LEVEL SECURITY;
ALTER TABLE branch_bssids DISABLE ROW LEVEL SECURITY;
ALTER TABLE blv_profiles DISABLE ROW LEVEL SECURITY;
ALTER TABLE blv_training_data DISABLE ROW LEVEL SECURITY;
ALTER TABLE blv_verification_logs DISABLE ROW LEVEL SECURITY;
ALTER TABLE geofence_tracking DISABLE ROW LEVEL SECURITY;

-- Verify
SELECT 
    tablename, 
    rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
    AND tablename IN (
        'branches', 
        'employees', 
        'attendance', 
        'pulses',
        'attendance_requests',
        'leave_requests',
        'salary_advances',
        'breaks',
        'branch_bssids',
        'blv_profiles',
        'blv_training_data',
        'blv_verification_logs',
        'geofence_tracking'
    )
ORDER BY tablename;

SELECT '✅ RLS Disabled for all tables - App should work now!' AS result;
