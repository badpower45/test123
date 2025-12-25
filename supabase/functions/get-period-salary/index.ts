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

function getCurrentPeriodRange(): { startDate: string; endDate: string } {
  const now = getCairoNow();
  const currentDay = now.getDate();
  const currentMonth = now.getMonth();
  const currentYear = now.getFullYear();

  let startDate: string;
  let endDate: string;

  if (currentDay <= 15) {
    startDate = `${currentYear}-${String(currentMonth + 1).padStart(2, '0')}-01`;
    endDate = `${currentYear}-${String(currentMonth + 1).padStart(2, '0')}-15`;
  } else {
    startDate = `${currentYear}-${String(currentMonth + 1).padStart(2, '0')}-16`;
    const lastDay = new Date(currentYear, currentMonth + 1, 0).getDate();
    endDate = `${currentYear}-${String(currentMonth + 1).padStart(2, '0')}-${lastDay}`;
  }

  return { startDate, endDate };
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
    const { employee_id, start_date, end_date } = body;

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

    // Determine date range
    let dateRange = { startDate: start_date, endDate: end_date };
    if (!start_date || !end_date) {
      dateRange = getCurrentPeriodRange();
    }

    console.log(`[get-period-salary] Fetching for ${employee_id} from ${dateRange.startDate} to ${dateRange.endDate}`);

    // Get all daily calculations for the period
    const { data: calculations, error: calcError } = await supabase
      .from('daily_salary_calculations')
      .select('*')
      .eq('employee_id', employee_id)
      .gte('calculation_date', dateRange.startDate)
      .lte('calculation_date', dateRange.endDate)
      .order('calculation_date', { ascending: true });

    if (calcError) {
      console.error('[get-period-salary] Error fetching calculations', calcError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to fetch salary calculations' }),
        { status: 500, headers: corsHeaders }
      );
    }

    // Calculate totals
    let totalWorkHours = 0;
    let totalGrossSalary = 0;
    let totalFalsePulses = 0;
    let totalPulseDeductions = 0;
    let totalOtherDeductions = 0;
    let totalDeductions = 0;
    let totalNetSalary = 0;

    const dailyBreakdown = [];

    if (calculations && calculations.length > 0) {
      for (const calc of calculations) {
        totalWorkHours += Number(calc.total_work_hours ?? 0);
        totalGrossSalary += Number(calc.gross_salary ?? 0);
        totalFalsePulses += Number(calc.false_pulses_count ?? 0);
        totalPulseDeductions += Number(calc.pulse_deduction_amount ?? 0);
        totalOtherDeductions += Number(calc.other_deductions ?? 0);
        totalDeductions += Number(calc.total_deductions ?? 0);
        totalNetSalary += Number(calc.net_salary ?? 0);

        dailyBreakdown.push({
          date: calc.calculation_date,
          work_hours: Number(calc.total_work_hours ?? 0),
          gross_salary: Number(calc.gross_salary ?? 0),
          false_pulses: Number(calc.false_pulses_count ?? 0),
          deductions: Number(calc.total_deductions ?? 0),
          net_salary: Number(calc.net_salary ?? 0),
        });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        employee_id: employee_id,
        period: {
          start_date: dateRange.startDate,
          end_date: dateRange.endDate,
        },
        totals: {
          work_hours: totalWorkHours,
          gross_salary: totalGrossSalary,
          false_pulses: totalFalsePulses,
          pulse_deductions: totalPulseDeductions,
          other_deductions: totalOtherDeductions,
          total_deductions: totalDeductions,
          net_salary: totalNetSalary,
        },
        daily_breakdown: dailyBreakdown,
      }),
      { status: 200, headers: corsHeaders }
    );
  } catch (error) {
    console.error('[get-period-salary] Unexpected error', error);
    return new Response(
      JSON.stringify({ success: false, error: 'Internal server error' }),
      { status: 500, headers: corsHeaders }
    );
  }
});
