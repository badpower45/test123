-- Fix shift times for employee empp and delete old advances
UPDATE employees 
SET shift_start_time = '20:00', 
    shift_end_time = '23:00',
    updated_at = NOW()
WHERE id = 'empp';

-- Delete the old 3744 EGP advance
DELETE FROM salary_advances 
WHERE employee_id = 'empp' 
  AND amount = 3744;

-- Show current employee data
SELECT id, full_name, shift_start_time, shift_end_time, hourly_rate 
FROM employees 
WHERE id = 'empp';

-- Show remaining advances
SELECT id, employee_id, amount, status, approved_at, created_at 
FROM salary_advances 
WHERE employee_id = 'empp' 
ORDER BY created_at DESC;
