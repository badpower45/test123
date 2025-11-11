-- إضافة أعمدة الموقع والـWiFi لجدول attendance (إذا لزم الأمر)

-- التحقق من وجود الأعمدة أولاً
-- إذا كانت موجودة، هذا الكود مش هيعمل حاجة
-- إذا مش موجودة، هيضيفها

-- 1. إضافة أعمدة الـCheck-in
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS check_in_latitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS check_in_longitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS check_in_wifi_bssid TEXT;

-- 2. إضافة أعمدة الـCheck-out
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS check_out_latitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS check_out_longitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS check_out_wifi_bssid TEXT;

-- 3. إضافة indexes للبحث السريع
CREATE INDEX IF NOT EXISTS idx_attendance_checkin_location 
ON attendance(check_in_latitude, check_in_longitude);

CREATE INDEX IF NOT EXISTS idx_attendance_checkout_location 
ON attendance(check_out_latitude, check_out_longitude);

-- 4. تحديث RLS policies (إذا لزم الأمر)
-- مفيش حاجة مطلوبة - الأعمدة الجديدة تابعة لنفس الـrow policies الموجودة

-- ملاحظة: هذا السكريبت اختياري
-- النظام الحالي بيحفظ الموقع والـWiFi في جدول location_pulses
-- لكن إذا عايز تحفظهم في attendance كمان، استخدم هذا السكريبت
