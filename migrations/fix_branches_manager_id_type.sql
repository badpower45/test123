-- Fix branches.manager_id to reference employees (text) instead of users (uuid)

-- First, clear existing manager_id values (they were invalid UUIDs anyway)
UPDATE branches SET manager_id = NULL;

-- Drop the old foreign key constraint if it exists
ALTER TABLE branches DROP CONSTRAINT IF EXISTS branches_manager_id_users_id_fk;

-- Change column type from uuid to text
ALTER TABLE branches 
ALTER COLUMN manager_id TYPE TEXT USING manager_id::TEXT;

-- Add new foreign key constraint to employees table
ALTER TABLE branches 
ADD CONSTRAINT branches_manager_id_employees_id_fk 
FOREIGN KEY (manager_id) REFERENCES employees(id) ON DELETE SET NULL;

COMMENT ON COLUMN branches.manager_id IS 'Employee ID of the branch manager (references employees.id)';
