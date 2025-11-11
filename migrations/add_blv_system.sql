-- ============================================================================
-- BLV (Behavioral Location Verification) System Migration
-- Created: 2025-11-07
-- Purpose: Add complete BLV system with all fraud detection and baseline features
-- ============================================================================

-- Step 1: Update pulses table with BLV fields
ALTER TABLE pulses 
ADD COLUMN IF NOT EXISTS wifi_count INTEGER,
ADD COLUMN IF NOT EXISTS wifi_signal_strength INTEGER,
ADD COLUMN IF NOT EXISTS battery_level DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS is_charging BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS accel_variance DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS sound_level DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS device_orientation TEXT,
ADD COLUMN IF NOT EXISTS presence_score DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS trust_score DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS verification_method TEXT DEFAULT 'BLV',
ADD COLUMN IF NOT EXISTS device_model TEXT,
ADD COLUMN IF NOT EXISTS os_version TEXT,
ADD COLUMN IF NOT EXISTS raw_environment_data TEXT;

-- Add indexes for BLV fields
CREATE INDEX IF NOT EXISTS idx_pulses_presence_score ON pulses(presence_score);
CREATE INDEX IF NOT EXISTS idx_pulses_trust_score ON pulses(trust_score);
CREATE INDEX IF NOT EXISTS idx_pulses_status ON pulses(status);

-- Update existing pulses to have default BLV values
UPDATE pulses 
SET verification_method = 'WiFi', 
    presence_score = 1.0, 
    trust_score = 1.0 
WHERE verification_method IS NULL;

-- Step 2: Create branch_environment_baselines table
CREATE TABLE IF NOT EXISTS branch_environment_baselines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  time_slot TEXT NOT NULL,
  avg_wifi_count DOUBLE PRECISION,
  wifi_count_std_dev DOUBLE PRECISION,
  avg_signal_strength DOUBLE PRECISION,
  avg_battery_level DOUBLE PRECISION,
  charging_likelihood DOUBLE PRECISION,
  avg_accel_variance DOUBLE PRECISION,
  accel_variance_std_dev DOUBLE PRECISION,
  avg_sound_level DOUBLE PRECISION,
  sound_level_std_dev DOUBLE PRECISION,
  sample_count INTEGER DEFAULT 0,
  last_updated TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  confidence DOUBLE PRECISION DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_baseline_branch_id ON branch_environment_baselines(branch_id);
CREATE INDEX idx_baseline_time_slot ON branch_environment_baselines(time_slot);
CREATE INDEX idx_baseline_branch_time ON branch_environment_baselines(branch_id, time_slot);

-- Step 3: Create device_calibrations table
CREATE TABLE IF NOT EXISTS device_calibrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_model TEXT NOT NULL UNIQUE,
  os_type TEXT NOT NULL,
  accel_calibration_factor DOUBLE PRECISION DEFAULT 1.0,
  sound_calibration_factor DOUBLE PRECISION DEFAULT 1.0,
  wifi_signal_calibration_factor DOUBLE PRECISION DEFAULT 1.0,
  sample_count INTEGER DEFAULT 0,
  avg_reading_drift DOUBLE PRECISION,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_calibration_device_model ON device_calibrations(device_model);

-- Step 4: Create employee_device_baselines table
CREATE TABLE IF NOT EXISTS employee_device_baselines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  device_model TEXT,
  personal_accel_variance DOUBLE PRECISION,
  personal_sound_sensitivity DOUBLE PRECISION,
  typical_charging_pattern TEXT,
  total_pulses INTEGER DEFAULT 0,
  avg_presence_score DOUBLE PRECISION,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_emp_baseline_employee_id ON employee_device_baselines(employee_id);
CREATE INDEX idx_emp_baseline_device_id ON employee_device_baselines(device_id);
CREATE INDEX idx_emp_baseline_emp_device ON employee_device_baselines(employee_id, device_id);

-- Step 5: Create pulse_flags table
CREATE TABLE IF NOT EXISTS pulse_flags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pulse_id UUID NOT NULL REFERENCES pulses(id) ON DELETE CASCADE,
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  flag_type TEXT NOT NULL,
  severity TEXT DEFAULT 'medium',
  description TEXT,
  details TEXT,
  is_resolved BOOLEAN DEFAULT FALSE,
  resolved_by TEXT REFERENCES employees(id),
  resolved_at TIMESTAMP WITH TIME ZONE,
  resolution_note TEXT,
  resolution_action TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_flags_pulse_id ON pulse_flags(pulse_id);
CREATE INDEX idx_flags_employee_id ON pulse_flags(employee_id);
CREATE INDEX idx_flags_type ON pulse_flags(flag_type);
CREATE INDEX idx_flags_resolved ON pulse_flags(is_resolved);
CREATE INDEX idx_flags_severity ON pulse_flags(severity);

-- Step 6: Create active_interaction_logs table
CREATE TABLE IF NOT EXISTS active_interaction_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES branches(id),
  interaction_type TEXT NOT NULL,
  interaction_data TEXT,
  attendance_id UUID REFERENCES attendance(id),
  shift_duration_minutes INTEGER,
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_interaction_employee_id ON active_interaction_logs(employee_id);
CREATE INDEX idx_interaction_timestamp ON active_interaction_logs(timestamp);
CREATE INDEX idx_interaction_type ON active_interaction_logs(interaction_type);

