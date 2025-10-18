-- =============================================================================
-- PULSE STREAM ALIGNMENT WITH MOBILE APP
-- =============================================================================
-- This migration restructures the pulses table to match the Flutter client
-- payload and introduces the employees table (if missing) with the required
-- role enum. It is idempotent so it can be executed safely multiple times on
-- remote databases.
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'employee_role') THEN
    CREATE TYPE employee_role AS ENUM ('owner','admin','manager','hr','monitor','staff');
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS employees (
  id TEXT PRIMARY KEY,
  full_name TEXT NOT NULL,
  pin_hash TEXT NOT NULL,
  role employee_role NOT NULL DEFAULT 'staff',
  permissions TEXT[] DEFAULT '{}',
  branch TEXT,
  monthly_salary NUMERIC,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE employees IS 'Directory of restaurant employees available to the mobile attendance app';
COMMENT ON COLUMN employees.permissions IS 'Array of permission tokens granted to the employee';

-- Drop legacy shift linkage and indexes that no longer apply
DROP INDEX IF EXISTS idx_pulses_shift_id;

ALTER TABLE pulses
  DROP CONSTRAINT IF EXISTS pulses_shift_id_fkey,
  DROP COLUMN IF EXISTS shift_id;

-- Ensure latitude/longitude columns exist and use double precision for Flutter payloads
ALTER TABLE pulses
  ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

-- Core columns required by the Flutter app
ALTER TABLE pulses
  ADD COLUMN IF NOT EXISTS employee_id TEXT,
  ADD COLUMN IF NOT EXISTS "timestamp" TIMESTAMPTZ;

ALTER TABLE pulses
  ALTER COLUMN employee_id SET NOT NULL,
  ALTER COLUMN "timestamp" SET DEFAULT NOW(),
  ALTER COLUMN "timestamp" SET NOT NULL;

ALTER TABLE pulses
  ADD COLUMN IF NOT EXISTS is_fake BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sent_from_device BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS sent_via_supabase BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS offline_batch_id UUID,
  ADD COLUMN IF NOT EXISTS source TEXT,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Maintain geofence behaviour by constructing location automatically
CREATE OR REPLACE FUNCTION check_geofence()
RETURNS TRIGGER AS $$
DECLARE
    restaurant_location GEOGRAPHY;
    pulse_distance NUMERIC;
    geofence_radius_meters NUMERIC := 100;
BEGIN
    restaurant_location := ST_GeogFromText('POINT(31.2357 30.0444)');

    IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
        NEW.location := ST_SetSRID(
            ST_MakePoint(NEW.longitude, NEW.latitude),
            4326
        )::geography;
    END IF;

    IF NEW.location IS NOT NULL THEN
        pulse_distance := ST_Distance(NEW.location, restaurant_location);
        NEW.is_within_geofence := pulse_distance <= geofence_radius_meters;
    ELSE
        NEW.is_within_geofence := FALSE;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION check_geofence() IS 'Validates geofence status using latitude/longitude payloads from the Flutter client';

-- Ensure trigger exists (re-create to pick up function changes)
DROP TRIGGER IF EXISTS on_pulse_insert ON pulses;
CREATE TRIGGER on_pulse_insert
    BEFORE INSERT ON pulses
    FOR EACH ROW
    EXECUTE FUNCTION check_geofence();

-- Foreign key and indexes aligned with new structure
ALTER TABLE pulses
  ADD CONSTRAINT IF NOT EXISTS pulses_employee_id_fkey
    FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_pulses_employee_id ON pulses(employee_id);
CREATE INDEX IF NOT EXISTS idx_pulses_timestamp ON pulses("timestamp");
CREATE INDEX IF NOT EXISTS idx_pulses_latitude_longitude ON pulses(latitude, longitude);

COMMENT ON COLUMN pulses.employee_id IS 'Employee identifier that sent the pulse (matches employees.id)';
COMMENT ON COLUMN pulses."timestamp" IS 'Original timestamp from the device when the pulse was generated';
COMMENT ON COLUMN pulses.is_fake IS 'Flag for synthetic/test pulses only';
COMMENT ON COLUMN pulses.sent_from_device IS 'True if pulse originated directly from a device';
COMMENT ON COLUMN pulses.sent_via_supabase IS 'True when the Flutter app posted the pulse through Supabase';
COMMENT ON COLUMN pulses.offline_batch_id IS 'Identifier grouping pulses that were synced in bulk after offline mode';
COMMENT ON COLUMN pulses.source IS 'Optional string describing the sender (device id, worker phone, etc.)';
COMMENT ON COLUMN pulses.created_at IS 'Server-side insertion timestamp';
