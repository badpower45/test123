import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || 'https://bbxuyuaemigrqsvsnxkj.supabase.co';
    const supabaseKey = Deno.env.get('SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !supabaseKey) {
      return new Response(
        JSON.stringify({ success: false, error: 'Server configuration error' }),
        { status: 500, headers: corsHeaders }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: { persistSession: false },
    });

    console.log('[auto-calculate-salaries] Starting automatic salary calculation for all active employees');

    // Get all active employees
    const { data: employees, error: empError } = await supabase
      .from('employees')
      .select('id, full_name, is_active')
      .eq('is_active', true);

    if (empError) {
      console.error('[auto-calculate-salaries] Error fetching employees', empError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to fetch employees' }),
        { status: 500, headers: corsHeaders }
      );
    }

    if (!employees || employees.length === 0) {
      console.log('[auto-calculate-salaries] No active employees found');
      return new Response(
        JSON.stringify({ success: true, message: 'No active employees to calculate' }),
        { status: 200, headers: corsHeaders }
      );
    }

    console.log(`[auto-calculate-salaries] Found ${employees.length} active employees`);

    const results = [];

    // Calculate for each employee
    for (const employee of employees) {
      try {
        console.log(`[auto-calculate-salaries] Calculating for ${employee.full_name} (${employee.id})`);
        
        // Call calculate-daily-salary function
        const response = await fetch(`${supabaseUrl}/functions/v1/calculate-daily-salary`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${supabaseKey}`,
          },
          body: JSON.stringify({
            employee_id: employee.id,
            recalculate_period: true, // Recalculate entire current period
          }),
        });

        const data = await response.json();
        
        results.push({
          employee_id: employee.id,
          employee_name: employee.full_name,
          success: data.success ?? false,
          calculations_count: data.calculations?.length ?? 0,
        });

        console.log(`[auto-calculate-salaries] ✅ Completed for ${employee.full_name}: ${data.calculations?.length ?? 0} days calculated`);
      } catch (error) {
        console.error(`[auto-calculate-salaries] ❌ Failed for ${employee.full_name}`, error);
        results.push({
          employee_id: employee.id,
          employee_name: employee.full_name,
          success: false,
          error: error.message,
        });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: `Calculated salaries for ${employees.length} employees`,
        results: results,
      }),
      { status: 200, headers: corsHeaders }
    );
  } catch (error) {
    console.error('[auto-calculate-salaries] Unexpected error', error);
    return new Response(
      JSON.stringify({ success: false, error: 'Internal server error' }),
      { status: 500, headers: corsHeaders }
    );
  }
});
