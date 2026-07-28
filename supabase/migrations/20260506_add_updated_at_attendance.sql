-- Migration: add updated_at to attendance
-- Adds a timestamptz `updated_at` column and a trigger to maintain it for per-employee attendance rows.

BEGIN;

-- 1) Ensure the helper function exists to update `updated_at` on update
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2) Add the column if missing
ALTER TABLE attendance
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- 3) Backfill from check_in_time when updated_at is NULL
UPDATE attendance
SET updated_at = COALESCE(updated_at, check_in_time, NOW())
WHERE updated_at IS NULL;

-- 4) Create trigger to keep updated_at current on updates
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trigger_attendance_updated_at'
  ) THEN
    CREATE TRIGGER trigger_attendance_updated_at
    BEFORE UPDATE ON attendance
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END
$$;

COMMIT;
