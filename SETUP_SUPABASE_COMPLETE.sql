-- ============================================
-- COMPLETE SUPABASE DATABASE SETUP
-- ============================================
-- نفذ هذا الـSQL في Supabase SQL Editor لإصلاح كل شيء

-- ============================================
-- STEP 1: FIX BRANCHES TABLE
-- ============================================

-- Drop old branches table
DROP TABLE IF EXISTS branches CASCADE;

-- Create new branches table with all required columns
CREATE TABLE branches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    address TEXT,
    phone TEXT,
    wifi_bssid TEXT,
    latitude DECIMAL(10, 6),
    longitude DECIMAL(10, 6),
    geofence_radius INTEGER DEFAULT 100,
    manager_id TEXT REFERENCES employees(id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX idx_branches_name ON branches(name);
CREATE INDEX idx_branches_manager_id ON branches(manager_id);
CREATE INDEX idx_branches_is_active ON branches(is_active);

-- Add helpful comments
COMMENT ON TABLE branches IS 'Company branches with BLV (WiFi + GPS + Geofence) support';
COMMENT ON COLUMN branches.wifi_bssid IS 'WiFi MAC address for indoor location validation';
COMMENT ON COLUMN branches.latitude IS 'GPS latitude for outdoor location';
COMMENT ON COLUMN branches.longitude IS 'GPS longitude for outdoor location';
COMMENT ON COLUMN branches.geofence_radius IS 'Allowed distance from branch center in meters';

-- Enable Row Level Security
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;

-- Create RLS policy: Allow all operations for authenticated users
CREATE POLICY "Allow all for authenticated users" ON branches
    FOR ALL
    USING (auth.role() = 'authenticated')
    WITH CHECK (auth.role() = 'authenticated');

-- ============================================
-- STEP 2: ADD SAMPLE BRANCH
-- ============================================

INSERT INTO branches (name, address, phone, wifi_bssid, latitude, longitude, geofence_radius, is_active)
VALUES (
    'الفرع الرئيسي',
    'القاهرة، مصر الجديدة، شارع النزهة',
    '01012345678',
    NULL, -- سيتم إضافته لاحقاً
    30.0444,
    31.2357,
    100,
    TRUE
)
ON CONFLICT DO NOTHING;

-- ============================================
-- STEP 3: VERIFY EMPLOYEES TABLE
-- ============================================

-- Check if employees table exists and has correct structure
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'employees') THEN
        RAISE EXCEPTION 'جدول employees غير موجود! يجب إنشاءه أولاً';
    END IF;
END $$;

-- ============================================
-- STEP 4: ADD SAMPLE EMPLOYEES (if needed)
-- ============================================

-- Add Owner
INSERT INTO employees (id, full_name, pin, role, is_active, branch, monthly_salary, hourly_rate)
VALUES ('OWNER001', 'صاحب العمل', '1234', 'owner', true, 'الفرع الرئيسي', 10000, 0)
ON CONFLICT (id) DO NOTHING;

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

-- ============================================
-- STEP 5: VERIFY OTHER TABLES
-- ============================================

-- Verify attendance table
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'attendance') THEN
        RAISE NOTICE 'تحذير: جدول attendance غير موجود';
    END IF;
END $$;

-- Verify leave_requests table
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'leave_requests') THEN
        RAISE NOTICE 'تحذير: جدول leave_requests غير موجود';
    END IF;
END $$;

-- Verify salary_advances table
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'salary_advances') THEN
        RAISE NOTICE 'تحذير: جدول salary_advances غير موجود';
    END IF;
END $$;

-- Verify attendance_requests table
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'attendance_requests') THEN
        RAISE NOTICE 'تحذير: جدول attendance_requests غير موجود';
    END IF;
END $$;

-- ============================================
-- FINAL SUCCESS MESSAGE
-- ============================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '✅✅✅ تم الانتهاء من الإعداد بنجاح! ✅✅✅';
    RAISE NOTICE '';
    RAISE NOTICE '📋 ملخص الإعداد:';
    RAISE NOTICE '   ✓ جدول branches تم إصلاحه بنجاح';
    RAISE NOTICE '   ✓ تم إضافة فرع تجريبي: الفرع الرئيسي';
    RAISE NOTICE '   ✓ تم إضافة 6 موظفين للتجربة';
    RAISE NOTICE '';
    RAISE NOTICE '🔐 بيانات تسجيل الدخول:';
    RAISE NOTICE '   👨‍💼 Owner: OWNER001 / 1234';
    RAISE NOTICE '   👔 Manager: MGR001 / 1111';
    RAISE NOTICE '   👤 Staff 1: EMP001 / 2222';
    RAISE NOTICE '   👤 Staff 2: EMP002 / 3333';
    RAISE NOTICE '   👤 Staff 3: EMP003 / 4444';
    RAISE NOTICE '   👥 HR: HR001 / 5555';
    RAISE NOTICE '';
    RAISE NOTICE '🎯 الخطوات التالية:';
    RAISE NOTICE '   1. شغّل التطبيق: flutter run -d edge';
    RAISE NOTICE '   2. سجل دخول بـ OWNER001 / 1234';
    RAISE NOTICE '   3. جرّب إدارة الفروع مع BLV';
    RAISE NOTICE '   4. اختبر كل صفحات الـOwner';
    RAISE NOTICE '';
    RAISE NOTICE '🚀 كل شيء جاهز للعمل!';
    RAISE NOTICE '';
END $$;
