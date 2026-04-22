-- Production diagnostics for attendance visibility mismatches.
-- Safe: read-only queries only.

-- 1) Confirm employees activity columns in production.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'employees'
  AND column_name IN ('is_active', 'active')
ORDER BY column_name;

-- 2) Check if daily summary table stores time-only fields.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'daily_attendance_summary'
  AND column_name IN ('attendance_date', 'check_in_time', 'check_out_time')
ORDER BY column_name;

-- 3) Open active sessions today (ground truth candidate).
WITH today AS (
  SELECT (now() AT TIME ZONE 'Africa/Cairo')::date AS d
)
SELECT
  a.employee_id,
  e.full_name,
  e.branch,
  e.is_active,
  a.status,
  a.check_in_time,
  a.check_out_time
FROM attendance a
JOIN employees e ON e.id = a.employee_id
JOIN today t ON TRUE
WHERE a.date = t.d
  AND a.status = 'active'
  AND a.check_out_time IS NULL
ORDER BY e.branch, e.full_name;

-- 4) Potentially wrong sessions: open check-in while employee inactive.
WITH today AS (
  SELECT (now() AT TIME ZONE 'Africa/Cairo')::date AS d
)
SELECT
  a.employee_id,
  e.full_name,
  e.branch,
  e.is_active,
  a.status,
  a.check_in_time,
  a.check_out_time
FROM attendance a
JOIN employees e ON e.id = a.employee_id
JOIN today t ON TRUE
WHERE a.date = t.d
  AND a.check_out_time IS NULL
  AND COALESCE(e.is_active, false) = false
ORDER BY e.branch, e.full_name;

-- 5) Branch-level counts comparison.
WITH today AS (
  SELECT (now() AT TIME ZONE 'Africa/Cairo')::date AS d
),
ground_truth AS (
  SELECT e.branch, COUNT(*) AS present_count
  FROM attendance a
  JOIN employees e ON e.id = a.employee_id
  JOIN today t ON TRUE
  WHERE a.date = t.d
    AND a.status = 'active'
    AND a.check_out_time IS NULL
    AND COALESCE(e.is_active, false) = true
  GROUP BY e.branch
),
open_any_status AS (
  SELECT e.branch, COUNT(*) AS open_any_status_count
  FROM attendance a
  JOIN employees e ON e.id = a.employee_id
  JOIN today t ON TRUE
  WHERE a.date = t.d
    AND a.check_out_time IS NULL
  GROUP BY e.branch
)
SELECT
  COALESCE(g.branch, o.branch) AS branch,
  COALESCE(g.present_count, 0) AS strict_present_count,
  COALESCE(o.open_any_status_count, 0) AS open_any_status_count,
  COALESCE(o.open_any_status_count, 0) - COALESCE(g.present_count, 0) AS mismatch_delta
FROM ground_truth g
FULL OUTER JOIN open_any_status o ON o.branch = g.branch
ORDER BY branch;

-- 6) Time sanity check: compare attendance vs daily summary for same employee/date.
WITH sample AS (
  SELECT
    a.employee_id,
    a.date,
    a.check_in_time,
    a.check_out_time,
    das.check_in_time AS summary_check_in_time,
    das.check_out_time AS summary_check_out_time
  FROM attendance a
  LEFT JOIN daily_attendance_summary das
    ON das.employee_id = a.employee_id
   AND das.attendance_date = a.date
  WHERE a.check_in_time IS NOT NULL
  ORDER BY a.check_in_time DESC
  LIMIT 200
)
SELECT *
FROM sample
ORDER BY check_in_time DESC;
