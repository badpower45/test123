-- ============================================
-- CONVERT DRIZZLE SCHEMA TO SUPABASE SQL
-- ============================================
-- هذا الملف يحول الـschema من Drizzle إلى SQL عادي

-- =============================================================================
-- ENUMS (من schema.ts)
-- =============================================================================

CREATE TYPE user_role AS ENUM ('OWNER', 'MANAGER', 'EMPLOYEE');
CREATE TYPE employee_role AS ENUM ('owner', 'admin', 'manager', 'hr', 'monitor', 'staff');
CREATE TYPE request_status AS ENUM ('pending', 'approved', 'rejected');
CREATE TYPE leave_type AS ENUM ('regular', 'emergency');

-- =============================================================================
-- BRANCHES TABLE (من schema.ts)
-- =============================================================================

CREATE TABLE IF NOT EXISTS branches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  manager_id TEXT, -- سيتمربطه بـemployees بعد إنشائه
  latitude NUMERIC,
  longitude NUMERIC,
  geofence_radius INTEGER DEFAULT 100,
  bssid_1 TEXT,
  bssid_2 TEXT DEFAULT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_branches_name ON branches(name);

-- =============================================================================
-- EMPLOYEES TABLE (من schema.ts)
-- =============================================================================

CREATE TABLE IF NOT EXISTS employees (
  id TEXT PRIMARY KEY,
  full_name TEXT NOT NULL,
  pin_hash TEXT NOT NULL,
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

CREATE INDEX idx_employees_branch ON employees(branch);
CREATE INDEX idx_employees_branch_id ON employees(branch_id);
CREATE INDEX idx_employees_role ON employees(role);

-- =============================================================================
-- ATTENDANCE TABLE (من schema.ts)
-- =============================================================================

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

CREATE INDEX idx_attendance_employee_id ON attendance(employee_id);
CREATE INDEX idx_attendance_check_in_time ON attendance(check_in_time);
CREATE INDEX idx_attendance_branch_id ON attendance(branch_id);

-- =============================================================================
-- PULSES TABLE (من schema.ts) - للـBLV System
-- =============================================================================

CREATE TABLE IF NOT EXISTS pulses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  attendance_id UUID NOT NULL REFERENCES attendance(id) ON DELETE CASCADE,
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

CREATE INDEX idx_pulses_attendance_id ON pulses(attendance_id);
CREATE INDEX idx_pulses_employee_id ON pulses(employee_id);
CREATE INDEX idx_pulses_timestamp ON pulses(timestamp);
CREATE INDEX idx_pulses_blv_score ON pulses(blv_score);

-- =============================================================================
-- LEAVE REQUESTS (من schema.ts)
-- =============================================================================

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

CREATE INDEX idx_leave_requests_employee_id ON leave_requests(employee_id);
CREATE INDEX idx_leave_requests_status ON leave_requests(status);

-- =============================================================================
-- ATTENDANCE REQUESTS (من schema.ts)
-- =============================================================================

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

CREATE INDEX idx_attendance_requests_employee_id ON attendance_requests(employee_id);
CREATE INDEX idx_attendance_requests_status ON attendance_requests(status);

-- =============================================================================
-- SALARY ADVANCES (من schema.ts)
-- =============================================================================

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

CREATE INDEX idx_salary_advances_employee_id ON salary_advances(employee_id);
CREATE INDEX idx_salary_advances_status ON salary_advances(status);

-- =============================================================================
-- BLV PATTERNS TABLE (للـ14-day learning)
-- =============================================================================

CREATE TABLE IF NOT EXISTS blv_patterns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  learning_start_date DATE,
  learning_end_date DATE,
  learning_complete BOOLEAN DEFAULT FALSE,
  
  -- WiFi patterns
  wifi_bssids JSONB, -- [{bssid, avg_signal, frequency}]
  
  -- GPS patterns
  gps_center_lat NUMERIC,
  gps_center_lng NUMERIC,
  gps_radius_meters INTEGER,
  
  -- Cell tower patterns
  cell_towers JSONB, -- [{mcc, mnc, lac, cid, frequency}]
  
  -- Environmental patterns
  sound_avg_db INTEGER,
  sound_std_deviation NUMERIC,
  light_avg_lux INTEGER,
  motion_patterns JSONB,
  bluetooth_beacons JSONB,
  
  -- Temporal patterns
  weekday_patterns JSONB,
  weekend_patterns JSONB,
  hourly_patterns JSONB,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_blv_patterns_branch_id ON blv_patterns(branch_id);

-- =============================================================================
-- BLV LEARNING DATA (raw sensor data during 14 days)
-- =============================================================================

CREATE TABLE IF NOT EXISTS blv_learning_data (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  employee_id TEXT NOT NULL REFERENCES employees(id),
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  
  -- Sensor readings
  wifi_data JSONB,
  gps_data JSONB,
  cell_data JSONB,
  sound_data JSONB,
  motion_data JSONB,
  light_data JSONB,
  bluetooth_data JSONB,
  battery_data JSONB,
  
  day_of_week INTEGER, -- 1-7
  hour_of_day INTEGER,  -- 0-23
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_blv_learning_data_branch_id ON blv_learning_data(branch_id);
CREATE INDEX idx_blv_learning_data_timestamp ON blv_learning_data(timestamp);

-- =============================================================================
-- BLV VALIDATION LOGS (real-time scoring)
-- =============================================================================

CREATE TABLE IF NOT EXISTS blv_validation_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id),
  branch_id UUID REFERENCES branches(id),
  validation_type TEXT, -- 'check-in', 'pulse', 'check-out'
  
  -- Scores breakdown
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
  
  -- Raw data snapshot
  sensor_snapshot JSONB,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_blv_validation_logs_employee_id ON blv_validation_logs(employee_id);
CREATE INDEX idx_blv_validation_logs_created_at ON blv_validation_logs(created_at);
CREATE INDEX idx_blv_validation_logs_is_approved ON blv_validation_logs(is_approved);

-- =============================================================================
-- ADD FOREIGN KEY CONSTRAINT (بعد إنشاء employees)
-- =============================================================================

ALTER TABLE branches 
ADD CONSTRAINT fk_branches_manager 
FOREIGN KEY (manager_id) REFERENCES employees(id) ON DELETE SET NULL;

-- =============================================================================
-- SUCCESS MESSAGE
-- =============================================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '✅✅✅ تم تحويل Schema بنجاح من Drizzle إلى Supabase! ✅✅✅';
  RAISE NOTICE '';
  RAISE NOTICE '📋 الجداول المُنشأة:';
  RAISE NOTICE '   ✓ branches (مع BLV support)';
  RAISE NOTICE '   ✓ employees (كامل)';
  RAISE NOTICE '   ✓ attendance';
  RAISE NOTICE '   ✓ pulses (للـBLV)';
  RAISE NOTICE '   ✓ leave_requests';
  RAISE NOTICE '   ✓ attendance_requests';
  RAISE NOTICE '   ✓ salary_advances';
  RAISE NOTICE '   ✓ blv_patterns (14-day learning)';
  RAISE NOTICE '   ✓ blv_learning_data';
  RAISE NOTICE '   ✓ blv_validation_logs';
  RAISE NOTICE '';
  RAISE NOTICE '🔐 الـENUMs:';
  RAISE NOTICE '   ✓ user_role';
  RAISE NOTICE '   ✓ employee_role';
  RAISE NOTICE '   ✓ request_status';
  RAISE NOTICE '   ✓ leave_type';
  RAISE NOTICE '';
  RAISE NOTICE '📊 الـIndexes: تم إنشاء كل الـindexes للأداء السريع';
  RAISE NOTICE '';
  RAISE NOTICE '🚀 الخطوة التالية:';
  RAISE NOTICE '   1. نفذ SETUP_SUPABASE_COMPLETE.sql لإضافة بيانات تجريبية';
  RAISE NOTICE '   2. أو ابدأ استخدام الجداول مباشرة';
  RAISE NOTICE '';
END $$;
