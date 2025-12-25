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

function daysBetweenCairo(d1: Date, d2: Date) {
  const a = new Date(d1.toLocaleString('en-US', { timeZone: 'Africa/Cairo' }));
  const b = new Date(d2.toLocaleString('en-US', { timeZone: 'Africa/Cairo' }));
  const ms = Math.abs(b.getTime() - a.getTime());
  return Math.floor(ms / (1000 * 60 * 60 * 24));
}

// Get current period range (1-15 or 16-end of month) up to today
function getCurrentPeriodRangeCairo() {
  const now = new Date();
  const cairoNow = new Date(now.toLocaleString('en-US', { timeZone: 'Africa/Cairo' }));
  const year = cairoNow.getFullYear();
  const month = cairoNow.getMonth();
  const day = cairoNow.getDate();

  let start: Date;
  if (day <= 15) {
    start = new Date(Date.UTC(year, month, 1));
  } else {
    start = new Date(Date.UTC(year, month, 16));
  }
  const today = new Date(Date.UTC(year, month, day));

  return {
    startDate: start.toISOString().slice(0, 10),
    endDate: today.toISOString().slice(0, 10),
  };
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
      console.error('[apply-advance-policy] Missing env');
      return err(500, 'Server configuration error');
    }
    const supabase = createClient(supabaseUrl, supabaseKey, { auth: { persistSession: false } });

    // Inputs
    let employeeId: string | null = null;
    if (req.method === 'GET') {
      const url = new URL(req.url);
      employeeId = url.searchParams.get('employee_id');
    } else {
      const body = await req.json().catch(() => ({}));
      employeeId = body.employee_id ?? null;
    }

    if (!employeeId) {
      return err(400, 'Missing employee_id');
    }

    // Fetch up-to-date salary using RPC to bypass RLS
    const { data: salaryInfo, error: salaryErr } = await supabase
      .rpc('get_employee_salary_info', { p_employee_id: employeeId });

    if (salaryErr) {
      console.error('[apply-advance-policy] RPC error:', salaryErr.message);
      return err(500, 'Failed to fetch salary info');
    }

    // RPC returns array with single row
    const salaryData = Array.isArray(salaryInfo) && salaryInfo.length > 0 ? salaryInfo[0] : null;

    const totalEarned = Number(salaryData?.total_net_salary ?? 0);
    const canRequest = salaryData?.can_request_advance ?? false;
    const daysSince = salaryData?.days_since_last_advance ?? 999;

    console.log(`[apply-advance-policy] Salary: ${totalEarned} EGP, Can request: ${canRequest}, Days since: ${daysSince}`);

    if (totalEarned <= 0) {
      return ok({ success: true, created: false, eligible: false, reason: 'no_earnings_yet' });
    }

    if (!canRequest) {
      const remainingDays = 5 - daysSince;
      return ok({
        success: true,
        created: false,
        eligible: false,
        reason: 'waiting_period',
        remaining_days: remainingDays > 0 ? remainingDays : 0,
      });
    }

    // Calculate 30% of total net salary as available advance
    const availableAdvance = Math.round(totalEarned * 0.3 * 100) / 100;

    // ✅ CHANGED: Do NOT create the advance automatically.
    // Just return the eligibility and the calculated amount so the UI can show it.
    // The user must click "Request Advance" to actually create it.

    return ok({
      success: true,
      created: false, // No longer auto-creating
      eligible: true,
      amount: availableAdvance, // Max amount they can request
      totalEarned,
      availableAdvance,
      reason: 'eligible_for_request'
    });
  } catch (e) {
    console.error('[apply-advance-policy] Unhandled error:', e);
    return err(500, 'Internal error');
  }
});
