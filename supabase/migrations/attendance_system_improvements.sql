-- ============================================================================
-- 🎯 تحسينات نظام الحضور الشاملة
-- Attendance System Improvements for HR Application Standards
-- ============================================================================
-- تاريخ الإنشاء: 2025-11-30
-- الوصف: إضافة حقول جديدة وتحسين جدول الحضور ليتوافق مع معايير HR Applications
-- ============================================================================

-- ============================================================================
-- 1️⃣ إضافة حقول جديدة لجدول attendance
-- ============================================================================

-- حقل مدة الاستراحات (بالدقائق)
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS break_duration_minutes INTEGER DEFAULT 0;

COMMENT ON COLUMN attendance.break_duration_minutes IS 'إجمالي وقت الاستراحات المأخوذة خلال اليوم بالدقائق';

-- حقل التأخير (بالدقائق)
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS late_minutes INTEGER DEFAULT 0;

COMMENT ON COLUMN attendance.late_minutes IS 'عدد دقائق التأخير عن موعد بدء الشيفت';

-- حقل العمل الإضافي (بالدقائق)
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS overtime_minutes INTEGER DEFAULT 0;

COMMENT ON COLUMN attendance.overtime_minutes IS 'عدد دقائق العمل الإضافي';

-- حقل صافي ساعات العمل (بعد خصم الاستراحات والوقت خارج النطاق)
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS net_work_hours DECIMAL(5,2);

COMMENT ON COLUMN attendance.net_work_hours IS 'صافي ساعات العمل بعد خصم الاستراحات والوقت خارج النطاق';

-- حقل نوع الحضور
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'attendance_type_enum') THEN
    CREATE TYPE attendance_type_enum AS ENUM (
      'regular',      -- حضور عادي
      'remote',       -- عمل من المنزل
      'field_work',   -- مأمورية خارجية
      'half_day',     -- نصف يوم
      'sick_leave',   -- إجازة مرضية (حضور جزئي)
      'official'      -- حضور رسمي/تدريب
    );
  END IF;
END $$;

ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS attendance_type TEXT DEFAULT 'regular';

COMMENT ON COLUMN attendance.attendance_type IS 'نوع الحضور: regular, remote, field_work, half_day, sick_leave, official';

-- حقل الوقت خارج النطاق (بالدقائق) - من النبضات الفاشلة
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS pause_duration_minutes INTEGER DEFAULT 0;

COMMENT ON COLUMN attendance.pause_duration_minutes IS 'إجمالي الوقت خارج نطاق العمل بالدقائق (من النبضات الفاشلة)';

-- حقل وقت بدء الشيفت المجدول
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS scheduled_start_time TIME;

COMMENT ON COLUMN attendance.scheduled_start_time IS 'وقت بدء الشيفت المجدول للموظف';

-- حقل وقت انتهاء الشيفت المجدول
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS scheduled_end_time TIME;

COMMENT ON COLUMN attendance.scheduled_end_time IS 'وقت انتهاء الشيفت المجدول للموظف';

-- حقل معدل العمل الإضافي
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS overtime_rate DECIMAL(3,2) DEFAULT 1.5;

COMMENT ON COLUMN attendance.overtime_rate IS 'معدل احتساب العمل الإضافي (1.5 = وقت ونصف)';

-- حقل الملاحظات
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS notes TEXT;

COMMENT ON COLUMN attendance.notes IS 'ملاحظات إضافية على سجل الحضور';

-- حقل الانصراف التلقائي (إذا لم يكن موجوداً)
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS is_auto_checkout BOOLEAN DEFAULT false;

COMMENT ON COLUMN attendance.is_auto_checkout IS 'هل تم تسجيل الانصراف تلقائياً بسبب الخروج من النطاق';

-- ============================================================================
-- 2️⃣ إضافة حقل assigned_manager_id للجداول الناقصة
-- ============================================================================

-- إضافة للـ leave_requests إذا لم يكن موجوداً
ALTER TABLE leave_requests 
ADD COLUMN IF NOT EXISTS assigned_manager_id TEXT;

COMMENT ON COLUMN leave_requests.assigned_manager_id IS 'معرف المدير المسؤول عن مراجعة الطلب';

-- إضافة للـ attendance_requests إذا لم يكن موجوداً  
ALTER TABLE attendance_requests 
ADD COLUMN IF NOT EXISTS assigned_manager_id TEXT;

COMMENT ON COLUMN attendance_requests.assigned_manager_id IS 'معرف المدير المسؤول عن مراجعة الطلب';

-- إضافة للـ salary_advances إذا لم يكن موجوداً
ALTER TABLE salary_advances 
ADD COLUMN IF NOT EXISTS assigned_manager_id TEXT;

