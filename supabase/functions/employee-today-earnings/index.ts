// @ts-nocheck
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

declare const Deno: {
  env: { get(key: string): string | undefined };
};

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

function getCairoDateRange(date?: string) {
  // Create date range [startOfDay, endOfDay) in Cairo timezone
  const base = date ? new Date(date) : new Date();
  const cairoNow = new Date(base.toLocaleString('en-US', { timeZone: 'Africa/Cairo' }));
  const start = new Date(cairoNow);
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return { start, end };
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
      console.error('[employee-today-earnings] Missing env vars');
      return err(500, 'Server configuration error');
    }

    const supabase = createClient(supabaseUrl, supabaseKey, { auth: { persistSession: false } });

    // Input: employee_id (required), date (optional YYYY-MM-DD)
    let employeeId: string | null = null;
    let dateParam: string | null = null;
    let persist: boolean = false;
    if (req.method === 'GET') {
      const url = new URL(req.url);
      employeeId = url.searchParams.get('employee_id');
      dateParam = url.searchParams.get('date');
      persist = (url.searchParams.get('persist') ?? '').toLowerCase() === 'true';
    } else {
      const body = await req.json().catch(() => ({}));
      employeeId = body.employee_id ?? null;
      dateParam = body.date ?? null;
      persist = !!body.persist;
    }

    if (!employeeId) {
      return err(400, 'Missing employee_id');
    }

    const { start, end } = getCairoDateRange(dateParam ?? undefined);
    const startIso = start.toISOString();
    const endIso = end.toISOString();

    // Employee hourly rate
    const { data: emp, error: empErr } = await supabase
      .from('employees')
      .select('hourly_rate, full_name')
      .eq('id', employeeId)
      .maybeSingle();
    if (empErr) {
      console.error('[employee-today-earnings] employees error:', empErr.message);
      return err(500, 'Failed to load employee');
    }
    const hourlyRate = Number(emp?.hourly_rate ?? 0) || 0;

    // All today attendances (check_in_time in [start, end))
    const { data: attendances, error: attErr } = await supabase
      .from('attendance')
      .select('id, check_in_time, check_out_time')
      .eq('employee_id', employeeId)
      .gte('check_in_time', startIso)
      .lt('check_in_time', endIso)
      .order('check_in_time', { ascending: true });
    if (attErr) {
      console.error('[employee-today-earnings] attendance error:', attErr.message);
      return err(500, 'Failed to load attendance');
    }

    let workedMinutesTotal = 0;
    let penaltyMinutesTotal = 0;
    let falseCountTotal = 0;

    let firstCheckIn: Date | null = null;
    let lastCheckOut: Date | null = null;
    for (const a of attendances ?? []) {
      const inAt = new Date(a.check_in_time);
      const outAt = a.check_out_time ? new Date(a.check_out_time) : new Date();
      const workedMinutes = Math.max(0, Math.floor((outAt.getTime() - inAt.getTime()) / 60000));
      if (!firstCheckIn || inAt.getTime() < firstCheckIn.getTime()) firstCheckIn = inAt;
      if (a.check_out_time && (!lastCheckOut || outAt.getTime() > lastCheckOut.getTime())) lastCheckOut = outAt;

      // Count false pulses within the attendance window
      const { data: falsePulses, error: pulseErr } = await supabase
        .from('pulses')
        .select('id')
        .eq('employee_id', employeeId)
        .eq('inside_geofence', false)
        .gte('timestamp', inAt.toISOString())
        .lt('timestamp', outAt.toISOString());
      if (pulseErr) {
        console.error('[employee-today-earnings] pulses error:', pulseErr.message);
        return err(500, 'Failed to load pulses');
      }
      const falseCount = (falsePulses ?? []).length;
      const penaltyMinutes = Math.min(workedMinutes, falseCount * 5);

      workedMinutesTotal += workedMinutes;
      penaltyMinutesTotal += penaltyMinutes;
      falseCountTotal += falseCount;
    }

    const gross = hourlyRate * (workedMinutesTotal / 60);
    const deduction = hourlyRate * (penaltyMinutesTotal / 60);
    const net = Math.max(0, gross - deduction);

    // Optionally persist into daily_attendance_summary
    if (persist) {
      try {
        const attendanceDate = startIso.substring(0, 10);
        // Cairo-local HH:MM for check-in/out
        const fmt = (d: Date | null) => {
          if (!d) return null;
          const cairo = new Date(d.toLocaleString('en-US', { timeZone: 'Africa/Cairo' }));
          const hh = String(cairo.getHours()).padStart(2, '0');
          const mm = String(cairo.getMinutes()).padStart(2, '0');
          return `${hh}:${mm}`;
        };

        const totalHours = Math.round((workedMinutesTotal / 60) * 100) / 100;

        const upsertPayload: Record<string, unknown> = {
          employee_id: employeeId,
          attendance_date: attendanceDate,
          check_in_time: fmt(firstCheckIn),
          check_out_time: fmt(lastCheckOut),
          total_hours: totalHours,
          hourly_rate: hourlyRate,
          daily_salary: net,
          is_absent: false,
          is_on_leave: false,
        };

        const { error: upsertErr } = await supabase
          .from('daily_attendance_summary')
          .upsert(upsertPayload, { onConflict: 'employee_id,attendance_date' });
        if (upsertErr) {
          console.error('[employee-today-earnings] upsert daily_attendance_summary error:', upsertErr.message);
        }
      } catch (perr) {
        console.error('[employee-today-earnings] persist handling error:', perr);
      }
    }

    return ok({
      success: true,
      employeeId,
      employeeName: emp?.full_name ?? null,
      date: startIso.substring(0, 10),
      workedMinutes: workedMinutesTotal,
      penaltyMinutes: penaltyMinutesTotal,
      falseCount: falseCountTotal,
      hourlyRate,
      gross,
      deduction,
      net,
    });
  } catch (e) {
    console.error('[employee-today-earnings] Unhandled error:', e);
    return err(500, 'Internal error');
  }
});
