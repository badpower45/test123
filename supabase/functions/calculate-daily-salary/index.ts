import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

function getCairoDateString(date: Date): string {
  const cairoDate = new Date(date.toLocaleString('en-US', { timeZone: 'Africa/Cairo' }));
  return cairoDate.toISOString().split('T')[0];
}

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
    // Period: 1st to 15th
    startDate = `${currentYear}-${String(currentMonth + 1).padStart(2, '0')}-01`;
    endDate = `${currentYear}-${String(currentMonth + 1).padStart(2, '0')}-15`;
  } else {
    // Period: 16th to end of month
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
    const { employee_id, date, recalculate_period } = body;

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

    // Get employee hourly rate
    const { data: employee, error: empError } = await supabase
      .from('employees')
      .select('id, hourly_rate')
      .eq('id', employee_id)
      .maybeSingle();

    if (empError || !employee) {
      console.error('[calculate-daily-salary] Employee not found', empError);
      return new Response(
        JSON.stringify({ success: false, error: 'Employee not found' }),
        { status: 404, headers: corsHeaders }
      );
    }

    const hourlyRate = Number(employee.hourly_rate ?? 60);
    const perMinuteRate = hourlyRate / 60;

    // Determine which dates to calculate
    let datesToCalculate: string[] = [];
    
    if (date) {
      // Calculate specific date
      datesToCalculate = [date];
    } else if (recalculate_period) {
      // Calculate entire current period
      const { startDate, endDate } = getCurrentPeriodRange();
      const start = new Date(startDate);
      const end = new Date(endDate);
      
      for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
        datesToCalculate.push(getCairoDateString(d));
      }
    } else {
      // Calculate today only
      datesToCalculate = [getCairoDateString(getCairoNow())];
    }

    console.log(`[calculate-daily-salary] Calculating for ${datesToCalculate.length} days`);

    const results = [];

    for (const calculationDate of datesToCalculate) {
      // 1. Get total work hours for this day
      const { data: attendanceRecords, error: attError } = await supabase
        .from('attendance')
        .select('work_hours, total_hours')
        .eq('employee_id', employee_id)
        .eq('date', calculationDate);

      if (attError) {
        console.error(`[calculate-daily-salary] Error fetching attendance for ${calculationDate}`, attError);
        continue;
      }

      let totalWorkHours = 0;
      if (attendanceRecords && attendanceRecords.length > 0) {
        for (const record of attendanceRecords) {
          const hours = Number(record.work_hours ?? record.total_hours ?? 0);
          totalWorkHours += hours;
        }
      }

      // 2. Get false pulses count for this day
      const { data: pulseRecords, error: pulseError } = await supabase
        .from('pulses')
        .select('id, is_within_geofence')
        .eq('employee_id', employee_id)
        .gte('timestamp', `${calculationDate}T00:00:00.000Z`)
        .lte('timestamp', `${calculationDate}T23:59:59.999Z`);

      if (pulseError) {
        console.error(`[calculate-daily-salary] Error fetching pulses for ${calculationDate}`, pulseError);
      }

      let falsePulsesCount = 0;
      if (pulseRecords && pulseRecords.length > 0) {
        falsePulsesCount = pulseRecords.filter(p => p.is_within_geofence === false).length;
      }

      // 3. Calculate salary
      const grossSalary = totalWorkHours * hourlyRate;
      const pulseDeduction = falsePulsesCount * 5 * perMinuteRate; // 5 minutes per false pulse
      const totalDeductions = pulseDeduction;
      const netSalary = Math.max(0, grossSalary - totalDeductions);

      // 4. Upsert into daily_salary_calculations
      const { data: calculation, error: calcError } = await supabase
        .from('daily_salary_calculations')
        .upsert({
          employee_id: employee_id,
          calculation_date: calculationDate,
          total_work_hours: totalWorkHours,
          hourly_rate: hourlyRate,
          gross_salary: grossSalary,
          false_pulses_count: falsePulsesCount,
          pulse_deduction_amount: pulseDeduction,
          other_deductions: 0,
          total_deductions: totalDeductions,
          net_salary: netSalary,
          updated_at: new Date().toISOString(),
        }, {
          onConflict: 'employee_id,calculation_date',
        })
        .select()
        .maybeSingle();

      if (calcError) {
        console.error(`[calculate-daily-salary] Error upserting calculation for ${calculationDate}`, calcError);
        continue;
      }

      results.push({
        date: calculationDate,
        total_work_hours: totalWorkHours,
        hourly_rate: hourlyRate,
        gross_salary: grossSalary,
        false_pulses_count: falsePulsesCount,
        pulse_deduction: pulseDeduction,
        net_salary: netSalary,
      });

      console.log(`[calculate-daily-salary] ${calculationDate}: ${totalWorkHours}h * ${hourlyRate} = ${grossSalary} - ${pulseDeduction} = ${netSalary} (${falsePulsesCount} false pulses)`);
    }

    // Calculate period totals
    let periodGross = 0;
    let periodDeductions = 0;
    let periodNet = 0;
    
    for (const r of results) {
      periodGross += r.gross_salary;
      periodDeductions += r.pulse_deduction;
      periodNet += r.net_salary;
    }

    return new Response(
      JSON.stringify({
        success: true,
        employee_id: employee_id,
        calculations: results,
        period_totals: {
          gross_salary: periodGross,
          total_deductions: periodDeductions,
          net_salary: periodNet,
        },
      }),
      { status: 200, headers: corsHeaders }
    );
  } catch (error) {
    console.error('[calculate-daily-salary] Unexpected error', error);
    return new Response(
      JSON.stringify({ success: false, error: 'Internal server error' }),
      { status: 500, headers: corsHeaders }
    );
  }
});
