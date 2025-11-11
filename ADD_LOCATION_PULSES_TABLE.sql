-- ==========================================
-- جدول النبضات الموقعية (Location Pulses)
-- ==========================================
-- هذا الجدول يخزن نبضات الموقع كل 5 دقائق
-- لحساب الوقت المقضي داخل الـ Geofence

CREATE TABLE IF NOT EXISTS location_pulses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  inside_geofence BOOLEAN DEFAULT FALSE,
  distance_from_center DOUBLE PRECISION,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_pulses_employee ON location_pulses(employee_id);
CREATE INDEX IF NOT EXISTS idx_pulses_timestamp ON location_pulses(timestamp);
CREATE INDEX IF NOT EXISTS idx_pulses_employee_date ON location_pulses(employee_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_pulses_inside_geofence ON location_pulses(inside_geofence);

-- Comments
COMMENT ON TABLE location_pulses IS 'نبضات الموقع كل 5 دقائق للتحقق من الوجود داخل Geofence';
COMMENT ON COLUMN location_pulses.inside_geofence IS 'هل الموظف داخل دائرة Geofence؟';
COMMENT ON COLUMN location_pulses.distance_from_center IS 'المسافة من مركز الفرع (بالأمتار)';

-- ==========================================
-- RLS Policies for location_pulses
-- ==========================================

ALTER TABLE location_pulses ENABLE ROW LEVEL SECURITY;

-- Employees can view their own pulses
DROP POLICY IF EXISTS "Employees view own pulses" ON location_pulses;
CREATE POLICY "Employees view own pulses"
ON location_pulses FOR SELECT
USING (employee_id = auth.uid()::text);

-- System can insert pulses
DROP POLICY IF EXISTS "System can insert pulses" ON location_pulses;
CREATE POLICY "System can insert pulses"
ON location_pulses FOR INSERT
WITH CHECK (true);

-- Managers can view branch pulses
DROP POLICY IF EXISTS "Managers view branch pulses" ON location_pulses;
CREATE POLICY "Managers view branch pulses"
ON location_pulses FOR SELECT
USING (
  employee_id IN (
    SELECT e.id FROM employees e
    JOIN branches b ON e.branch = b.name
    WHERE b.id::text IN (
      SELECT br.id::text FROM branches br
      JOIN employees emp ON emp.branch = br.name
      WHERE emp.id = auth.uid()::text AND emp.role = 'manager'
    )
  )
);

-- Owner can view all pulses
DROP POLICY IF EXISTS "Owners view all pulses" ON location_pulses;
CREATE POLICY "Owners view all pulses"
ON location_pulses FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM employees
    WHERE id = auth.uid()::text AND role = 'owner'
  )
);

-- ==========================================
-- Helper Function: Calculate work hours from pulses
-- ==========================================

CREATE OR REPLACE FUNCTION calculate_work_hours_from_pulses(
  p_employee_id TEXT,
  p_date DATE
) RETURNS DOUBLE PRECISION AS $$
DECLARE
  v_pulse_count INTEGER;
  v_total_minutes DOUBLE PRECISION;
BEGIN
  -- Count pulses inside geofence for the date
  SELECT COUNT(*)
  INTO v_pulse_count
  FROM location_pulses
  WHERE employee_id = p_employee_id
    AND DATE(timestamp) = p_date
    AND inside_geofence = TRUE;
  
  -- Each pulse = 5 minutes
  v_total_minutes := v_pulse_count * 5.0;
  
  -- Return hours
  RETURN v_total_minutes / 60.0;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_work_hours_from_pulses IS 'حساب ساعات العمل من النبضات (كل نبضة داخل Geofence = 5 دقائق)';

-- ==========================================
-- Helper Function: Get pulse statistics for employee
-- ==========================================

CREATE OR REPLACE FUNCTION get_pulse_statistics(
  p_employee_id TEXT,
  p_start_date DATE,
  p_end_date DATE
) RETURNS TABLE (
  total_pulses INTEGER,
  inside_pulses INTEGER,
  outside_pulses INTEGER,
  total_minutes DOUBLE PRECISION,
  total_hours DOUBLE PRECISION
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    COUNT(*)::INTEGER AS total_pulses,
    SUM(CASE WHEN inside_geofence THEN 1 ELSE 0 END)::INTEGER AS inside_pulses,
    SUM(CASE WHEN NOT inside_geofence THEN 1 ELSE 0 END)::INTEGER AS outside_pulses,
    (SUM(CASE WHEN inside_geofence THEN 1 ELSE 0 END) * 5.0)::DOUBLE PRECISION AS total_minutes,
    (SUM(CASE WHEN inside_geofence THEN 1 ELSE 0 END) * 5.0 / 60.0)::DOUBLE PRECISION AS total_hours
  FROM location_pulses
  WHERE employee_id = p_employee_id
    AND DATE(timestamp) BETWEEN p_start_date AND p_end_date;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_pulse_statistics IS 'الحصول على إحصائيات النبضات لموظف في فترة محددة';

-- ==========================================
-- Example Usage
-- ==========================================

-- Calculate work hours for today
-- SELECT calculate_work_hours_from_pulses('EMP001', CURRENT_DATE);

-- Get statistics for last 7 days
-- SELECT * FROM get_pulse_statistics('EMP001', CURRENT_DATE - 7, CURRENT_DATE);

-- ==========================================
-- Testing Data (Optional - Remove in production)
-- ==========================================

-- Insert test pulse
-- INSERT INTO location_pulses (employee_id, timestamp, latitude, longitude, inside_geofence, distance_from_center)
-- VALUES ('EMP001', NOW(), 30.0444, 31.2357, TRUE, 45.5);

-- ==========================================
-- انتهى! 
-- ==========================================
