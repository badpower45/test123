-- Migration: add updated_at to daily_attendance_summary
-- Adds a timestamptz `updated_at` column and a trigger to maintain it.

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
ALTER TABLE daily_attendance_summary
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- 3) Backfill from created_at when updated_at is NULL
UPDATE daily_attendance_summary
SET updated_at = COALESCE(updated_at, created_at, NOW())
WHERE updated_at IS NULL;

-- 4) Create trigger to keep updated_at current on updates
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trigger_daily_attendance_updated_at'
  ) THEN
    CREATE TRIGGER trigger_daily_attendance_updated_at
    BEFORE UPDATE ON daily_attendance_summary
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END
$$;

COMMIT;
