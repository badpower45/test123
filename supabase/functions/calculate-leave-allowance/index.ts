import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

function getCairoNow(): Date {
  const now = new Date();
  // Convert to Cairo time (UTC+2)
  const cairoTime = new Date(now.getTime() + (2 * 60 * 60 * 1000));
  return cairoTime;
}

function getCurrentPayrollPeriod(baseDate: Date) {
  const day = baseDate.getDate();
  const month = baseDate.getMonth() + 1;
  const year = baseDate.getFullYear();

  let periodStart: string;
  let periodEnd: string;

  if (day <= 15) {
    // Current period: 1st to 15th
    periodStart = `${year}-${String(month).padStart(2, '0')}-01`;
    periodEnd = `${year}-${String(month).padStart(2, '0')}-15`;
  } else {
    // Current period: 16th to end of month, then 1-15 of next month
    periodStart = `${year}-${String(month).padStart(2, '0')}-16`;
    
    // Get last day of current month
    const lastDayOfMonth = new Date(year, month, 0).getDate();
    periodEnd = `${year}-${String(month).padStart(2, '0')}-${lastDayOfMonth}`;
  }

  return { periodStart, periodEnd };
}

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
    const body = await req.json();
    const { employee_id } = body;

    if (!employee_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'employee_id is required' }),
        { status: 400, headers: corsHeaders }
      );
    }

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

    // Get current date and determine which payroll period we're in
    const now = getCairoNow();
    const { periodStart, periodEnd } = getCurrentPayrollPeriod(now);

    console.log(`[calculate-leave-allowance] Employee: ${employee_id}, Payroll Period: ${periodStart} to ${periodEnd}`);

    // Step 1: Get employee's hourly rate
    const { data: employee, error: empError } = await supabase
      .from('employees')
      .select('id, hourly_rate, leave_allowance')
      .eq('id', employee_id)
      .maybeSingle();

    if (empError || !employee) {
      console.error('[calculate-leave-allowance] Employee not found', empError);
      return new Response(
        JSON.stringify({ success: false, error: 'Employee not found' }),
        { status: 404, headers: corsHeaders }
      );
    }

    const hourlyRate = Number(employee.hourly_rate ?? 100);
    const persistedLeaveAllowance = Number(employee.leave_allowance ?? 100);

    // Step 2: Count leave requests that fall within the payroll period
    // Since period 2 (16-end + 1-15 next month) spans two months, 
    // we need to check if any leaves overlap with the period
    const { data: leaves, error: leavesError } = await supabase
      .from('leave_requests')
      .select('id, start_date, end_date, status')
      .eq('employee_id', employee_id)
      .eq('status', 'approved');

    if (leavesError) {
      console.error('[calculate-leave-allowance] Error fetching leaves', leavesError);
      return new Response(
        JSON.stringify({ success: false, error: 'Error fetching leaves' }),
        { status: 500, headers: corsHeaders }
      );
    }

    // Filter leaves that overlap with the current payroll period
    const periodStartDate = new Date(periodStart + 'T00:00:00.000Z');
    const periodEndDate = new Date(periodEnd + 'T23:59:59.999Z');

    const overlappingLeaves = (leaves ?? []).filter((leave) => {
      const leaveStart = new Date(leave.start_date);
      const leaveEnd = new Date(leave.end_date);
      
      // Check if leave overlaps with payroll period
      return leaveStart <= periodEndDate && leaveEnd >= periodStartDate;
    });

    const leaveCount = overlappingLeaves.length;
    console.log(`[calculate-leave-allowance] Overlapping leave requests count: ${leaveCount}`);

    // Step 3: Decision logic
    let leaveAllowance = persistedLeaveAllowance; // default to persisted value

    if (leaveCount > 2) {
      // More than 2 leave requests → no allowance
      leaveAllowance = 0;
      console.log('[calculate-leave-allowance] More than 2 leaves, setting allowance to 0');
    } else if (leaveCount === 0) {
      // No leaves → calculate based on last work day's hours within or before the period
      const { data: lastWorkDay, error: workDayError } = await supabase
        .from('attendance')
        .select('date, total_hours, work_hours')
        .eq('employee_id', employee_id)
        .lte('date', periodEnd) // on or before period end
        .order('date', { ascending: false })
        .limit(1)
        .maybeSingle();

      if (!workDayError && lastWorkDay) {
        const lastWorkHours = Number(lastWorkDay.total_hours ?? lastWorkDay.work_hours ?? 8);
        leaveAllowance = lastWorkHours * hourlyRate;
        console.log(`[calculate-leave-allowance] No leaves, calculated from last work day (${lastWorkDay.date}): ${lastWorkHours} hours × ${hourlyRate} = ${leaveAllowance}`);
      } else {
        // No work records, use default or persisted
        console.log('[calculate-leave-allowance] No work records found, using persisted or default');
        leaveAllowance = persistedLeaveAllowance;
      }
    } else {
      // 1 or 2 leaves → use persisted value
      console.log('[calculate-leave-allowance] 1-2 leaves, using persisted allowance');
      leaveAllowance = persistedLeaveAllowance;
    }

    console.log(`[calculate-leave-allowance] Final allowance: ${leaveAllowance}`);

    // Determine period name
    const day = now.getDate();
    const periodName = day <= 15 ? 'Period 1 (1-15)' : 'Period 2 (16-end)';

    return new Response(
      JSON.stringify({
        success: true,
        employee_id,
        period_start: periodStart,
        period_end: periodEnd,
        period_name: periodName,
        leave_request_count: leaveCount,
        leave_allowance: leaveAllowance,
        calculated_at: new Date().toISOString(),
      }),
      { status: 200, headers: corsHeaders }
    );
  } catch (error) {
    console.error('[calculate-leave-allowance] Error:', error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: corsHeaders }
    );
  }
});
