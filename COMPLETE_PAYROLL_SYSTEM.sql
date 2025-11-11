-- ========================================
-- نظام المرتبات والغياب الكامل - نسخة نهائية
-- Complete Payroll and Absence System - Final Version
-- ========================================
-- 
-- هذا الملف يحتوي على:
-- 1. سعر الساعة ومواعيد الشيفتات
-- 2. نظام الغياب والخصومات  
-- 3. نظام المرتبات الكامل
--
-- ملاحظة: تأكد من تنفيذ هذا الملف مرة واحدة فقط
-- ========================================

-- ==========================================
-- القسم 1: إضافة سعر الساعة ومواعيد الشيفت
-- ==========================================

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

COMMENT ON COLUMN employees.hourly_rate IS 'سعر الساعة للموظف (جنيه/ساعة)';
COMMENT ON COLUMN employees.shift_start_time IS 'وقت بداية شيفت الموظف (مثال: 09:00)';
COMMENT ON COLUMN employees.shift_end_time IS 'وقت نهاية شيفت الموظف (مثال: 17:00)';

-- ==========================================
-- القسم 2: نظام الغياب والخصومات
-- ==========================================

-- 1. جدول الغياب (absences)
CREATE TABLE IF NOT EXISTS absences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  manager_id TEXT REFERENCES employees(id) ON DELETE SET NULL,
  absence_date DATE NOT NULL,
  shift_start_time TIME,
  shift_end_time TIME,
  status TEXT DEFAULT 'pending', -- pending, approved, rejected
  manager_response TEXT, -- approved or rejected reason
  deduction_amount DECIMAL(10,2) DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. جدول الخصومات (deductions)
CREATE TABLE IF NOT EXISTS deductions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  absence_id UUID REFERENCES absences(id) ON DELETE CASCADE,
  amount DECIMAL(10,2) NOT NULL, -- سالب دائماً (negative)
  reason TEXT NOT NULL,
  deduction_date DATE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Indexes للأداء - نظام الغياب
CREATE INDEX IF NOT EXISTS idx_absences_employee ON absences(employee_id);
CREATE INDEX IF NOT EXISTS idx_absences_branch ON absences(branch_id);
CREATE INDEX IF NOT EXISTS idx_absences_manager ON absences(manager_id);
CREATE INDEX IF NOT EXISTS idx_absences_status ON absences(status);
CREATE INDEX IF NOT EXISTS idx_absences_date ON absences(absence_date);
CREATE INDEX IF NOT EXISTS idx_deductions_employee ON deductions(employee_id);

-- 4. Comments - نظام الغياب
COMMENT ON TABLE absences IS 'جدول تسجيل غياب الموظفين عن الشيفتات';
COMMENT ON TABLE deductions IS 'جدول الخصومات المالية للموظفين';
COMMENT ON COLUMN absences.status IS 'حالة الغياب: pending (قيد المراجعة), approved (موافق عليه), rejected (مرفوض - سيتم الخصم)';
COMMENT ON COLUMN deductions.amount IS 'قيمة الخصم (دائماً سالب)';

-- ==========================================
-- القسم 3: نظام المرتبات الكامل
-- ==========================================

