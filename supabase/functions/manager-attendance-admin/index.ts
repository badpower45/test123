// @ts-nocheck
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const DAY_PENALTY = 100;
const CAIRO_UTC_OFFSET_HOURS = 2;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

class HttpError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function jsonResponse(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: corsHeaders,
  });
}

function toNumber(value: unknown): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function pad(value: number): string {
  return value.toString().padStart(2, '0');
}

function dateOnly(value: string): string {
  return value.split('T')[0];
}

function parseMonthRange(monthRaw?: string) {
  const month = (monthRaw ?? '').trim();
  const monthRegex = /^\d{4}-\d{2}$/;
  const normalized = monthRegex.test(month)
    ? month
    : `${new Date().getUTCFullYear()}-${pad(new Date().getUTCMonth() + 1)}`;

  const [yearText, monthText] = normalized.split('-');
  const year = Number(yearText);
  const monthIndex = Number(monthText);

  if (!Number.isInteger(year) || !Number.isInteger(monthIndex) || monthIndex < 1 || monthIndex > 12) {
    throw new HttpError(400, 'صيغة الشهر غير صحيحة. استخدم YYYY-MM');
  }

  const start = `${year}-${pad(monthIndex)}-01`;
  const endDate = new Date(Date.UTC(year, monthIndex, 0));
  const end = `${year}-${pad(monthIndex)}-${pad(endDate.getUTCDate())}`;

  return {
    month: `${year}-${pad(monthIndex)}`,
    startDate: start,
    endDate: end,
  };
}

function parseDateInput(value: unknown): string {
  const text = (value ?? '').toString().trim();
  const regex = /^\d{4}-\d{2}-\d{2}$/;
  if (!regex.test(text)) {
    throw new HttpError(400, 'صيغة التاريخ غير صحيحة. استخدم YYYY-MM-DD');
  }
  return text;
}

function parseTimeInput(value: unknown): string {
  const text = (value ?? '').toString().trim();
  const match = /^(\d{1,2}):(\d{2})(?::\d{2})?$/.exec(text);

  if (!match) {
    throw new HttpError(400, 'صيغة الوقت غير صحيحة. استخدم HH:mm');
  }

  const hour = Number(match[1]);
  const minute = Number(match[2]);

  if (!Number.isInteger(hour) || !Number.isInteger(minute) || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    throw new HttpError(400, 'قيمة الوقت غير صحيحة');
  }

  return `${pad(hour)}:${pad(minute)}`;
}

function normalizeSummaryTime(value: unknown): string | null {
  if (value == null) return null;

  const raw = value.toString().trim();
  if (raw.length === 0) return null;

  const direct = /^(\d{1,2}):(\d{2})(?::\d{2})?$/.exec(raw);
  if (direct) {
    return `${pad(Number(direct[1]))}:${pad(Number(direct[2]))}`;
  }

  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }

  const cairo = new Date(parsed.getTime() + CAIRO_UTC_OFFSET_HOURS * 60 * 60 * 1000);
  return `${pad(cairo.getUTCHours())}:${pad(cairo.getUTCMinutes())}`;
}

function formatIsoTimeToCairo(value: unknown): string | null {
  if (!value) return null;
  const parsed = new Date(value.toString());
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }

  const cairo = new Date(parsed.getTime() + CAIRO_UTC_OFFSET_HOURS * 60 * 60 * 1000);
  return `${pad(cairo.getUTCHours())}:${pad(cairo.getUTCMinutes())}`;
}

function dateFromIso(value: unknown): string | null {
  if (!value) return null;
  const parsed = new Date(value.toString());
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }
  return dateOnly(parsed.toISOString());
}

function cairoDateTimeToUtcIso(date: string, timeHHmm: string): string {
  const local = new Date(`${date}T${timeHHmm}:00+02:00`);
  if (Number.isNaN(local.getTime())) {
    throw new HttpError(400, 'تعذر تحويل التاريخ والوقت');
  }
  return local.toISOString();
}

function hoursBetween(checkInIso: string, checkOutIso: string): number {
  const checkIn = new Date(checkInIso);
  const checkOut = new Date(checkOutIso);

  if (Number.isNaN(checkIn.getTime()) || Number.isNaN(checkOut.getTime())) {
    throw new HttpError(400, 'تعذر حساب عدد الساعات');
  }

  const hours = (checkOut.getTime() - checkIn.getTime()) / (1000 * 60 * 60);
  if (hours <= 0) {
    throw new HttpError(400, 'وقت الانصراف يجب أن يكون بعد وقت الحضور');
  }

  return Number(hours.toFixed(2));
}

