-- =============================================================================
-- ROLES AND PERMISSIONS SYSTEM
-- نظام الأدوار والصلاحيات
-- =============================================================================

-- =============================================================================
-- TABLE: users (Admin users for the system)
-- جدول المستخدمين الإداريين
-- =============================================================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    full_name TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);

COMMENT ON TABLE users IS 'Admin users who manage the system (Super Admin, Managers, HR, etc.)';

-- =============================================================================
-- TABLE: roles (Job titles/roles in the system)
-- جدول الأدوار (المناصب الوظيفية)
-- =============================================================================
CREATE TABLE IF NOT EXISTS roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL,
    name_ar TEXT NOT NULL,
    description TEXT,
    is_system_role BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_roles_name ON roles(name);

COMMENT ON TABLE roles IS 'Roles like Super Admin, Restaurant Manager, HR Manager';
COMMENT ON COLUMN roles.is_system_role IS 'If true, this role cannot be deleted (default system roles)';

-- =============================================================================
-- TABLE: permissions (Specific actions users can perform)
-- جدول الصلاحيات (الإجراءات المحددة التي يمكن للمستخدمين القيام بها)
-- =============================================================================
CREATE TABLE IF NOT EXISTS permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL,
    name_ar TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_permissions_name ON permissions(name);
CREATE INDEX IF NOT EXISTS idx_permissions_category ON permissions(category);

COMMENT ON TABLE permissions IS 'Individual permissions like view_employees, edit_payroll, etc.';
COMMENT ON COLUMN permissions.category IS 'Groups permissions by area: user_management, employee_management, payroll, monitoring, etc.';

-- =============================================================================
-- TABLE: role_permissions (Links roles to permissions)
-- جدول ربط الأدوار بالصلاحيات
-- =============================================================================
CREATE TABLE IF NOT EXISTS role_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(role_id, permission_id)
);

CREATE INDEX IF NOT EXISTS idx_role_permissions_role_id ON role_permissions(role_id);
CREATE INDEX IF NOT EXISTS idx_role_permissions_permission_id ON role_permissions(permission_id);

COMMENT ON TABLE role_permissions IS 'Many-to-many relationship between roles and permissions';

-- =============================================================================
-- TABLE: user_roles (Links users to roles)
-- جدول ربط المستخدمين بالأدوار
-- =============================================================================
CREATE TABLE IF NOT EXISTS user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ DEFAULT NOW(),
    assigned_by UUID REFERENCES users(id),
    UNIQUE(user_id, role_id)
);

CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role_id ON user_roles(role_id);

COMMENT ON TABLE user_roles IS 'Many-to-many relationship between users and roles';

-- =============================================================================
-- INSERT DEFAULT PERMISSIONS
-- إدخال الصلاحيات الافتراضية
-- =============================================================================

-- User Management Permissions
INSERT INTO permissions (name, name_ar, description, category) VALUES
('create_users', 'إنشاء مستخدمين', 'Can create new admin users', 'user_management'),
('edit_users', 'تعديل المستخدمين', 'Can edit existing admin users', 'user_management'),
('delete_users', 'حذف المستخدمين', 'Can delete admin users', 'user_management'),
('view_users', 'عرض المستخدمين', 'Can view all admin users', 'user_management'),
('manage_roles', 'إدارة الأدوار', 'Can create and edit roles and permissions', 'user_management')
ON CONFLICT (name) DO NOTHING;

-- Employee Management Permissions
INSERT INTO permissions (name, name_ar, description, category) VALUES
('create_employees', 'إضافة موظفين', 'Can add new employees', 'employee_management'),
('edit_employees', 'تعديل الموظفين', 'Can edit employee profiles', 'employee_management'),
('delete_employees', 'حذف الموظفين', 'Can delete employees', 'employee_management'),
('view_employees', 'عرض الموظفين', 'Can view employee profiles', 'employee_management')
ON CONFLICT (name) DO NOTHING;