COMMENT ON COLUMN salary_advances.assigned_manager_id IS 'معرف المدير المسؤول عن مراجعة الطلب';

-- ============================================================================
-- 3️⃣ إنشاء View للحضور الصافي مع كل التفاصيل
-- ============================================================================

DROP VIEW IF EXISTS v_daily_attendance_details;

CREATE OR REPLACE VIEW v_daily_attendance_details AS
SELECT 
  a.id,
  a.employee_id,
  e.full_name AS employee_name,
  e.branch,
  e.hourly_rate,
  a.date,
  a.check_in_time,
  a.check_out_time,
  a.scheduled_start_time,
  a.scheduled_end_time,
  e.shift_start_time AS employee_shift_start,
  e.shift_end_time AS employee_shift_end,
  a.status,
  a.attendance_type,
  
  -- ساعات العمل الإجمالية
  COALESCE(a.work_hours, 0) AS gross_work_hours,
  
  -- وقت الاستراحات
  COALESCE(a.break_duration_minutes, 0) AS break_minutes,
  
  -- الوقت خارج النطاق
  COALESCE(a.pause_duration_minutes, 0) AS pause_minutes,
  
  -- صافي ساعات العمل
  COALESCE(a.net_work_hours, 
    GREATEST(0, COALESCE(a.work_hours, 0) - (COALESCE(a.break_duration_minutes, 0) + COALESCE(a.pause_duration_minutes, 0)) / 60.0)
  ) AS net_hours,
  
  -- التأخير
  COALESCE(a.late_minutes, 0) AS late_minutes,
  
  -- العمل الإضافي
  COALESCE(a.overtime_minutes, 0) AS overtime_minutes,
  
  -- حساب التأخير التلقائي
  CASE 
    WHEN a.check_in_time IS NOT NULL AND a.scheduled_start_time IS NOT NULL THEN
      GREATEST(0, EXTRACT(EPOCH FROM (a.check_in_time::time - a.scheduled_start_time)) / 60)::INTEGER
    WHEN a.check_in_time IS NOT NULL AND e.shift_start_time IS NOT NULL THEN
      GREATEST(0, EXTRACT(EPOCH FROM (a.check_in_time::time - e.shift_start_time::time)) / 60)::INTEGER
    ELSE 0
  END AS calculated_late_minutes,
  
  -- الراتب اليومي المحسوب
  ROUND(
    COALESCE(a.net_work_hours, 
      GREATEST(0, COALESCE(a.work_hours, 0) - (COALESCE(a.break_duration_minutes, 0) + COALESCE(a.pause_duration_minutes, 0)) / 60.0)
    ) * COALESCE(e.hourly_rate::DECIMAL, 0), 2
  ) AS daily_salary,
  
  -- راتب العمل الإضافي
  ROUND(
    (COALESCE(a.overtime_minutes, 0) / 60.0) * COALESCE(e.hourly_rate::DECIMAL, 0) * COALESCE(a.overtime_rate, 1.5), 2
  ) AS overtime_salary,
  
  a.notes,
  a.is_auto_checkout,
  a.created_at,
  a.updated_at

FROM attendance a
JOIN employees e ON a.employee_id = e.id
WHERE e.is_active = true;

COMMENT ON VIEW v_daily_attendance_details IS 'عرض تفصيلي للحضور اليومي مع كل الحسابات';

-- ============================================================================
-- 4️⃣ Function لحساب صافي ساعات العمل تلقائياً
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_net_work_hours()
RETURNS TRIGGER AS $$
DECLARE
  v_break_minutes INTEGER;
  v_pause_minutes INTEGER;
  v_gross_hours DECIMAL;
  v_net_hours DECIMAL;
  v_late_minutes INTEGER;
  v_scheduled_start TIME;
  v_employee_shift_start TEXT;