function startAndEndIsoForDate(date: string) {
  return {
    startIso: new Date(`${date}T00:00:00+02:00`).toISOString(),
    endIso: new Date(`${date}T23:59:59+02:00`).toISOString(),
  };
}

function isTruthy(value: unknown): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') {
    return ['true', 't', '1', 'yes'].includes(value.toLowerCase());
  }
  return false;
}

async function getActor(supabase: any, managerId: string) {
  const { data, error } = await supabase
    .from('employees')
    .select('id, full_name, role, branch, branch_id')
    .eq('id', managerId)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, `فشل التحقق من المدير: ${error.message}`);
  }

  if (!data) {
    throw new HttpError(404, 'لم يتم العثور على حساب المدير');
  }

  const allowedRoles = ['manager', 'admin', 'owner', 'hr'];
  if (!allowedRoles.includes((data.role ?? '').toString())) {
    throw new HttpError(403, 'ليس لديك صلاحية إدارة الحضور والجزاءات');
  }

  return data;
}

function ensureBranchScope(actor: any, branchName: string) {
  const role = (actor.role ?? '').toString();
  if (role === 'manager' && (actor.branch ?? '').toString() !== branchName) {
    throw new HttpError(403, 'مدير الفرع يمكنه إدارة بيانات فرعه فقط');
  }
}

async function ensureEmployeeInBranch(supabase: any, employeeId: string, branchName: string) {
  const { data, error } = await supabase
    .from('employees')
    .select('id, full_name, branch, branch_id, hourly_rate, shift_start_time, shift_end_time, role')
    .eq('id', employeeId)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, `فشل تحميل الموظف: ${error.message}`);
  }

  if (!data) {
    throw new HttpError(404, 'لم يتم العثور على الموظف');
  }

  if ((data.branch ?? '').toString() !== branchName) {
    throw new HttpError(403, 'الموظف ليس ضمن هذا الفرع');
  }

  if ((data.role ?? '').toString() === 'owner') {
    throw new HttpError(403, 'لا يمكن تطبيق هذا الإجراء على حساب المالك');
  }

  return data;
}

async function fetchAttendanceRowsForRange(
  supabase: any,
  employeeId: string,
  startDate: string,
  endDate: string,
) {
  const byDate = await supabase
    .from('attendance')
    .select('*')
    .eq('employee_id', employeeId)
    .gte('date', startDate)
    .lte('date', endDate)
    .order('date', { ascending: true })
    .order('check_in_time', { ascending: true });

  if (!byDate.error) {
    return byDate.data ?? [];
  }

  const fallback = await supabase
    .from('attendance')
    .select('*')
    .eq('employee_id', employeeId)
    .gte('check_in_time', `${startDate}T00:00:00`)
    .lte('check_in_time', `${endDate}T23:59:59`)
    .order('check_in_time', { ascending: true });

  if (fallback.error) {
    throw new HttpError(500, `فشل تحميل سجلات الحضور: ${fallback.error.message}`);
  }

  return fallback.data ?? [];
}

async function fetchAttendanceRowsForDate(supabase: any, employeeId: string, date: string) {
  const byDate = await supabase
    .from('attendance')
    .select('*')
    .eq('employee_id', employeeId)
    .eq('date', date)
    .order('check_in_time', { ascending: true });

  if (!byDate.error) {
    return byDate.data ?? [];
  }

  const range = startAndEndIsoForDate(date);
  const fallback = await supabase
    .from('attendance')
    .select('*')
    .eq('employee_id', employeeId)
    .gte('check_in_time', range.startIso)
    .lte('check_in_time', range.endIso)
    .order('check_in_time', { ascending: true });

  if (fallback.error) {
    throw new HttpError(500, `فشل تحميل يوم الحضور: ${fallback.error.message}`);
  }

  return fallback.data ?? [];
}

function penaltyLabel(type: string) {
  switch (type) {
    case 'half_day':
      return 'نصف يوم';
    case 'day':
      return 'يوم';
    case 'two_days':
      return 'يومين';
    case 'custom':
      return 'مبلغ مخصص';
    default:
      return 'جزاء';
  }
}

