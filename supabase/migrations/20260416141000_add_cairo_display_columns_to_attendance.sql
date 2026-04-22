-- Keep canonical UTC timestamps, but expose Cairo-local display columns in the same table.
-- This avoids confusion when reviewing rows directly in the database UI.

ALTER TABLE public.attendance
ADD COLUMN IF NOT EXISTS check_in_time_cairo timestamp
GENERATED ALWAYS AS ((check_in_time AT TIME ZONE 'Africa/Cairo')) STORED;

ALTER TABLE public.attendance
ADD COLUMN IF NOT EXISTS check_out_time_cairo timestamp
GENERATED ALWAYS AS ((check_out_time AT TIME ZONE 'Africa/Cairo')) STORED;
