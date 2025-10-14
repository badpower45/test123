-- =============================================================================
-- COMPLETE DATABASE SCHEMA FOR OLDIES WORKERS ATTENDANCE SYSTEM
-- Migrated from Supabase to Neon PostgreSQL
-- =============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

-- =============================================================================
-- TABLE: profiles (employee information)
-- =============================================================================
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY,
    full_name TEXT NOT NULL,
    employee_id TEXT UNIQUE NOT NULL,
    role TEXT DEFAULT 'employee' NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for profiles
CREATE INDEX IF NOT EXISTS idx_profiles_employee_id ON profiles(employee_id);
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);

COMMENT ON TABLE profiles IS 'User profiles with employee information';

-- =============================================================================
-- TABLE: shifts (work shift records)
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

-- Indexes for shifts
CREATE INDEX IF NOT EXISTS idx_shifts_user_id ON shifts(user_id);
CREATE INDEX IF NOT EXISTS idx_shifts_status ON shifts(status);
CREATE INDEX IF NOT EXISTS idx_shifts_check_in_time ON shifts(check_in_time);

COMMENT ON TABLE shifts IS 'Employee work shifts with check-in/check-out times';

-- =============================================================================
-- TABLE: pulses (location updates with geofencing)
-- =============================================================================
CREATE TABLE IF NOT EXISTS pulses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
    latitude NUMERIC,
    longitude NUMERIC,
    location GEOGRAPHY(Point, 4326),
    is_within_geofence BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for pulses
CREATE INDEX IF NOT EXISTS idx_pulses_shift_id ON pulses(shift_id);
CREATE INDEX IF NOT EXISTS idx_pulses_lat_lon ON pulses(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_pulses_location ON pulses USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_pulses_geofence ON pulses(is_within_geofence);
CREATE INDEX IF NOT EXISTS idx_pulses_created_at ON pulses(created_at);

COMMENT ON TABLE pulses IS 'Location pulses sent periodically during shifts for attendance verification';
COMMENT ON COLUMN pulses.location IS 'Geographic point (latitude, longitude) stored as PostGIS geography';
COMMENT ON COLUMN pulses.is_within_geofence IS 'Automatically calculated by trigger to verify if pulse is within restaurant area';

-- =============================================================================
-- GEOFENCE VALIDATION FUNCTION
-- =============================================================================
-- Restaurant location: Cairo area (30.0444°N, 31.2357°E)
-- Geofence radius: 100 meters

CREATE OR REPLACE FUNCTION check_geofence()
RETURNS TRIGGER AS $$
DECLARE
    restaurant_location GEOGRAPHY;
    pulse_distance NUMERIC;
    geofence_radius_meters NUMERIC := 100;
BEGIN
    -- Define the restaurant's fixed location (POINT(longitude latitude))
    restaurant_location := ST_GeogFromText('POINT(31.2357 30.0444)');
    
    -- Build geography point from latitude/longitude if provided
    IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
        NEW.location := ST_SetSRID(
            ST_MakePoint(NEW.longitude, NEW.latitude),
            4326
        )::geography;
    END IF;
    
    -- Calculate distance and validate geofence if location is available
    IF NEW.location IS NOT NULL THEN
        pulse_distance := ST_Distance(
            NEW.location,
            restaurant_location
        );
        
        -- Check if pulse is within geofence radius
        IF pulse_distance <= geofence_radius_meters THEN
            NEW.is_within_geofence := TRUE;
        ELSE
            NEW.is_within_geofence := FALSE;
        END IF;
    ELSE
        -- If no location data, mark as outside geofence
        NEW.is_within_geofence := FALSE;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION check_geofence() IS 'Validates if pulse location is within restaurant geofence, accepts latitude/longitude and builds geography point automatically';

-- =============================================================================
-- TRIGGER: Automatic geofence validation on pulse insert
-- =============================================================================
DROP TRIGGER IF EXISTS on_pulse_insert ON pulses;

CREATE TRIGGER on_pulse_insert
    BEFORE INSERT ON pulses
    FOR EACH ROW
    EXECUTE FUNCTION check_geofence();

COMMENT ON TRIGGER on_pulse_insert ON pulses IS 'Triggers geofence validation before inserting new pulse records';

-- =============================================================================
-- HELPER FUNCTION: Update restaurant location
-- =============================================================================
CREATE OR REPLACE FUNCTION update_restaurant_location(
    new_longitude NUMERIC,
    new_latitude NUMERIC,
    new_radius_meters NUMERIC DEFAULT 100
)
RETURNS TEXT AS $$
BEGIN
    RETURN FORMAT(
        'To update restaurant location, modify the check_geofence() function with:
        POINT(%s %s) and radius %s meters',
        new_longitude, new_latitude, new_radius_meters
    );
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- INITIAL DATA: Demo employees (optional)
-- =============================================================================
-- Insert demo employees if they don't exist
INSERT INTO profiles (id, full_name, employee_id, role)
VALUES 
    (gen_random_uuid(), 'مريم حسن', 'EMP001', 'admin'),
    (gen_random_uuid(), 'عمر سعيد', 'EMP002', 'hr'),
    (gen_random_uuid(), 'نورة عادل', 'EMP003', 'monitor')
ON CONFLICT (employee_id) DO NOTHING;

-- =============================================================================
-- SCHEMA COMPLETE
-- =============================================================================
