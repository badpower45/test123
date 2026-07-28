-- Migration: allow service_role to insert/update/select on daily_attendance_summary
-- Ensures RLS enabled and adds policies to permit service_role full access and a system insert policy.

BEGIN;

-- Ensure RLS is enabled
ALTER TABLE IF EXISTS daily_attendance_summary ENABLE ROW LEVEL SECURITY;

-- 1) Allow service_role to do anything: drop/create (avoid querying pg_policies)
DROP POLICY IF EXISTS "Service role can do everything" ON daily_attendance_summary;
CREATE POLICY "Service role can do everything"
ON daily_attendance_summary FOR ALL
USING (auth.role() = 'service_role');

-- 2) Ensure system insert/update policies exist as fallback
DROP POLICY IF EXISTS "System can insert daily attendance" ON daily_attendance_summary;
CREATE POLICY "System can insert daily attendance"
ON daily_attendance_summary FOR INSERT
WITH CHECK (true);

DROP POLICY IF EXISTS "System can update daily attendance" ON daily_attendance_summary;
CREATE POLICY "System can update daily attendance"
ON daily_attendance_summary FOR UPDATE
USING (true);

COMMIT;
