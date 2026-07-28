-- Add request_date column to salary_advances to avoid runtime errors when accessing NEW.request_date

ALTER TABLE salary_advances
ADD COLUMN IF NOT EXISTS request_date TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Backfill existing rows where request_date is NULL to created_at
UPDATE salary_advances
SET request_date = COALESCE(request_date, created_at);
