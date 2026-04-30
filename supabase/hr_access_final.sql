-- HR Final Access Fix
-- الرجاء نسخ هذا الكود بالكامل ولصقه في Supabase SQL Editor ثم الضغط على Run

-- 1. التأكد من إنشاء جدول المكافآت
CREATE TABLE IF NOT EXISTS bonuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  reason TEXT NOT NULL,
  bonus_date DATE NOT NULL,
  created_by TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. إيقاف RLS لجميع الجداول التي تحتاجها صفحة الموارد البشرية لكي تعمل بدون قيود
ALTER TABLE employees DISABLE ROW LEVEL SECURITY;
ALTER TABLE pulses DISABLE ROW LEVEL SECURITY;
ALTER TABLE absences DISABLE ROW LEVEL SECURITY;
ALTER TABLE deductions DISABLE ROW LEVEL SECURITY;
ALTER TABLE bonuses DISABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests DISABLE ROW LEVEL SECURITY;
ALTER TABLE salary_advances DISABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_requests DISABLE ROW LEVEL SECURITY;

-- 3. إعطاء الصلاحيات للكل (المسجلين)
GRANT ALL ON employees TO authenticated;
GRANT ALL ON pulses TO authenticated;
GRANT ALL ON absences TO authenticated;
GRANT ALL ON deductions TO authenticated;
GRANT ALL ON bonuses TO authenticated;
GRANT ALL ON leave_requests TO authenticated;
GRANT ALL ON salary_advances TO authenticated;
GRANT ALL ON attendance_requests TO authenticated;

SELECT 'تم إصلاح جميع صلاحيات الموارد البشرية بنجاح!' as status;
