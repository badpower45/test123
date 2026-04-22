// @ts-nocheck
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

type JsonRecord = Record<string, unknown>;

type AttendanceCheckOutPayload = {
  employee_id?: string;
  attendance_id?: string; // ✅ Added: Allow specifying attendance_id directly
  latitude?: number;
  longitude?: number;
  wifi_bssid?: string;
  timestamp?: string | number;
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

function response(status: number, body: JsonRecord) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function normalizeBssid(value?: string | null): string | null {
  if (!value) return null;
  return value.trim().toUpperCase().replace(/-/g, ':');
}

function toNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return null;
}

function getCairoNow(): Date {
  // Return current UTC time - Supabase stores in UTC and converts automatically
  // DO NOT add hours manually - this causes time to be saved 2 hours ahead
  return new Date();
}

function getCairoOffsetMinutes(referenceUtc: Date): number {
  const timezonePart = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Africa/Cairo',
    timeZoneName: 'shortOffset',
    hour: '2-digit',
    minute: '2-digit',
  }).formatToParts(referenceUtc).find((part) => part.type === 'timeZoneName')?.value ?? 'GMT+2';

  const match = timezonePart.match(/GMT([+-])(\d{1,2})(?::?(\d{2}))?/i);
  if (!match) {
    return 120;
  }

  const sign = match[1] === '-' ? -1 : 1;
  const hours = Number(match[2] ?? '0');
  const minutes = Number(match[3] ?? '0');

  return sign * ((hours * 60) + minutes);
}

function parseNaiveCairoTimestamp(input: string): Date | null {
  const match = input.match(
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?$/,
  );

  if (!match) {
    return null;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6] ?? '0');
  const millisecond = Number((match[7] ?? '').padEnd(3, '0') || '0');

  if (
    !Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day) ||
    !Number.isInteger(hour) || !Number.isInteger(minute) || !Number.isInteger(second) ||
    month < 1 || month > 12 || day < 1 || day > 31 ||
    hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59
  ) {
    return null;
  }

  const utcGuessMs = Date.UTC(year, month - 1, day, hour, minute, second, millisecond);
  const offsetMinutes = getCairoOffsetMinutes(new Date(utcGuessMs));
  const corrected = new Date(utcGuessMs - (offsetMinutes * 60 * 1000));

  return Number.isNaN(corrected.getTime()) ? null : corrected;
}

