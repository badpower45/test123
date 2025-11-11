-- ============================================================================
-- Payroll System Migration
-- ============================================================================
-- This migration creates the complete payroll system that calculates
-- employee pay based on BLV-verified working hours with deductions
--
-- Author: Claude Code
-- Date: 2025-11-09
-- Task: 10.1 - Design and Implement Payroll Database Schema
-- ============================================================================

-- ============================================================================
-- Step 1: Create BLV Validation Logs Table (if not exists)
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
-- Step 2: Update Attendance Table with BLV Fields
-- ============================================================================

-- Add pause_duration_minutes to track time out of valid zone
ALTER TABLE attendance
  ADD COLUMN IF NOT EXISTS pause_duration_minutes INTEGER DEFAULT 0;

-- Add blv_verified_hours (total hours - pause duration)
ALTER TABLE attendance
  ADD COLUMN IF NOT EXISTS blv_verified_hours NUMERIC(10, 2);

-- Add index for payroll calculations
CREATE INDEX IF NOT EXISTS idx_attendance_payroll
  ON attendance(employee_id, date, blv_verified_hours)
  WHERE blv_verified_hours IS NOT NULL;

-- ============================================================================
-- Step 3: Create Payroll Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS payroll (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,

  -- Pay period
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,

  -- Hours breakdown
  total_hours NUMERIC(10, 2) NOT NULL DEFAULT 0, -- Raw hours from check-in/out
  pause_duration_minutes INTEGER NOT NULL DEFAULT 0, -- Out-of-range time
  blv_verified_hours NUMERIC(10, 2) NOT NULL DEFAULT 0, -- Actual paid hours

  -- Work days and shifts
  work_days INTEGER NOT NULL DEFAULT 0,
  total_shifts INTEGER NOT NULL DEFAULT 0,

  -- Pay calculation
  hourly_rate NUMERIC(10, 2) NOT NULL,
  base_salary NUMERIC(10, 2), -- Monthly salary if applicable
  gross_pay NUMERIC(12, 2) NOT NULL DEFAULT 0, -- blv_verified_hours * hourly_rate

  -- Deductions
  advances_total NUMERIC(12, 2) NOT NULL DEFAULT 0, -- Salary advances to deduct
  deductions_total NUMERIC(12, 2) NOT NULL DEFAULT 0, -- Other deductions
  absence_deductions NUMERIC(12, 2) NOT NULL DEFAULT 0, -- Absence penalties
  late_deductions NUMERIC(12, 2) NOT NULL DEFAULT 0, -- Late arrival penalties

  -- Final amount
  net_pay NUMERIC(12, 2) NOT NULL DEFAULT 0, -- gross_pay - all deductions

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
  calculation_details JSONB, -- Detailed breakdown for transparency
  notes TEXT,
  payment_method TEXT, -- 'cash', 'bank_transfer', 'check'
  payment_reference TEXT, -- Transaction ID or check number

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
-- Step 4: Create Payroll History/Audit Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS payroll_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_id UUID NOT NULL REFERENCES payroll(id) ON DELETE CASCADE,

  -- Track changes
  action TEXT NOT NULL, -- 'CALCULATED', 'APPROVED', 'PAID', 'MODIFIED', 'CANCELLED'
  field_changed TEXT, -- Which field was modified
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
-- Step 5: Helper Functions for Payroll System
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
    AND deducted_at IS NULL  -- Not yet deducted
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
    -- Calculate total hours
    NEW.work_hours := calculate_work_hours(NEW.check_in_time, NEW.check_out_time);

    -- Calculate BLV verified hours (total - pause duration)
    NEW.blv_verified_hours := GREATEST(
      0,
      NEW.work_hours - (COALESCE(NEW.pause_duration_minutes, 0) / 60.0)
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-calculate BLV verified hours
DROP TRIGGER IF EXISTS trigger_update_blv_verified_hours ON attendance;
CREATE TRIGGER trigger_update_blv_verified_hours
  BEFORE INSERT OR UPDATE ON attendance
  FOR EACH ROW
  WHEN (NEW.check_in_time IS NOT NULL AND NEW.check_out_time IS NOT NULL)
  EXECUTE FUNCTION update_blv_verified_hours();

-- ============================================================================
-- Step 6: Payroll Summary View
-- ============================================================================

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
-- Step 7: Row Level Security (RLS)
-- ============================================================================

-- Enable RLS on payroll table
ALTER TABLE payroll ENABLE ROW LEVEL SECURITY;

-- Employees can view their own payroll
CREATE POLICY payroll_employee_select
  ON payroll FOR SELECT
  USING (employee_id = auth.uid());

-- Managers can view payroll for their branch
CREATE POLICY payroll_manager_select
  ON payroll FOR SELECT
  USING (
    branch_id IN (
      SELECT branch_id FROM employees
      WHERE id = auth.uid() AND (role = 'manager' OR role = 'owner')
    )
  );

-- Only owners can insert/update payroll
CREATE POLICY payroll_owner_all
  ON payroll FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE id = auth.uid() AND role = 'owner'
    )
  );

-- ============================================================================
-- Step 8: Add Comments for Documentation
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

-- ============================================================================
-- Success Message
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Payroll system migration completed successfully';
  RAISE NOTICE '   - blv_validation_logs table created';
  RAISE NOTICE '   - attendance table updated with BLV fields';
  RAISE NOTICE '   - payroll table created with complete schema';
  RAISE NOTICE '   - payroll_history table created for audit trail';
  RAISE NOTICE '   - Helper functions created:';
  RAISE NOTICE '     • calculate_work_hours(check_in, check_out)';
  RAISE NOTICE '     • get_employee_hourly_rate(employee_id)';
  RAISE NOTICE '     • get_advances_for_period(employee_id, start, end)';
  RAISE NOTICE '     • get_deductions_for_period(employee_id, start, end)';
  RAISE NOTICE '   - Auto-trigger for BLV verified hours calculation';
  RAISE NOTICE '   - v_payroll_summary view created';
  RAISE NOTICE '   - Row Level Security enabled';
  RAISE NOTICE '';
  RAISE NOTICE '📋 Next steps:';
  RAISE NOTICE '   1. Deploy this migration to Supabase';
  RAISE NOTICE '   2. Create Edge Function for automatic payroll calculation';
  RAISE NOTICE '   3. Set up pg_cron for scheduled execution';
END $$;
