-- =============================================================================
-- MIGRATION: Multi-Branch Schema Update for Smart Heartbeat Attendance System
-- =============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

-- =============================================================================
-- TABLE: Users (Unified for OWNER, MANAGER, EMPLOYEE)
-- =============================================================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT CHECK (role IN ('OWNER', 'MANAGER', 'EMPLOYEE')) NOT NULL,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL, -- NULL for OWNER
    full_name TEXT NOT NULL,
    email TEXT UNIQUE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_branch_id ON users(branch_id);

COMMENT ON TABLE users IS 'Unified users table for all roles in the multi-branch system';

-- =============================================================================
-- TABLE: Branches (Multi-Branch Support)
-- =============================================================================
CREATE TABLE IF NOT EXISTS branches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    address TEXT,
    manager_id UUID REFERENCES users(id) ON DELETE SET NULL,
    geo_lat DECIMAL,
    geo_lon DECIMAL,
    geo_radius INTEGER DEFAULT 100,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_branches_name ON branches(name);
CREATE INDEX IF NOT EXISTS idx_branches_manager_id ON branches(manager_id);

COMMENT ON TABLE branches IS 'Branches with dynamic geofence settings';

-- =============================================================================
-- TABLE: Branch_BSSIDs (Multiple BSSIDs per Branch)
-- =============================================================================
CREATE TABLE IF NOT EXISTS branch_bssids (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
    bssid_address TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_branch_bssids_branch_id ON branch_bssids(branch_id);
CREATE INDEX IF NOT EXISTS idx_branch_bssids_bssid_address ON branch_bssids(bssid_address);

COMMENT ON TABLE branch_bssids IS 'Valid BSSID addresses for each branch (supports multiple routers)';

-- =============================================================================
-- UPDATED TABLE: Pulses (Include branch_id, remove shift_id)
-- =============================================================================
CREATE TABLE IF NOT EXISTS pulses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
    latitude DECIMAL,
    longitude DECIMAL,
    location GEOGRAPHY(Point, 4326),
    bssid_address TEXT,
    is_within_geofence BOOLEAN DEFAULT FALSE,
    is_synced BOOLEAN DEFAULT TRUE,
    status TEXT CHECK (status IN ('IN', 'OUT')) DEFAULT 'IN',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pulses_user_id ON pulses(user_id);
CREATE INDEX IF NOT EXISTS idx_pulses_branch_id ON pulses(branch_id);
CREATE INDEX IF NOT EXISTS idx_pulses_lat_lon ON pulses(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_pulses_location ON pulses USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_pulses_geofence ON pulses(is_within_geofence);
CREATE INDEX IF NOT EXISTS idx_pulses_created_at ON pulses(created_at);

COMMENT ON TABLE pulses IS 'Updated pulses with branch_id and BSSID for multi-branch support';

-- =============================================================================
-- GEOFENCE VALIDATION FUNCTION (Dynamic per Branch)
-- =============================================================================
CREATE OR REPLACE FUNCTION check_geofence()
RETURNS TRIGGER AS $$
DECLARE
    branch_record RECORD;
    pulse_distance NUMERIC;
BEGIN
    -- Get branch settings for the pulse's branch_id
    SELECT geo_lat, geo_lon, geo_radius INTO branch_record
    FROM branches
    WHERE id = NEW.branch_id;

    IF branch_record IS NULL THEN
        NEW.is_within_geofence := FALSE;
        RETURN NEW;
    END IF;

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
            ST_SetSRID(ST_MakePoint(branch_record.geo_lon, branch_record.geo_lat), 4326)::geography
        );

        IF pulse_distance <= branch_record.geo_radius THEN
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

COMMENT ON FUNCTION check_geofence() IS 'Validates pulse against branch-specific geofence';

-- Trigger for pulses
DROP TRIGGER IF EXISTS on_pulse_insert ON pulses;
CREATE TRIGGER on_pulse_insert
    BEFORE INSERT ON pulses
    FOR EACH ROW
    EXECUTE FUNCTION check_geofence();

-- =============================================================================
-- BSSID VALIDATION FUNCTION (Check against Branch_BSSIDs)
-- =============================================================================
CREATE OR REPLACE FUNCTION validate_bssid()
RETURNS TRIGGER AS $$
DECLARE
    valid_bssid BOOLEAN := FALSE;
BEGIN
    -- Check if BSSID matches any for the branch
    SELECT EXISTS(
        SELECT 1 FROM branch_bssids
        WHERE branch_id = NEW.branch_id AND bssid_address = NEW.bssid_address
    ) INTO valid_bssid;

    IF NEW.bssid_address IS NOT NULL AND NOT valid_bssid THEN
        RAISE EXCEPTION 'BSSID % does not match any valid BSSIDs for branch %', NEW.bssid_address, NEW.branch_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_bssid() IS 'Validates BSSID against branch-specific list';

-- Trigger for pulses
DROP TRIGGER IF EXISTS on_pulse_bssid_check ON pulses;
CREATE TRIGGER on_pulse_bssid_check
    BEFORE INSERT ON pulses
    FOR EACH ROW
    EXECUTE FUNCTION validate_bssid();

-- =============================================================================
-- SAMPLE DATA (Optional)
-- =============================================================================
-- Insert Owner
INSERT INTO users (username, password_hash, role, full_name, email) VALUES
('owner1', crypt('password', gen_salt('bf')), 'OWNER', 'System Owner', 'owner@example.com');

-- Insert a Branch
INSERT INTO branches (name, address, geo_lat, geo_lon, geo_radius) VALUES
('Main Branch', '123 Main St', 30.0444, 31.2357, 100);

-- Assign Manager (assuming a user with MANAGER role)
INSERT INTO users (username, password_hash, role, branch_id, full_name, email) VALUES
('manager1', crypt('password', gen_salt('bf')), 'MANAGER', (SELECT id FROM branches WHERE name='Main Branch'), 'Branch Manager', 'manager@example.com');

-- Update Branch with Manager
UPDATE branches SET manager_id = (SELECT id FROM users WHERE username='manager1') WHERE name='Main Branch';

-- Add BSSIDs for Branch
INSERT INTO branch_bssids (branch_id, bssid_address) VALUES
((SELECT id FROM branches WHERE name='Main Branch'), 'AA:BB:CC:DD:EE:FF');

-- Insert Employee
INSERT INTO users (username, password_hash, role, branch_id, full_name, email) VALUES
('employee1', crypt('password', gen_salt('bf')), 'EMPLOYEE', (SELECT id FROM branches WHERE name='Main Branch'), 'John Doe', 'employee@example.com');

-- =============================================================================
-- SCHEMA COMPLETE
-- =============================================================================