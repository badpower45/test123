-- 1. Add is_super_employee column to employees
ALTER TABLE employees ADD COLUMN IF NOT EXISTS is_super_employee BOOLEAN DEFAULT FALSE NOT NULL;

-- 2. Create attendance_rules table
CREATE TABLE IF NOT EXISTS attendance_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  grace_period_minutes INTEGER DEFAULT 15 NOT NULL,
  deduction_multiplier NUMERIC DEFAULT 1.0 NOT NULL,
  deduction_type TEXT DEFAULT 'hourly_pro_rata' NOT NULL, -- 'hourly_pro_rata', 'fixed_per_incident', 'tiered'
  fixed_deduction_amount NUMERIC DEFAULT 0 NOT NULL,
  tiered_rules JSONB DEFAULT '[]'::jsonb NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT unique_branch_rule UNIQUE (branch_id)
);

-- Insert a default global rule (where branch_id is null)
INSERT INTO attendance_rules (branch_id, grace_period_minutes, deduction_multiplier, deduction_type, fixed_deduction_amount, tiered_rules)
VALUES (NULL, 15, 1.0, 'hourly_pro_rata', 0, '[]'::jsonb)
ON CONFLICT (branch_id) DO NOTHING;

-- RLS policies
ALTER TABLE attendance_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners manage all rules" ON attendance_rules;
CREATE POLICY "Owners manage all rules" ON attendance_rules
  FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM employees WHERE employees.id = auth.uid()::text AND employees.role = 'owner')
  );

DROP POLICY IF EXISTS "Anyone authenticated can view rules" ON attendance_rules;
CREATE POLICY "Anyone authenticated can view rules" ON attendance_rules
  FOR SELECT TO authenticated USING (true);
