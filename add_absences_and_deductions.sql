-- إضافة جدول الغياب والخصومات
-- Add absence and deductions table

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

-- 3. Indexes للأداء
CREATE INDEX IF NOT EXISTS idx_absences_employee ON absences(employee_id);
CREATE INDEX IF NOT EXISTS idx_absences_branch ON absences(branch_id);
CREATE INDEX IF NOT EXISTS idx_absences_manager ON absences(manager_id);
CREATE INDEX IF NOT EXISTS idx_absences_status ON absences(status);
CREATE INDEX IF NOT EXISTS idx_absences_date ON absences(absence_date);
CREATE INDEX IF NOT EXISTS idx_deductions_employee ON deductions(employee_id);

-- 4. Comments
COMMENT ON TABLE absences IS 'جدول تسجيل غياب الموظفين عن الشيفتات';
COMMENT ON TABLE deductions IS 'جدول الخصومات المالية للموظفين';
COMMENT ON COLUMN absences.status IS 'حالة الغياب: pending (قيد المراجعة), approved (موافق عليه), rejected (مرفوض - سيتم الخصم)';
COMMENT ON COLUMN deductions.amount IS 'قيمة الخصم (دائماً سالب)';

-- 5. RLS Policies
ALTER TABLE absences ENABLE ROW LEVEL SECURITY;
ALTER TABLE deductions ENABLE ROW LEVEL SECURITY;

-- Policy: Managers can view absences in their branch
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
CREATE POLICY "System can insert absences"
ON absences FOR INSERT
WITH CHECK (true);

-- Policy: Employees can view their own deductions
CREATE POLICY "Employees view own deductions"
ON deductions FOR SELECT
USING (employee_id = auth.uid()::text);

-- Policy: System can insert deductions
CREATE POLICY "System can insert deductions"
ON deductions FOR INSERT
WITH CHECK (true);