BEGIN
  -- الحصول على وقت الشيفت من الموظف إذا لم يكن محدداً
  IF NEW.scheduled_start_time IS NULL THEN
    SELECT shift_start_time INTO v_employee_shift_start
    FROM employees WHERE id = NEW.employee_id;
    
    IF v_employee_shift_start IS NOT NULL THEN
      NEW.scheduled_start_time := v_employee_shift_start::TIME;
    END IF;
  END IF;
  
  -- حساب إجمالي وقت الاستراحات من جدول breaks
  SELECT COALESCE(SUM(
    CASE 
      WHEN break_end IS NOT NULL THEN
        EXTRACT(EPOCH FROM (break_end - break_start)) / 60
      ELSE 0
    END
  ), 0)::INTEGER INTO v_break_minutes
  FROM breaks
  WHERE employee_id = NEW.employee_id
    AND status = 'COMPLETED'
    AND DATE(break_start) = NEW.date;
  
  NEW.break_duration_minutes := v_break_minutes;
  
  -- حساب الوقت خارج النطاق من النبضات الفاشلة
  SELECT COALESCE(COUNT(*) * 5, 0)::INTEGER INTO v_pause_minutes
  FROM pulses
  WHERE employee_id = NEW.employee_id
    AND DATE(timestamp) = NEW.date
    AND (is_within_geofence = false OR inside_geofence = false);
  
  NEW.pause_duration_minutes := v_pause_minutes;
  
  -- حساب ساعات العمل الإجمالية
  IF NEW.check_in_time IS NOT NULL AND NEW.check_out_time IS NOT NULL THEN
    v_gross_hours := EXTRACT(EPOCH FROM (NEW.check_out_time - NEW.check_in_time)) / 3600.0;
    NEW.work_hours := ROUND(v_gross_hours, 2);
  END IF;
  
  -- حساب صافي ساعات العمل
  v_gross_hours := COALESCE(NEW.work_hours::DECIMAL, 0);
  v_net_hours := GREATEST(0, v_gross_hours - (v_break_minutes + v_pause_minutes) / 60.0);
  NEW.net_work_hours := ROUND(v_net_hours, 2);
  
  -- حساب التأخير
  IF NEW.check_in_time IS NOT NULL AND NEW.scheduled_start_time IS NOT NULL THEN
    v_late_minutes := GREATEST(0, 
      EXTRACT(EPOCH FROM (NEW.check_in_time::TIME - NEW.scheduled_start_time)) / 60
    )::INTEGER;
    NEW.late_minutes := v_late_minutes;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- إزالة الـ trigger القديم إذا وجد
DROP TRIGGER IF EXISTS trigger_calculate_net_work_hours ON attendance;

-- إنشاء الـ trigger الجديد
CREATE TRIGGER trigger_calculate_net_work_hours
  BEFORE INSERT OR UPDATE OF check_in_time, check_out_time, status
  ON attendance
  FOR EACH ROW
  EXECUTE FUNCTION calculate_net_work_hours();

COMMENT ON FUNCTION calculate_net_work_hours() IS 'حساب صافي ساعات العمل تلقائياً عند تحديث سجل الحضور';

-- ============================================================================
-- 5️⃣ Function لتحديث وقت الاستراحات عند انتهاء استراحة
-- ============================================================================

CREATE OR REPLACE FUNCTION update_attendance_break_duration()
RETURNS TRIGGER AS $$
DECLARE
  v_total_break_minutes INTEGER;
  v_attendance_date DATE;
BEGIN
  -- فقط عند اكتمال الاستراحة
  IF NEW.status = 'COMPLETED' AND NEW.break_end IS NOT NULL THEN
    v_attendance_date := DATE(NEW.break_start);
    
    -- حساب إجمالي الاستراحات لهذا اليوم
    SELECT COALESCE(SUM(
      EXTRACT(EPOCH FROM (break_end - break_start)) / 60
    ), 0)::INTEGER INTO v_total_break_minutes
    FROM breaks
    WHERE employee_id = NEW.employee_id
      AND status = 'COMPLETED'
      AND DATE(break_start) = v_attendance_date;
    
    -- تحديث سجل الحضور
    UPDATE attendance
    SET break_duration_minutes = v_total_break_minutes,
        net_work_hours = GREATEST(0, COALESCE(work_hours, 0) - (v_total_break_minutes + COALESCE(pause_duration_minutes, 0)) / 60.0)
    WHERE employee_id = NEW.employee_id
      AND date = v_attendance_date;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- إزالة الـ trigger القديم إذا وجد
DROP TRIGGER IF EXISTS trigger_update_attendance_break_duration ON breaks;

-- إنشاء الـ trigger الجديد
CREATE TRIGGER trigger_update_attendance_break_duration
  AFTER UPDATE OF status, break_end
  ON breaks
  FOR EACH ROW
  EXECUTE FUNCTION update_attendance_break_duration();

COMMENT ON FUNCTION update_attendance_break_duration() IS 'تحديث وقت الاستراحات في سجل الحضور عند انتهاء استراحة';

-- ============================================================================
-- 6️⃣ Function لتحديث الوقت خارج النطاق من النبضات
-- ============================================================================

CREATE OR REPLACE FUNCTION update_attendance_pause_duration()
RETURNS TRIGGER AS $$
DECLARE
  v_total_pause_minutes INTEGER;
  v_attendance_date DATE;
