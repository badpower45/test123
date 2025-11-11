-- ============================================================================
-- BLV Fraud Detection Trigger System
-- ============================================================================
-- This migration creates a trigger system that automatically detects
-- fraud attempts based on BLV validation scores and sends alerts.
--
-- Author: Claude Code
-- Date: 2025-11-09
-- ============================================================================

-- Create fraud alerts table to store detected fraud attempts
CREATE TABLE IF NOT EXISTS fraud_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL,
  branch_id TEXT,
  validation_log_id UUID,
  alert_type TEXT NOT NULL, -- 'LOW_SCORE', 'REJECTED', 'SUSPICIOUS_PATTERN'
  severity NUMERIC NOT NULL DEFAULT 0.5, -- 0.0 to 1.0
  total_score INTEGER,
  details JSONB,
  notified_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  resolved_by TEXT,
  resolution_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Foreign key constraints
  CONSTRAINT fk_employee FOREIGN KEY (employee_id)
    REFERENCES employees(id) ON DELETE CASCADE
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_fraud_alerts_employee
  ON fraud_alerts(employee_id);
CREATE INDEX IF NOT EXISTS idx_fraud_alerts_created
  ON fraud_alerts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_fraud_alerts_unresolved
  ON fraud_alerts(resolved_at) WHERE resolved_at IS NULL;

-- ============================================================================
-- Fraud Detection Function
-- ============================================================================

CREATE OR REPLACE FUNCTION detect_blv_fraud()
RETURNS TRIGGER AS $$
DECLARE
  employee_name TEXT;
  branch_name TEXT;
  alert_severity NUMERIC;
  alert_type TEXT;
  should_alert BOOLEAN := FALSE;
BEGIN
  -- Only process insertions where validation was rejected or score is low
  IF NEW.is_approved = FALSE OR (NEW.total_score IS NOT NULL AND NEW.total_score < 40) THEN

    -- Determine alert type and severity
    IF NEW.total_score IS NOT NULL AND NEW.total_score < 20 THEN
      alert_type := 'LOW_SCORE';
      alert_severity := 0.9;  -- Critical
      should_alert := TRUE;
    ELSIF NEW.total_score IS NOT NULL AND NEW.total_score < 40 THEN
      alert_type := 'LOW_SCORE';
      alert_severity := 0.6;  -- Warning
      should_alert := TRUE;
    ELSIF NEW.is_approved = FALSE THEN
      alert_type := 'REJECTED';
      alert_severity := 0.7;  -- Warning
      should_alert := TRUE;
    END IF;

    IF should_alert THEN
      -- Get employee name
      SELECT full_name INTO employee_name
      FROM employees
      WHERE id = NEW.employee_id;

      -- Get branch name if available
      IF NEW.branch_id IS NOT NULL THEN
        SELECT name INTO branch_name
        FROM branches
        WHERE id = NEW.branch_id;
      END IF;

      -- Insert fraud alert record
      INSERT INTO fraud_alerts (
        employee_id,
        branch_id,
        validation_log_id,
        alert_type,
        severity,
        total_score,
        details
      ) VALUES (
        NEW.employee_id,
        NEW.branch_id,
        NEW.id,
        alert_type,
        alert_severity,
        NEW.total_score,
        jsonb_build_object(
          'employee_name', COALESCE(employee_name, 'Unknown'),
          'branch_name', COALESCE(branch_name, 'Unknown'),
          'validation_type', NEW.validation_type,
          'timestamp', NEW.created_at,
          'wifi_score', NEW.wifi_score,
          'gps_score', NEW.gps_score,
          'cell_score', NEW.cell_score,
          'sound_score', NEW.sound_score,
          'motion_score', NEW.motion_score
        )
      );

      -- Log to console
      RAISE NOTICE 'Fraud alert created: Employee %, Score %, Type %',
        employee_name, NEW.total_score, alert_type;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Create Trigger
-- ============================================================================

DROP TRIGGER IF NOT EXISTS trigger_blv_fraud_detection
  ON blv_validation_logs;

