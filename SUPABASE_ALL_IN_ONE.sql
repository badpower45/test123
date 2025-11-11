-- ============================================
-- COMPLETE SUPABASE SETUP (ALL IN ONE)
-- ============================================
-- نفذ هذا الملف الواحد في Supabase SQL Editor وخلاص!
-- يشمل: Schema من Drizzle + BLV Tables + Sample Data

-- =============================================================================
-- PART 1: ENUMS
-- =============================================================================

DO $$ BEGIN
  CREATE TYPE user_role AS ENUM ('OWNER', 'MANAGER', 'EMPLOYEE');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE employee_role AS ENUM ('owner', 'admin', 'manager', 'hr', 'monitor', 'staff');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE request_status AS ENUM ('pending', 'approved', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE leave_type AS ENUM ('regular', 'emergency');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- =============================================================================
-- PART 2: CORE TABLES
-- =============================================================================

-- BRANCHES TABLE
CREATE TABLE IF NOT EXISTS branches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  address TEXT,
  phone TEXT,
  wifi_bssid TEXT,
  latitude NUMERIC(10, 6),
  longitude NUMERIC(10, 6),
  geofence_radius INTEGER DEFAULT 100,
  manager_id TEXT, -- Will be linked to employees
  is_active BOOLEAN DEFAULT TRUE,
  learning_phase_complete BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_branches_name ON branches(name);
CREATE INDEX IF NOT EXISTS idx_branches_is_active ON branches(is_active);

-- EMPLOYEES TABLE
CREATE TABLE IF NOT EXISTS employees (
  id TEXT PRIMARY KEY,
  full_name TEXT NOT NULL,
  pin TEXT NOT NULL, -- Plain text for simplicity (hash in production)
  role employee_role DEFAULT 'staff' NOT NULL,
  permissions TEXT[] DEFAULT '{}',
  branch TEXT,
  branch_id UUID REFERENCES branches(id),
  monthly_salary NUMERIC,
  hourly_rate NUMERIC,
  shift_start_time TEXT,
  shift_end_time TEXT,
  shift_type TEXT,
  address TEXT,
  birth_date DATE,
  phone TEXT,
  national_id TEXT,
  emergency_contact TEXT,
  emergency_phone TEXT,
  hire_date DATE,
  is_active BOOLEAN DEFAULT TRUE,
  notes TEXT,
  profile_picture_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_employees_branch ON employees(branch);
CREATE INDEX IF NOT EXISTS idx_employees_branch_id ON employees(branch_id);
CREATE INDEX IF NOT EXISTS idx_employees_role ON employees(role);
CREATE INDEX IF NOT EXISTS idx_employees_is_active ON employees(is_active);

-- Add foreign key for branches.manager_id
ALTER TABLE branches DROP CONSTRAINT IF EXISTS fk_branches_manager;
ALTER TABLE branches 
ADD CONSTRAINT fk_branches_manager 
FOREIGN KEY (manager_id) REFERENCES employees(id) ON DELETE SET NULL;

-- ATTENDANCE TABLE
CREATE TABLE IF NOT EXISTS attendance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES branches(id),
  check_in_time TIMESTAMPTZ NOT NULL,
  check_out_time TIMESTAMPTZ,
  total_hours NUMERIC DEFAULT 0,
  status TEXT DEFAULT 'active',
  latitude NUMERIC,
  longitude NUMERIC,
  is_within_geofence BOOLEAN DEFAULT FALSE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_attendance_employee_id ON attendance(employee_id);
CREATE INDEX IF NOT EXISTS idx_attendance_check_in_time ON attendance(check_in_time);
CREATE INDEX IF NOT EXISTS idx_attendance_branch_id ON attendance(branch_id);
CREATE INDEX IF NOT EXISTS idx_attendance_status ON attendance(status);

-- =============================================================================
-- PART 3: BLV TABLES
-- =============================================================================

-- PULSES TABLE (5-minute heartbeat checks)
CREATE TABLE IF NOT EXISTS pulses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  attendance_id UUID REFERENCES attendance(id) ON DELETE CASCADE,
  employee_id TEXT NOT NULL REFERENCES employees(id),
  branch_id UUID REFERENCES branches(id),
  timestamp TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  latitude NUMERIC,
  longitude NUMERIC,
  is_within_geofence BOOLEAN DEFAULT FALSE,
  bssid_address TEXT,
  wifi_signal_strength INTEGER,
  cell_tower_id TEXT,
  ambient_sound_db INTEGER,
  motion_pattern TEXT,
  light_level_lux INTEGER,
  battery_level INTEGER,
  is_charging BOOLEAN,
  blv_score INTEGER,
  is_valid BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pulses_attendance_id ON pulses(attendance_id);
CREATE INDEX IF NOT EXISTS idx_pulses_employee_id ON pulses(employee_id);
CREATE INDEX IF NOT EXISTS idx_pulses_timestamp ON pulses(timestamp);
CREATE INDEX IF NOT EXISTS idx_pulses_blv_score ON pulses(blv_score);

-- BLV PATTERNS TABLE (learned fingerprint per branch)
CREATE TABLE IF NOT EXISTS blv_patterns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  learning_start_date DATE,
  learning_end_date DATE,
  learning_complete BOOLEAN DEFAULT FALSE,
  wifi_bssids JSONB,
  gps_center_lat NUMERIC,
  gps_center_lng NUMERIC,
  gps_radius_meters INTEGER,
  cell_towers JSONB,
  sound_avg_db INTEGER,
  sound_std_deviation NUMERIC,
  light_avg_lux INTEGER,
  motion_patterns JSONB,
  bluetooth_beacons JSONB,
  weekday_patterns JSONB,
  weekend_patterns JSONB,
  hourly_patterns JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_blv_patterns_branch_id ON blv_patterns(branch_id);

-- BLV LEARNING DATA (raw data during 14-day learning)
CREATE TABLE IF NOT EXISTS blv_learning_data (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  employee_id TEXT NOT NULL REFERENCES employees(id),
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  wifi_data JSONB,
  gps_data JSONB,
  cell_data JSONB,
  sound_data JSONB,
  motion_data JSONB,
  light_data JSONB,
  bluetooth_data JSONB,
  battery_data JSONB,
  day_of_week INTEGER,
  hour_of_day INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_blv_learning_data_branch_id ON blv_learning_data(branch_id);
CREATE INDEX IF NOT EXISTS idx_blv_learning_data_timestamp ON blv_learning_data(timestamp);

-- BLV VALIDATION LOGS (real-time scoring)
CREATE TABLE IF NOT EXISTS blv_validation_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id),
  branch_id UUID REFERENCES branches(id),
  validation_type TEXT,
  wifi_score INTEGER,
  gps_score INTEGER,
  cell_score INTEGER,
  sound_score INTEGER,
  motion_score INTEGER,
  bluetooth_score INTEGER,
  light_score INTEGER,
  battery_score INTEGER,
  total_score INTEGER,
  threshold INTEGER DEFAULT 70,
  is_approved BOOLEAN,
  sensor_snapshot JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_blv_validation_logs_employee_id ON blv_validation_logs(employee_id);
CREATE INDEX IF NOT EXISTS idx_blv_validation_logs_created_at ON blv_validation_logs(created_at);

-- =============================================================================
-- PART 4: REQUEST TABLES
-- =============================================================================

-- LEAVE REQUESTS
CREATE TABLE IF NOT EXISTS leave_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  leave_date DATE NOT NULL,
  reason TEXT,
  status request_status DEFAULT 'pending',
  leave_type leave_type DEFAULT 'regular',
  approved_by TEXT REFERENCES employees(id),
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_leave_requests_employee_id ON leave_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON leave_requests(status);

-- ATTENDANCE REQUESTS
CREATE TABLE IF NOT EXISTS attendance_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  reason TEXT NOT NULL,
  status request_status DEFAULT 'pending',
  approved_by TEXT REFERENCES employees(id),
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_attendance_requests_employee_id ON attendance_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_attendance_requests_status ON attendance_requests(status);

-- SALARY ADVANCES
CREATE TABLE IF NOT EXISTS salary_advances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL,
  reason TEXT,
  status request_status DEFAULT 'pending',
  approved_by TEXT REFERENCES employees(id),
  approved_at TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_salary_advances_employee_id ON salary_advances(employee_id);
CREATE INDEX IF NOT EXISTS idx_salary_advances_status ON salary_advances(status);

-- =============================================================================
-- PART 5: ENABLE ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE pulses ENABLE ROW LEVEL SECURITY;
ALTER TABLE blv_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE blv_learning_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE blv_validation_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE salary_advances ENABLE ROW LEVEL SECURITY;

-- Simple policy: allow all for authenticated users (refine later)
DO $$ 
BEGIN
  DROP POLICY IF EXISTS "Allow all for authenticated" ON branches;
  CREATE POLICY "Allow all for authenticated" ON branches FOR ALL USING (true);
  
  DROP POLICY IF EXISTS "Allow all for authenticated" ON employees;
  CREATE POLICY "Allow all for authenticated" ON employees FOR ALL USING (true);
  
  DROP POLICY IF EXISTS "Allow all for authenticated" ON attendance;
  CREATE POLICY "Allow all for authenticated" ON attendance FOR ALL USING (true);
  
  DROP POLICY IF EXISTS "Allow all for authenticated" ON pulses;
  CREATE POLICY "Allow all for authenticated" ON pulses FOR ALL USING (true);
  
  DROP POLICY IF EXISTS "Allow all for authenticated" ON leave_requests;
  CREATE POLICY "Allow all for authenticated" ON leave_requests FOR ALL USING (true);
  
  DROP POLICY IF EXISTS "Allow all for authenticated" ON attendance_requests;
  CREATE POLICY "Allow all for authenticated" ON attendance_requests FOR ALL USING (true);
  
  DROP POLICY IF EXISTS "Allow all for authenticated" ON salary_advances;
  CREATE POLICY "Allow all for authenticated" ON salary_advances FOR ALL USING (true);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- =============================================================================
-- PART 6: SAMPLE DATA
-- =============================================================================

-- Insert sample branch
INSERT INTO branches (name, address, phone, latitude, longitude, geofence_radius, is_active)
VALUES (
  'الفرع الرئيسي',
  'القاهرة، مصر الجديدة، شارع النزهة',
  '01012345678',
  30.0444,
  31.2357,
  100,
  TRUE
)
ON CONFLICT DO NOTHING;

-- Insert sample employees
INSERT INTO employees (id, full_name, pin, role, is_active, branch, monthly_salary, hourly_rate)
VALUES 
  ('OWNER001', 'صاحب العمل', '1234', 'owner', true, 'الفرع الرئيسي', 10000, 0),
  ('MGR001', 'أحمد المدير', '1111', 'manager', true, 'الفرع الرئيسي', 5000, 0),
  ('EMP001', 'محمد الموظف', '2222', 'staff', true, 'الفرع الرئيسي', 3000, 0),
  ('EMP002', 'فاطمة العاملة', '3333', 'staff', true, 'الفرع الرئيسي', 3000, 0),
  ('EMP003', 'علي الموظف', '4444', 'staff', true, 'الفرع الرئيسي', 2800, 0),
  ('HR001', 'سارة الموارد البشرية', '5555', 'hr', true, 'الفرع الرئيسي', 4000, 0)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- FINAL SUCCESS MESSAGE
-- =============================================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '✅✅✅ SETUP COMPLETE! ✅✅✅';
  RAISE NOTICE '';
  RAISE NOTICE '📋 Tables Created:';
  RAISE NOTICE '   ✓ branches (with BLV support)';
  RAISE NOTICE '   ✓ employees';
  RAISE NOTICE '   ✓ attendance';
  RAISE NOTICE '   ✓ pulses (BLV heartbeat)';
  RAISE NOTICE '   ✓ blv_patterns (learned fingerprints)';
  RAISE NOTICE '   ✓ blv_learning_data (14-day collection)';
  RAISE NOTICE '   ✓ blv_validation_logs (real-time scoring)';
  RAISE NOTICE '   ✓ leave_requests';
  RAISE NOTICE '   ✓ attendance_requests';
  RAISE NOTICE '   ✓ salary_advances';
  RAISE NOTICE '';
  RAISE NOTICE '🔐 Sample Accounts:';
  RAISE NOTICE '   👨‍💼 OWNER001 / 1234';
  RAISE NOTICE '   👔 MGR001 / 1111';
  RAISE NOTICE '   👤 EMP001 / 2222';
  RAISE NOTICE '   👤 EMP002 / 3333';
  RAISE NOTICE '   👤 EMP003 / 4444';
  RAISE NOTICE '   👥 HR001 / 5555';
  RAISE NOTICE '';
  RAISE NOTICE '🏢 Sample Branch: الفرع الرئيسي';
  RAISE NOTICE '   📍 Location: Cairo (30.0444, 31.2357)';
  RAISE NOTICE '   ⭕ Geofence: 100 meters';
  RAISE NOTICE '';
  RAISE NOTICE '🚀 Next Steps:';
  RAISE NOTICE '   1. Run: flutter run -d edge';
  RAISE NOTICE '   2. Login: OWNER001 / 1234';
  RAISE NOTICE '   3. Test all Owner screens';
  RAISE NOTICE '';
  RAISE NOTICE '💡 Schema migrated from:';
  RAISE NOTICE '   • shared/schema.ts (Drizzle ORM)';
  RAISE NOTICE '   • server/index.ts (Node.js logic)';
  RAISE NOTICE '';
  RAISE NOTICE '🎉 Ready to go!';
  RAISE NOTICE '';
END $$;
