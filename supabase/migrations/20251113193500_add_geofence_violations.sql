-- Create table to persist geofence violations as a server-side alert fallback
CREATE TABLE IF NOT EXISTS geofence_violations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attendance_id uuid,
  employee_id text,
  branch_id uuid,
  timestamp timestamptz NOT NULL DEFAULT now(),
  latitude double precision,
  longitude double precision,
  distance_from_center double precision,
  radius_meters double precision,
  bssid_address text,
  resolved boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE geofence_violations IS 'Logged when a check-in pulse is outside the configured geofence radius. Used for manager alerts.';
COMMENT ON COLUMN geofence_violations.attendance_id IS 'Related attendance record, if available';
COMMENT ON COLUMN geofence_violations.employee_id IS 'Employee identifier as used by app (text)';
COMMENT ON COLUMN geofence_violations.branch_id IS 'Branch UUID where violation occurred';
COMMENT ON COLUMN geofence_violations.distance_from_center IS 'Meters away from branch center';
COMMENT ON COLUMN geofence_violations.radius_meters IS 'Configured branch geofence radius in meters at time of violation';

-- Enable RLS so only service role / server can access by default
ALTER TABLE geofence_violations ENABLE ROW LEVEL SECURITY;