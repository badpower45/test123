-- =============================================================================
-- ADD LATITUDE AND LONGITUDE COLUMNS TO PULSES TABLE
-- =============================================================================
-- This migration adds separate latitude and longitude columns to support
-- the Flutter app which sends location data as separate numeric fields
-- instead of a single geography point.
-- =============================================================================

-- Add latitude and longitude columns
ALTER TABLE pulses 
ADD COLUMN IF NOT EXISTS latitude NUMERIC,
ADD COLUMN IF NOT EXISTS longitude NUMERIC;

-- Make the location column nullable temporarily for migration
ALTER TABLE pulses 
ALTER COLUMN location DROP NOT NULL;

-- Backfill latitude/longitude from existing location data (if any)
UPDATE pulses 
SET 
  latitude = ST_Y(location::geometry),
  longitude = ST_X(location::geometry)
WHERE location IS NOT NULL 
  AND latitude IS NULL 
  AND longitude IS NULL;

-- Create index for latitude/longitude queries
CREATE INDEX IF NOT EXISTS idx_pulses_lat_lon ON pulses(latitude, longitude);

-- Add comment
COMMENT ON COLUMN pulses.latitude IS 'Latitude coordinate from Flutter app';
COMMENT ON COLUMN pulses.longitude IS 'Longitude coordinate from Flutter app';

-- =============================================================================
-- UPDATED GEOFENCE VALIDATION FUNCTION
-- =============================================================================
-- This function now accepts latitude/longitude and builds the geography point
-- automatically before checking the geofence.
-- =============================================================================

CREATE OR REPLACE FUNCTION check_geofence()
RETURNS TRIGGER AS $$
DECLARE
    restaurant_location GEOGRAPHY;
    pulse_distance NUMERIC;
    geofence_radius_meters NUMERIC := 100;
BEGIN
    -- Define the restaurant's fixed location
    restaurant_location := ST_GeogFromText('POINT(31.2357 30.0444)');
    
    -- Build geography point from latitude/longitude if not already set
    IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
        NEW.location := ST_SetSRID(
            ST_MakePoint(NEW.longitude, NEW.latitude),
            4326
        )::geography;
    END IF;
    
    -- Calculate the distance if location is available
    IF NEW.location IS NOT NULL THEN
        pulse_distance := ST_Distance(
            NEW.location,
            restaurant_location
        );
        
        -- Check if the pulse is within the geofence radius
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

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON FUNCTION check_geofence() IS 'Updated geofence function that accepts latitude/longitude and builds geography point automatically';