function parseTimestamp(input: unknown): Date | null {
  if (!input) return null;
  if (input instanceof Date) {
    return Number.isNaN(input.getTime()) ? null : input;
  }
  if (typeof input === 'number') {
    const normalized = input < 1e12 ? input * 1000 : input;
    const date = new Date(normalized);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (typeof input === 'string') {
    const trimmed = input.trim();
    if (!trimmed) return null;

    const normalized = trimmed.replace(' ', 'T');
    const hasTimezone = /(?:Z|[+-]\d{2}(?::?\d{2})?)$/i.test(normalized);

    let date: Date;
    if (hasTimezone) {
      date = new Date(normalized);
    } else {
      // Legacy/mobile fallback: naive timestamps are treated as Cairo local time,
      // including DST-aware offset changes.
      date = parseNaiveCairoTimestamp(normalized) ?? new Date(normalized);
    }

    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function parseAllowedBssids(branch: any, bssidRecords: any[]): Set<string> {
  const allowed = new Set<string>();

  const primary = branch?.wifi_bssid ?? branch?.bssid_1 ?? branch?.primary_bssid;
  const secondary = branch?.bssid_2 ?? branch?.secondary_bssid;

  const addFromString = (value?: string | null) => {
    if (!value) return;
    value
      .split(/[\s,\n]+/)
      .map((part) => normalizeBssid(part))
      .filter(Boolean)
      .forEach((bssid) => allowed.add(bssid as string));
  };

  addFromString(primary);
  addFromString(secondary);

  bssidRecords.forEach((record) => {
    const fromRecord = normalizeBssid(record?.bssid_address ?? record?.bssidAddress ?? record?.wifi_bssid);
    if (fromRecord) {
      allowed.add(fromRecord);
    }
  });

  return allowed;
}

function cairoDateTimeString(date: Date): string {
  const formatter = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Africa/Cairo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  });
  return formatter.format(date);
}

function haversineDistanceMeters(
  lat1?: number | null,
  lon1?: number | null,
  lat2?: number | null,
  lon2?: number | null,
): number | null {
  if (
    typeof lat1 !== 'number' ||
    typeof lon1 !== 'number' ||
    typeof lat2 !== 'number' ||
    typeof lon2 !== 'number'
  ) {
    return null;
  }

  const R = 6371000;
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const φ1 = toRad(lat1);
  const φ2 = toRad(lat2);
  const Δφ = toRad(lat2 - lat1);
  const Δλ = toRad(lon2 - lon1);

  const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
    Math.cos(φ1) * Math.cos(φ2) *
      Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c;
}

async function fetchBranchBssids(
  supabase: any,
  branchId: string,
): Promise<{ records: any[]; error?: Error }> {
  try {
    const { data, error } = await supabase
      .from('branch_bssids')
      .select('*')
      .eq('branch_id', branchId);

    if (error && error.message?.includes('column "branch_id" does not exist')) {
      const fallback = await supabase
        .from('branch_bssids')
        .select('*')
        .eq('branchId', branchId);
      if (fallback.error) {
        return { records: [], error: fallback.error };
      }
      return { records: fallback.data ?? [] };
    }

    if (error) {
      return { records: [], error };
    }

    return { records: data ?? [] };
  } catch (err) {
    return { records: [], error: err as Error };
  }
}

serve(async (req: Request) => {
  console.log('[attendance-check-out] 📥 Received request:', req.method, req.url);
  
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return response(405, { success: false, error: 'Method not allowed' });
  }

  try {
    const body = (await req.json()) as AttendanceCheckOutPayload;
    console.log('[attendance-check-out] 📦 Request body:', JSON.stringify(body));
    
    const employeeId = body.employee_id?.trim();

    if (!employeeId) {
      console.error('[attendance-check-out] ❌ Missing employee_id');
      return response(400, { success: false, error: 'Employee ID is required' });
    }

    console.log('[attendance-check-out] 👤 Processing checkout for employee:', employeeId);

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || 'https://bbxuyuaemigrqsvsnxkj.supabase.co';
    const supabaseKey =
      Deno.env.get('SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !supabaseKey) {
      console.error('[attendance-check-out] Missing Supabase credentials');
      return response(500, { success: false, error: 'Server configuration error' });
    }

    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: { persistSession: false },
    });

    const { data: employee, error: employeeError } = await supabase
      .from('employees')
      .select('id, full_name, role, branch_id, branch, hourly_rate, is_active')
      .eq('id', employeeId)
      .maybeSingle();

    if (employeeError) {
      console.error('[attendance-check-out] Failed to fetch employee', employeeError);
      return response(500, { success: false, error: 'Failed to fetch employee data' });
    }

    if (!employee) {
      return response(404, { success: false, error: 'Employee not found' });
    }

    if (employee.is_active === false) {
      return response(403, { success: false, error: 'لا يمكن تسجيل الانصراف لموظف غير نشط' });
    }

    const branchId = employee.branch_id ?? employee.branchId ?? null;
    let branch: any = null;

    if (branchId) {
      const { data: branchData, error: branchError } = await supabase
        .from('branches')
        .select('id, name, wifi_bssid, bssid_1, bssid_2, latitude, longitude, geofence_radius')
        .eq('id', branchId)
        .maybeSingle();

      if (branchError) {
        // Do not hard-fail on branch fetch; proceed without branch to allow checkout
        console.warn('[attendance-check-out] Failed to fetch branch, proceeding without branch', branchError);
      }

      branch = branchData ?? null;
    } else if (employee.branch) {
      const { data: branchData, error: branchByNameError } = await supabase
        .from('branches')
        .select('id, name, wifi_bssid, bssid_1, bssid_2, latitude, longitude, geofence_radius')
        .ilike('name', employee.branch)
        .limit(1)
        .maybeSingle();

      if (branchByNameError) {
        // Do not hard-fail on branch fetch by name; proceed without branch
        console.warn('[attendance-check-out] Failed to fetch branch by name, proceeding without branch', branchByNameError);
      }

      branch = branchData ?? null;
    }

    let allowedBssids = new Set<string>();
    if (branch?.id) {
      const { records, error: bssidsError } = await fetchBranchBssids(supabase, branch.id);
      if (bssidsError) {
        console.warn('[attendance-check-out] Failed to fetch branch BSSIDs', bssidsError.message);
      }
      allowedBssids = parseAllowedBssids(branch, records);
    }

    const normalizedProvidedBssid = normalizeBssid(body.wifi_bssid);
    let isWifiValid = false;
    if (allowedBssids.size === 0) {
      isWifiValid = true;
    } else if (normalizedProvidedBssid && allowedBssids.has(normalizedProvidedBssid)) {
      isWifiValid = true;
    }

    const branchLat = toNumber(branch?.latitude) ?? toNumber(branch?.geo_lat);
    const branchLon = toNumber(branch?.longitude) ?? toNumber(branch?.geo_lon);
    const radiusMeters = toNumber(branch?.geofence_radius) ?? toNumber(branch?.geo_radius) ?? 200;

    const latitude = toNumber(body.latitude) ?? undefined;
    const longitude = toNumber(body.longitude) ?? undefined;
    const distance = haversineDistanceMeters(branchLat, branchLon, latitude, longitude);
    const isLocationValid = distance !== null && radiusMeters ? distance <= radiusMeters : true;
    const validationPassed = isWifiValid || isLocationValid;

    if (!validationPassed) {
      console.warn('[attendance-check-out] bypassing validation for employee', employeeId, {
        providedBssid: normalizedProvidedBssid,
        distance,
      });
    }

    const eventTimestamp = parseTimestamp(body.timestamp) ?? getCairoNow();

    // ✅ If attendance_id is provided, use it directly; otherwise find active attendance
    let activeAttendance: any = null;
    
    if (body.attendance_id) {
      const providedAttendanceId = body.attendance_id.trim();

      if (!isUuid(providedAttendanceId)) {
        console.warn(
          `[attendance-check-out] Non-UUID attendance_id provided (${providedAttendanceId}), falling back to active lookup`,
        );
      } else {
        console.log(`[attendance-check-out] Using provided attendance_id: ${providedAttendanceId}`);
        const { data: attendanceRecord, error: attendanceError } = await supabase
          .from('attendance')
          .select('id, check_in_time, check_out_time, status, work_hours, employee_id')
          .eq('id', providedAttendanceId)
          .maybeSingle();

        if (attendanceError) {
          console.error('[attendance-check-out] Failed to fetch attendance by ID, falling back to active lookup', attendanceError);
        } else if (!attendanceRecord) {
          console.warn('[attendance-check-out] Provided attendance record not found, falling back to active lookup');
        } else {
          // Verify the attendance belongs to this employee
          if (attendanceRecord.employee_id !== employeeId) {
            return response(403, { success: false, error: 'سجل الحضور لا ينتمي لهذا الموظف' });
          }

          // Check if already completed
          if (attendanceRecord.status === 'completed') {
            const completedCheckOut = parseTimestamp(attendanceRecord.check_out_time) ?? eventTimestamp;
            return response(200, {
              success: true,
              alreadyCheckedOut: true,
              message: 'لقد سجلت انصرافك بالفعل',
              attendance: attendanceRecord,
              time_context: {
                stored_timezone: 'UTC',
                display_timezone: 'Africa/Cairo',
                check_out_time_cairo: cairoDateTimeString(completedCheckOut),
              },
            });
          }

          activeAttendance = attendanceRecord;
        }
      }
    }

    if (!activeAttendance) {
      console.log(`[attendance-check-out] Finding active attendance for employee: ${employeeId}`);
      const { data: activeRecords, error: activeError } = await supabase
        .from('attendance')
        .select('id, check_in_time, status, work_hours')
        .eq('employee_id', employeeId)
        .eq('status', 'active')
        .order('check_in_time', { ascending: false })
        .limit(1);

      if (activeError) {
        console.error('[attendance-check-out] Failed to fetch active attendance', activeError);
        return response(500, { success: false, error: 'فشل التحقق من سجلات الحضور' });
      }

      activeAttendance = activeRecords?.[0] ?? null;
    }

    if (!activeAttendance) {
      const { data: completedRecords, error: completedError } = await supabase
        .from('attendance')
        .select('id, check_in_time, check_out_time, work_hours, status')
        .eq('employee_id', employeeId)
        .eq('status', 'completed')
        .order('check_out_time', { ascending: false })
        .limit(1);

      if (completedError) {
        console.error('[attendance-check-out] Failed to fetch completed attendance', completedError);
        return response(400, { success: false, error: 'لا يوجد سجل حضور نشط' });
      }

      const completed = completedRecords?.[0];
      if (completed) {
        const completedCheckOut = parseTimestamp(completed.check_out_time) ?? eventTimestamp;
        return response(200, {
          success: true,
          alreadyCheckedOut: true,
          message: 'لقد سجلت انصرافك بالفعل اليوم',
          attendance: completed,
          time_context: {
            stored_timezone: 'UTC',
            display_timezone: 'Africa/Cairo',
            check_out_time_cairo: cairoDateTimeString(completedCheckOut),
          },
        });
      }

      return response(400, {
        success: false,
        error: 'لا يوجد تسجيل حضور نشط لهذا اليوم',
        code: 'NO_ACTIVE_CHECKIN',
      });
    }

    const checkInTime = new Date(activeAttendance.check_in_time);
    const diffMs = eventTimestamp.getTime() - checkInTime.getTime();
    const hours = diffMs > 0 ? diffMs / (1000 * 60 * 60) : 0;
    const workHours = Math.max(hours, 0);
    const formattedHours = workHours.toFixed(2);

    console.log('[attendance-check-out] 📊 Calculating work hours:', {
      checkInTime: checkInTime.toISOString(),
      checkOutTime: eventTimestamp.toISOString(),
      diffMs,
      hours,
      formattedHours,
    });

    const updatePayload: JsonRecord = {
      check_out_time: eventTimestamp.toISOString(),
      status: 'completed',
      work_hours: formattedHours,
    };

    if (typeof latitude === 'number') {
      updatePayload.check_out_latitude = latitude;
    }
    if (typeof longitude === 'number') {
      updatePayload.check_out_longitude = longitude;
    }
    if (normalizedProvidedBssid) {
      updatePayload.check_out_wifi_bssid = normalizedProvidedBssid;
    }

    console.log(`[attendance-check-out] 🔄 Updating attendance record:`, {
      id: activeAttendance.id,
      employee_id: employeeId,
      payload: updatePayload,
    });

    // Try update with retry logic
    let { data: updatedAttendance, error: updateError } = await supabase
      .from('attendance')
      .update(updatePayload)
      .eq('id', activeAttendance.id)
      .select('id, check_in_time, check_out_time, work_hours, status')
      .maybeSingle();

    console.log(`[attendance-check-out] 📥 Update result:`, {
      success: !updateError,
      error: updateError?.message,
      errorCode: updateError?.code,
      errorDetails: updateError?.details,
      updated: updatedAttendance,
    });

    // If update failed, try without optional fields
    if (updateError) {
      console.log('[attendance-check-out] ⚠️ First update attempt failed, trying minimal update...');
      const minimalPayload: JsonRecord = {
        check_out_time: eventTimestamp.toISOString(),
        status: 'completed',
        work_hours: formattedHours,
      };
      
      const retry = await supabase
        .from('attendance')
        .update(minimalPayload)
        .eq('id', activeAttendance.id)
        .select('id, check_in_time, check_out_time, work_hours, status')
        .maybeSingle();
      
      console.log('[attendance-check-out] 🔄 Retry result:', {
        success: !retry.error,
        error: retry.error?.message,
        updated: retry.data,
      });
      
      if (!retry.error) {
        console.log('[attendance-check-out] ✅ Minimal update succeeded');
        updatedAttendance = retry.data;
        updateError = null;
      } else {
        console.error('[attendance-check-out] ❌ Minimal update also failed:', retry.error);
        updateError = retry.error;
      }
    }

    if (updateError) {
      console.error('[attendance-check-out] Failed to update attendance', updateError);
      console.error('[attendance-check-out] Update error details:', JSON.stringify(updateError));
      return response(500, { 
        success: false, 
        error: 'تعذر تسجيل الانصراف',
        details: updateError.message || 'Unknown error',
      });
    }

    if (!updatedAttendance) {
      console.error('[attendance-check-out] Update succeeded but no data returned');
      return response(500, { success: false, error: 'تعذر تسجيل الانصراف - لا توجد بيانات' });
    }

    console.log('[attendance-check-out] ✅ Attendance updated successfully:', updatedAttendance.id);

    if (updatedAttendance?.id && branch?.id) {
      const pulsePayload: JsonRecord = {
        attendance_id: updatedAttendance.id,
        employee_id: employeeId,
        branch_id: branch.id,
        timestamp: eventTimestamp.toISOString(),
        is_within_geofence: isLocationValid,
        status: 'OUT',
      };

      if (typeof latitude === 'number') pulsePayload.latitude = latitude;
      if (typeof longitude === 'number') pulsePayload.longitude = longitude;
      if (normalizedProvidedBssid) pulsePayload.bssid_address = normalizedProvidedBssid;
      pulsePayload.inside_geofence = isLocationValid;
      pulsePayload.distance_from_center =
        typeof distance === 'number'
          ? distance
          : (isLocationValid ? 0 : (typeof radiusMeters === 'number' ? radiusMeters : 0));

      const { error: pulseError } = await supabase.from('pulses').insert(pulsePayload);
      if (pulseError) {
        console.warn('[attendance-check-out] Failed to insert pulse', pulseError.message);
      }
    }

    // Update daily summary with checkout, total hours and salary
    try {
      // Get date/time strings in Cairo timezone correctly
      const formatter = new Intl.DateTimeFormat('en-CA', {
        timeZone: 'Africa/Cairo',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
      });
      const timeFormatter = new Intl.DateTimeFormat('en-US', {
        timeZone: 'Africa/Cairo',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: false,
      });
      const attendanceDate = formatter.format(eventTimestamp);
      const checkOutTimeStr = timeFormatter.format(eventTimestamp);
      const totalHoursNum = Number(formattedHours);
      const hourlyRate = Number((employee as any)?.hourly_rate ?? 0) || 0;
      const dailySalary = Number((totalHoursNum * hourlyRate).toFixed(2));

      console.log(`[attendance-check-out] Updating daily_attendance_summary:`, {
        employee_id: employeeId,
        attendance_date: attendanceDate,
        check_out_time: checkOutTimeStr,
        total_hours: totalHoursNum,
        hourly_rate: hourlyRate,
        daily_salary: dailySalary,
      });

      const upsertPayload: JsonRecord = {
        employee_id: employeeId,
        attendance_date: attendanceDate,
        check_out_time: checkOutTimeStr,
        total_hours: totalHoursNum.toString(),
        hourly_rate: hourlyRate.toString(),
        daily_salary: dailySalary.toString(),
        is_absent: false,
      };

      const { error: upsertErr } = await supabase
        .from('daily_attendance_summary')
        .upsert(upsertPayload, { onConflict: 'employee_id,attendance_date' });
      if (upsertErr) {
        console.warn('[attendance-check-out] daily_attendance_summary upsert failed', upsertErr.message);
        console.warn('[attendance-check-out] Upsert error details:', JSON.stringify(upsertErr));
      } else {
        console.log('[attendance-check-out] ✅ daily_attendance_summary updated successfully');
      }
    } catch (e) {
      console.warn('[attendance-check-out] daily_attendance_summary upsert exception', (e as Error).message);
      // Don't fail the whole request if summary update fails
    }

    // ✅ Always return success if attendance was updated, even if summary update failed
    console.log('[attendance-check-out] ✅ Returning success response');
    return response(200, {
      success: true,
      message: validationPassed ? 'تم تسجيل الانصراف بنجاح' : 'تم تسجيل الانصراف بدون تحقق موقع/واي فاي',
      attendance: updatedAttendance,
      time_context: {
        stored_timezone: 'UTC',
        display_timezone: 'Africa/Cairo',
        check_out_time_cairo: cairoDateTimeString(eventTimestamp),
      },
      validation: {
        wifi: isWifiValid,
        location: isLocationValid,
      },
    });
  } catch (error) {
    console.error('[attendance-check-out] Unexpected error', error);
    return response(500, { success: false, error: 'Internal server error' });
  }
});
