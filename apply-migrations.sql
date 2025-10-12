-- =============================================================================
-- APPLY ALL MIGRATIONS TO SUPABASE
-- =============================================================================
-- Copy this entire file and run it in Supabase SQL Editor
-- =============================================================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

-- =============================================================================
-- TABLE: profiles
-- =============================================================================
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY,
    full_name TEXT NOT NULL,
    employee_id TEXT UNIQUE NOT NULL,
    role TEXT DEFAULT 'employee' NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profiles_employee_id ON profiles(employee_id);
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);

-- =============================================================================
-- TABLE: shifts
-- =============================================================================
CREATE TABLE IF NOT EXISTS shifts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    check_in_time TIMESTAMPTZ DEFAULT NOW(),
    check_out_time TIMESTAMPTZ,
    status TEXT DEFAULT 'active' NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shifts_user_id ON shifts(user_id);
CREATE INDEX IF NOT EXISTS idx_shifts_status ON shifts(status);
CREATE INDEX IF NOT EXISTS idx_shifts_check_in_time ON shifts(check_in_time);

-- =============================================================================
-- TABLE: pulses (WITH LAT/LON COLUMNS)
-- =============================================================================
CREATE TABLE IF NOT EXISTS pulses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shift_id UUID REFERENCES shifts(id) ON DELETE CASCADE,
    latitude NUMERIC,
    longitude NUMERIC,
    location GEOGRAPHY(Point, 4326),
    is_within_geofence BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pulses_shift_id ON pulses(shift_id);
CREATE INDEX IF NOT EXISTS idx_pulses_location ON pulses USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_pulses_geofence ON pulses(is_within_geofence);
CREATE INDEX IF NOT EXISTS idx_pulses_created_at ON pulses(created_at);
CREATE INDEX IF NOT EXISTS idx_pulses_lat_lon ON pulses(latitude, longitude);

-- =============================================================================
-- GEOFENCE FUNCTION (UPDATED TO USE LAT/LON)
-- =============================================================================
CREATE OR REPLACE FUNCTION check_geofence()
RETURNS TRIGGER AS $$
DECLARE
    restaurant_location GEOGRAPHY;
    pulse_distance NUMERIC;
    geofence_radius_meters NUMERIC := 100;
BEGIN
    -- Restaurant location: Cairo (30.0444°N, 31.2357°E)
    restaurant_location := ST_GeogFromText('POINT(31.2357 30.0444)');
    
    -- Build geography point from latitude/longitude if provided
    IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
        NEW.location := ST_SetSRID(
            ST_MakePoint(NEW.longitude, NEW.latitude),
            4326
        )::geography;
    END IF;
    
    -- Calculate distance if location is available
    IF NEW.location IS NOT NULL THEN
        pulse_distance := ST_Distance(NEW.location, restaurant_location);
        
        IF pulse_distance <= geofence_radius_meters THEN
            NEW.is_within_geofence := TRUE;
        ELSE
            NEW.is_within_geofence := FALSE;
        END IF;
    ELSE
        NEW.is_within_geofence := FALSE;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- TRIGGER
-- =============================================================================
DROP TRIGGER IF EXISTS on_pulse_insert ON pulses;
CREATE TRIGGER on_pulse_insert
    BEFORE INSERT ON pulses
    FOR EACH ROW
    EXECUTE FUNCTION check_geofence();

-- =============================================================================
-- ROW LEVEL SECURITY (RLS)
-- =============================================================================
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE pulses ENABLE ROW LEVEL SECURITY;

-- Profiles policies
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
CREATE POLICY "Users can view own profile"
    ON profiles FOR SELECT
    USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id AND role = (SELECT role FROM profiles WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Admins can view all profiles" ON profiles;
CREATE POLICY "Admins can view all profiles"
    ON profiles FOR SELECT
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

DROP POLICY IF EXISTS "Admins can insert profiles" ON profiles;
CREATE POLICY "Admins can insert profiles"
    ON profiles FOR INSERT
    WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

DROP POLICY IF EXISTS "Admins can update all profiles" ON profiles;
CREATE POLICY "Admins can update all profiles"
    ON profiles FOR UPDATE
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- Shifts policies
DROP POLICY IF EXISTS "Users can view own shifts" ON shifts;
CREATE POLICY "Users can view own shifts"
    ON shifts FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create own shifts" ON shifts;
CREATE POLICY "Users can create own shifts"
    ON shifts FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own shifts" ON shifts;
CREATE POLICY "Users can update own shifts"
    ON shifts FOR UPDATE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can view all shifts" ON shifts;
CREATE POLICY "Admins can view all shifts"
    ON shifts FOR SELECT
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

DROP POLICY IF EXISTS "Admins can update all shifts" ON shifts;
CREATE POLICY "Admins can update all shifts"
    ON shifts FOR UPDATE
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- Pulses policies
DROP POLICY IF EXISTS "Users can view own pulses" ON pulses;
CREATE POLICY "Users can view own pulses"
    ON pulses FOR SELECT
    USING (EXISTS (SELECT 1 FROM shifts WHERE shifts.id = pulses.shift_id AND shifts.user_id = auth.uid()));

DROP POLICY IF EXISTS "Users can create pulses for own shifts" ON pulses;
CREATE POLICY "Users can create pulses for own shifts"
    ON pulses FOR INSERT
    WITH CHECK (EXISTS (SELECT 1 FROM shifts WHERE shifts.id = shift_id AND shifts.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can view all pulses" ON pulses;
CREATE POLICY "Admins can view all pulses"
    ON pulses FOR SELECT
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- Service role policies
DROP POLICY IF EXISTS "Service role full access to profiles" ON profiles;
CREATE POLICY "Service role full access to profiles"
    ON profiles FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

DROP POLICY IF EXISTS "Service role full access to shifts" ON shifts;
CREATE POLICY "Service role full access to shifts"
    ON shifts FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

DROP POLICY IF EXISTS "Service role full access to pulses" ON pulses;
CREATE POLICY "Service role full access to pulses"
    ON pulses FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

-- =============================================================================
-- ALLOW ANONYMOUS INSERTS (FOR TESTING - REMOVE IN PRODUCTION!)
-- =============================================================================
-- This allows the app to insert pulses without authentication for testing
DROP POLICY IF EXISTS "Allow anonymous pulse inserts" ON pulses;
CREATE POLICY "Allow anonymous pulse inserts"
    ON pulses FOR INSERT
    WITH CHECK (true);

-- =============================================================================
-- SUCCESS MESSAGE
-- =============================================================================
DO $$
BEGIN
    RAISE NOTICE 'All migrations applied successfully! Tables created with lat/lon support.';
END $$;
