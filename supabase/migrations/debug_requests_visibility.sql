-- Debug script: inspect leave_requests & attendance_requests visibility for branch managers
-- Works in Supabase SQL Editor (no psql meta commands)
-- Steps:
-- 1. Summary counts
-- 2. Employees in branch
-- 3. Raw pending requests
-- 4. Trigger & schema verification
-- 5. Optional seed (uncomment block)
-- Change branch name by editing the constant below.

DO $$ BEGIN RAISE NOTICE 'Using branch: %', 'last2'; END $$;
-- Set the branch you want to inspect here
WITH branch_constant AS (SELECT 'last2'::text AS branch_name)
SELECT * FROM branch_constant;  -- Shows chosen branch

-- =============================
-- 1. Basic counts
-- =============================
DO $$
DECLARE
  v_branch TEXT := 'last2';
  v_leave_total INT; v_leave_pending INT; v_leave_manager_set INT; v_leave_without_manager INT;
  v_att_total INT; v_att_pending INT;
BEGIN
  SELECT COUNT(*) INTO v_leave_total FROM leave_requests;
  SELECT COUNT(*) INTO v_leave_pending FROM leave_requests WHERE status='pending';
  SELECT COUNT(*) INTO v_leave_manager_set FROM leave_requests WHERE assigned_manager_id IS NOT NULL;
  SELECT COUNT(*) INTO v_leave_without_manager FROM leave_requests WHERE assigned_manager_id IS NULL;

  SELECT COUNT(*) INTO v_att_total FROM attendance_requests;
  SELECT COUNT(*) INTO v_att_pending FROM attendance_requests WHERE status='pending';

  RAISE NOTICE '================= REQUESTS SUMMARY =================';
  RAISE NOTICE 'Leave total: % | pending: % | with manager: % | without manager: %', v_leave_total, v_leave_pending, v_leave_manager_set, v_leave_without_manager;
  RAISE NOTICE 'Attendance total: % | pending: %', v_att_total, v_att_pending;
  RAISE NOTICE 'Target branch: %', v_branch;
  RAISE NOTICE '====================================================';
END $$;

-- =============================
-- 2. Employees in branch
-- =============================
SELECT id, full_name, role, branch, is_active
FROM employees
WHERE branch = 'last2'
ORDER BY role DESC, full_name;

-- =============================
-- 3. Pending requests for branch employees (raw)
-- =============================
WITH branch_emps AS (
  SELECT id FROM employees WHERE branch = 'last2'
) 
SELECT 'LEAVE' AS type, lr.id, lr.employee_id, lr.leave_type, lr.start_date, lr.end_date,
       lr.status, lr.assigned_manager_id, lr.created_at
FROM leave_requests lr
JOIN branch_emps be ON be.id = lr.employee_id
ORDER BY lr.created_at DESC
LIMIT 30;

WITH branch_emps AS (
  SELECT id FROM employees WHERE branch = 'last2'
) 
SELECT 'ATTENDANCE' AS type, ar.id, ar.employee_id, ar.request_type, ar.requested_time,
       ar.status, ar.assigned_manager_id, ar.created_at
FROM attendance_requests ar
JOIN branch_emps be ON be.id = ar.employee_id
ORDER BY ar.created_at DESC
LIMIT 30;

-- =============================
-- 4. Verify trigger existence for leave manager assignment
-- =============================
SELECT tg.tgname AS trigger_name, c.relname AS table_name, pg_get_triggerdef(tg.oid) AS definition
FROM pg_trigger tg
JOIN pg_class c ON c.oid = tg.tgrelid
WHERE c.relname = 'leave_requests' AND NOT tg.tgisinternal;

-- =============================
-- 5. Schema check (columns)
-- =============================
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name='leave_requests'
ORDER BY ordinal_position;

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name='attendance_requests'
ORDER BY ordinal_position;

-- =============================
-- 6. SAMPLE DATA (optional) ****************************************
-- Remove leading dashes to seed one leave + one attendance request for branch employees.
-- Will pick first NON-manager active employee in branch. Safe idempotent (won't duplicate if pending exists today).
-- *****************************************************************
-- OPTIONAL SEED (uncomment to create 1 leave + 1 attendance request)
-- DO $$
-- DECLARE
--   v_emp TEXT; v_exists INT; v_branch TEXT := 'last2';
-- BEGIN
--   SELECT id INTO v_emp FROM employees 
--    WHERE branch = v_branch AND role <> 'manager' AND is_active = true LIMIT 1;
--   IF v_emp IS NULL THEN RAISE NOTICE 'No active non-manager employee in branch %', v_branch; RETURN; END IF;
--   SELECT COUNT(*) INTO v_exists FROM leave_requests 
--    WHERE employee_id = v_emp AND start_date = CURRENT_DATE AND status='pending';
--   IF v_exists = 0 THEN
--     INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, reason, status)
--     VALUES (v_emp, 'regular', CURRENT_DATE, CURRENT_DATE + INTERVAL '1 day', 'Seed test leave', 'pending');
--     RAISE NOTICE 'Inserted leave for %', v_emp; END IF;
--   SELECT COUNT(*) INTO v_exists FROM attendance_requests 
--    WHERE employee_id = v_emp AND status='pending' AND created_at::date = CURRENT_DATE;
--   IF v_exists = 0 THEN
--     INSERT INTO attendance_requests (employee_id, request_type, requested_time, status, reason)
--     VALUES (v_emp, 'check-in', to_char(NOW(), 'HH24:MI'), 'pending', 'Seed test attendance');
--     RAISE NOTICE 'Inserted attendance for %', v_emp; END IF;
-- END $$;

-- =============================
-- 7. FINAL RECAP AFTER OPTIONAL SEED (re-run counts quickly)
-- =============================
-- DO $$
-- DECLARE v_leave INT; v_att INT; BEGIN
--   SELECT COUNT(*) INTO v_leave FROM leave_requests;
--   SELECT COUNT(*) INTO v_att FROM attendance_requests;
--   RAISE NOTICE 'Final leave count: %', v_leave; RAISE NOTICE 'Final attendance count: %', v_att;
-- END $$;

-- End of debug script