function penaltyAmount(type: string, customAmount: number) {
  switch (type) {
    case 'half_day':
      return DAY_PENALTY / 2;
    case 'day':
      return DAY_PENALTY;
    case 'two_days':
      return DAY_PENALTY * 2;
    case 'custom':
      if (customAmount <= 0) {
        throw new HttpError(400, 'قيمة الجزاء المخصص يجب أن تكون أكبر من صفر');
      }
      return Number(customAmount.toFixed(2));
    default:
      throw new HttpError(400, 'نوع الجزاء غير مدعوم');
  }
}

async function actionGetBranchEmployees(supabase: any, body: any) {
  const managerId = (body.managerId ?? '').toString();
  const branchName = (body.branchName ?? '').toString().trim();

  if (!managerId || !branchName) {
    throw new HttpError(400, 'managerId و branchName مطلوبان');
  }

  const actor = await getActor(supabase, managerId);
  ensureBranchScope(actor, branchName);

  const { data, error } = await supabase
    .from('employees')
    .select('id, full_name, branch, branch_id, role, hourly_rate, shift_start_time, shift_end_time')
    .eq('branch', branchName)
    .eq('is_active', true)
    .neq('role', 'owner')
    .order('full_name', { ascending: true });

  if (error) {
    throw new HttpError(500, `فشل تحميل موظفي الفرع: ${error.message}`);
  }

  return {
    actor,
    employees: (data ?? []).map((employee: any) => ({
      id: employee.id,
      full_name: employee.full_name,
      role: employee.role,
      branch: employee.branch,
      branch_id: employee.branch_id,
      hourly_rate: toNumber(employee.hourly_rate),
      shift_start_time: employee.shift_start_time,
      shift_end_time: employee.shift_end_time,
    })),
  };
}

