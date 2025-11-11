-- ============================================
-- Add onboarding_completed column to employees table
-- ============================================

ALTER TABLE employees 
ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN DEFAULT FALSE;

-- Update existing employees to have onboarding_completed = true if they have complete data
UPDATE employees 
SET onboarding_completed = TRUE
WHERE phone IS NOT NULL 
  AND phone != '' 
  AND address IS NOT NULL 
  AND address != '';

SELECT '✅ Added onboarding_completed column to employees table' AS result;
