-- إضافة سعر الساعة ومواعيد الشيفت لجدول الموظفين
-- Add hourly_rate and shift times to employees table

-- 1. إضافة عمود سعر الساعة
ALTER TABLE employees 
ADD COLUMN IF NOT EXISTS hourly_rate DECIMAL(10,2) DEFAULT 0;

-- 2. إضافة عمود وقت بداية الشيفت
ALTER TABLE employees 
ADD COLUMN IF NOT EXISTS shift_start_time TIME;

-- 3. إضافة عمود وقت نهاية الشيفت
ALTER TABLE employees 
ADD COLUMN IF NOT EXISTS shift_end_time TIME;

-- 4. تحديث الموظفين الحاليين (optional - يحول المرتب الشهري لسعر ساعة تقريبي)
-- افتراض: 26 يوم عمل × 8 ساعات = 208 ساعة في الشهر
UPDATE employees
SET hourly_rate = ROUND(monthly_salary / 208.0, 2)
WHERE monthly_salary > 0 AND hourly_rate = 0;

-- 5. يمكن حذف عمود monthly_salary لاحقاً إذا أردت (optional)
-- ALTER TABLE employees DROP COLUMN monthly_salary;

COMMENT ON COLUMN employees.hourly_rate IS 'سعر الساعة للموظف (جنيه/ساعة)';
COMMENT ON COLUMN employees.shift_start_time IS 'وقت بداية شيفت الموظف (مثال: 09:00)';
COMMENT ON COLUMN employees.shift_end_time IS 'وقت نهاية شيفت الموظف (مثال: 17:00)';
