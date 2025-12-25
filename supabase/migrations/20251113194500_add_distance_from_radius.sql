-- Add distance_from_radius column to branches for owner-configurable pulse tolerance
-- This defines how far outside the geofence_radius pulses can still be recorded
ALTER TABLE branches
ADD COLUMN IF NOT EXISTS distance_from_radius DOUBLE PRECISION DEFAULT 100;

COMMENT ON COLUMN branches.distance_from_radius IS 'Maximum allowed distance (meters) outside geofence_radius for pulse recording. Check-in is only allowed within geofence_radius itself.';
