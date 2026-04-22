-- Allow multiple attendance sessions in the same day for the same employee.
-- Keep active-session prevention in application logic and edge functions.

ALTER TABLE public.attendance
DROP CONSTRAINT IF EXISTS attendance_employee_date_unique;

DROP INDEX IF EXISTS public.attendance_employee_date_unique;
