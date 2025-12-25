-- Ensure every pulse row has distance_from_center populated even when the client skips it
-- 1) Helper function to compute meters using the haversine formula
CREATE OR REPLACE FUNCTION public.haversine_distance_m(
  lat1 DOUBLE PRECISION,
  lon1 DOUBLE PRECISION,
  lat2 DOUBLE PRECISION,
  lon2 DOUBLE PRECISION
) RETURNS DOUBLE PRECISION
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  r CONSTANT DOUBLE PRECISION := 6371000; -- Earth radius in meters
  dlat DOUBLE PRECISION;
  dlon DOUBLE PRECISION;
  a_val DOUBLE PRECISION;
BEGIN
  IF lat1 IS NULL OR lon1 IS NULL OR lat2 IS NULL OR lon2 IS NULL THEN
    RETURN NULL;
  END IF;

  dlat := radians(lat2 - lat1);
  dlon := radians(lon2 - lon1);

  a_val := POWER(sin(dlat / 2), 2) +
           cos(radians(lat1)) * cos(radians(lat2)) * POWER(sin(dlon / 2), 2);

  RETURN r * 2 * asin(sqrt(a_val));
END;
$$;

-- 2) Trigger that fills distance_from_center + inside_geofence before insert/update
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
  derived_inside BOOLEAN;
BEGIN
  -- Resolve branch_id from attendance if it is missing
  IF NEW.branch_id IS NOT NULL THEN
    effective_branch_id := NEW.branch_id;
  ELSIF NEW.attendance_id IS NOT NULL THEN
    SELECT branch_id INTO effective_branch_id
    FROM attendance
    WHERE id = NEW.attendance_id;

    IF NEW.branch_id IS NULL THEN
      NEW.branch_id := effective_branch_id;
    END IF;
  END IF;

  -- Calculate distance if we have all coordinates and it is still null
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

      NEW.distance_from_center := computed_distance;

      IF branch_radius IS NOT NULL THEN
        derived_inside := (computed_distance <= branch_radius);
        NEW.is_within_geofence := COALESCE(NEW.is_within_geofence, derived_inside);
        -- inside_geofence column exists for mobile app compatibility
        BEGIN
          NEW.inside_geofence := COALESCE(NEW.inside_geofence, derived_inside);
        EXCEPTION WHEN undefined_column THEN
          -- Older schemas might not have inside_geofence; ignore in that case
        END;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_pulse_distance ON pulses;
CREATE TRIGGER trg_set_pulse_distance
BEFORE INSERT OR UPDATE ON pulses
FOR EACH ROW
EXECUTE FUNCTION public.set_pulse_distance();

-- 3) Backfill existing rows that already have coordinates but missing distance/branch info
DO $$
DECLARE
  attendance_has_branch_id BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'attendance'
      AND column_name = 'branch_id'
  ) INTO attendance_has_branch_id;

  IF attendance_has_branch_id THEN
    EXECUTE $stmt$
      WITH source_data AS (
        SELECT
          p.id,
          COALESCE(p.branch_id, a.branch_id) AS resolved_branch_id,
          p.latitude,
          p.longitude
        FROM pulses p
        LEFT JOIN attendance a ON a.id = p.attendance_id
        WHERE p.distance_from_center IS NULL
          AND p.latitude IS NOT NULL
          AND p.longitude IS NOT NULL
          AND (p.branch_id IS NOT NULL OR a.branch_id IS NOT NULL)
      ),
      resolved AS (
        SELECT
          sd.id,
          sd.resolved_branch_id,
          b.latitude AS branch_lat,
          b.longitude AS branch_lng,
          b.geofence_radius,
          public.haversine_distance_m(b.latitude, b.longitude, sd.latitude, sd.longitude) AS distance_m
        FROM source_data sd
        JOIN branches b ON b.id = sd.resolved_branch_id
        WHERE b.latitude IS NOT NULL
          AND b.longitude IS NOT NULL
      )
      UPDATE pulses p
      SET
        branch_id = COALESCE(p.branch_id, r.resolved_branch_id),
        distance_from_center = r.distance_m,
        is_within_geofence = COALESCE(p.is_within_geofence, CASE
          WHEN r.geofence_radius IS NULL THEN NULL
          ELSE r.distance_m <= r.geofence_radius
        END),
        inside_geofence = COALESCE(p.inside_geofence, CASE
          WHEN r.geofence_radius IS NULL THEN p.inside_geofence
          ELSE r.distance_m <= r.geofence_radius
        END)
      FROM resolved r
      WHERE p.id = r.id;
    $stmt$;
  ELSE
    EXECUTE $stmt$
      WITH source_data AS (
        SELECT
          p.id,
          p.branch_id AS resolved_branch_id,
          p.latitude,
          p.longitude
        FROM pulses p
        WHERE p.distance_from_center IS NULL
          AND p.latitude IS NOT NULL
          AND p.longitude IS NOT NULL
          AND p.branch_id IS NOT NULL
      ),
      resolved AS (
        SELECT
          sd.id,
          sd.resolved_branch_id,
          b.latitude AS branch_lat,
          b.longitude AS branch_lng,
          b.geofence_radius,
          public.haversine_distance_m(b.latitude, b.longitude, sd.latitude, sd.longitude) AS distance_m
        FROM source_data sd
        JOIN branches b ON b.id = sd.resolved_branch_id
        WHERE b.latitude IS NOT NULL
          AND b.longitude IS NOT NULL
      )
      UPDATE pulses p
      SET
        distance_from_center = r.distance_m,
        is_within_geofence = COALESCE(p.is_within_geofence, CASE
          WHEN r.geofence_radius IS NULL THEN NULL
          ELSE r.distance_m <= r.geofence_radius
        END),
        inside_geofence = COALESCE(p.inside_geofence, CASE
          WHEN r.geofence_radius IS NULL THEN p.inside_geofence
          ELSE r.distance_m <= r.geofence_radius
        END)
      FROM resolved r
      WHERE p.id = r.id;
    $stmt$;
  END IF;
END $$;
