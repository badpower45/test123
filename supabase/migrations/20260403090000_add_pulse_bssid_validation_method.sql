-- Add WiFi BSSID and validation method to pulses
ALTER TABLE pulses ADD COLUMN IF NOT EXISTS wifi_bssid TEXT;
ALTER TABLE pulses ADD COLUMN IF NOT EXISTS validation_method TEXT;
