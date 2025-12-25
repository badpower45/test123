-- ==========================================
-- إضافة distance_from_center لجدول pulses
-- ==========================================
-- هذا الحقل مهم جداً لحساب بُعد الموظف عن مركز الفرع
-- يتم حسابه كل 5 دقائق مع كل نبضة

-- Add distance_from_center column if not exists
ALTER TABLE pulses
ADD COLUMN IF NOT EXISTS distance_from_center DOUBLE PRECISION;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_pulses_distance ON pulses(distance_from_center);

-- Add comment
COMMENT ON COLUMN pulses.distance_from_center IS 'المسافة من مركز الفرع بالأمتار - يتم حسابها مع كل نبضة';

-- Update existing rows to have NULL distance (can't calculate retroactively)
-- NULL means distance was not recorded

