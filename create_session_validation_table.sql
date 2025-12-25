-- ✅ Session Validation Requests Table
-- Used when employee has a gap in pulse tracking > 5.5 minutes
-- Manager can approve (create TRUE pulses) or reject (create FALSE pulses)

CREATE TABLE IF NOT EXISTS session_validation_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  attendance_id UUID REFERENCES attendance(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
  manager_id TEXT REFERENCES employees(id) ON DELETE SET NULL,
  
  -- Gap information
  gap_start_time TIMESTAMPTZ NOT NULL,
  gap_end_time TIMESTAMPTZ NOT NULL,
  gap_duration_minutes INTEGER NOT NULL,
  expected_pulses_count INTEGER NOT NULL,
  
  -- Request status
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  manager_response_time TIMESTAMPTZ,
  manager_notes TEXT,
  
  -- Metadata
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_session_validation_employee ON session_validation_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_session_validation_manager ON session_validation_requests(manager_id);
CREATE INDEX IF NOT EXISTS idx_session_validation_status ON session_validation_requests(status);
CREATE INDEX IF NOT EXISTS idx_session_validation_created ON session_validation_requests(created_at);

-- RLS Policies
ALTER TABLE session_validation_requests ENABLE ROW LEVEL SECURITY;

-- Allow all operations (since we're using TEXT IDs, not auth.uid())
-- The app handles authorization through its own logic
CREATE POLICY "Allow all read access"
  ON session_validation_requests
  FOR SELECT
  USING (true);

CREATE POLICY "Allow all insert access"
  ON session_validation_requests
  FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Allow all update access"
  ON session_validation_requests
  FOR UPDATE
  USING (true);

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION update_session_validation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER session_validation_updated_at
  BEFORE UPDATE ON session_validation_requests
  FOR EACH ROW
  EXECUTE FUNCTION update_session_validation_timestamp();

-- ✅ Add column to location_pulses to mark validation-generated pulses
ALTER TABLE location_pulses 
ADD COLUMN IF NOT EXISTS created_by_validation BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS validation_request_id UUID REFERENCES session_validation_requests(id) ON DELETE SET NULL;

-- Index for validation-generated pulses
CREATE INDEX IF NOT EXISTS idx_location_pulses_validation ON location_pulses(created_by_validation, validation_request_id);

-- Comments
COMMENT ON TABLE session_validation_requests IS 'Requests for manager approval when employee has a gap in pulse tracking > 5.5 minutes';
COMMENT ON COLUMN session_validation_requests.gap_start_time IS 'Start time of the tracking gap (last pulse or check-in time)';
COMMENT ON COLUMN session_validation_requests.gap_end_time IS 'End time of the tracking gap (when employee resumed)';
COMMENT ON COLUMN session_validation_requests.expected_pulses_count IS 'Number of pulses that should have been recorded (every 5 minutes)';
COMMENT ON COLUMN session_validation_requests.status IS 'pending: awaiting manager decision, approved: creates TRUE pulses, rejected: creates FALSE pulses';