-- 1. جدول دورات المرتبات (Payroll Cycles)
CREATE TABLE IF NOT EXISTS payroll_cycles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  total_amount DECIMAL(10,2) DEFAULT 0,
  status TEXT DEFAULT 'pending', -- pending, paid
  paid_at TIMESTAMP WITH TIME ZONE,
  paid_by TEXT REFERENCES employees(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. جدول مرتبات الموظفين (Employee Payroll)
CREATE TABLE IF NOT EXISTS employee_payrolls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_cycle_id UUID REFERENCES payroll_cycles(id) ON DELETE CASCADE,
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  
  -- Calculated amounts
  total_hours DECIMAL(10,2) DEFAULT 0,
  hourly_rate DECIMAL(10,2) DEFAULT 0,
  base_salary DECIMAL(10,2) DEFAULT 0, -- total_hours × hourly_rate
  
  -- Additions
  leave_allowance DECIMAL(10,2) DEFAULT 0, -- بدل إجازة (100 جنيه)
  total_advances DECIMAL(10,2) DEFAULT 0, -- إجمالي السلف
  
  -- Deductions
  absence_days INTEGER DEFAULT 0,
  absence_deductions DECIMAL(10,2) DEFAULT 0, -- خصم الغياب
  total_deductions DECIMAL(10,2) DEFAULT 0, -- إجمالي الخصومات
  
  -- Final amount
  net_salary DECIMAL(10,2) DEFAULT 0, -- الصافي النهائي
  
  status TEXT DEFAULT 'pending', -- pending, paid
  paid_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. جدول تفاصيل الحضور اليومي (Daily Attendance Details)
CREATE TABLE IF NOT EXISTS daily_attendance_summary (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  attendance_date DATE NOT NULL,
  
  check_in_time TIME,
  check_out_time TIME,
  total_hours DECIMAL(10,2) DEFAULT 0,
  
  -- Daily calculations
  hourly_rate DECIMAL(10,2) DEFAULT 0,
  daily_salary DECIMAL(10,2) DEFAULT 0,
  
  -- Daily advances
  advance_amount DECIMAL(10,2) DEFAULT 0,
  
  -- Leave allowance (if applicable)
  leave_allowance DECIMAL(10,2) DEFAULT 0,
  
  -- Deductions
  deduction_amount DECIMAL(10,2) DEFAULT 0,
  
  -- Status
  is_absent BOOLEAN DEFAULT FALSE,
  is_on_leave BOOLEAN DEFAULT FALSE,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  UNIQUE(employee_id, attendance_date)
);

-- 4. Indexes للأداء - نظام المرتبات
CREATE INDEX IF NOT EXISTS idx_payroll_cycles_branch ON payroll_cycles(branch_id);
CREATE INDEX IF NOT EXISTS idx_payroll_cycles_status ON payroll_cycles(status);
CREATE INDEX IF NOT EXISTS idx_employee_payrolls_cycle ON employee_payrolls(payroll_cycle_id);
CREATE INDEX IF NOT EXISTS idx_employee_payrolls_employee ON employee_payrolls(employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_payrolls_status ON employee_payrolls(status);
CREATE INDEX IF NOT EXISTS idx_daily_attendance_employee ON daily_attendance_summary(employee_id);
CREATE INDEX IF NOT EXISTS idx_daily_attendance_date ON daily_attendance_summary(attendance_date);

-- 5. Function: حساب بدل الإجازة (100 جنيه لو غاب أقل من 3 أيام)
CREATE OR REPLACE FUNCTION calculate_leave_allowance(
  p_employee_id TEXT,
  p_start_date DATE,
  p_end_date DATE
) RETURNS DECIMAL(10,2) AS $$
DECLARE
  v_absence_days INTEGER;
  v_leave_allowance DECIMAL(10,2) := 0;
BEGIN
  -- Count absence days in period
  SELECT COUNT(*)
  INTO v_absence_days
  FROM daily_attendance_summary
  WHERE employee_id = p_employee_id
    AND attendance_date BETWEEN p_start_date AND p_end_date
    AND (is_absent = TRUE OR is_on_leave = TRUE);
  
  -- If less than 3 days, add 100 EGP allowance
  IF v_absence_days > 0 AND v_absence_days < 3 THEN
    v_leave_allowance := 100.00;
  END IF;
  
  RETURN v_leave_allowance;
END;
$$ LANGUAGE plpgsql;

-- 6. Function: حساب مرتب موظف لدورة معينة
CREATE OR REPLACE FUNCTION calculate_employee_payroll(
  p_payroll_cycle_id UUID,
  p_employee_id TEXT
) RETURNS UUID AS $$
DECLARE
  v_cycle RECORD;
  v_employee RECORD;
  v_total_hours DECIMAL(10,2);
  v_base_salary DECIMAL(10,2);
  v_leave_allowance DECIMAL(10,2);
  v_total_advances DECIMAL(10,2);
  v_absence_days INTEGER;
  v_total_deductions DECIMAL(10,2);
  v_net_salary DECIMAL(10,2);
  v_payroll_id UUID;
BEGIN
  -- Get cycle info
  SELECT * INTO v_cycle FROM payroll_cycles WHERE id = p_payroll_cycle_id;
  
  -- Get employee info
  SELECT * INTO v_employee FROM employees WHERE id = p_employee_id;
  
  -- Calculate total hours worked
  SELECT COALESCE(SUM(total_hours), 0)
  INTO v_total_hours
  FROM daily_attendance_summary
  WHERE employee_id = p_employee_id
    AND attendance_date BETWEEN v_cycle.start_date AND v_cycle.end_date
    AND is_absent = FALSE;
  
  -- Calculate base salary
  v_base_salary := v_total_hours * v_employee.hourly_rate;
  
  -- Calculate leave allowance
  v_leave_allowance := calculate_leave_allowance(p_employee_id, v_cycle.start_date, v_cycle.end_date);
  
  -- Calculate total advances
  SELECT COALESCE(SUM(advance_amount), 0)
  INTO v_total_advances
  FROM daily_attendance_summary
  WHERE employee_id = p_employee_id
    AND attendance_date BETWEEN v_cycle.start_date AND v_cycle.end_date;
  
  -- Count absence days
  SELECT COUNT(*)
  INTO v_absence_days
  FROM daily_attendance_summary
  WHERE employee_id = p_employee_id
    AND attendance_date BETWEEN v_cycle.start_date AND v_cycle.end_date
    AND is_absent = TRUE;
  
  -- Calculate total deductions (from deductions table)
  SELECT COALESCE(SUM(ABS(amount)), 0)
  INTO v_total_deductions
  FROM deductions
  WHERE employee_id = p_employee_id
    AND deduction_date BETWEEN v_cycle.start_date AND v_cycle.end_date;
  
  -- Calculate net salary
  v_net_salary := v_base_salary + v_leave_allowance - v_total_advances - v_total_deductions;
  
  -- Insert or update employee payroll
  INSERT INTO employee_payrolls (
    payroll_cycle_id,
    employee_id,
    total_hours,
    hourly_rate,
    base_salary,
    leave_allowance,
    total_advances,
    absence_days,
    absence_deductions,
    total_deductions,
    net_salary
  ) VALUES (
    p_payroll_cycle_id,
    p_employee_id,
    v_total_hours,
    v_employee.hourly_rate,
    v_base_salary,
    v_leave_allowance,
    v_total_advances,
    v_absence_days,
    0, -- We'll calculate this separately
    v_total_deductions,
    v_net_salary
  )
  ON CONFLICT (payroll_cycle_id, employee_id) 
  DO UPDATE SET
    total_hours = EXCLUDED.total_hours,
    hourly_rate = EXCLUDED.hourly_rate,
    base_salary = EXCLUDED.base_salary,
    leave_allowance = EXCLUDED.leave_allowance,
    total_advances = EXCLUDED.total_advances,
    absence_days = EXCLUDED.absence_days,
    total_deductions = EXCLUDED.total_deductions,
    net_salary = EXCLUDED.net_salary,
    updated_at = NOW()
  RETURNING id INTO v_payroll_id;
  
  RETURN v_payroll_id;
END;
$$ LANGUAGE plpgsql;

-- 7. Add unique constraint
ALTER TABLE employee_payrolls 
DROP CONSTRAINT IF EXISTS unique_employee_payroll_cycle;

ALTER TABLE employee_payrolls 
ADD CONSTRAINT unique_employee_payroll_cycle 
UNIQUE (payroll_cycle_id, employee_id);

-- 8. Comments - نظام المرتبات
COMMENT ON TABLE payroll_cycles IS 'دورات المرتبات الشهرية لكل فرع';
COMMENT ON TABLE employee_payrolls IS 'تفاصيل مرتبات الموظفين لكل دورة';
COMMENT ON TABLE daily_attendance_summary IS 'ملخص الحضور اليومي لكل موظف';
COMMENT ON COLUMN employee_payrolls.leave_allowance IS 'بدل الإجازة 100 جنيه (لو غاب أقل من 3 أيام)';
COMMENT ON COLUMN employee_payrolls.net_salary IS 'المرتب الصافي النهائي';

-- ==========================================
-- القسم 4: RLS Policies (Row Level Security)
-- ==========================================

-- Absence & Deductions Policies
ALTER TABLE absences ENABLE ROW LEVEL SECURITY;
ALTER TABLE deductions ENABLE ROW LEVEL SECURITY;

-- Policy: Managers can view absences in their branch
DROP POLICY IF EXISTS "Managers can view branch absences" ON absences;
CREATE POLICY "Managers can view branch absences"
ON absences FOR SELECT
USING (
  branch_id::text IN (
    SELECT b.id::text FROM branches b
    JOIN employees e ON e.branch = b.name
    WHERE e.id = auth.uid()::text AND e.role = 'manager'
  )
);

-- Policy: Managers can update absences status
DROP POLICY IF EXISTS "Managers can update absences" ON absences;
CREATE POLICY "Managers can update absences"
ON absences FOR UPDATE
USING (
  branch_id::text IN (
    SELECT b.id::text FROM branches b
    JOIN employees e ON e.branch = b.name
    WHERE e.id = auth.uid()::text AND e.role = 'manager'
  )
);

-- Policy: System can insert absences
DROP POLICY IF EXISTS "System can insert absences" ON absences;
CREATE POLICY "System can insert absences"
ON absences FOR INSERT
WITH CHECK (true);

-- Policy: Employees can view their own deductions
DROP POLICY IF EXISTS "Employees view own deductions" ON deductions;
CREATE POLICY "Employees view own deductions"
ON deductions FOR SELECT
USING (employee_id = auth.uid()::text);

-- Policy: System can insert deductions
DROP POLICY IF EXISTS "System can insert deductions" ON deductions;
CREATE POLICY "System can insert deductions"
ON deductions FOR INSERT
WITH CHECK (true);

-- Payroll Policies
ALTER TABLE payroll_cycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_payrolls ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_attendance_summary ENABLE ROW LEVEL SECURITY;

-- Owner can view all payrolls
DROP POLICY IF EXISTS "Owners can view all payrolls" ON payroll_cycles;
CREATE POLICY "Owners can view all payrolls"
ON payroll_cycles FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM employees
    WHERE id = auth.uid()::text AND role = 'owner'
  )
);

