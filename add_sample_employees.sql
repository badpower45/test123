-- ============================================
-- ADD SAMPLE EMPLOYEES FOR TESTING
-- ============================================
-- Run this in Supabase SQL Editor after running the main migration

-- Add Manager
INSERT INTO employees (id, full_name, pin, role, is_active, branch, monthly_salary, hourly_rate)
VALUES ('MGR001', 'أحمد المدير', '1111', 'manager', true, 'الفرع الرئيسي', 5000, 0)
ON CONFLICT (id) DO NOTHING;

-- Add Staff Members
INSERT INTO employees (id, full_name, pin, role, is_active, branch, monthly_salary, hourly_rate)
VALUES ('EMP001', 'محمد الموظف', '2222', 'staff', true, 'الفرع الرئيسي', 3000, 0)
ON CONFLICT (id) DO NOTHING;

INSERT INTO employees (id, full_name, pin, role, is_active, branch, monthly_salary, hourly_rate)
VALUES ('EMP002', 'فاطمة العاملة', '3333', 'staff', true, 'الفرع الرئيسي', 3000, 0)
ON CONFLICT (id) DO NOTHING;

INSERT INTO employees (id, full_name, pin, role, is_active, branch, monthly_salary, hourly_rate)
VALUES ('EMP003', 'علي الموظف', '4444', 'staff', true, 'الفرع الرئيسي', 2800, 0)
ON CONFLICT (id) DO NOTHING;

-- Add HR
INSERT INTO employees (id, full_name, pin, role, is_active, branch, monthly_salary, hourly_rate)
VALUES ('HR001', 'سارة الموارد البشرية', '5555', 'hr', true, 'الفرع الرئيسي', 4000, 0)
ON CONFLICT (id) DO NOTHING;

-- Success Message
DO $$
BEGIN
    RAISE NOTICE '✅ تم إضافة الموظفين بنجاح!';
    RAISE NOTICE '👥 تم إضافة 5 موظفين:';
    RAISE NOTICE '   1. MGR001 / 1111 (Manager) - أحمد المدير';
    RAISE NOTICE '   2. EMP001 / 2222 (Staff) - محمد الموظف';
    RAISE NOTICE '   3. EMP002 / 3333 (Staff) - فاطمة العاملة';
    RAISE NOTICE '   4. EMP003 / 4444 (Staff) - علي الموظف';
    RAISE NOTICE '   5. HR001 / 5555 (HR) - سارة الموارد البشرية';
END $$;
