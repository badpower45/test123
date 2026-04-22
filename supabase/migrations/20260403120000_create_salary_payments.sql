-- Track owner salary payments by employee and payroll period.

CREATE TABLE IF NOT EXISTS salary_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  net_amount NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (net_amount >= 0),
  status TEXT NOT NULL DEFAULT 'paid' CHECK (status IN ('paid', 'reversed')),
  paid_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  paid_by TEXT REFERENCES employees(id) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT salary_payments_period_dates_check CHECK (period_end >= period_start),
  CONSTRAINT salary_payments_unique_employee_period UNIQUE (employee_id, period_start, period_end)
);

ALTER TABLE salary_payments
  ADD COLUMN IF NOT EXISTS employee_id TEXT;

ALTER TABLE salary_payments
  ADD COLUMN IF NOT EXISTS period_start DATE;

ALTER TABLE salary_payments
  ADD COLUMN IF NOT EXISTS period_end DATE;

ALTER TABLE salary_payments
  ADD COLUMN IF NOT EXISTS net_amount NUMERIC(12, 2) DEFAULT 0;

ALTER TABLE salary_payments
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'paid';

ALTER TABLE salary_payments
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ DEFAULT NOW();

ALTER TABLE salary_payments
  ADD COLUMN IF NOT EXISTS paid_by TEXT;

ALTER TABLE salary_payments
  ADD COLUMN IF NOT EXISTS notes TEXT;

ALTER TABLE salary_payments
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

ALTER TABLE salary_payments
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

UPDATE salary_payments
   SET net_amount = COALESCE(net_amount, 0),
       status = COALESCE(NULLIF(status, ''), 'paid'),
       paid_at = COALESCE(paid_at, created_at, NOW()),
       created_at = COALESCE(created_at, NOW()),
       updated_at = COALESCE(updated_at, NOW())
 WHERE net_amount IS NULL
    OR status IS NULL
    OR status = ''
    OR paid_at IS NULL
    OR created_at IS NULL
    OR updated_at IS NULL;

ALTER TABLE salary_payments
  ALTER COLUMN net_amount SET DEFAULT 0;

ALTER TABLE salary_payments
  ALTER COLUMN status SET DEFAULT 'paid';

ALTER TABLE salary_payments
  ALTER COLUMN paid_at SET DEFAULT NOW();

ALTER TABLE salary_payments
  ALTER COLUMN created_at SET DEFAULT NOW();

ALTER TABLE salary_payments
  ALTER COLUMN updated_at SET DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_salary_payments_period
  ON salary_payments(period_start, period_end);

CREATE INDEX IF NOT EXISTS idx_salary_payments_employee
  ON salary_payments(employee_id, paid_at DESC);

CREATE INDEX IF NOT EXISTS idx_salary_payments_status
  ON salary_payments(status, paid_at DESC);

CREATE OR REPLACE FUNCTION set_salary_payments_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_salary_payments_updated_at ON salary_payments;

CREATE TRIGGER trigger_salary_payments_updated_at
BEFORE UPDATE ON salary_payments
FOR EACH ROW
EXECUTE FUNCTION set_salary_payments_updated_at();

-- Insert salary payment once per employee/period and return existing row id if already paid.
CREATE OR REPLACE FUNCTION mark_salary_payment(
  p_employee_id TEXT,
  p_period_start DATE,
  p_period_end DATE,
  p_net_amount NUMERIC,
  p_paid_by TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_payment_id TEXT;
BEGIN
  SELECT id::TEXT
    INTO v_payment_id
    FROM salary_payments
   WHERE employee_id = p_employee_id
     AND period_start = p_period_start
     AND period_end = p_period_end
   ORDER BY COALESCE(paid_at, created_at, NOW()) DESC, id::TEXT DESC
   LIMIT 1;

  IF v_payment_id IS NOT NULL THEN
    RETURN v_payment_id;
  END IF;

  INSERT INTO salary_payments (
    employee_id,
    period_start,
    period_end,
    net_amount,
    paid_by,
    notes,
    status
  )
  VALUES (
    p_employee_id,
    p_period_start,
    p_period_end,
    GREATEST(COALESCE(p_net_amount, 0), 0),
    p_paid_by,
    p_notes,
    'paid'
  )
  RETURNING id::TEXT INTO v_payment_id;

  RETURN v_payment_id;
END;
$$;

GRANT EXECUTE ON FUNCTION mark_salary_payment(TEXT, DATE, DATE, NUMERIC, TEXT, TEXT)
TO anon, authenticated;

ALTER TABLE salary_payments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'salary_payments'
       AND policyname = 'salary_payments_select_all'
  ) THEN
    CREATE POLICY salary_payments_select_all
      ON salary_payments
      FOR SELECT
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'salary_payments'
       AND policyname = 'salary_payments_insert_all'
  ) THEN
    CREATE POLICY salary_payments_insert_all
      ON salary_payments
      FOR INSERT
      WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'salary_payments'
       AND policyname = 'salary_payments_update_all'
  ) THEN
    CREATE POLICY salary_payments_update_all
      ON salary_payments
      FOR UPDATE
      USING (true);
  END IF;
END;
$$;

COMMENT ON TABLE salary_payments IS 'Tracks salary payments done by owner for each employee and payroll period.';
COMMENT ON FUNCTION mark_salary_payment(TEXT, DATE, DATE, NUMERIC, TEXT, TEXT) IS 'Insert salary payment once per employee/period and return payment id.';