BEGIN
  v_attendance_date := DATE(NEW.timestamp);
  
  -- حساب إجمالي الوقت خارج النطاق (كل نبضة = 5 دقائق)
  SELECT COALESCE(COUNT(*) * 5, 0)::INTEGER INTO v_total_pause_minutes
  FROM pulses
  WHERE employee_id = NEW.employee_id
    AND DATE(timestamp) = v_attendance_date
    AND (is_within_geofence = false OR inside_geofence = false);
  
  -- تحديث سجل الحضور
  UPDATE attendance
  SET pause_duration_minutes = v_total_pause_minutes,
      net_work_hours = GREATEST(0, COALESCE(work_hours, 0) - (COALESCE(break_duration_minutes, 0) + v_total_pause_minutes) / 60.0)
  WHERE employee_id = NEW.employee_id
    AND date = v_attendance_date;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- إزالة الـ trigger القديم إذا وجد
DROP TRIGGER IF EXISTS trigger_update_attendance_pause_duration ON pulses;

-- إنشاء الـ trigger الجديد
CREATE TRIGGER trigger_update_attendance_pause_duration
  AFTER INSERT
  ON pulses
  FOR EACH ROW
  WHEN (NEW.is_within_geofence = false OR NEW.inside_geofence = false)
  EXECUTE FUNCTION update_attendance_pause_duration();

COMMENT ON FUNCTION update_attendance_pause_duration() IS 'تحديث الوقت خارج النطاق في سجل الحضور عند إضافة نبضة فاشلة';

-- ============================================================================
-- 7️⃣ View ملخص الحضور الشهري
-- ============================================================================

DROP VIEW IF EXISTS v_monthly_attendance_summary;

CREATE OR REPLACE VIEW v_monthly_attendance_summary AS
SELECT 
  e.id AS employee_id,
  e.full_name,
  e.branch,
  DATE_TRUNC('month', a.date) AS month,
  
  -- عدد أيام الحضور
  COUNT(DISTINCT a.date) AS total_days_present,
  
  -- إجمالي ساعات العمل
  ROUND(SUM(COALESCE(a.work_hours::DECIMAL, 0)), 2) AS total_gross_hours,
  
  -- صافي ساعات العمل
  ROUND(SUM(COALESCE(a.net_work_hours, 0)), 2) AS total_net_hours,
  
  -- إجمالي وقت الاستراحات
  SUM(COALESCE(a.break_duration_minutes, 0)) AS total_break_minutes,
  
  -- إجمالي الوقت خارج النطاق
  SUM(COALESCE(a.pause_duration_minutes, 0)) AS total_pause_minutes,
  
  -- إجمالي دقائق التأخير
  SUM(COALESCE(a.late_minutes, 0)) AS total_late_minutes,
  
  -- إجمالي دقائق العمل الإضافي
  SUM(COALESCE(a.overtime_minutes, 0)) AS total_overtime_minutes,
  
  -- عدد مرات الانصراف التلقائي
  COUNT(CASE WHEN a.is_auto_checkout = true THEN 1 END) AS auto_checkout_count,
  
  -- الراتب المستحق (صافي)
  ROUND(SUM(COALESCE(a.net_work_hours, 0)) * COALESCE(e.hourly_rate::DECIMAL, 0), 2) AS monthly_salary,
  
  -- راتب العمل الإضافي
  ROUND(SUM((COALESCE(a.overtime_minutes, 0) / 60.0) * COALESCE(e.hourly_rate::DECIMAL, 0) * COALESCE(a.overtime_rate, 1.5)), 2) AS monthly_overtime_salary

FROM employees e
LEFT JOIN attendance a ON e.id = a.employee_id
WHERE e.is_active = true
  AND a.date IS NOT NULL
GROUP BY e.id, e.full_name, e.branch, e.hourly_rate, DATE_TRUNC('month', a.date);

COMMENT ON VIEW v_monthly_attendance_summary IS 'ملخص الحضور الشهري لكل موظف';

-- ============================================================================
-- 8️⃣ Function للحصول على تقرير الحضور اليومي للفرع
-- ============================================================================

