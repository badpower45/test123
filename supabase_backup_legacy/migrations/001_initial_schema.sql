-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable pgcrypto for gen_random_uuid() function
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Enable PostGIS for geographic data
CREATE EXTENSION IF NOT EXISTS postgis;

-- =============================================================================
-- TABLE: profiles (extends auth.users)
-- =============================================================================
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    employee_id TEXT UNIQUE NOT NULL,
    role TEXT DEFAULT 'employee' NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for faster employee_id lookups
CREATE INDEX idx_profiles_employee_id ON profiles(employee_id);

-- Index for role-based queries
CREATE INDEX idx_profiles_role ON profiles(role);

-- =============================================================================
-- TABLE: shifts (records each work shift)
-- =============================================================================
CREATE TABLE shifts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    check_in_time TIMESTAMPTZ DEFAULT NOW(),
    check_out_time TIMESTAMPTZ,
    status TEXT DEFAULT 'active' NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for user's shifts
CREATE INDEX idx_shifts_user_id ON shifts(user_id);

-- Index for shift status queries
CREATE INDEX idx_shifts_status ON shifts(status);

-- Index for time-based queries
CREATE INDEX idx_shifts_check_in_time ON shifts(check_in_time);

-- =============================================================================
-- TABLE: pulses (stores periodic location updates)
-- =============================================================================
CREATE TABLE pulses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
    location GEOGRAPHY(Point, 4326) NOT NULL,
    is_within_geofence BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for shift's pulses
CREATE INDEX idx_pulses_shift_id ON pulses(shift_id);

-- Spatial index for location queries
CREATE INDEX idx_pulses_location ON pulses USING GIST(location);

-- Index for geofence filtering
CREATE INDEX idx_pulses_geofence ON pulses(is_within_geofence);

-- Index for time-based queries
CREATE INDEX idx_pulses_created_at ON pulses(created_at);

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE profiles IS 'User profiles extending auth.users with employee information';
COMMENT ON TABLE shifts IS 'Employee work shifts with check-in/check-out times';
COMMENT ON TABLE pulses IS 'Location pulses sent periodically during shifts for attendance verification';
COMMENT ON COLUMN pulses.location IS 'Geographic point (latitude, longitude) stored as PostGIS geography';
COMMENT ON COLUMN pulses.is_within_geofence IS 'Automatically calculated by trigger to verify if pulse is within restaurant area';
