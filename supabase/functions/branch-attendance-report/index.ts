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
};

type AttendanceRow = {
  id: string;
  employee_id: string;
  check_in_time: string | null;
  check_out_time: string | null;
  work_hours: number | string | null;
  status: string | null;
  date: string;
  employees?: {
    full_name: string | null;
  };
};

function parseNumber(value: unknown): number | null {
  if (value === null || value === undefined) {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function formatDateInput(input?: string | null): string {
  if (input && /^\d{4}-\d{2}-\d{2}$/.test(input)) {
    return input;
  }
  return new Date().toISOString().split('T')[0];
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
    const requestedDate = formatDateInput(url.searchParams.get('date'));

    if (!branchName) {
      return response(400, { success: false, message: 'Missing branch parameter' });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || 'https://bbxuyuaemigrqsvsnxkj.supabase.co';
    const supabaseKey =
      Deno.env.get('SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !supabaseKey) {
      console.error('[branch-attendance-report] Missing Supabase env vars');
      return response(500, { success: false, message: 'Server configuration error' });
    }

    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: {
        persistSession: false,
      },
    });

    const { data: branchEmployeesData, error: employeesError } = await supabase
      .from('employees')
      .select('id, full_name, role, branch_id, branch, is_active')
      .eq('branch', branchName);

    if (employeesError) {
      console.error('[branch-attendance-report] Error fetching employees:', employeesError.message);
      return response(500, { success: false, message: 'Failed to fetch employees' });
    }

    const branchEmployees = (branchEmployeesData ?? []) as BranchEmployeeRow[];

    if (branchEmployees.length === 0) {
      return response(200, {
        success: true,
        date: requestedDate,
        report: [],
      });
    }

    const employeeIds = branchEmployees.map((emp: BranchEmployeeRow) => emp.id);

    // First try using the 'date' column (preferred)
    let attendanceData: AttendanceRow[] | null = null;
    let attendanceError: any = null;
    try {
      const res = await supabase
        .from('attendance')
        .select('id, employee_id, check_in_time, check_out_time, work_hours, status, date, employees!inner(full_name, hourly_rate)')
        .in('employee_id', employeeIds)
        .eq('date', requestedDate)
        .order('check_in_time', { ascending: true });
      attendanceData = (res.data ?? []) as any;
      attendanceError = res.error;
    } catch (e) {
      attendanceError = e as Error;
    }

    // Fallback: if 'date' column is missing, filter by Cairo-local day using check_in_time
    if (attendanceError) {
      console.warn('[branch-attendance-report] Falling back to time range filter:', attendanceError.message ?? attendanceError);
      const dayStart = new Date(new Date(`${requestedDate}T00:00:00.000Z`).toLocaleString('en-US', { timeZone: 'Africa/Cairo' }));
      const dayEnd = new Date(new Date(`${requestedDate}T23:59:59.999Z`).toLocaleString('en-US', { timeZone: 'Africa/Cairo' }));
      const startIso = dayStart.toISOString();
      const endIso = dayEnd.toISOString();

      const res2 = await supabase
        .from('attendance')
        .select('id, employee_id, check_in_time, check_out_time, work_hours, status, employees!inner(full_name, hourly_rate)')
        .in('employee_id', employeeIds)
        .gte('check_in_time', startIso)
        .lte('check_in_time', endIso)
        .order('check_in_time', { ascending: true });

      if (res2.error) {
        console.error('[branch-attendance-report] Error fetching attendance (fallback):', res2.error.message);
        return response(500, { success: false, message: 'Failed to fetch attendance records' });
      }
      attendanceData = (res2.data ?? []) as any;
    }

    const cairoNow = new Date(new Date().toLocaleString('en-US', { timeZone: 'Africa/Cairo' }));
    const report = (attendanceData ?? []).map((row: AttendanceRow & { employees?: { full_name: string|null; hourly_rate?: number|string|null } }) => {
      const baseHours = parseNumber(row.work_hours) ?? 0;
      let liveHours = baseHours;
      let liveSalary: number | null = null;

      if ((row.status === 'active' || !row.check_out_time) && row.check_in_time) {
        const checkIn = new Date(row.check_in_time);
        const diffMs = cairoNow.getTime() - checkIn.getTime();
        const hours = diffMs > 0 ? diffMs / (1000 * 60 * 60) : 0;
        liveHours = Number(hours.toFixed(2));
        const rate = Number(row.employees?.hourly_rate ?? 0) || 0;
        liveSalary = Number((liveHours * rate).toFixed(2));
      } else {
        const rate = Number(row.employees?.hourly_rate ?? 0) || 0;
        if (baseHours > 0 && rate > 0) {
          liveSalary = Number((baseHours * rate).toFixed(2));
        }
      }

      return {
        id: row.id,
        employeeId: row.employee_id,
        employeeName: row.employees?.full_name ?? null,
        checkInTime: row.check_in_time,
        checkOutTime: row.check_out_time,
        workHours: liveHours,
        status: row.status,
        date: (row as any).date ?? requestedDate,
        hourlyRate: Number(row.employees?.hourly_rate ?? 0) || 0,
        dailySalary: liveSalary,
      };
    });

    return response(200, {
      success: true,
      date: requestedDate,
      report,
    });
  } catch (error) {
    console.error('[branch-attendance-report] Unexpected error:', error);
    return response(500, { success: false, message: 'Internal server error' });
  }
});
