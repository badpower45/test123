-- BLV System Enhancements Migration
-- Adds performance indexes, drift detection, and device trust layer

-- ============================================================================
-- PERFORMANCE INDEXES
-- ============================================================================

-- Pulses table - heavy query optimization
CREATE INDEX IF NOT EXISTS idx_pulses_branch_created 
  ON pulses(branch_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_pulses_employee_created 
  ON pulses(employee_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_pulses_verification_method 
  ON pulses(verification_method) 
  WHERE verification_method IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pulses_blv_scores 
  ON pulses(presence_score, trust_score) 
  WHERE wifi_count IS NOT NULL;

-- Composite index for complex queries
CREATE INDEX IF NOT EXISTS idx_pulses_branch_employee_date 
  ON pulses(branch_id, employee_id, created_at DESC);

-- Flags table - quick manager reviews
CREATE INDEX IF NOT EXISTS idx_flags_employee_date 
  ON pulse_flags(employee_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_flags_unresolved 
  ON pulse_flags(is_resolved, severity DESC) 
  WHERE is_resolved = FALSE;

CREATE INDEX IF NOT EXISTS idx_flags_type_severity 
  ON pulse_flags(flag_type, severity DESC);

CREATE INDEX IF NOT EXISTS idx_flags_pulse_employee 
  ON pulse_flags(pulse_id, employee_id, is_resolved);

-- WiFi Signals - fingerprinting
CREATE INDEX IF NOT EXISTS idx_wifi_branch_time 
  ON wifi_signals(branch_id, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_wifi_bssid 
  ON wifi_signals(bssid);

-- ============================================================================
-- DRIFT DETECTION SYSTEM
-- ============================================================================

CREATE TABLE IF NOT EXISTS drift_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  time_slot VARCHAR(20), -- e.g., 'morning', 'afternoon'
  
  drift_type VARCHAR(50) NOT NULL, -- 'WIFI', 'BATTERY', 'MOTION'
  old_value DECIMAL(10,2),
  new_value DECIMAL(10,2),
  drift_magnitude DECIMAL(5,2), -- How much it drifted (ratio)
  
  detected_at TIMESTAMP DEFAULT NOW(),
  resolved BOOLEAN DEFAULT FALSE,
  resolved_at TIMESTAMP,
  resolution_notes TEXT
);

CREATE INDEX idx_drift_branch ON drift_alerts(branch_id, detected_at DESC);
CREATE INDEX idx_drift_unresolved ON drift_alerts(resolved) WHERE resolved = FALSE;

-- ============================================================================
-- DEVICE TRUST LAYER
-- ============================================================================

CREATE TABLE IF NOT EXISTS device_fingerprints (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id VARCHAR(255) UNIQUE NOT NULL, -- IMEI / Android ID / iOS UUID
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  
  -- Device Info
  device_model VARCHAR(100),
  os_type VARCHAR(20), -- 'android', 'ios'
  os_version VARCHAR(20),
  app_version VARCHAR(20),
  
  -- Timestamps
  first_seen TIMESTAMP DEFAULT NOW(),
  last_seen TIMESTAMP DEFAULT NOW(),
  
  -- Trust Metrics
  total_pulses INTEGER DEFAULT 0,
  flagged_pulses INTEGER DEFAULT 0,
  approved_pulses INTEGER DEFAULT 0,
  
  calibration_factor DECIMAL(5,2) DEFAULT 1.0, -- Sensor correction factor
  reliability_index DECIMAL(5,2) DEFAULT 0.8,  -- 0.0 - 1.0 (starts at 0.8)
  
  -- Behavioral Patterns
  avg_gps_accuracy DECIMAL(10,2),
  typical_battery_drain DECIMAL(5,2),
  typical_wifi_count INTEGER,
  
  -- Security
  is_blacklisted BOOLEAN DEFAULT FALSE,
  blacklist_reason TEXT,
  blacklisted_at TIMESTAMP,
  
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_device_employee ON device_fingerprints(employee_id);
CREATE INDEX idx_device_trust_score ON device_fingerprints(reliability_index DESC);
CREATE INDEX idx_device_blacklist ON device_fingerprints(is_blacklisted) 
  WHERE is_blacklisted = TRUE;
CREATE INDEX idx_device_last_seen ON device_fingerprints(last_seen DESC);

-- ============================================================================
-- SYSTEM HEALTH MONITORING
-- ============================================================================

CREATE TABLE IF NOT EXISTS blv_health_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  timestamp TIMESTAMP DEFAULT NOW(),
  metric_type VARCHAR(50) NOT NULL, -- 'HEARTBEAT', 'FALLBACK', 'ERROR'
  
  -- Metrics
  total_pulses_today INTEGER,
  blv_success_rate DECIMAL(5,2),
  avg_response_time_ms INTEGER,
  error_count INTEGER DEFAULT 0,
  
  -- System State
  is_fallback_mode BOOLEAN DEFAULT FALSE,
  last_heartbeat TIMESTAMP,
  
  details JSONB
);

CREATE INDEX idx_health_timestamp ON blv_health_logs(timestamp DESC);
CREATE INDEX idx_health_metric_type ON blv_health_logs(metric_type);

-- ============================================================================
-- BASELINE CONFIDENCE TRACKING
-- ============================================================================

-- Add last_updated column to track baseline freshness
ALTER TABLE branch_environment_baselines 
  ADD COLUMN IF NOT EXISTS last_updated TIMESTAMP DEFAULT NOW();

-- Add index for confidence decay queries
CREATE INDEX IF NOT EXISTS idx_baselines_updated 
  ON branch_environment_baselines(last_updated DESC);

-- ============================================================================
-- VIEWS FOR ANALYTICS
-- ============================================================================

-- Real-time system health view
CREATE OR REPLACE VIEW v_blv_system_health AS
SELECT 
  DATE(created_at) as date,
  COUNT(*) as total_pulses,
  COUNT(*) FILTER (WHERE verification_method = 'BLV') as blv_pulses,
  COUNT(*) FILTER (WHERE verification_method = 'WiFi') as wifi_pulses,
  COUNT(*) FILTER (WHERE verification_method = 'GPS') as gps_pulses,
  AVG(presence_score) FILTER (WHERE presence_score IS NOT NULL) as avg_presence,
  AVG(trust_score) FILTER (WHERE trust_score IS NOT NULL) as avg_trust,
  COUNT(*) FILTER (WHERE presence_score >= 0.7 AND trust_score >= 0.6) as successful_verifications,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE presence_score >= 0.7 AND trust_score >= 0.6) / 
    NULLIF(COUNT(*) FILTER (WHERE wifi_count IS NOT NULL), 0),
    2
  ) as success_rate_percent
FROM pulses
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- Top flagged employees view
CREATE OR REPLACE VIEW v_top_flagged_employees AS
SELECT 
  e.id as employee_id,
  e.full_name,
  e.branch_id,
  COUNT(pf.id) as total_flags,
  COUNT(*) FILTER (WHERE pf.is_resolved = FALSE) as unresolved_flags,
  AVG(pf.severity) as avg_severity,
  array_agg(DISTINCT pf.flag_type) as flag_types,
  MAX(pf.created_at) as last_flagged_at
FROM employees e
JOIN pulse_flags pf ON pf.employee_id = e.id
WHERE pf.created_at >= NOW() - INTERVAL '30 days'
GROUP BY e.id, e.full_name, e.branch_id
HAVING COUNT(pf.id) > 5
ORDER BY total_flags DESC;

-- Device trust scores view
CREATE OR REPLACE VIEW v_device_trust_scores AS
SELECT 
  device_id,
  employee_id,
  device_model,
  os_type,
  total_pulses,
  flagged_pulses,
  ROUND(100.0 * flagged_pulses / NULLIF(total_pulses, 0), 2) as flag_rate_percent,
  reliability_index,
  is_blacklisted,
  last_seen,
  EXTRACT(EPOCH FROM (NOW() - last_seen)) / 3600 as hours_since_last_seen
FROM device_fingerprints
WHERE total_pulses > 10
ORDER BY reliability_index ASC, flagged_pulses DESC;

-- Baseline freshness view
CREATE OR REPLACE VIEW v_baseline_freshness AS
SELECT 
  beb.branch_id,
  b.name as branch_name,
  beb.time_slot,
  beb.confidence as original_confidence,
  beb.last_updated,
  EXTRACT(EPOCH FROM (NOW() - beb.last_updated)) / 86400 as days_since_update,
  ROUND(
    beb.confidence * POW(0.98, EXTRACT(EPOCH FROM (NOW() - beb.last_updated)) / 86400),
    3
  ) as current_confidence,
  CASE
    WHEN beb.confidence * POW(0.98, EXTRACT(EPOCH FROM (NOW() - beb.last_updated)) / 86400) < 0.5 
      THEN 'NEEDS_RECALIBRATION'
    WHEN beb.confidence * POW(0.98, EXTRACT(EPOCH FROM (NOW() - beb.last_updated)) / 86400) < 0.7 
      THEN 'WARNING'
    ELSE 'OK'
  END as status
FROM branch_environment_baselines beb
JOIN branches b ON b.id = beb.branch_id
ORDER BY current_confidence ASC;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Function to update device trust after each pulse
CREATE OR REPLACE FUNCTION update_device_trust()
RETURNS TRIGGER AS $$
BEGIN
  -- Update device fingerprint statistics
  UPDATE device_fingerprints
  SET 
    total_pulses = total_pulses + 1,
    last_seen = NEW.created_at,
    updated_at = NOW()
  WHERE device_id = NEW.device_id;
  
  -- If device doesn't exist, create it
  IF NOT FOUND THEN
    INSERT INTO device_fingerprints (device_id, employee_id, total_pulses, last_seen)
    VALUES (NEW.device_id, NEW.employee_id, 1, NEW.created_at);
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-update device trust
DROP TRIGGER IF EXISTS trigger_update_device_trust ON pulses;
CREATE TRIGGER trigger_update_device_trust
  AFTER INSERT ON pulses
  FOR EACH ROW
  WHEN (NEW.device_id IS NOT NULL)
  EXECUTE FUNCTION update_device_trust();

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE drift_alerts IS 'Tracks when branch environmental baselines drift from current conditions';
COMMENT ON TABLE device_fingerprints IS 'Stores device trust scores and behavioral patterns';
COMMENT ON TABLE blv_health_logs IS 'System health monitoring and heartbeat tracking';

COMMENT ON VIEW v_blv_system_health IS 'Daily BLV system performance metrics';
COMMENT ON VIEW v_top_flagged_employees IS 'Employees with most BLV flags';
COMMENT ON VIEW v_device_trust_scores IS 'Device reliability rankings';
COMMENT ON VIEW v_baseline_freshness IS 'Baseline confidence with decay calculation';

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

-- Log migration
DO $$
BEGIN
  RAISE NOTICE 'BLV Enhancements Migration Complete';
  RAISE NOTICE 'Added: Performance indexes, Drift detection, Device trust layer';
  RAISE NOTICE 'Created: 3 new tables, 4 analytics views, 1 trigger function';
END $$;
