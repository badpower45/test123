// @ts-nocheck
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          persistSession: false,
        },
      }
    );

    // Optional: Verify user is authenticated (but not required with SERVICE_ROLE_KEY)
    // We can skip this check since SERVICE_ROLE_KEY bypasses RLS

    const url = new URL(req.url);
    const employeeId = url.searchParams.get('employee_id');

    if (!employeeId) {
      return new Response(
        JSON.stringify({ error: 'employee_id is required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      );
    }

    console.log(`🗑️ [Delete Employee] Starting deletion for employee: ${employeeId}`);

    // Verify employee exists
    const { data: existingEmployee, error: employeeError } = await supabaseClient
      .from('employees')
      .select('id, full_name')
      .eq('id', employeeId)
      .maybeSingle();

    if (employeeError) {
      console.error('❌ Error fetching employee:', employeeError);
      return new Response(
        JSON.stringify({ error: 'Failed to fetch employee' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      );
    }

    if (!existingEmployee) {
      return new Response(
        JSON.stringify({ error: 'الموظف غير موجود' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 }
      );
    }

    console.log(`✅ [Delete Employee] Found employee: ${existingEmployee.full_name}`);

    // Delete all related records in order
    const tablesToDelete = [
      { table: 'pulses', column: 'employee_id' },
      { table: 'breaks', column: 'employee_id' },
      { table: 'attendance', column: 'employee_id' },
      { table: 'device_sessions', column: 'employee_id' },
      { table: 'notifications', column: 'recipient_id' },
      { table: 'salary_calculations', column: 'employee_id' },
      { table: 'attendance_requests', column: 'employee_id' },
      { table: 'leave_requests', column: 'employee_id' },
      { table: 'salary_advances', column: 'employee_id' },
      { table: 'deductions', column: 'employee_id' },
      { table: 'absences', column: 'employee_id' }, // Add absences table
      { table: 'absence_notifications', column: 'employee_id' },
      { table: 'branch_managers', column: 'employee_id' },
    ];

    // Delete from each table
    for (const { table, column } of tablesToDelete) {
      try {
        const { error: deleteError } = await supabaseClient
          .from(table)
          .delete()
          .eq(column, employeeId);
        
        if (deleteError) {
          console.warn(`⚠️ [Delete Employee] Error deleting from ${table}:`, deleteError);
          // Continue with other tables even if one fails
        } else {
          console.log(`✅ [Delete Employee] Deleted from ${table}`);
        }
      } catch (e) {
        console.warn(`⚠️ [Delete Employee] Exception deleting from ${table}:`, e);
      }
    }

    // Unlink manager from branches if this employee was a manager
    try {
      const { error: updateError } = await supabaseClient
        .from('branches')
        .update({ manager_id: null, updated_at: new Date().toISOString() })
        .eq('manager_id', employeeId);
      
      if (updateError) {
        console.warn('⚠️ [Delete Employee] Error unlinking from branches:', updateError);
      } else {
        console.log('✅ [Delete Employee] Unlinked from branches');
      }
    } catch (e) {
      console.warn('⚠️ [Delete Employee] Exception unlinking from branches:', e);
    }

    // Finally, delete the employee
    const { error: deleteEmployeeError } = await supabaseClient
      .from('employees')
      .delete()
      .eq('id', employeeId);

    if (deleteEmployeeError) {
      console.error('❌ [Delete Employee] Error deleting employee:', deleteEmployeeError);
      return new Response(
        JSON.stringify({ 
          error: 'فشل حذف الموظف', 
          message: deleteEmployeeError.message 
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      );
    }

    console.log(`✅ [Delete Employee] Successfully deleted employee: ${employeeId}`);

    return new Response(
      JSON.stringify({
        success: true,
        message: 'تم حذف الموظف وجميع سجلاته المرتبطة بنجاح',
        employeeId,
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200 
      }
    );

  } catch (error) {
    console.error('❌ [Delete Employee] Unexpected error:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error', 
        message: error.message 
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500 
      }
    );
  }
});

