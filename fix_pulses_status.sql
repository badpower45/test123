-- ============================================
-- FIX: Add missing 'status' column to pulses table
-- ============================================

-- Add status column to pulses
ALTER TABLE pulses 
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';

-- Create the index that was failing
CREATE INDEX IF NOT EXISTS idx_pulses_status ON pulses(status);

-- Success message
SELECT '✅ Fixed: status column added to pulses table' AS result;
