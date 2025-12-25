-- Function to delete branch and unlink employees
CREATE OR REPLACE FUNCTION delete_branch_with_unlink(branch_id_to_delete UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  branch_name TEXT;
  employees_count INTEGER;
  result JSON;
BEGIN
  -- Get branch name
  SELECT name INTO branch_name
  FROM branches
  WHERE id = branch_id_to_delete;
  
  IF branch_name IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'الفرع غير موجود'
    );
  END IF;
  
  -- Count employees in this branch
  SELECT COUNT(*) INTO employees_count
  FROM employees
  WHERE branch_id = branch_id_to_delete;
  
  -- Use transaction to ensure atomicity
  BEGIN
    -- Delete related BSSIDs first
    DELETE FROM branch_bssids WHERE branch_id = branch_id_to_delete;
    
    -- Unlink employees from this branch (set branchId and branch name to null)
    UPDATE employees
    SET branch_id = NULL, branch = NULL, updated_at = NOW()
    WHERE branch_id = branch_id_to_delete;
    
    -- Unlink any managers directly linked via branch_managers table
    DELETE FROM branch_managers WHERE branch_id = branch_id_to_delete;
    
    -- Finally, delete the branch itself
    DELETE FROM branches WHERE id = branch_id_to_delete;
    
    result := json_build_object(
      'success', true,
      'message', 'تم حذف الفرع بنجاح، وتم فك ارتباط ' || employees_count || ' موظف من هذا الفرع.',
      'branch_id', branch_id_to_delete,
      'branch_name', branch_name,
      'employees_unlinked', employees_count
    );
    
    RETURN result;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN json_build_object(
        'success', false,
        'error', 'خطأ في حذف الفرع: ' || SQLERRM
      );
  END;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION delete_branch_with_unlink(UUID) TO authenticated;

COMMENT ON FUNCTION delete_branch_with_unlink(UUID) IS 'حذف الفرع وفك ارتباط الموظفين تلقائياً';

