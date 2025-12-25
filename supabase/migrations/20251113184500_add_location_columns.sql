-- Add missing location and distance columns to attendance and pulses tables
-- These columns are required by the mobile app and Edge Functions

-- Fix attendance table
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

COMMENT ON COLUMN attendance.latitude IS 'GPS latitude at check-in';
COMMENT ON COLUMN attendance.longitude IS 'GPS longitude at check-in';

-- Fix pulses table
ALTER TABLE pulses
ADD COLUMN IF NOT EXISTS distance_from_center DOUBLE PRECISION;

COMMENT ON COLUMN pulses.distance_from_center IS 'Distance in meters from branch center';
