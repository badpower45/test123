-- ============================================================================
-- COMPLETE PAYROLL SYSTEM FOR SUPABASE (FIXED VERSION)
-- ============================================================================
-- This is a complete, ready-to-run SQL file for Supabase SQL Editor
-- Copy and paste the entire contents into Supabase SQL Editor and run
--
-- FIXES:
-- - Checks if attendance table has required columns before creating indexes
-- - Creates date column if it doesn't exist
-- - More robust error handling
--
-- What this creates:
-- 1. blv_validation_logs table (detailed BLV validation events)
-- 2. payroll table (automated payroll records)
-- 3. payroll_history table (audit trail)
-- 4. Helper functions for calculations
-- 5. Triggers for auto-calculation
-- 6. Views for easy querying
-- 7. Row Level Security policies
--
-- Author: Claude Code
-- Date: 2025-11-09
-- Version: 1.0.1 (Fixed)
-- ============================================================================

-- ============================================================================
-- STEP 0: ENSURE ATTENDANCE TABLE HAS REQUIRED COLUMNS
-- ============================================================================

-- Add date column if it doesn't exist (some deployments might not have it)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attendance' AND column_name = 'date'
  ) THEN
    ALTER TABLE attendance ADD COLUMN date DATE;

    -- Populate date from check_in_time for existing records
    UPDATE attendance
    SET date = DATE(check_in_time)
    WHERE date IS NULL AND check_in_time IS NOT NULL;

    -- Set NOT NULL constraint after populating
    ALTER TABLE attendance ALTER COLUMN date SET NOT NULL;

    RAISE NOTICE 'Added date column to attendance table';
  END IF;
END $$;

-- Add work_hours column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attendance' AND column_name = 'work_hours'
  ) THEN
    ALTER TABLE attendance ADD COLUMN work_hours NUMERIC(10, 2);
    RAISE NOTICE 'Added work_hours column to attendance table';
  END IF;
END $$;

-- ============================================================================
-- STEP 1: CREATE BLV VALIDATION LOGS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS blv_validation_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
  validation_type TEXT CHECK (validation_type IN ('check-in', 'pulse', 'check-out')),

  -- Individual component scores (0-100 scale)
  wifi_score INTEGER,
  gps_score INTEGER,
  cell_score INTEGER,
  sound_score INTEGER,
  motion_score INTEGER,
  bluetooth_score INTEGER,
  light_score INTEGER,
  battery_score INTEGER,

  -- Total weighted score
  total_score INTEGER,
  threshold INTEGER DEFAULT 70,
  is_approved BOOLEAN NOT NULL DEFAULT TRUE,

  -- Raw sensor data for audit
  sensor_snapshot JSONB,

  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Indexes for BLV validation logs