-- Owner can update payroll status
DROP POLICY IF EXISTS "Owners can update payrolls" ON payroll_cycles;
CREATE POLICY "Owners can update payrolls"
ON payroll_cycles FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM employees
    WHERE id = auth.uid()::text AND role = 'owner'
  )
);

-- Employees can view their own payroll
DROP POLICY IF EXISTS "Employees view own payroll" ON employee_payrolls;
CREATE POLICY "Employees view own payroll"
ON employee_payrolls FOR SELECT
USING (employee_id = auth.uid()::text);

-- Owner can insert payroll cycles
DROP POLICY IF EXISTS "Owners can insert payrolls" ON payroll_cycles;
CREATE POLICY "Owners can insert payrolls"
ON payroll_cycles FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM employees
    WHERE id = auth.uid()::text AND role = 'owner'
  )
);

-- System can insert employee payrolls
DROP POLICY IF EXISTS "System can insert employee payrolls" ON employee_payrolls;
CREATE POLICY "System can insert employee payrolls"
ON employee_payrolls FOR INSERT
WITH CHECK (true);

-- System can update employee payrolls
DROP POLICY IF EXISTS "System can update employee payrolls" ON employee_payrolls;
CREATE POLICY "System can update employee payrolls"
ON employee_payrolls FOR UPDATE
USING (true);

