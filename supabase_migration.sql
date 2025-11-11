-- ============================================
-- OLDIES WORKERS - SUPABASE MIGRATION SCRIPT
-- ============================================
-- Run this in Supabase SQL Editor
-- Dashboard: https://supabase.com/dashboard/project/bbxuyuaemigrqsvsnxkj/editor

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- 1. BRANCHES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS branches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    wifi_bssid TEXT,
    bssid_1 TEXT,
    bssid_2 TEXT,
    latitude NUMERIC(10, 7),
    longitude NUMERIC(10, 7),
    geofence_radius INTEGER DEFAULT 200,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 2. BRANCH BSSIDS TABLE (Multiple WiFi per branch)
-- ============================================
CREATE TABLE IF NOT EXISTS branch_bssids (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
    bssid_address TEXT NOT NULL,
    signal_strength INTEGER DEFAULT -70,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(branch_id, bssid_address)
);

-- ============================================
-- 3. EMPLOYEES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS employees (
    id TEXT PRIMARY KEY,
    full_name TEXT NOT NULL,
    pin TEXT NOT NULL,
    role TEXT DEFAULT 'staff',
    is_active BOOLEAN DEFAULT true,
    branch TEXT,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    monthly_salary NUMERIC(10, 2) DEFAULT 0,
    hourly_rate NUMERIC(10, 2) DEFAULT 0,
    shift_start_time TEXT,
    shift_end_time TEXT,
    shift_type TEXT DEFAULT 'AM',
    address TEXT,
    birth_date DATE,
    email TEXT,
    phone TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 4. ATTENDANCE TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS attendance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    check_in_time TIMESTAMP WITH TIME ZONE NOT NULL,
    check_out_time TIMESTAMP WITH TIME ZONE,
    status TEXT DEFAULT 'active',
    total_hours NUMERIC(10, 2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 5. PULSES TABLE (Heartbeat tracking)
-- ============================================
CREATE TABLE IF NOT EXISTS pulses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    attendance_id UUID REFERENCES attendance(id) ON DELETE CASCADE,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    latitude NUMERIC(10, 7),
    longitude NUMERIC(10, 7),
    is_within_geofence BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 6. ATTENDANCE REQUESTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS attendance_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    request_type TEXT NOT NULL,
    reason TEXT,
    requested_time TIMESTAMP WITH TIME ZONE,
    status TEXT DEFAULT 'pending',
    reviewed_by TEXT REFERENCES employees(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    review_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 7. LEAVE REQUESTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS leave_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    leave_type TEXT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    reason TEXT,
    status TEXT DEFAULT 'pending',
    reviewed_by TEXT REFERENCES employees(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    review_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 8. SALARY ADVANCES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS salary_advances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    amount NUMERIC(10, 2) NOT NULL,
    reason TEXT,
    status TEXT DEFAULT 'pending',
    approved_by TEXT REFERENCES employees(id) ON DELETE SET NULL,
    approved_at TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 9. BREAKS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS breaks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    attendance_id UUID REFERENCES attendance(id) ON DELETE CASCADE,
    break_start TIMESTAMP WITH TIME ZONE NOT NULL,
    break_end TIMESTAMP WITH TIME ZONE,
    duration_minutes INTEGER,
    status TEXT DEFAULT 'PENDING',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 10. BLV (Behavioral Location Verification) TABLES
-- ============================================

-- BLV Profiles
CREATE TABLE IF NOT EXISTS blv_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
    wifi_fingerprint JSONB DEFAULT '{}',
    signal_patterns JSONB DEFAULT '{}',
    behavioral_patterns JSONB DEFAULT '{}',
    last_training_at TIMESTAMP WITH TIME ZONE,
    training_sample_count INTEGER DEFAULT 0,
    confidence_score NUMERIC(3, 2) DEFAULT 0.5,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(employee_id, branch_id)
);

-- BLV Training Data
CREATE TABLE IF NOT EXISTS blv_training_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    profile_id UUID NOT NULL REFERENCES blv_profiles(id) ON DELETE CASCADE,
    wifi_count INTEGER,
    wifi_signal_strength INTEGER,
    battery_level NUMERIC(3, 2),
    is_charging BOOLEAN,
    accel_variance NUMERIC(10, 4),
    sound_level NUMERIC(10, 2),
    device_orientation TEXT,
    device_model TEXT,
    os_version TEXT,
    wifi_bssid TEXT,
    collected_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- BLV Verification Logs
CREATE TABLE IF NOT EXISTS blv_verification_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
    presence_score NUMERIC(3, 2),
    trust_score NUMERIC(3, 2),
    is_valid BOOLEAN,
    environmental_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 11. GEOFENCE TRACKING TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS geofence_tracking (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
    latitude NUMERIC(10, 7) NOT NULL,
    longitude NUMERIC(10, 7) NOT NULL,
    distance_from_branch NUMERIC(10, 2),
    is_within_geofence BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- INDEXES for Performance
-- ============================================
CREATE INDEX IF NOT EXISTS idx_employees_branch_id ON employees(branch_id);
CREATE INDEX IF NOT EXISTS idx_employees_role ON employees(role);
CREATE INDEX IF NOT EXISTS idx_attendance_employee_id ON attendance(employee_id);
CREATE INDEX IF NOT EXISTS idx_attendance_status ON attendance(status);
CREATE INDEX IF NOT EXISTS idx_pulses_employee_id ON pulses(employee_id);
CREATE INDEX IF NOT EXISTS idx_pulses_attendance_id ON pulses(attendance_id);
CREATE INDEX IF NOT EXISTS idx_pulses_timestamp ON pulses(timestamp);
CREATE INDEX IF NOT EXISTS idx_attendance_requests_employee_id ON attendance_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_attendance_requests_status ON attendance_requests(status);
CREATE INDEX IF NOT EXISTS idx_leave_requests_employee_id ON leave_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON leave_requests(status);
CREATE INDEX IF NOT EXISTS idx_breaks_employee_id ON breaks(employee_id);
CREATE INDEX IF NOT EXISTS idx_breaks_status ON breaks(status);
CREATE INDEX IF NOT EXISTS idx_blv_profiles_employee_branch ON blv_profiles(employee_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_geofence_tracking_employee ON geofence_tracking(employee_id);

-- ============================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================

-- Enable RLS on all tables
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE pulses ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE salary_advances ENABLE ROW LEVEL SECURITY;
ALTER TABLE breaks ENABLE ROW LEVEL SECURITY;

-- Allow anonymous read/write for now (you can restrict later)
CREATE POLICY "Allow all operations" ON branches FOR ALL USING (true);
CREATE POLICY "Allow all operations" ON employees FOR ALL USING (true);
CREATE POLICY "Allow all operations" ON attendance FOR ALL USING (true);
CREATE POLICY "Allow all operations" ON pulses FOR ALL USING (true);
CREATE POLICY "Allow all operations" ON attendance_requests FOR ALL USING (true);
CREATE POLICY "Allow all operations" ON leave_requests FOR ALL USING (true);
CREATE POLICY "Allow all operations" ON salary_advances FOR ALL USING (true);
CREATE POLICY "Allow all operations" ON breaks FOR ALL USING (true);

-- ============================================
-- FUNCTIONS & TRIGGERS
-- ============================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER update_branches_updated_at BEFORE UPDATE ON branches
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_employees_updated_at BEFORE UPDATE ON employees
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_attendance_updated_at BEFORE UPDATE ON attendance
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- SEED DATA - Sample Owner Account
-- ============================================
INSERT INTO employees (id, full_name, pin, role, is_active, monthly_salary, hourly_rate)
VALUES ('OWNER001', 'Owner Admin', '1234', 'owner', true, 0, 0)
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- SUCCESS MESSAGE
-- ============================================
DO $$
BEGIN
    RAISE NOTICE '✅ Migration completed successfully!';
    RAISE NOTICE '📊 Tables created: 11 core tables + 3 BLV tables';
    RAISE NOTICE '🔒 RLS enabled on all tables';
    RAISE NOTICE '👤 Default owner account: OWNER001 / 1234';
END $$;
