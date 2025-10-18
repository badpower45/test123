-- Add POSTPONED to break_status enum if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_enum e ON t.oid = e.enumtypid
    WHERE t.typname = 'break_status' AND e.enumlabel = 'POSTPONED'
  ) THEN
    ALTER TYPE break_status ADD VALUE 'POSTPONED';
  END IF;
END$$;

-- Add payout fields to breaks table if not exists
ALTER TABLE breaks
  ADD COLUMN IF NOT EXISTS payout_eligible boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS payout_applied boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS payout_applied_at timestamptz;