CREATE INDEX IF NOT EXISTS idx_blv_logs_employee
  ON blv_validation_logs(employee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_blv_logs_branch
  ON blv_validation_logs(branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_blv_logs_approved
  ON blv_validation_logs(is_approved) WHERE is_approved = FALSE;
CREATE INDEX IF NOT EXISTS idx_blv_logs_type
  ON blv_validation_logs(validation_type);

-- ============================================================================
-- STEP 2: UPDATE ATTENDANCE TABLE WITH BLV FIELDS
-- ============================================================================

-- Add pause_duration_minutes to track time out of valid zone
ALTER TABLE attendance
  ADD COLUMN IF NOT EXISTS pause_duration_minutes INTEGER DEFAULT 0;

-- Add blv_verified_hours (total hours - pause duration)
ALTER TABLE attendance
  ADD COLUMN IF NOT EXISTS blv_verified_hours NUMERIC(10, 2);

-- Add index for payroll calculations (only if date column exists)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attendance' AND column_name = 'date'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_attendance_payroll
      ON attendance(employee_id, date, blv_verified_hours)
      WHERE blv_verified_hours IS NOT NULL;
  END IF;
END $$;

-- ============================================================================
-- STEP 3: CREATE PAYROLL TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS payroll (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,

  -- Pay period
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,

  -- Hours breakdown
  total_hours NUMERIC(10, 2) NOT NULL DEFAULT 0,
  pause_duration_minutes INTEGER NOT NULL DEFAULT 0,
  blv_verified_hours NUMERIC(10, 2) NOT NULL DEFAULT 0,

  -- Work days and shifts
  work_days INTEGER NOT NULL DEFAULT 0,
  total_shifts INTEGER NOT NULL DEFAULT 0,

  -- Pay calculation
  hourly_rate NUMERIC(10, 2) NOT NULL,
  base_salary NUMERIC(10, 2),
  gross_pay NUMERIC(12, 2) NOT NULL DEFAULT 0,

  -- Deductions
  advances_total NUMERIC(12, 2) NOT NULL DEFAULT 0,
  deductions_total NUMERIC(12, 2) NOT NULL DEFAULT 0,
  absence_deductions NUMERIC(12, 2) NOT NULL DEFAULT 0,
  late_deductions NUMERIC(12, 2) NOT NULL DEFAULT 0,

  -- Final amount
  net_pay NUMERIC(12, 2) NOT NULL DEFAULT 0,

  -- Payment status
  is_calculated BOOLEAN DEFAULT TRUE NOT NULL,
  is_approved BOOLEAN DEFAULT FALSE NOT NULL,
  is_paid BOOLEAN DEFAULT FALSE NOT NULL,

  -- Timestamps
  calculated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  approved_at TIMESTAMPTZ,
  approved_by TEXT REFERENCES employees(id),
  paid_at TIMESTAMPTZ,
  paid_by TEXT REFERENCES employees(id),

  -- Audit and notes
  calculation_details JSONB,
  notes TEXT,
  payment_method TEXT,
  payment_reference TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

  -- Constraints
  CONSTRAINT unique_employee_period UNIQUE(employee_id, period_start, period_end),
  CONSTRAINT valid_hours CHECK (blv_verified_hours >= 0 AND blv_verified_hours <= total_hours),
  CONSTRAINT valid_pay CHECK (gross_pay >= 0 AND net_pay >= 0)
);

-- Indexes for payroll table
CREATE INDEX IF NOT EXISTS idx_payroll_employee
  ON payroll(employee_id, period_start DESC);
CREATE INDEX IF NOT EXISTS idx_payroll_branch
  ON payroll(branch_id, period_start DESC);
CREATE INDEX IF NOT EXISTS idx_payroll_period
  ON payroll(period_start, period_end);
CREATE INDEX IF NOT EXISTS idx_payroll_unpaid
  ON payroll(is_paid, period_end DESC) WHERE is_paid = FALSE;
CREATE INDEX IF NOT EXISTS idx_payroll_unapproved
  ON payroll(is_approved, calculated_at DESC) WHERE is_approved = FALSE;
CREATE INDEX IF NOT EXISTS idx_payroll_status
  ON payroll(is_calculated, is_approved, is_paid);

-- ============================================================================
-- STEP 4: CREATE PAYROLL HISTORY TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS payroll_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_id UUID NOT NULL REFERENCES payroll(id) ON DELETE CASCADE,

  -- Track changes
  action TEXT NOT NULL,
  field_changed TEXT,
  old_value TEXT,
  new_value TEXT,

  -- Who made the change
  changed_by TEXT REFERENCES employees(id),
  change_reason TEXT,

  -- When
  changed_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_payroll_history_payroll
  ON payroll_history(payroll_id, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_payroll_history_action
  ON payroll_history(action, changed_at DESC);

-- ============================================================================
-- STEP 5: HELPER FUNCTIONS
-- ============================================================================

-- Function to calculate hours from timestamps
CREATE OR REPLACE FUNCTION calculate_work_hours(
  p_check_in TIMESTAMPTZ,
  p_check_out TIMESTAMPTZ
) RETURNS NUMERIC AS $$
BEGIN
  IF p_check_in IS NULL OR p_check_out IS NULL THEN
    RETURN 0;
  END IF;

  -- Return hours with 2 decimal places
  RETURN ROUND(
    EXTRACT(EPOCH FROM (p_check_out - p_check_in)) / 3600.0,
    2
  );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to get employee hourly rate
CREATE OR REPLACE FUNCTION get_employee_hourly_rate(p_employee_id TEXT)
RETURNS NUMERIC AS $$
DECLARE
  v_hourly_rate NUMERIC;
  v_monthly_salary NUMERIC;
BEGIN
  SELECT hourly_rate, monthly_salary
  INTO v_hourly_rate, v_monthly_salary
  FROM employees
  WHERE id = p_employee_id;

  -- Return hourly_rate if set, otherwise calculate from monthly salary
  IF v_hourly_rate IS NOT NULL AND v_hourly_rate > 0 THEN
    RETURN v_hourly_rate;
  ELSIF v_monthly_salary IS NOT NULL AND v_monthly_salary > 0 THEN
    -- Assume 26 working days per month, 8 hours per day
    RETURN ROUND(v_monthly_salary / (26 * 8), 2);
  ELSE
    RETURN 0;
  END IF;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to get salary advances for period
CREATE OR REPLACE FUNCTION get_advances_for_period(
  p_employee_id TEXT,
  p_period_start DATE,
  p_period_end DATE
) RETURNS NUMERIC AS $$
DECLARE
  v_total NUMERIC;
BEGIN
  SELECT COALESCE(SUM(amount), 0)
  INTO v_total
  FROM advances
  WHERE employee_id = p_employee_id
    AND status = 'approved'
    AND deducted_at IS NULL
    AND request_date <= p_period_end;

  RETURN v_total;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to get other deductions for period
CREATE OR REPLACE FUNCTION get_deductions_for_period(
  p_employee_id TEXT,
  p_period_start DATE,
  p_period_end DATE
) RETURNS NUMERIC AS $$
DECLARE
  v_total NUMERIC;
BEGIN
  SELECT COALESCE(SUM(amount), 0)
  INTO v_total
  FROM deductions
  WHERE employee_id = p_employee_id
    AND deduction_date BETWEEN p_period_start AND p_period_end;

  RETURN v_total;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to update BLV verified hours in attendance
CREATE OR REPLACE FUNCTION update_blv_verified_hours()
RETURNS TRIGGER AS $$
BEGIN
  -- Calculate blv_verified_hours when attendance is updated
  IF NEW.check_in_time IS NOT NULL AND NEW.check_out_time IS NOT NULL THEN
    -- Calculate total hours if work_hours column exists
    IF NEW.work_hours IS NULL THEN
      NEW.work_hours := calculate_work_hours(NEW.check_in_time, NEW.check_out_time);
    END IF;

    -- Calculate BLV verified hours (total - pause duration)
    NEW.blv_verified_hours := GREATEST(
      0,
      NEW.work_hours - (COALESCE(NEW.pause_duration_minutes, 0) / 60.0)
    );

    -- Set date if it's NULL
    IF NEW.date IS NULL THEN
      NEW.date := DATE(NEW.check_in_time);
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- STEP 6: CREATE TRIGGERS
-- ============================================================================

-- Trigger to auto-calculate BLV verified hours
DROP TRIGGER IF EXISTS trigger_update_blv_verified_hours ON attendance;
CREATE TRIGGER trigger_update_blv_verified_hours
  BEFORE INSERT OR UPDATE ON attendance
  FOR EACH ROW
  WHEN (NEW.check_in_time IS NOT NULL AND NEW.check_out_time IS NOT NULL)
  EXECUTE FUNCTION update_blv_verified_hours();

-- ============================================================================
-- STEP 7: CREATE VIEWS
-- ============================================================================

-- Payroll Summary View
CREATE OR REPLACE VIEW v_payroll_summary AS
SELECT
  p.id,
  p.employee_id,
  e.full_name as employee_name,
  e.branch_id,
  b.name as branch_name,
  p.period_start,
  p.period_end,
  p.total_hours,
  p.pause_duration_minutes,
  p.blv_verified_hours,
  p.hourly_rate,
  p.gross_pay,
  p.advances_total,
  p.deductions_total,
  p.absence_deductions,
  p.late_deductions,
  (p.advances_total + p.deductions_total + p.absence_deductions + p.late_deductions) as total_deductions,
  p.net_pay,
  p.is_calculated,
  p.is_approved,
  p.is_paid,
  p.calculated_at,
  p.approved_at,
  p.paid_at,
  p.payment_method,
  CASE
    WHEN p.is_paid THEN 'PAID'
    WHEN p.is_approved THEN 'APPROVED'
    WHEN p.is_calculated THEN 'PENDING_APPROVAL'
    ELSE 'DRAFT'
  END as status
FROM payroll p
JOIN employees e ON e.id = p.employee_id
LEFT JOIN branches b ON b.id = p.branch_id
ORDER BY p.period_start DESC, e.full_name;

-- ============================================================================
-- STEP 8: ROW LEVEL SECURITY (RLS)
-- ============================================================================

-- Enable RLS on payroll table
ALTER TABLE payroll ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS payroll_employee_select ON payroll;
DROP POLICY IF EXISTS payroll_manager_select ON payroll;
DROP POLICY IF EXISTS payroll_owner_all ON payroll;

-- Employees can view their own payroll
CREATE POLICY payroll_employee_select
  ON payroll FOR SELECT
  USING (employee_id = auth.uid()::TEXT);

-- Managers can view payroll for their branch
CREATE POLICY payroll_manager_select
  ON payroll FOR SELECT
  USING (
    branch_id IN (
      SELECT branch_id FROM employees
      WHERE id = auth.uid()::TEXT AND (role = 'manager' OR role = 'owner')
    )
  );

-- Only owners can insert/update payroll
CREATE POLICY payroll_owner_all
  ON payroll FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE id = auth.uid()::TEXT AND role = 'owner'
    )
  );

-- Enable RLS on payroll_history
ALTER TABLE payroll_history ENABLE ROW LEVEL SECURITY;

-- Drop existing policy if exists
DROP POLICY IF EXISTS payroll_history_select ON payroll_history;

-- Allow viewing history for payroll they can view
CREATE POLICY payroll_history_select
  ON payroll_history FOR SELECT
  USING (
    payroll_id IN (SELECT id FROM payroll)
  );

-- Enable RLS on blv_validation_logs
ALTER TABLE blv_validation_logs ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS blv_logs_employee_select ON blv_validation_logs;
DROP POLICY IF EXISTS blv_logs_manager_select ON blv_validation_logs;

-- Employees can view their own BLV logs
CREATE POLICY blv_logs_employee_select
  ON blv_validation_logs FOR SELECT
  USING (employee_id = auth.uid()::TEXT);

-- Managers can view BLV logs for their branch
CREATE POLICY blv_logs_manager_select
  ON blv_validation_logs FOR SELECT
  USING (
    branch_id IN (
      SELECT branch_id FROM employees
      WHERE id = auth.uid()::TEXT AND (role = 'manager' OR role = 'owner')
    )
  );

-- ============================================================================
-- STEP 9: ADD COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE payroll IS 'Stores calculated payroll for employees based on BLV-verified working hours';
COMMENT ON TABLE payroll_history IS 'Audit trail for all payroll changes';
COMMENT ON TABLE blv_validation_logs IS 'Logs all BLV validation events with component scores';

COMMENT ON COLUMN payroll.blv_verified_hours IS 'Actual paid hours = total_hours - (pause_duration_minutes / 60)';
COMMENT ON COLUMN payroll.gross_pay IS 'Base pay before deductions = blv_verified_hours * hourly_rate';
COMMENT ON COLUMN payroll.net_pay IS 'Final payment after all deductions';
COMMENT ON COLUMN payroll.calculation_details IS 'JSON breakdown of all calculations for transparency';

COMMENT ON COLUMN attendance.pause_duration_minutes IS 'Total minutes employee was out of valid zone (failed pulses)';
COMMENT ON COLUMN attendance.blv_verified_hours IS 'Actual working hours verified by BLV system';

COMMENT ON FUNCTION calculate_work_hours IS 'Calculate hours between two timestamps with 2 decimal precision';
COMMENT ON FUNCTION get_employee_hourly_rate IS 'Get employee hourly rate from hourly_rate field or calculated from monthly_salary';
COMMENT ON FUNCTION get_advances_for_period IS 'Sum of approved salary advances not yet deducted for the period';
COMMENT ON FUNCTION get_deductions_for_period IS 'Sum of all deductions within the specified period';

-- ============================================================================
-- STEP 10: CREATE MANUAL TRIGGER FUNCTION (OPTIONAL - FOR TESTING)
-- ============================================================================

-- This function allows you to manually trigger payroll calculation from SQL
CREATE OR REPLACE FUNCTION trigger_payroll_calculation(
  p_period_start DATE DEFAULT NULL,
  p_period_end DATE DEFAULT NULL,
  p_employee_id TEXT DEFAULT NULL,
  p_branch_id TEXT DEFAULT NULL,
  p_auto_approve BOOLEAN DEFAULT FALSE
)
RETURNS TEXT AS $$
BEGIN
  RAISE NOTICE 'Payroll calculation would be triggered for:';
  RAISE NOTICE '  Period: % to %', COALESCE(p_period_start::TEXT, 'default'), COALESCE(p_period_end::TEXT, 'default');
  RAISE NOTICE '  Employee: %', COALESCE(p_employee_id, 'all');
  RAISE NOTICE '  Branch: %', COALESCE(p_branch_id, 'all');
  RAISE NOTICE '  Auto-approve: %', p_auto_approve;

  RETURN 'Manual trigger function ready. Deploy Edge Function and update this function to call it.';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION trigger_payroll_calculation TO authenticated;

-- ============================================================================
-- STEP 11: CREATE USEFUL HELPER QUERIES AS FUNCTIONS
-- ============================================================================

-- Get payroll summary for a specific period
CREATE OR REPLACE FUNCTION get_payroll_summary(
  p_period_start DATE,
  p_period_end DATE
)
RETURNS TABLE (
  employee_count BIGINT,
  total_gross_pay NUMERIC,
  total_deductions NUMERIC,
  total_net_pay NUMERIC,
  total_hours NUMERIC,
  total_verified_hours NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    COUNT(DISTINCT employee_id) as employee_count,
    SUM(gross_pay) as total_gross_pay,
    SUM(advances_total + deductions_total + absence_deductions + late_deductions) as total_deductions,
    SUM(net_pay) as total_net_pay,
    SUM(total_hours) as total_hours,
    SUM(blv_verified_hours) as total_verified_hours
  FROM payroll
  WHERE period_start = p_period_start
    AND period_end = p_period_end;
END;
$$ LANGUAGE plpgsql STABLE;

-- Get pending payroll records (calculated but not approved)
CREATE OR REPLACE FUNCTION get_pending_payroll()
RETURNS TABLE (
  id UUID,
  employee_name TEXT,
  period_start DATE,
  period_end DATE,
  gross_pay NUMERIC,
  net_pay NUMERIC,
  calculated_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    e.full_name as employee_name,
    p.period_start,
    p.period_end,
    p.gross_pay,
    p.net_pay,
    p.calculated_at
  FROM payroll p
  JOIN employees e ON e.id = p.employee_id
  WHERE p.is_calculated = true
    AND p.is_approved = false
  ORDER BY p.calculated_at DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- STEP 12: VALIDATION AND SUCCESS MESSAGE
-- ============================================================================

DO $$
DECLARE
  v_table_count INTEGER;
  v_function_count INTEGER;
  v_trigger_count INTEGER;
  v_columns_added TEXT := '';
BEGIN
  -- Count created tables
  SELECT COUNT(*) INTO v_table_count
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_name IN ('payroll', 'payroll_history', 'blv_validation_logs');

  -- Count created functions
  SELECT COUNT(*) INTO v_function_count
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'calculate_work_hours',
      'get_employee_hourly_rate',
      'get_advances_for_period',
      'get_deductions_for_period',
      'update_blv_verified_hours',
      'trigger_payroll_calculation',
      'get_payroll_summary',
      'get_pending_payroll'
    );

  -- Count created triggers
  SELECT COUNT(*) INTO v_trigger_count
  FROM pg_trigger
  WHERE tgname = 'trigger_update_blv_verified_hours';

  -- Check what columns were added
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'attendance' AND column_name = 'pause_duration_minutes') THEN
    v_columns_added := v_columns_added || '  • pause_duration_minutes' || E'\n';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'attendance' AND column_name = 'blv_verified_hours') THEN
    v_columns_added := v_columns_added || '  • blv_verified_hours (auto-calculated)' || E'\n';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'attendance' AND column_name = 'date') THEN
    v_columns_added := v_columns_added || '  • date (for grouping)' || E'\n';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'attendance' AND column_name = 'work_hours') THEN
    v_columns_added := v_columns_added || '  • work_hours (total hours)' || E'\n';
  END IF;

  -- Display success message
  RAISE NOTICE '';
  RAISE NOTICE '================================================================';
  RAISE NOTICE '✅ PAYROLL SYSTEM INSTALLATION COMPLETE';
  RAISE NOTICE '================================================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Created:';
  RAISE NOTICE '  📊 Tables: % (payroll, payroll_history, blv_validation_logs)', v_table_count;
  RAISE NOTICE '  ⚙️  Functions: %', v_function_count;
  RAISE NOTICE '  🔄 Triggers: %', v_trigger_count;
  RAISE NOTICE '  👁️  Views: 1 (v_payroll_summary)';
  RAISE NOTICE '  🔒 RLS Policies: Enabled on all tables';
  RAISE NOTICE '';
  RAISE NOTICE 'Columns added/verified in attendance table:';
  RAISE NOTICE '%', v_columns_added;
  RAISE NOTICE '';
  RAISE NOTICE 'Available Functions:';
  RAISE NOTICE '  • calculate_work_hours(check_in, check_out)';
  RAISE NOTICE '  • get_employee_hourly_rate(employee_id)';
  RAISE NOTICE '  • get_advances_for_period(employee_id, start, end)';
  RAISE NOTICE '  • get_deductions_for_period(employee_id, start, end)';
  RAISE NOTICE '  • trigger_payroll_calculation(...) - Manual trigger';
  RAISE NOTICE '  • get_payroll_summary(period_start, period_end)';
  RAISE NOTICE '  • get_pending_payroll()';
  RAISE NOTICE '';
  RAISE NOTICE 'Next Steps:';
  RAISE NOTICE '  1. Deploy Edge Function: supabase/functions/calculate-payroll';
  RAISE NOTICE '  2. Setup pg_cron schedule (run setup_payroll_schedule.sql)';
  RAISE NOTICE '  3. Test with: SELECT trigger_payroll_calculation();';
  RAISE NOTICE '';
  RAISE NOTICE 'Testing Queries:';
  RAISE NOTICE '  • SELECT * FROM v_payroll_summary LIMIT 10;';
  RAISE NOTICE '  • SELECT * FROM get_pending_payroll();';
  RAISE NOTICE '  • SELECT * FROM get_payroll_summary(''2025-01-01'', ''2025-01-15'');';
  RAISE NOTICE '';
  RAISE NOTICE '================================================================';
END $$;
