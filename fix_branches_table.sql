-- ============================================
-- FIX BRANCHES TABLE STRUCTURE
-- ============================================
-- Run this in Supabase SQL Editor to fix the schema

-- Drop the old branches table if it exists
DROP TABLE IF EXISTS branches CASCADE;

-- Create new branches table with correct columns
CREATE TABLE branches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    address TEXT,
    phone TEXT,
    wifi_bssid TEXT,
    latitude DECIMAL(10, 6),
    longitude DECIMAL(10, 6),
    geofence_radius INTEGER DEFAULT 100,
    manager_id TEXT REFERENCES employees(id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes
CREATE INDEX idx_branches_name ON branches(name);
CREATE INDEX idx_branches_manager_id ON branches(manager_id);
CREATE INDEX idx_branches_is_active ON branches(is_active);

-- Add comments
COMMENT ON TABLE branches IS 'Branches with BLV (Baseline Location Validation) support';
COMMENT ON COLUMN branches.wifi_bssid IS 'WiFi MAC address for indoor location validation';
COMMENT ON COLUMN branches.latitude IS 'GPS latitude for outdoor location validation';
COMMENT ON COLUMN branches.longitude IS 'GPS longitude for outdoor location validation';
COMMENT ON COLUMN branches.geofence_radius IS 'Allowed distance from branch center in meters (default 100m)';

-- Enable Row Level Security
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;

-- Add sample branch for testing
INSERT INTO branches (name, address, phone, wifi_bssid, latitude, longitude, geofence_radius, is_active)
VALUES (
    'الفرع الرئيسي',
    'القاهرة، مصر الجديدة',
    '01012345678',
    NULL,
    30.0444,
    31.2357,
    100,
    TRUE
)
ON CONFLICT DO NOTHING;

-- Success Message
DO $$
BEGIN
    RAISE NOTICE '✅ تم إصلاح جدول branches بنجاح!';
    RAISE NOTICE '📋 الأعمدة المتاحة: id, name, address, phone, wifi_bssid, latitude, longitude, geofence_radius, manager_id, is_active';
    RAISE NOTICE '🏢 تم إضافة فرع تجريبي: الفرع الرئيسي';
END $$;
