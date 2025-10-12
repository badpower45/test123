-- =============================================================================
-- GEOFENCE VALIDATION FUNCTION
-- =============================================================================
-- This function automatically checks if a new pulse is within the restaurant's
-- geofence area. It calculates the distance from a fixed restaurant location
-- and sets the is_within_geofence flag accordingly.
-- =============================================================================

-- Restaurant location configuration
-- Default: Cairo area (30.0444°N, 31.2357°E)
-- Geofence radius: 100 meters
-- You can modify these values based on your restaurant's actual location

CREATE OR REPLACE FUNCTION check_geofence()
RETURNS TRIGGER AS $$
DECLARE
    restaurant_location GEOGRAPHY;
    pulse_distance NUMERIC;
    geofence_radius_meters NUMERIC := 100; -- 100 meters radius
BEGIN
    -- Define the restaurant's fixed location
    -- Format: POINT(longitude latitude) - note the order!
    restaurant_location := ST_GeogFromText('POINT(31.2357 30.0444)');
    
    -- Calculate the distance between the pulse location and restaurant
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
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- TRIGGER: on_pulse_insert
-- =============================================================================
-- This trigger executes the check_geofence function before every INSERT
-- operation on the pulses table, automatically validating location.
-- =============================================================================

CREATE TRIGGER on_pulse_insert
    BEFORE INSERT ON pulses
    FOR EACH ROW
    EXECUTE FUNCTION check_geofence();

-- =============================================================================
-- HELPER FUNCTION: Update restaurant location
-- =============================================================================
-- Use this function to easily update the restaurant location if needed
-- Example: SELECT update_restaurant_location(31.2652, 29.9863, 150);
-- =============================================================================

CREATE OR REPLACE FUNCTION update_restaurant_location(
    new_longitude NUMERIC,
    new_latitude NUMERIC,
    new_radius_meters NUMERIC DEFAULT 100
)
RETURNS TEXT AS $$
BEGIN
    -- This is a placeholder function to document how to update the location
    -- In practice, you would need to alter the check_geofence function
    -- or use a configuration table to store the restaurant location
    
    RETURN FORMAT(
        'To update restaurant location, modify the check_geofence() function with:
        POINT(%s %s) and radius %s meters',
        new_longitude, new_latitude, new_radius_meters
    );
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON FUNCTION check_geofence() IS 'Automatically validates if a pulse location is within the restaurant geofence';
COMMENT ON TRIGGER on_pulse_insert ON pulses IS 'Triggers geofence validation before inserting new pulse records';