async function actionGetMonthlyAttendance(supabase: any, body: any) {
  const managerId = (body.managerId ?? '').toString();
  const branchName = (body.branchName ?? '').toString().trim();
  const employeeId = (body.employeeId ?? '').toString();

  if (!managerId || !branchName || !employeeId) {
    throw new HttpError(400, 'managerId و branchName و employeeId مطلوبون');
  }

  const actor = await getActor(supabase, managerId);
  ensureBranchScope(actor, branchName);

  const employee = await ensureEmployeeInBranch(supabase, employeeId, branchName);
  const monthRange = parseMonthRange(body.month);

  const attendanceRows = await fetchAttendanceRowsForRange(
    supabase,
    employeeId,
    monthRange.startDate,
    monthRange.endDate,
  );

  const { data: summaryRows, error: summaryError } = await supabase
    .from('daily_attendance_summary')
    .select('*')
    .eq('employee_id', employeeId)
    .gte('attendance_date', monthRange.startDate)
    .lte('attendance_date', monthRange.endDate);

  if (summaryError) {
    throw new HttpError(500, `فشل تحميل الملخص اليومي: ${summaryError.message}`);
  }

  const { data: deductionRows, error: deductionError } = await supabase
    .from('deductions')
    .select('id, employee_id, amount, reason, deduction_date, created_at')
    .eq('employee_id', employeeId)
    .gte('deduction_date', monthRange.startDate)
    .lte('deduction_date', monthRange.endDate)
    .order('created_at', { ascending: false });

  if (deductionError) {
    throw new HttpError(500, `فشل تحميل الجزاءات: ${deductionError.message}`);
  }

  const attendanceByDate = new Map<string, any>();

  for (const row of attendanceRows) {
    const dateKey =
      (row.date ? row.date.toString() : null) ??
      dateFromIso(row.check_in_time) ??
      dateFromIso(row.check_out_time);

    if (!dateKey) continue;

    const current = attendanceByDate.get(dateKey) ?? {
      checkInIso: null,
      checkOutIso: null,
      totalHours: 0,
    };

    const checkInIso = row.check_in_time?.toString() ?? null;
    const checkOutIso = row.check_out_time?.toString() ?? null;

    if (checkInIso && (!current.checkInIso || checkInIso < current.checkInIso)) {
      current.checkInIso = checkInIso;
    }

    if (checkOutIso && (!current.checkOutIso || checkOutIso > current.checkOutIso)) {
      current.checkOutIso = checkOutIso;
    }

    current.totalHours += toNumber(row.work_hours ?? row.total_hours);
    attendanceByDate.set(dateKey, current);
  }

  for (const [dateKey, record] of attendanceByDate.entries()) {
    if (record.totalHours <= 0 && record.checkInIso && record.checkOutIso) {
      try {
        record.totalHours = hoursBetween(record.checkInIso, record.checkOutIso);
      } catch (_e) {
        record.totalHours = 0;
      }
      attendanceByDate.set(dateKey, record);
    }
  }

  const summaryByDate = new Map<string, any>();
  for (const summary of summaryRows ?? []) {
    summaryByDate.set(summary.attendance_date.toString(), summary);
  }

  const deductionsByDate = new Map<string, { amount: number; reasons: string[] }>();
  for (const deduction of deductionRows ?? []) {
    const dateKey = deduction.deduction_date?.toString()?.split('T')[0];
    if (!dateKey) continue;

    const current = deductionsByDate.get(dateKey) ?? { amount: 0, reasons: [] };
    current.amount += Math.abs(toNumber(deduction.amount));

    if (deduction.reason) {
      current.reasons.push(deduction.reason.toString());
    }

    deductionsByDate.set(dateKey, current);
  }

  const days: Record<string, unknown>[] = [];
  let cursor = new Date(`${monthRange.startDate}T00:00:00.000Z`);
  const endCursor = new Date(`${monthRange.endDate}T00:00:00.000Z`);

  while (cursor <= endCursor) {
    const dateKey = dateOnly(cursor.toISOString());
    const attendance = attendanceByDate.get(dateKey);
    const summary = summaryByDate.get(dateKey);
    const deductionInfo = deductionsByDate.get(dateKey);

    const checkInTime =
      formatIsoTimeToCairo(attendance?.checkInIso) ?? normalizeSummaryTime(summary?.check_in_time);
    const checkOutTime =
      formatIsoTimeToCairo(attendance?.checkOutIso) ?? normalizeSummaryTime(summary?.check_out_time);

    let totalHours = toNumber(summary?.total_hours);
    if (totalHours <= 0) {
      totalHours = toNumber(attendance?.totalHours);
    }

    const summaryDeduction = Math.abs(toNumber(summary?.deduction_amount));
    const recordDeduction = Math.abs(toNumber(deductionInfo?.amount));
    const deductionAmount = summaryDeduction > 0 ? summaryDeduction : recordDeduction;

    const isOnLeave = isTruthy(summary?.is_on_leave);
    const isAbsent = isTruthy(summary?.is_absent);

    let status = 'none';
    if (isOnLeave) {
      status = 'on_leave';
    } else if (isAbsent) {
      status = 'absent';
    } else if (checkInTime && !checkOutTime) {
      status = 'active';
    } else if (checkInTime) {
      status = 'present';
    }

    days.push({
      date: dateKey,
      check_in_time: checkInTime,
      check_out_time: checkOutTime,
      total_hours: Number(totalHours.toFixed(2)),
      daily_salary: Number(toNumber(summary?.daily_salary).toFixed(2)),
      deduction_amount: Number(deductionAmount.toFixed(2)),
      status,
      penalty_reasons: deductionInfo?.reasons?.join('، ') ?? '',
      is_absent: isAbsent,
      is_on_leave: isOnLeave,
    });

    cursor = new Date(cursor.getTime() + 24 * 60 * 60 * 1000);
  }

  return {
    actor,
    employee: {
      id: employee.id,
      full_name: employee.full_name,
      hourly_rate: toNumber(employee.hourly_rate),
      shift_start_time: employee.shift_start_time,
      shift_end_time: employee.shift_end_time,
    },
    month: monthRange.month,
    start_date: monthRange.startDate,
    end_date: monthRange.endDate,
    day_penalty_value: DAY_PENALTY,
    days,
  };
}

