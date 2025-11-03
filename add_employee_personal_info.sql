-- Add personal information fields to employees table
-- Run this script carefully to avoid breaking the server

-- Add address field
ALTER TABLE employees 
ADD COLUMN IF NOT EXISTS address TEXT;

-- Add birth_date field  
ALTER TABLE employees
ADD COLUMN IF NOT EXISTS birth_date DATE;

-- Add email field
ALTER TABLE employees
ADD COLUMN IF NOT EXISTS email TEXT;

-- Add phone field
ALTER TABLE employees
ADD COLUMN IF NOT EXISTS phone TEXT;

-- Verify the changes
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'employees' 
AND column_name IN ('address', 'birth_date', 'email', 'phone');
