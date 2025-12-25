// @ts-nocheck
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

declare const Deno: { env: { get(key: string): string | undefined } };

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

function ok(body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status: 200, headers: corsHeaders });
}

function err(status: number, message: string, extra: Record<string, unknown> = {}) {
  return new Response(JSON.stringify({ success: false, message, ...extra }), {
    status,
    headers: corsHeaders,
  });
}

// Determine current period window within the month
// Period A: 1..15, Period B: 16..end-of-month
function getCurrentPeriodRangeTodayCairo() {
  const now = new Date();
  const cairoNow = new Date(now.toLocaleString('en-US', { timeZone: 'Africa/Cairo' }));
  const year = cairoNow.getFullYear();
  const month = cairoNow.getMonth(); // 0-based
  const day = cairoNow.getDate();

  let start: Date;
  let end: Date; // inclusive end for reporting (today)

  if (day <= 15) {
    start = new Date(Date.UTC(year, month, 1));
  } else {
    start = new Date(Date.UTC(year, month, 16));
  }

  const today = new Date(Date.UTC(year, month, day));
  end = today; // period-to-date ends today

  const fmt = (d: Date) => d.toISOString().slice(0, 10);
  return { startDate: fmt(start), endDate: fmt(end) };
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  if (req.method !== 'GET' && req.method !== 'POST') {
    return err(405, 'Method not allowed');
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseKey = Deno.env.get('SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !supabaseKey) {
      console.error('[employee-period-earnings] Missing env');
      return err(500, 'Server configuration error');
    }
    const supabase = createClient(supabaseUrl, supabaseKey, { auth: { persistSession: false } });

    // Inputs
    let employeeId: string | null = null;
    let startDate: string | null = null; // YYYY-MM-DD optional override
    let endDate: string | null = null;   // YYYY-MM-DD optional override
    if (req.method === 'GET') {
      const url = new URL(req.url);
      employeeId = url.searchParams.get('employee_id');
      startDate = url.searchParams.get('start_date');
      endDate = url.searchParams.get('end_date');
    } else {
      const body = await req.json().catch(() => ({}));
      employeeId = body.employee_id ?? null;
      startDate = body.start_date ?? null;
      endDate = body.end_date ?? null;
    }

    if (!employeeId) {
      return err(400, 'Missing employee_id');
    }

    const defaultRange = getCurrentPeriodRangeTodayCairo();
    const periodStart = startDate ?? defaultRange.startDate;
    const periodEnd = endDate ?? defaultRange.endDate;

    // ✅ STEP 1: Try to get from up_to_date_salary_with_advances first
    const { data: currentSalary, error: currentErr } = await supabase
      .from('up_to_date_salary_with_advances')
      .select('current_salary, available_advance_30_percent, total_net_salary, total_approved_advances')
      .eq('employee_id', employeeId)
      .maybeSingle();

    if (currentErr) {
      console.error('[employee-period-earnings] up_to_date_salary_with_advances error:', currentErr.message);
    }

    let salary = 0;
    let totalApprovedAdvances = 0;

    // Use current salary (after deducting advances)
    if (currentSalary && currentSalary.current_salary) {
      salary = Number(currentSalary.current_salary ?? 0);
      totalApprovedAdvances = Number(currentSalary.total_approved_advances ?? 0);
      console.log(`[employee-period-earnings] Using view data: ${salary.toFixed(2)} EGP (Net: ${currentSalary.total_net_salary}, Advances: ${totalApprovedAdvances})`);
    } else {
      // ✅ STEP 2: Fallback - Calculate from daily_attendance_summary (for trial employees or missing data)
      console.log('[employee-period-earnings] No salary in view, calculating from daily_attendance_summary...');

      const { data: attendanceData, error: attendanceErr } = await supabase
        .from('daily_attendance_summary')
        .select('daily_salary')
        .eq('employee_id', employeeId)
        .gte('attendance_date', periodStart)
        .lte('attendance_date', periodEnd);

      if (attendanceErr) {
        console.error('[employee-period-earnings] daily_attendance_summary error:', attendanceErr.message);
      }

      if (attendanceData && attendanceData.length > 0) {
        salary = attendanceData.reduce((sum, record) => sum + Number(record.daily_salary ?? 0), 0);
        console.log(`[employee-period-earnings] Calculated from attendance: ${salary.toFixed(2)} EGP (${attendanceData.length} days)`);
      } else {
        console.log('[employee-period-earnings] No attendance data found, returning 0');
      }

      // Get approved advances for this period
      const { data: advancesData, error: advancesErr } = await supabase
        .from('salary_advances')
        .select('amount')
        .eq('employee_id', employeeId)
        .eq('status', 'approved')
        .gte('approved_at', periodStart)
        .lte('approved_at', periodEnd);

      if (!advancesErr && advancesData) {
        totalApprovedAdvances = advancesData.reduce((sum, adv) => sum + Number(adv.amount ?? 0), 0);
        console.log(`[employee-period-earnings] Approved advances: ${totalApprovedAdvances.toFixed(2)} EGP`);
      }
    }

    console.log(`[employee-period-earnings] Final: salary=${salary.toFixed(2)}, advances=${totalApprovedAdvances.toFixed(2)}, net=${(salary - totalApprovedAdvances).toFixed(2)}`);

    // Calculate net salary (gross - advances)
    const netSalary = salary - totalApprovedAdvances;

    return ok({
      success: true,
      employeeId,
      period: { start: periodStart, end: periodEnd },
      totals: {
        salary: Math.round(salary * 100) / 100, // Gross salary
        leaveAllowance: 0,
        advances: Math.round(totalApprovedAdvances * 100) / 100,
        deductions: 0,
        gross: Math.round(salary * 100) / 100,
        net: Math.round(netSalary * 100) / 100, // Net = Gross - Advances
      },
    });
  } catch (e) {
    console.error('[employee-period-earnings] Unhandled error:', e);
    return err(500, 'Internal error');
  }
});