async function actionUpdateDayTimes(supabase: any, body: any) {
  const managerId = (body.managerId ?? '').toString();
  const branchName = (body.branchName ?? '').toString().trim();
  const employeeId = (body.employeeId ?? '').toString();
  const date = parseDateInput(body.date);

  if (!managerId || !branchName || !employeeId) {
    throw new HttpError(400, 'managerId و branchName و employeeId مطلوبون');
  }

  const checkInTime = parseTimeInput(body.checkInTime);
  const checkOutTime = parseTimeInput(body.checkOutTime);

  const actor = await getActor(supabase, managerId);
  ensureBranchScope(actor, branchName);

  const employee = await ensureEmployeeInBranch(supabase, employeeId, branchName);

  const checkInIso = cairoDateTimeToUtcIso(date, checkInTime);
  const checkOutIso = cairoDateTimeToUtcIso(date, checkOutTime);
  const totalHours = hoursBetween(checkInIso, checkOutIso);
  const hourlyRate = toNumber(employee.hourly_rate);
  const dailySalary = Number((totalHours * hourlyRate).toFixed(2));

  const dayRows = await fetchAttendanceRowsForDate(supabase, employeeId, date);

  const attendancePayload: Record<string, unknown> = {
    date,
    check_in_time: checkInIso,
    check_out_time: checkOutIso,
    status: 'completed',
    updated_at: new Date().toISOString(),
    work_hours: totalHours,
    total_hours: totalHours,
  };

  if (dayRows.length > 0) {
    const targetId = dayRows[0].id;
    const { error: updateError } = await supabase
      .from('attendance')
      .update(attendancePayload)
      .eq('id', targetId);

    if (updateError) {
      throw new HttpError(500, `فشل تعديل سجل الحضور: ${updateError.message}`);
    }
  } else {
    const { error: insertError } = await supabase
      .from('attendance')
      .insert({
        employee_id: employeeId,
        branch_id: employee.branch_id ?? null,
        ...attendancePayload,
      });

    if (insertError) {
      throw new HttpError(500, `فشل إنشاء سجل حضور جديد: ${insertError.message}`);
    }
  }

  const summaryPayload = {
    employee_id: employeeId,
    attendance_date: date,
    check_in_time: `${checkInTime}:00`,
    check_out_time: `${checkOutTime}:00`,
    total_hours: totalHours,
    hourly_rate: hourlyRate,
    daily_salary: dailySalary,
    is_absent: false,
    is_on_leave: false,
    updated_at: new Date().toISOString(),
  };

  const { error: summaryError } = await supabase
    .from('daily_attendance_summary')
    .upsert(summaryPayload, { onConflict: 'employee_id,attendance_date' });

  if (summaryError) {
    throw new HttpError(500, `فشل تحديث الملخص اليومي: ${summaryError.message}`);
  }

  return {
    actor,
    employee_id: employeeId,
    date,
    check_in_time: checkInTime,
    check_out_time: checkOutTime,
    total_hours: totalHours,
    daily_salary: dailySalary,
  };
}

async function actionDeleteDay(supabase: any, body: any) {
  const managerId = (body.managerId ?? '').toString();
  const branchName = (body.branchName ?? '').toString().trim();
  const employeeId = (body.employeeId ?? '').toString();
  const date = parseDateInput(body.date);

  if (!managerId || !branchName || !employeeId) {
    throw new HttpError(400, 'managerId و branchName و employeeId مطلوبون');
  }

  const actor = await getActor(supabase, managerId);
  ensureBranchScope(actor, branchName);
  await ensureEmployeeInBranch(supabase, employeeId, branchName);

  let attendanceDeleted = 0;
  const attendanceDeleteByDate = await supabase
    .from('attendance')
    .delete({ count: 'exact' })
    .eq('employee_id', employeeId)
    .eq('date', date);

  if (!attendanceDeleteByDate.error) {
    attendanceDeleted = attendanceDeleteByDate.count ?? 0;
  } else {
    const range = startAndEndIsoForDate(date);
    const fallbackDelete = await supabase
      .from('attendance')
      .delete({ count: 'exact' })
      .eq('employee_id', employeeId)
      .gte('check_in_time', range.startIso)
      .lte('check_in_time', range.endIso);

    if (fallbackDelete.error) {
      throw new HttpError(500, `فشل حذف سجل الحضور: ${fallbackDelete.error.message}`);
    }

    attendanceDeleted = fallbackDelete.count ?? 0;
  }

  const summaryDelete = await supabase
    .from('daily_attendance_summary')
    .delete({ count: 'exact' })
    .eq('employee_id', employeeId)
    .eq('attendance_date', date);

  if (summaryDelete.error) {
    throw new HttpError(500, `فشل حذف الملخص اليومي: ${summaryDelete.error.message}`);
  }

  const deductionDelete = await supabase
    .from('deductions')
    .delete({ count: 'exact' })
    .eq('employee_id', employeeId)
    .eq('deduction_date', date);

  if (deductionDelete.error) {
    throw new HttpError(500, `فشل حذف جزاءات اليوم: ${deductionDelete.error.message}`);
  }

  // Optional cleanup for absences on the same date.
  await supabase
    .from('absences')
    .delete()
    .eq('employee_id', employeeId)
    .eq('absence_date', date);

  return {
    actor,
    employee_id: employeeId,
    date,
    deleted: {
      attendance: attendanceDeleted,
      summaries: summaryDelete.count ?? 0,
      deductions: deductionDelete.count ?? 0,
    },
  };
}

