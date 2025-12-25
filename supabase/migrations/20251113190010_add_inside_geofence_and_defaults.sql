-- Add inside_geofence to pulses for offline/client compatibility
ALTER TABLE pulses
ADD COLUMN IF NOT EXISTS inside_geofence BOOLEAN;

COMMENT ON COLUMN pulses.inside_geofence IS 'Whether the pulse is inside the branch geofence (client usage)';

-- Ensure attendance.date has a sensible default to satisfy NOT NULL on fallback inserts
ALTER TABLE attendance
ALTER COLUMN date SET DEFAULT (CURRENT_DATE);
