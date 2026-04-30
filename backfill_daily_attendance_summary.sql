-- Backfill daily_attendance_summary from attendance table
-- This will populate missing records from the attendance table

INSERT INTO daily_attendance_summary (
  employee_id,
  attendance_date,
  check_in_time,
  check_out_time,
  total_hours,
  hourly_rate,
  daily_salary,
  is_absent
)
SELECT
  a.employee_id,
  a.date::date as attendance_date,
  to_char(a.check_in_time AT TIME ZONE 'Africa/Cairo', 'HH24:MI:SS') as check_in_time,
  CASE WHEN a.check_out_time IS NOT NULL 
    THEN to_char(a.check_out_time AT TIME ZONE 'Africa/Cairo', 'HH24:MI:SS')
    ELSE NULL
  END as check_out_time,
  CAST(COALESCE(a.work_hours, 0) AS NUMERIC) as total_hours,
  CAST(COALESCE(e.hourly_rate, 0) AS NUMERIC) as hourly_rate,
  CAST(
    (COALESCE(a.work_hours, 0)::NUMERIC * COALESCE(e.hourly_rate, 0)::NUMERIC)
    AS NUMERIC(10, 2)
  ) as daily_salary,
  CASE WHEN a.status = 'absent' THEN true ELSE false END as is_absent
FROM
  attendance a
  LEFT JOIN employees e ON a.employee_id = e.id
WHERE
  a.status IN ('completed', 'absent')
  AND a.check_out_time IS NOT NULL
  -- Only insert if the record doesn't already exist
  AND NOT EXISTS (
    SELECT 1 FROM daily_attendance_summary das
    WHERE das.employee_id = a.employee_id
    AND das.attendance_date = a.date::date
  )
ORDER BY
  a.employee_id, a.date;

-- Log the number of records inserted
SELECT COUNT(*) as backfilled_records FROM daily_attendance_summary
WHERE check_in_time IS NOT NULL;