CREATE OR REPLACE FUNCTION get_branch_daily_attendance(
  p_branch_name TEXT,
  p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
  employee_id TEXT,
  employee_name TEXT,
  check_in_time TIMESTAMPTZ,
  check_out_time TIMESTAMPTZ,
  gross_hours DECIMAL,
  break_minutes INTEGER,
  pause_minutes INTEGER,
  net_hours DECIMAL,
  late_minutes INTEGER,
  overtime_minutes INTEGER,
  daily_salary DECIMAL,
  status TEXT,
  attendance_type TEXT,
  is_present BOOLEAN
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    e.id,
    e.full_name,
    a.check_in_time,
    a.check_out_time,
    COALESCE(a.work_hours::DECIMAL, 0),
    COALESCE(a.break_duration_minutes, 0),
    COALESCE(a.pause_duration_minutes, 0),
    COALESCE(a.net_work_hours, 0),
    COALESCE(a.late_minutes, 0),
    COALESCE(a.overtime_minutes, 0),
    ROUND(COALESCE(a.net_work_hours, 0) * COALESCE(e.hourly_rate::DECIMAL, 0), 2),
    COALESCE(a.status, 'absent'),
    COALESCE(a.attendance_type, 'none'),
    (a.id IS NOT NULL)
  FROM employees e
  LEFT JOIN attendance a ON e.id = a.employee_id AND a.date = p_date
  WHERE e.branch = p_branch_name
    AND e.is_active = true
  ORDER BY e.full_name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_branch_daily_attendance(TEXT, DATE) IS 'الحصول على تقرير الحضور اليومي للفرع';

-- ============================================================================
-- 9️⃣ إضافة Indexes لتحسين الأداء
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_attendance_date_employee 
  ON attendance(date, employee_id);

CREATE INDEX IF NOT EXISTS idx_attendance_status_date 
  ON attendance(status, date);

CREATE INDEX IF NOT EXISTS idx_breaks_employee_date 
  ON breaks(employee_id, DATE(break_start));

CREATE INDEX IF NOT EXISTS idx_pulses_employee_date_geofence 
  ON pulses(employee_id, DATE(timestamp), is_within_geofence);

-- ============================================================================
-- 🔟 تحديث السجلات الموجودة
-- ============================================================================

-- تحديث scheduled_start_time من بيانات الموظف للسجلات الموجودة
UPDATE attendance a
SET scheduled_start_time = e.shift_start_time::TIME
FROM employees e
WHERE a.employee_id = e.id
  AND a.scheduled_start_time IS NULL
  AND e.shift_start_time IS NOT NULL;

-- تحديث scheduled_end_time من بيانات الموظف للسجلات الموجودة
UPDATE attendance a
SET scheduled_end_time = e.shift_end_time::TIME
FROM employees e
WHERE a.employee_id = e.id
  AND a.scheduled_end_time IS NULL
  AND e.shift_end_time IS NOT NULL;

-- إعادة حساب صافي ساعات العمل للسجلات الموجودة
UPDATE attendance
SET net_work_hours = GREATEST(0, COALESCE(work_hours::DECIMAL, 0) - (COALESCE(break_duration_minutes, 0) + COALESCE(pause_duration_minutes, 0)) / 60.0)
WHERE status = 'completed';

-- ============================================================================
-- ✅ انتهاء الـ Migration
-- ============================================================================

-- عرض رسالة النجاح
DO $$
BEGIN
  RAISE NOTICE '✅ تم تنفيذ جميع التحسينات بنجاح!';
  RAISE NOTICE '📊 الحقول الجديدة المضافة:';
  RAISE NOTICE '   - break_duration_minutes: وقت الاستراحات';
  RAISE NOTICE '   - late_minutes: دقائق التأخير';
  RAISE NOTICE '   - overtime_minutes: دقائق العمل الإضافي';
  RAISE NOTICE '   - net_work_hours: صافي ساعات العمل';
  RAISE NOTICE '   - attendance_type: نوع الحضور';
  RAISE NOTICE '   - pause_duration_minutes: الوقت خارج النطاق';
  RAISE NOTICE '   - scheduled_start_time: وقت بدء الشيفت';
  RAISE NOTICE '   - scheduled_end_time: وقت انتهاء الشيفت';
  RAISE NOTICE '   - overtime_rate: معدل العمل الإضافي';
  RAISE NOTICE '   - notes: ملاحظات';
  RAISE NOTICE '';
  RAISE NOTICE '🔄 الـ Triggers الجديدة:';
  RAISE NOTICE '   - trigger_calculate_net_work_hours: حساب صافي العمل تلقائياً';
  RAISE NOTICE '   - trigger_update_attendance_break_duration: تحديث الاستراحات';
  RAISE NOTICE '   - trigger_update_attendance_pause_duration: تحديث الوقت خارج النطاق';
  RAISE NOTICE '';
  RAISE NOTICE '📋 الـ Views الجديدة:';
  RAISE NOTICE '   - v_daily_attendance_details: تفاصيل الحضور اليومي';
  RAISE NOTICE '   - v_monthly_attendance_summary: ملخص الحضور الشهري';
END $$;
