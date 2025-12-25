-- Fix update_current_salary trigger function to work for both sources:
-- 1) salary_advances (uses NEW.status)
-- 2) up_to_date_salary (no status column)

CREATE OR REPLACE FUNCTION update_current_salary()
RETURNS TRIGGER AS $$
DECLARE
  v_employee_id TEXT;
  v_total_net DECIMAL(10, 2);
  v_total_advances DECIMAL(10, 2);
  v_current DECIMAL(10, 2);
  v_available DECIMAL(10, 2);
  v_should_update BOOLEAN := FALSE;
  v_source_table TEXT := TG_TABLE_NAME;
BEGIN
  -- Determine source and whether we should update
  IF v_source_table = 'salary_advances' THEN
    IF TG_OP = 'INSERT' AND NEW.status = 'approved' THEN
      v_should_update := TRUE; v_employee_id := NEW.employee_id;
    ELSIF TG_OP = 'UPDATE' AND NEW.status = 'approved' AND (OLD.status IS NULL OR OLD.status <> 'approved') THEN
      v_should_update := TRUE; v_employee_id := NEW.employee_id;
    ELSIF TG_OP = 'DELETE' AND OLD.status = 'approved' THEN
      v_should_update := TRUE; v_employee_id := OLD.employee_id;
    END IF;
  ELSIF v_source_table = 'up_to_date_salary' THEN
    -- Always update when up_to_date_salary changes (no status column here)
    v_should_update := TRUE;
    IF TG_OP = 'DELETE' THEN
      v_employee_id := OLD.employee_id;
    ELSE
      v_employee_id := NEW.employee_id;
    END IF;
  ELSE
    -- Fallback: attempt update using available keys
    v_should_update := TRUE;
    IF TG_OP = 'DELETE' THEN
      v_employee_id := COALESCE(OLD.employee_id, NEW.employee_id);
    ELSE
      v_employee_id := COALESCE(NEW.employee_id, OLD.employee_id);
    END IF;
  END IF;

  IF NOT v_should_update OR v_employee_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Get total net salary
  SELECT COALESCE(total_net_salary, 0)
  INTO v_total_net
  FROM up_to_date_salary
  WHERE employee_id = v_employee_id;

  -- Calculate total approved advances
  SELECT COALESCE(SUM(amount), 0)
  INTO v_total_advances
  FROM salary_advances
  WHERE employee_id = v_employee_id
    AND status = 'approved';

  -- Calculate current salary and available advance (30%)
  v_current := v_total_net - v_total_advances;
  v_available := ROUND(v_current * 0.30, 2);

  -- Upsert into up_to_date_salary_with_advances
  INSERT INTO up_to_date_salary_with_advances (
    employee_id,
    total_net_salary,
    total_approved_advances,
    current_salary,
    available_advance_30_percent,
    last_updated,
    created_at
  ) VALUES (
    v_employee_id,
    v_total_net,
    v_total_advances,
    v_current,
    v_available,
    NOW(),
    NOW()
  )
  ON CONFLICT (employee_id)
  DO UPDATE SET
    total_net_salary = EXCLUDED.total_net_salary,
    total_approved_advances = EXCLUDED.total_approved_advances,
    current_salary = EXCLUDED.current_salary,
    available_advance_30_percent = EXCLUDED.available_advance_30_percent,
    last_updated = NOW();

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- No trigger changes required; existing triggers will call this function.
