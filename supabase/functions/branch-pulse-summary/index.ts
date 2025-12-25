// @ts-nocheck
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

declare const Deno: {
  env: {
    get(key: string): string | undefined;
  };
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json'
};

type BranchEmployeeRow = {
  id: string;
  full_name: string;
  role: string | null;
  branch_id: string | null;
  branch: string | null;
  is_active: boolean | null;
  hourly_rate: number | string | null;
};

type PulseRow = {
  employee_id: string;
  created_at: string;
  is_within_geofence: boolean | null;
};

type AttendanceRow = {
  employee_id: string;
  check_in_time: string | null;
};

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function getCairoNow(): Date {
  const now = new Date();
  // Convert to Cairo time (UTC+2)
  const cairoTime = new Date(now.getTime() + (2 * 60 * 60 * 1000));
  return cairoTime;
}

function parseIsoDate(value: string | null): Date | null {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function parseRange(startParam: string | null, endParam: string | null) {
  const cairoNow = getCairoNow();
  const defaultEnd = cairoNow;
  const defaultStart = new Date(cairoNow);
  defaultStart.setHours(0, 0, 0, 0);

  const start = parseIsoDate(startParam) ?? defaultStart;
  const end = parseIsoDate(endParam) ?? defaultEnd;

  return { start, end };
}

function parseHourlyRate(value: unknown): number {
  if (value === null || value === undefined) {
    return 40;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || Number.isNaN(parsed)) {
    return 40;
  }
  return parsed;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  if (req.method !== 'GET') {
    return response(405, { success: false, message: 'Method not allowed' });
  }

  try {
    const url = new URL(req.url);
    const branchName = url.searchParams.get('branch');
    const { start, end } = parseRange(url.searchParams.get('start'), url.searchParams.get('end'));

    if (!branchName) {
      return response(400, { success: false, message: 'Missing branch parameter' });
    }

    if (start.getTime() > end.getTime()) {
      return response(400, { success: false, message: 'Start date must be before end date' });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseKey =
      Deno.env.get('SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !supabaseKey) {
      console.error('[branch-pulse-summary] Missing Supabase env vars');
      return response(500, { success: false, message: 'Server configuration error' });
    }

    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: {
        persistSession: false,
      },
    });

    const [{ data: branchRecord, error: branchError }, { data: branchEmployeesData, error: employeesError }] = await Promise.all([
      supabase.from('branches').select('id, name').eq('name', branchName).maybeSingle(),
      supabase
        .from('employees')
        .select('id, full_name, role, branch_id, branch, is_active, hourly_rate')
        .eq('branch', branchName),
    ]);

    if (branchError) {
      console.error('[branch-pulse-summary] Error fetching branch:', branchError.message);
      return response(500, { success: false, message: 'Failed to fetch branch' });
    }

    if (employeesError) {
      console.error('[branch-pulse-summary] Error fetching employees:', employeesError.message);
      return response(500, { success: false, message: 'Failed to fetch employees' });
    }

    const branchEmployees = (branchEmployeesData ?? []) as BranchEmployeeRow[];

    if (branchEmployees.length === 0) {
      return response(200, {
        success: true,
        branch: {
          id: branchRecord?.id ?? null,
          name: branchName,
        },
        period: {
          start: start.toISOString(),
          end: end.toISOString(),
          timezone: 'Africa/Cairo',
        },
        summary: {
          employeeCount: 0,
          activeEmployeeCount: 0,
          totalPulses: 0,
          totalValidPulses: 0,
          totalInvalidPulses: 0,
          totalEarnings: 0,
          averageEarningsPerEmployee: 0,
        },
        employees: [],
      });
    }

    const employeeIds = branchEmployees.map((emp: BranchEmployeeRow) => emp.id);
    const startIso = start.toISOString();
    const endIso = end.toISOString();

    const [pulsesRes, attendanceRes] = await Promise.all([
      supabase
        .from('pulses')
        .select('employee_id, created_at, is_within_geofence')
        .in('employee_id', employeeIds)
        .gte('created_at', startIso)
        .lte('created_at', endIso)
        .order('created_at', { ascending: true }),
      supabase
        .from('attendance')
        .select('employee_id, check_in_time')
        .in('employee_id', employeeIds)
        .eq('status', 'active'),
    ]);

    if (pulsesRes.error) {
      console.error('[branch-pulse-summary] Error fetching pulses:', pulsesRes.error.message);
      return response(500, { success: false, message: 'Failed to fetch pulses' });
    }

    if (attendanceRes.error) {
      console.error('[branch-pulse-summary] Error fetching attendance:', attendanceRes.error.message);
      return response(500, { success: false, message: 'Failed to fetch attendance' });
    }

    const pulseStats = new Map<string, {
      totalPulses: number;
      validPulses: number;
      invalidPulses: number;
      firstPulse: Date | null;
      lastPulse: Date | null;
    }>();

    for (const row of (pulsesRes.data ?? []) as PulseRow[]) {
      const stats = pulseStats.get(row.employee_id) ?? {
        totalPulses: 0,
        validPulses: 0,
        invalidPulses: 0,
        firstPulse: null,
        lastPulse: null,
      };

      stats.totalPulses += 1;
      if (row.is_within_geofence) {
        stats.validPulses += 1;
      } else {
        stats.invalidPulses += 1;
      }

      const pulseTime = new Date(row.created_at);
      if (!stats.firstPulse || pulseTime < stats.firstPulse) {
        stats.firstPulse = pulseTime;
      }
      if (!stats.lastPulse || pulseTime > stats.lastPulse) {
        stats.lastPulse = pulseTime;
      }

      pulseStats.set(row.employee_id, stats);
    }

    const attendanceMap = new Map<string, Date | null>();
    for (const record of (attendanceRes.data ?? []) as AttendanceRow[]) {
      if (!attendanceMap.has(record.employee_id)) {
        attendanceMap.set(record.employee_id, record.check_in_time ? new Date(record.check_in_time) : null);
      }
    }

    const employeesWithStats = branchEmployees.map((emp: BranchEmployeeRow) => {
      const stats = pulseStats.get(emp.id) ?? {
        totalPulses: 0,
        validPulses: 0,
        invalidPulses: 0,
        firstPulse: null,
        lastPulse: null,
      };

      const hourlyRate = parseHourlyRate(emp.hourly_rate);
      const pulseValue = (hourlyRate / 3600) * 30;
      const earnings = Number((stats.validPulses * pulseValue).toFixed(2));
      const checkInTime = attendanceMap.get(emp.id);

      return {
        id: emp.id,
        fullName: emp.full_name,
        role: emp.role,
        active: emp.active,
        branchId: emp.branch_id,
        hourlyRate: Number(hourlyRate.toFixed(2)),
        totalPulses: stats.totalPulses,
        validPulses: stats.validPulses,
        invalidPulses: stats.invalidPulses,
        earnings,
        firstPulseAt: stats.firstPulse ? stats.firstPulse.toISOString() : null,
        lastPulseAt: stats.lastPulse ? stats.lastPulse.toISOString() : null,
        isCheckedIn: attendanceMap.has(emp.id),
        checkInTime: checkInTime ? checkInTime.toISOString() : null,
      };
    });

    employeesWithStats.sort((a, b) => b.earnings - a.earnings);

    const summaryTotals = employeesWithStats.reduce(
      (acc, employee) => {
        acc.totalPulses += employee.totalPulses;
        acc.totalValidPulses += employee.validPulses;
        acc.totalInvalidPulses += employee.invalidPulses;
        acc.totalEarnings += employee.earnings;
        if (employee.isCheckedIn) {
          acc.activeEmployeeCount += 1;
        }
        return acc;
      },
      {
        totalPulses: 0,
        totalValidPulses: 0,
        totalInvalidPulses: 0,
        totalEarnings: 0,
        activeEmployeeCount: 0,
      }
    );

    const averageEarnings = employeesWithStats.length > 0
      ? Number((summaryTotals.totalEarnings / employeesWithStats.length).toFixed(2))
      : 0;

    return response(200, {
      success: true,
      branch: {
        id: branchRecord?.id ?? employeesWithStats.find((employee) => employee.branchId)?.branchId ?? null,
        name: branchName,
      },
      period: {
        start: startIso,
        end: endIso,
        timezone: 'Africa/Cairo',
      },
      summary: {
        employeeCount: employeesWithStats.length,
        activeEmployeeCount: summaryTotals.activeEmployeeCount,
        totalPulses: summaryTotals.totalPulses,
        totalValidPulses: summaryTotals.totalValidPulses,
        totalInvalidPulses: summaryTotals.totalInvalidPulses,
        totalEarnings: Number(summaryTotals.totalEarnings.toFixed(2)),
        averageEarningsPerEmployee: averageEarnings,
      },
      employees: employeesWithStats,
    });
  } catch (error) {
    console.error('[branch-pulse-summary] Unexpected error:', error);
    return response(500, { success: false, message: 'Internal server error' });
  }
});