CREATE TRIGGER trigger_blv_fraud_detection
  AFTER INSERT ON blv_validation_logs
  FOR EACH ROW
  EXECUTE FUNCTION detect_blv_fraud();

-- ============================================================================
-- Helper Functions for Managers/Owners
-- ============================================================================

-- Get unresolved fraud alerts for a branch
CREATE OR REPLACE FUNCTION get_unresolved_fraud_alerts(p_branch_id TEXT)
RETURNS TABLE (
  id UUID,
  employee_id TEXT,
  employee_name TEXT,
  alert_type TEXT,
  severity NUMERIC,
  total_score INTEGER,
  created_at TIMESTAMPTZ,
  details JSONB
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    fa.id,
    fa.employee_id,
    e.full_name as employee_name,
    fa.alert_type,
    fa.severity,
    fa.total_score,
    fa.created_at,
    fa.details
  FROM fraud_alerts fa
  JOIN employees e ON fa.employee_id = e.id
  WHERE fa.branch_id = p_branch_id
    AND fa.resolved_at IS NULL
  ORDER BY fa.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Resolve a fraud alert
CREATE OR REPLACE FUNCTION resolve_fraud_alert(
  p_alert_id UUID,
  p_resolved_by TEXT,
  p_notes TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE fraud_alerts
  SET
    resolved_at = NOW(),
    resolved_by = p_resolved_by,
    resolution_notes = p_notes
  WHERE id = p_alert_id
    AND resolved_at IS NULL;

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Get fraud statistics for a branch
CREATE OR REPLACE FUNCTION get_fraud_stats(
  p_branch_id TEXT,
  p_start_date TIMESTAMPTZ DEFAULT NOW() - INTERVAL '30 days'
)
RETURNS TABLE (
  total_alerts INTEGER,
  critical_alerts INTEGER,
  resolved_alerts INTEGER,
  pending_alerts INTEGER,
  avg_response_time INTERVAL
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    COUNT(*)::INTEGER as total_alerts,
    COUNT(CASE WHEN severity > 0.8 THEN 1 END)::INTEGER as critical_alerts,
    COUNT(CASE WHEN resolved_at IS NOT NULL THEN 1 END)::INTEGER as resolved_alerts,
    COUNT(CASE WHEN resolved_at IS NULL THEN 1 END)::INTEGER as pending_alerts,
    AVG(resolved_at - created_at) as avg_response_time
  FROM fraud_alerts
  WHERE branch_id = p_branch_id
    AND created_at >= p_start_date;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Row Level Security (RLS)
-- ============================================================================

ALTER TABLE fraud_alerts ENABLE ROW LEVEL SECURITY;

-- Managers can see alerts for their branch
CREATE POLICY fraud_alerts_manager_select
  ON fraud_alerts FOR SELECT
  USING (
    branch_id IN (
      SELECT branch_id FROM employees
      WHERE id = auth.uid() AND (role = 'manager' OR role = 'owner')
    )
  );

-- Managers can update (resolve) alerts
CREATE POLICY fraud_alerts_manager_update
  ON fraud_alerts FOR UPDATE
  USING (
    branch_id IN (
      SELECT branch_id FROM employees
      WHERE id = auth.uid() AND (role = 'manager' OR role = 'owner')
    )
  );

-- System can insert fraud alerts
CREATE POLICY fraud_alerts_system_insert
  ON fraud_alerts FOR INSERT
  WITH CHECK (true);

-- ============================================================================
-- Success Message
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Fraud detection trigger system installed successfully';
  RAISE NOTICE '   - fraud_alerts table created';
  RAISE NOTICE '   - trigger_blv_fraud_detection enabled';
  RAISE NOTICE '   - Helper functions available:';
  RAISE NOTICE '     • get_unresolved_fraud_alerts(branch_id)';
  RAISE NOTICE '     • resolve_fraud_alert(alert_id, resolved_by, notes)';
  RAISE NOTICE '     • get_fraud_stats(branch_id, start_date)';
END $$;
