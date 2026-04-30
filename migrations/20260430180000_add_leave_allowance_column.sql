-- Add leave_allowance column to employees if not exists
ALTER TABLE public.employees
ADD COLUMN IF NOT EXISTS leave_allowance numeric DEFAULT 100;

-- Update NULL values
UPDATE public.employees
SET leave_allowance = 100
WHERE leave_allowance IS NULL;

-- Add comment
COMMENT ON COLUMN public.employees.leave_allowance IS 'Leave allowance amount per period (default: 100)';