-- System can insert/update daily attendance
DROP POLICY IF EXISTS "System can insert daily attendance" ON daily_attendance_summary;
CREATE POLICY "System can insert daily attendance"
ON daily_attendance_summary FOR INSERT
WITH CHECK (true);

DROP POLICY IF EXISTS "System can update daily attendance" ON daily_attendance_summary;
CREATE POLICY "System can update daily attendance"
ON daily_attendance_summary FOR UPDATE
USING (true);

-- Employees can view their own attendance
DROP POLICY IF EXISTS "Employees view own attendance" ON daily_attendance_summary;
CREATE POLICY "Employees view own attendance"
ON daily_attendance_summary FOR SELECT
USING (employee_id = auth.uid()::text);

-- Managers can view branch attendance
DROP POLICY IF EXISTS "Managers view branch attendance" ON daily_attendance_summary;
CREATE POLICY "Managers view branch attendance"
ON daily_attendance_summary FOR SELECT
USING (
  employee_id IN (
    SELECT e.id FROM employees e
    JOIN branches b ON e.branch = b.name
    WHERE b.id::text IN (
      SELECT br.id::text FROM branches br
      JOIN employees emp ON emp.branch = br.name
      WHERE emp.id = auth.uid()::text AND emp.role = 'manager'
    )
  )
);

-- Owner can view all attendance
DROP POLICY IF EXISTS "Owners view all attendance" ON daily_attendance_summary;
CREATE POLICY "Owners view all attendance"
ON daily_attendance_summary FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM employees
    WHERE id = auth.uid()::text AND role = 'owner'
  )
);

-- ==========================================
-- انتهى! النظام جاهز للعمل
-- ==========================================

-- ملاحظات مهمة:
-- 1. تم إصلاح جميع مشاكل type casting (TEXT vs UUID)
-- 2. تم إضافة DROP POLICY قبل كل CREATE لتجنب التكرار
-- 3. جميع الـ Policies تستخدم ::text للتحويل الصريح
-- 4. النظام يدعم:
--    - سعر الساعة ومواعيد الشيفتات
--    - نظام الغياب مع الخصومات
--    - نظام المرتبات الكامل مع التقارير
--    - بدل الإجازة (100 جنيه لو غاب أقل من 3 أيام)