-- Step 7: Create attendance_exemptions table
CREATE TABLE IF NOT EXISTS attendance_exemptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES branches(id),
  exemption_type TEXT NOT NULL,
  start_time TIMESTAMP WITH TIME ZONE NOT NULL,
  end_time TIMESTAMP WITH TIME ZONE NOT NULL,
  reason TEXT NOT NULL,
  status request_status DEFAULT 'pending' NOT NULL,
  requested_by TEXT REFERENCES employees(id),
  approved_by TEXT REFERENCES employees(id),
  approved_at TIMESTAMP WITH TIME ZONE,
  evidence_urls TEXT[],
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_exemption_employee_id ON attendance_exemptions(employee_id);
CREATE INDEX idx_exemption_status ON attendance_exemptions(status);
CREATE INDEX idx_exemption_type ON attendance_exemptions(exemption_type);
CREATE INDEX idx_exemption_time_range ON attendance_exemptions(start_time, end_time);

-- Step 8: Create manual_overrides table
CREATE TABLE IF NOT EXISTS manual_overrides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pulse_id UUID REFERENCES pulses(id) ON DELETE CASCADE,
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  original_presence_score DOUBLE PRECISION,
  original_trust_score DOUBLE PRECISION,
  original_status TEXT,
  new_presence_score DOUBLE PRECISION,
  new_trust_score DOUBLE PRECISION,
  new_status TEXT,
  override_by TEXT NOT NULL REFERENCES employees(id),
  override_reason TEXT NOT NULL,
  override_category TEXT,
  manager_approval BOOLEAN DEFAULT FALSE,
  hr_approval BOOLEAN DEFAULT FALSE,
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_override_pulse_id ON manual_overrides(pulse_id);
CREATE INDEX idx_override_employee_id ON manual_overrides(employee_id);
CREATE INDEX idx_override_by ON manual_overrides(override_by);
CREATE INDEX idx_override_timestamp ON manual_overrides(timestamp);

-- Step 9: Create blv_system_config table
CREATE TABLE IF NOT EXISTS blv_system_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id UUID REFERENCES branches(id),
  min_presence_score DOUBLE PRECISION DEFAULT 0.7,
  min_trust_score DOUBLE PRECISION DEFAULT 0.6,
  wifi_weight DOUBLE PRECISION DEFAULT 0.4,
  motion_weight DOUBLE PRECISION DEFAULT 0.2,
  sound_weight DOUBLE PRECISION DEFAULT 0.2,
  battery_weight DOUBLE PRECISION DEFAULT 0.2,
  active_interaction_interval_minutes INTEGER DEFAULT 120,
  max_continuous_hours_without_interaction INTEGER DEFAULT 6,
  baseline_learning_period_days INTEGER DEFAULT 14,
  baseline_update_frequency_days INTEGER DEFAULT 7,
  min_samples_for_baseline INTEGER DEFAULT 50,
  enable_no_motion_flag BOOLEAN DEFAULT TRUE,
  no_motion_threshold_minutes INTEGER DEFAULT 120,
  enable_heartbeat_check BOOLEAN DEFAULT TRUE,
  fallback_to_wifi_only BOOLEAN DEFAULT TRUE,
  allow_manual_override BOOLEAN DEFAULT TRUE,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_config_branch_id ON blv_system_config(branch_id);
CREATE INDEX idx_config_is_active ON blv_system_config(is_active);

-- Step 10: Insert default global configuration
INSERT INTO blv_system_config (branch_id, is_active) 
VALUES (NULL, TRUE)
ON CONFLICT DO NOTHING;

-- Step 11: Insert default device calibrations for common models
INSERT INTO device_calibrations (device_model, os_type, accel_calibration_factor, sound_calibration_factor, wifi_signal_calibration_factor)
VALUES 
  ('iPhone 15', 'ios', 1.0, 1.0, 1.0),
  ('iPhone 14', 'ios', 1.0, 1.0, 1.0),
  ('Samsung Galaxy S23', 'android', 1.05, 0.98, 1.02),
  ('Samsung Galaxy A54', 'android', 1.08, 0.95, 1.03),
  ('Xiaomi Redmi Note 12', 'android', 1.10, 0.92, 1.05),
  ('Oppo Reno 10', 'android', 1.07, 0.96, 1.04),
  ('Unknown', 'android', 1.0, 1.0, 1.0),
  ('Unknown', 'ios', 1.0, 1.0, 1.0)
ON CONFLICT (device_model) DO NOTHING;

-- Step 12: Create function to auto-update timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 13: Add triggers for updated_at
CREATE TRIGGER update_baseline_updated_at 
  BEFORE UPDATE ON branch_environment_baselines 
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_calibration_updated_at 
  BEFORE UPDATE ON device_calibrations 
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_emp_baseline_updated_at 
  BEFORE UPDATE ON employee_device_baselines 
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_config_updated_at 
  BEFORE UPDATE ON blv_system_config 
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Step 14: Add comments for documentation
COMMENT ON TABLE branch_environment_baselines IS 'Environmental baseline (fingerprint) for each branch by time of day';
COMMENT ON TABLE device_calibrations IS 'Calibration factors for different device models to normalize sensor readings';
COMMENT ON TABLE employee_device_baselines IS 'Personal behavioral baseline for each employee-device combination';
COMMENT ON TABLE pulse_flags IS 'Flags and alerts for suspicious or anomalous pulses requiring review';
COMMENT ON TABLE active_interaction_logs IS 'Log of active user interactions to detect passive/abandoned devices';
COMMENT ON TABLE attendance_exemptions IS 'Approved exemptions for attendance verification (sick leave, missions, etc.)';
COMMENT ON TABLE manual_overrides IS 'Manual corrections to pulse verification scores by managers/HR';
COMMENT ON TABLE blv_system_config IS 'Configuration parameters for the BLV verification system';

-- Migration complete!
SELECT 'BLV System Migration Completed Successfully!' AS status;
