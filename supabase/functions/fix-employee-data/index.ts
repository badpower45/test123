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

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ success: false, error: 'Method not allowed' }),
      { status: 405, headers: corsHeaders }
    );
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

    // Fix shift times for employee empp
    const { error: updateError } = await supabase
      .from('employees')
      .update({
        shift_start_time: '20:00',
        shift_end_time: '23:00',
        updated_at: new Date().toISOString(),
      })
      .eq('id', 'empp');

    if (updateError) {
      console.error('[fix-employee-data] Failed to update shift times', updateError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to update shift times' }),
        { status: 500, headers: corsHeaders }
      );
    }

    // Delete old 3744 EGP advance
    const { error: deleteError } = await supabase
      .from('salary_advances')
      .delete()
      .eq('employee_id', 'empp')
      .eq('amount', 3744);

    if (deleteError) {
      console.warn('[fix-employee-data] Failed to delete old advance', deleteError);
    }

    // Get current employee data
    const { data: employee, error: employeeError } = await supabase
      .from('employees')
      .select('id, full_name, shift_start_time, shift_end_time, hourly_rate')
      .eq('id', 'empp')
      .maybeSingle();

    // Get remaining advances
    const { data: advances, error: advancesError } = await supabase
      .from('salary_advances')
      .select('id, employee_id, amount, status, approved_at, created_at')
      .eq('employee_id', 'empp')
      .order('created_at', { ascending: false });

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Employee data fixed successfully',
        employee: employee ?? null,
        advances: advances ?? [],
      }),
      { status: 200, headers: corsHeaders }
    );
  } catch (error) {
    console.error('[fix-employee-data] Unexpected error', error);
    return new Response(
      JSON.stringify({ success: false, error: 'Internal server error' }),
      { status: 500, headers: corsHeaders }
    );
  }
});
