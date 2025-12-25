-- Add WiFi BSSID tracking columns to attendance table
-- These columns store the WiFi network the employee was connected to during check-in/out
-- for additional verification and audit purposes

ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS check_in_wifi_bssid TEXT,
ADD COLUMN IF NOT EXISTS check_out_wifi_bssid TEXT;

-- Add helpful comment
COMMENT ON COLUMN attendance.check_in_wifi_bssid IS 'WiFi BSSID (MAC address) at check-in time';
COMMENT ON COLUMN attendance.check_out_wifi_bssid IS 'WiFi BSSID (MAC address) at check-out time';