async function actionApplyPenalty(supabase: any, body: any) {
  const managerId = (body.managerId ?? '').toString();
  const branchName = (body.branchName ?? '').toString().trim();
  const employeeId = (body.employeeId ?? '').toString();
  const date = parseDateInput(body.date);
  const type = (body.penaltyType ?? '').toString().trim();

  if (!managerId || !branchName || !employeeId || !type) {
    throw new HttpError(400, 'managerId و branchName و employeeId و penaltyType مطلوبون');
  }

  const actor = await getActor(supabase, managerId);
  ensureBranchScope(actor, branchName);
  const employee = await ensureEmployeeInBranch(supabase, employeeId, branchName);

  const customAmount = toNumber(body.customAmount);
  const amount = penaltyAmount(type, customAmount);
  const defaultReason = `جزاء ${penaltyLabel(type)} يوم ${date}`;
  const reason = (body.reason ?? '').toString().trim() || defaultReason;

  const baseDeductionPayload = {
    employee_id: employeeId,
    amount,
    reason,
    deduction_date: date,
    created_at: new Date().toISOString(),
  };

  let deductionRecord: any = null;
  let deductionError: any = null;

  const insertWithMeta = await supabase
    .from('deductions')
    .insert({
      ...baseDeductionPayload,
      deduction_type: 'manual_penalty',
      applied_by: managerId,
    })
    .select()
    .maybeSingle();

  if (!insertWithMeta.error) {
    deductionRecord = insertWithMeta.data;
  } else {
    const fallbackInsert = await supabase
      .from('deductions')
      .insert(baseDeductionPayload)
      .select()
      .maybeSingle();

    deductionRecord = fallbackInsert.data;
    deductionError = fallbackInsert.error;
  }

  if (deductionError) {
    throw new HttpError(500, `فشل تسجيل الجزاء: ${deductionError.message}`);
  }

  const { data: summaryRow, error: summaryFetchError } = await supabase
    .from('daily_attendance_summary')
    .select('*')
    .eq('employee_id', employeeId)
    .eq('attendance_date', date)
    .maybeSingle();

  if (summaryFetchError) {
    throw new HttpError(500, `فشل تحديث ملخص اليوم: ${summaryFetchError.message}`);
  }

  if (summaryRow) {
    const updatedDeduction = Number((toNumber(summaryRow.deduction_amount) + amount).toFixed(2));
    const { error: updateSummaryError } = await supabase
      .from('daily_attendance_summary')
      .update({
        deduction_amount: updatedDeduction,
        updated_at: new Date().toISOString(),
      })
      .eq('employee_id', employeeId)
      .eq('attendance_date', date);

    if (updateSummaryError) {
      throw new HttpError(500, `فشل تعديل قيمة الجزاء اليومية: ${updateSummaryError.message}`);
    }
  } else {
    const { error: insertSummaryError } = await supabase
      .from('daily_attendance_summary')
      .insert({
        employee_id: employeeId,
        attendance_date: date,
        check_in_time: null,
        check_out_time: null,
        total_hours: 0,
        hourly_rate: toNumber(employee.hourly_rate),
        daily_salary: 0,
        advance_amount: 0,
        leave_allowance: 0,
        deduction_amount: amount,
        is_absent: false,
        is_on_leave: false,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });

    if (insertSummaryError) {
      throw new HttpError(500, `فشل إنشاء ملخص اليوم بعد تسجيل الجزاء: ${insertSummaryError.message}`);
    }
  }

  return {
    actor,
    employee_id: employeeId,
    date,
    amount,
    reason,
    penalty_type: type,
    day_penalty_value: DAY_PENALTY,
    deduction: deductionRecord,
  };
}