-- Monitoring Permissions
INSERT INTO permissions (name, name_ar, description, category) VALUES
('view_live_dashboard', 'عرض لوحة المراقبة الحية', 'Can access live monitoring dashboard', 'monitoring'),
('view_pulse_logs', 'عرض سجلات النبضات', 'Can view pulse logs and location history', 'monitoring'),
('view_reports', 'عرض التقارير', 'Can view attendance and work hour reports', 'monitoring')
ON CONFLICT (name) DO NOTHING;

-- Payroll Permissions
INSERT INTO permissions (name, name_ar, description, category) VALUES
('view_payroll', 'عرض الرواتب', 'Can view payroll information', 'payroll'),
('edit_payroll', 'تعديل الرواتب', 'Can calculate and process payroll', 'payroll'),
('export_payroll', 'تصدير الرواتب', 'Can export payroll reports', 'payroll'),
('approve_payroll', 'اعتماد الرواتب', 'Can give final approval on payroll', 'payroll')
ON CONFLICT (name) DO NOTHING;

-- System Settings Permissions
INSERT INTO permissions (name, name_ar, description, category) VALUES
('edit_system_settings', 'تعديل إعدادات النظام', 'Can change system settings like geofence radius, pay rates, etc.', 'system_settings'),
('view_system_settings', 'عرض إعدادات النظام', 'Can view system settings', 'system_settings')
ON CONFLICT (name) DO NOTHING;

-- =============================================================================
-- INSERT DEFAULT ROLES
-- إدخال الأدوار الافتراضية
-- =============================================================================

INSERT INTO roles (name, name_ar, description, is_system_role) VALUES
('super_admin', 'مدير النظام', 'Full system access with all permissions', TRUE),
('restaurant_manager', 'مدير المطعم', 'Manages daily operations and staff', TRUE),
('hr_payroll_manager', 'مدير الموارد البشرية والرواتب', 'Handles payroll and HR functions', TRUE)
ON CONFLICT (name) DO NOTHING;

-- =============================================================================
-- ASSIGN PERMISSIONS TO ROLES
-- تعيين الصلاحيات للأدوار
-- =============================================================================

-- Super Admin: All permissions
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name = 'super_admin'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Restaurant Manager: Employee management + Monitoring (NO payroll/financial)
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
WHERE r.name = 'restaurant_manager'
AND p.name IN (
    'create_employees',
    'edit_employees',
    'view_employees',
    'view_live_dashboard',
    'view_pulse_logs',
    'view_reports',
    'view_system_settings'
)
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- HR/Payroll Manager: Payroll + Reports (NO live monitoring, NO employee management)
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
WHERE r.name = 'hr_payroll_manager'
AND p.name IN (
    'view_employees',
    'view_payroll',
    'edit_payroll',
    'export_payroll',
    'view_reports',
    'view_system_settings'
)
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Function to get all permissions for a user
CREATE OR REPLACE FUNCTION get_user_permissions(user_uuid UUID)
RETURNS TABLE(permission_name TEXT, permission_name_ar TEXT, category TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT p.name, p.name_ar, p.category
    FROM users u
    JOIN user_roles ur ON ur.user_id = u.id
    JOIN role_permissions rp ON rp.role_id = ur.role_id
    JOIN permissions p ON p.id = rp.permission_id
    WHERE u.id = user_uuid
    AND u.is_active = TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to check if user has a specific permission
CREATE OR REPLACE FUNCTION user_has_permission(user_uuid UUID, permission_name TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    has_perm BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1
        FROM users u
        JOIN user_roles ur ON ur.user_id = u.id
        JOIN role_permissions rp ON rp.role_id = ur.role_id
        JOIN permissions p ON p.id = rp.permission_id
        WHERE u.id = user_uuid
        AND u.is_active = TRUE
        AND p.name = permission_name
    ) INTO has_perm;
    
    RETURN has_perm;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_user_permissions IS 'Returns all permissions for a given user based on their roles';
COMMENT ON FUNCTION user_has_permission IS 'Checks if a user has a specific permission';

-- =============================================================================
-- SCHEMA COMPLETE
-- =============================================================================
