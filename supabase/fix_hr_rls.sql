-- Fix RLS policies for HR access to request tables
-- Run this in Supabase SQL Editor

-- 1. Leave Requests - Allow all authenticated users to read
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all operations" ON leave_requests;
CREATE POLICY "allow_read_leave_requests" ON leave_requests FOR SELECT TO authenticated USING (true);

-- 2. Salary Advances - Allow all authenticated users to read
ALTER TABLE salary_advances ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all operations" ON salary_advances;
CREATE POLICY "allow_read_salary_advances" ON salary_advances FOR SELECT TO authenticated USING (true);

-- 3. Attendance Requests - Allow all authenticated users to read
ALTER TABLE attendance_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_read_attendance_requests" ON attendance_requests FOR SELECT TO authenticated USING (true);

-- 4. Breaks - Allow all authenticated users to read
ALTER TABLE breaks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_read_breaks" ON breaks FOR SELECT TO authenticated USING (true);

-- 5. Pulses - Allow all authenticated users to read
ALTER TABLE pulses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_read_pulses" ON pulses FOR SELECT TO authenticated USING (true);

-- 6. Absences - Allow all authenticated users to read
ALTER TABLE absences ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_read_absences" ON absences FOR SELECT TO authenticated USING (true);

-- 7. Deductions - Allow all authenticated users to read
ALTER TABLE deductions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_read_deductions" ON deductions FOR SELECT TO authenticated USING (true);

-- 8. Bonuses - Allow all authenticated users to read (if table exists)
-- Will be created if it doesn't exist yet
CREATE TABLE IF NOT EXISTS bonuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  reason TEXT NOT NULL,
  bonus_date DATE NOT NULL,
  created_by TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE bonuses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_read_bonuses" ON bonuses FOR SELECT TO authenticated USING (true);
CREATE POLICY "allow_insert_bonuses" ON bonuses FOR INSERT TO authenticated WITH CHECK (true);

-- 9. Ensure employees and branches are readable
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_read_employees" ON employees FOR SELECT TO authenticated USING (true);

ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_read_branches" ON branches FOR SELECT TO authenticated USING (true);

-- Grant permissions
GRANT SELECT ON leave_requests TO authenticated;
GRANT SELECT ON salary_advances TO authenticated;
GRANT SELECT ON attendance_requests TO authenticated;
GRANT SELECT ON breaks TO authenticated;
GRANT SELECT ON pulses TO authenticated;
GRANT SELECT ON absences TO authenticated;
GRANT SELECT ON deductions TO authenticated;
GRANT SELECT ON bonuses TO authenticated;
GRANT SELECT ON employees TO authenticated;
GRANT SELECT ON branches TO authenticated;
GRANT ALL ON bonuses TO authenticated;