async function actionListPenalties(supabase: any, body: any) {
  const managerId = (body.managerId ?? '').toString();
  const branchName = (body.branchName ?? '').toString().trim();
  const requestedEmployeeId = (body.employeeId ?? '').toString().trim();

  if (!managerId || !branchName) {
    throw new HttpError(400, 'managerId و branchName مطلوبان');
  }

  const actor = await getActor(supabase, managerId);
  ensureBranchScope(actor, branchName);

  const monthRange = parseMonthRange(body.month);

  const { data: branchEmployees, error: branchEmployeesError } = await supabase
    .from('employees')
    .select('id, full_name, branch, role')
    .eq('branch', branchName)
    .eq('is_active', true)
    .neq('role', 'owner');

  if (branchEmployeesError) {
    throw new HttpError(500, `فشل تحميل موظفي الفرع: ${branchEmployeesError.message}`);
  }

  const employeeMap = new Map<string, string>();
  for (const employee of branchEmployees ?? []) {
    employeeMap.set(employee.id.toString(), (employee.full_name ?? '').toString());
  }

  let employeeIds = Array.from(employeeMap.keys());

  if (requestedEmployeeId) {
    if (!employeeMap.has(requestedEmployeeId)) {
      throw new HttpError(403, 'الموظف المحدد ليس ضمن هذا الفرع');
    }
    employeeIds = [requestedEmployeeId];
  }

  if (employeeIds.length === 0) {
    return {
      actor,
      month: monthRange.month,
      start_date: monthRange.startDate,
      end_date: monthRange.endDate,
      penalties: [],
    };
  }

  const { data: deductions, error: deductionsError } = await supabase
    .from('deductions')
    .select('id, employee_id, amount, reason, deduction_date, created_at')
    .in('employee_id', employeeIds)
    .gte('deduction_date', monthRange.startDate)
    .lte('deduction_date', monthRange.endDate)
    .order('deduction_date', { ascending: false })
    .order('created_at', { ascending: false });

  if (deductionsError) {
    throw new HttpError(500, `فشل تحميل سجل الجزاءات: ${deductionsError.message}`);
  }

  const penalties = (deductions ?? []).map((deduction: any) => ({
    id: deduction.id,
    employee_id: deduction.employee_id,
    employee_name: employeeMap.get((deduction.employee_id ?? '').toString()) ?? 'غير معروف',
    amount: Math.abs(Number(toNumber(deduction.amount).toFixed(2))),
    reason: deduction.reason ?? '',
    deduction_date: deduction.deduction_date,
    created_at: deduction.created_at,
  }));

  return {
    actor,
    month: monthRange.month,
    start_date: monthRange.startDate,
    end_date: monthRange.endDate,
    penalties,
  };
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse(405, {
      success: false,
      error: 'Method not allowed',
    });
  }

  try {
    const body = await req.json();
    const action = (body.action ?? '').toString().trim();

    if (!action) {
      throw new HttpError(400, 'action مطلوب');
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || 'https://bbxuyuaemigrqsvsnxkj.supabase.co';
    const serviceRoleKey = Deno.env.get('SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !serviceRoleKey) {
      throw new HttpError(500, 'بيانات اتصال Supabase غير مكتملة على الخادم');
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
      },
    });

    let data: Record<string, unknown>;

    switch (action) {
      case 'get_branch_employees':
        data = await actionGetBranchEmployees(supabase, body);
        break;
      case 'get_monthly_attendance':
        data = await actionGetMonthlyAttendance(supabase, body);
        break;
      case 'update_day_times':
        data = await actionUpdateDayTimes(supabase, body);
        break;
      case 'delete_day':
        data = await actionDeleteDay(supabase, body);
        break;
      case 'apply_penalty':
        data = await actionApplyPenalty(supabase, body);
        break;
      case 'list_penalties':
        data = await actionListPenalties(supabase, body);
        break;
      default:
        throw new HttpError(400, 'action غير مدعوم');
    }

    return jsonResponse(200, {
      success: true,
      data,
    });
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    const message = error instanceof Error ? error.message : 'حدث خطأ غير متوقع';

    console.error('[manager-attendance-admin] error:', error);

    return jsonResponse(status, {
      success: false,
      error: message,
    });
  }
});
