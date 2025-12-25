-- Ensure pulses always store distance_from_center and inside_geofence
CREATE OR REPLACE FUNCTION public.set_pulse_distance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  effective_branch_id UUID;
  branch_lat DOUBLE PRECISION;
  branch_lng DOUBLE PRECISION;
  branch_radius DOUBLE PRECISION;
  computed_distance DOUBLE PRECISION;
  derived_inside BOOLEAN := NULL;
BEGIN
  effective_branch_id := NEW.branch_id;
  IF effective_branch_id IS NULL AND NEW.attendance_id IS NOT NULL THEN
    BEGIN
      SELECT branch_id INTO effective_branch_id
      FROM attendance
      WHERE id = NEW.attendance_id;
    EXCEPTION WHEN undefined_column THEN
      effective_branch_id := NULL;
    END;

    IF NEW.branch_id IS NULL THEN
      NEW.branch_id := effective_branch_id;
    END IF;
  END IF;

  IF NEW.distance_from_center IS NULL
     AND NEW.latitude IS NOT NULL
     AND NEW.longitude IS NOT NULL
     AND effective_branch_id IS NOT NULL THEN

    SELECT latitude, longitude, geofence_radius
    INTO branch_lat, branch_lng, branch_radius
    FROM branches
    WHERE id = effective_branch_id;

    IF branch_lat IS NOT NULL AND branch_lng IS NOT NULL THEN
      computed_distance := public.haversine_distance_m(
        branch_lat,
        branch_lng,
        NEW.latitude,
        NEW.longitude
      );

      IF computed_distance IS NOT NULL THEN
        NEW.distance_from_center := computed_distance;
      END IF;

      IF branch_radius IS NOT NULL AND computed_distance IS NOT NULL THEN
        derived_inside := computed_distance <= branch_radius;
        NEW.is_within_geofence := COALESCE(NEW.is_within_geofence, derived_inside);
        NEW.inside_geofence := COALESCE(NEW.inside_geofence, derived_inside);
      END IF;
    END IF;
  END IF;

  IF NEW.inside_geofence IS NULL THEN
    NEW.inside_geofence := COALESCE(NEW.is_within_geofence, derived_inside, false);
  END IF;

  IF NEW.is_within_geofence IS NULL THEN
    NEW.is_within_geofence := NEW.inside_geofence;
  END IF;

  IF NEW.distance_from_center IS NULL THEN
    IF NEW.inside_geofence THEN
      NEW.distance_from_center := 0;
    ELSIF branch_radius IS NOT NULL THEN
      NEW.distance_from_center := branch_radius + 1;
    ELSE
      NEW.distance_from_center := 9999;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Re-run trigger for rows where distance can be calculated
UPDATE pulses
SET latitude = latitude
WHERE distance_from_center IS NULL
  AND latitude IS NOT NULL
  AND longitude IS NOT NULL;

-- Ensure boolean flag is never NULL
UPDATE pulses
SET inside_geofence = COALESCE(inside_geofence, is_within_geofence, false)
WHERE inside_geofence IS NULL;

-- Fill remaining NULL distances with deterministic fallback
UPDATE pulses
SET distance_from_center = CASE
  WHEN COALESCE(inside_geofence, is_within_geofence, false) THEN 0
  ELSE 9999
END
WHERE distance_from_center IS NULL;
