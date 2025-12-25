// @ts-nocheck
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

type JsonRecord = Record<string, unknown>;

type AttendanceCheckInPayload = {
  employee_id?: string;
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

function parseTimestamp(input: unknown): Date | null {
  if (!input) return null;
  if (input instanceof Date) {
    return Number.isNaN(input.getTime()) ? null : input;
  }
  if (typeof input === 'number') {
    const date = new Date(input);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (typeof input === 'string') {
    const trimmed = input.trim();
    if (!trimmed) return null;
    const date = new Date(trimmed);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function cairoDateString(date: Date): string {
  // Get date string in Cairo timezone
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Africa/Cairo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  return formatter.format(date);
}

function cairoTimeString(date: Date): string {
  // Get time string in Cairo timezone (HH:mm:ss)
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Africa/Cairo',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  });
  return formatter.format(date);
}

function isSameCairoDay(target: string | Date, compare: Date): boolean {
  const targetDate = parseTimestamp(target) ?? new Date(target);
  if (Number.isNaN(targetDate.getTime())) return false;
  return cairoDateString(targetDate) === cairoDateString(compare);
}

function parseAllowedBssids(branch: any, bssidRecords: any[]): Set<string> {
  const allowed = new Set<string>();

  const primary = normalizeBssid(branch?.bssid_1 ?? branch?.wifi_bssid ?? branch?.primary_bssid);
  if (primary) {
    const split = primary
      .split(/[\n,\s]+/)
      .map((part) => normalizeBssid(part))
      .filter(Boolean) as string[];
    for (const item of split) allowed.add(item);
  }

  const secondary = normalizeBssid(branch?.bssid_2 ?? branch?.secondary_bssid);
  if (secondary) {
    allowed.add(secondary);
  }

  bssidRecords.forEach((record) => {
    const fromRecord = normalizeBssid(record?.bssid_address ?? record?.bssidAddress ?? record?.wifi_bssid);
    if (fromRecord) {
      allowed.add(fromRecord);
    }
  });

  return allowed;
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

  const R = 6371000; // Earth radius in meters
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

function parseShiftTime(value?: string | null): string | null {
  if (!value) return null;
  if (/^\d{2}:\d{2}$/.test(value)) {
    return value;
  }
  try {
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) {
      return date.toISOString().split('T')[1]?.slice(0, 5) ?? null;
    }
  } catch (_) {
    // ignore
  }
  return null;
}

function isWithinShift(current: Date, start?: string | null, end?: string | null): boolean {
  const startTime = parseShiftTime(start);
  const endTime = parseShiftTime(end);
  if (!startTime || !endTime) {
    return true;
  }

  const [startHour, startMinute] = startTime.split(':').map(Number);
  const [endHour, endMinute] = endTime.split(':').map(Number);

  const cairoTime = new Date(
    current.toLocaleString('en-US', { timeZone: 'Africa/Cairo' }),
  );

  const currentMinutes = cairoTime.getHours() * 60 + cairoTime.getMinutes();
  const startMinutes = startHour * 60 + startMinute;
  const endMinutes = endHour * 60 + endMinute;

  if (startMinutes <= endMinutes) {
    return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
  }

  // Overnight shift
  return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
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
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return response(405, { success: false, error: 'Method not allowed' });
  }

  try {
    const body = (await req.json()) as AttendanceCheckInPayload;
    const employeeId = body.employee_id?.trim();

    if (!employeeId) {
      return response(400, { success: false, error: 'Employee ID is required' });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || 'https://bbxuyuaemigrqsvsnxkj.supabase.co';
    const supabaseKey =
      Deno.env.get('SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !supabaseKey) {
      console.error('[attendance-check-in] Missing Supabase credentials');
      return response(500, { success: false, error: 'Server configuration error' });
    }

    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: { persistSession: false },
    });

    const { data: employee, error: employeeError } = await supabase
      .from('employees')
      .select('id, full_name, role, branch_id, branch, shift_start_time, shift_end_time, hourly_rate, is_active')
      .eq('id', employeeId)
      .maybeSingle();

    if (employeeError) {
      console.error('[attendance-check-in] Failed to fetch employee', employeeError);
      return response(500, { success: false, error: 'Failed to fetch employee data' });
    }

    if (!employee) {
      return response(404, { success: false, error: 'Employee not found' });
    }

    if (employee.is_active === false) {
      return response(403, { success: false, error: 'لا يمكن تسجيل الحضور لموظف غير نشط' });
    }

    // Use current time directly - Supabase stores in UTC
    const cairoNow = new Date();
    // Shift validation disabled - allow check-in at any time
    // const withinShift = isWithinShift(cairoNow, employee.shift_start_time, employee.shift_end_time);
    // console.log(`[attendance-check-in] Shift check: current=${cairoNow.toISOString()}, start=${employee.shift_start_time}, end=${employee.shift_end_time}, withinShift=${withinShift}`);
    // 
    // if (!withinShift) {
    //   const startTime = parseShiftTime(employee.shift_start_time);
    //   const endTime = parseShiftTime(employee.shift_end_time);
    //   console.log(`[attendance-check-in] Rejecting check-in: outside shift hours`);
    //   return response(403, {
    //     success: false,
    //     error: 'لا يمكن تسجيل الحضور خارج وقت الشيفت المحدد',
    //     message: startTime && endTime
    //       ? `وقت الشيفت من ${startTime} إلى ${endTime}`
    //       : 'مواعيد الشيفت غير محددة لهذا الموظف',
    //     code: 'OUTSIDE_SHIFT_HOURS',
    //   });
    // }

    const branchId = employee.branch_id ?? employee.branchId ?? null;
    let branch: any = null;

    if (branchId) {
      const { data: branchData, error: branchError } = await supabase
        .from('branches')
        .select('id, name, wifi_bssid, bssid_1, bssid_2, latitude, longitude, geofence_radius, distance_from_radius')
        .eq('id', branchId)
        .maybeSingle();

      if (branchError) {
        // Do not hard-fail if branch cannot be fetched; proceed without branch
        console.warn('[attendance-check-in] Failed to fetch branch, proceeding without branch', branchError);
      }

      branch = branchData ?? null;
    } else if (employee.branch) {
      const { data: branchData, error: branchByNameError } = await supabase
        .from('branches')
        .select('id, name, wifi_bssid, bssid_1, bssid_2, latitude, longitude, geofence_radius, distance_from_radius')
        .ilike('name', employee.branch)
        .limit(1)
        .maybeSingle();

      if (branchByNameError) {
        // Do not hard-fail if branch cannot be fetched by name; proceed without branch
        console.warn('[attendance-check-in] Failed to fetch branch by name, proceeding without branch', branchByNameError);
      }

      branch = branchData ?? null;
    }

    let allowedBssids = new Set<string>();
    if (branch?.id) {
      const { records, error: bssidsError } = await fetchBranchBssids(supabase, branch.id);
      if (bssidsError) {
        console.warn('[attendance-check-in] Failed to fetch branch BSSIDs', bssidsError.message);
      }
      allowedBssids = parseAllowedBssids(branch, records);
    }

    const normalizedProvidedBssid = normalizeBssid(body.wifi_bssid);

    let isWifiValid = false;
    if (allowedBssids.size === 0) {
      isWifiValid = true; // No WiFi configured -> treat as pass
    } else if (normalizedProvidedBssid && allowedBssids.has(normalizedProvidedBssid)) {
      isWifiValid = true;
    }

    const branchLat = toNumber(branch?.latitude) ?? toNumber(branch?.geo_lat);
    const branchLon = toNumber(branch?.longitude) ?? toNumber(branch?.geo_lon);
    const configuredRadius = toNumber(branch?.geofence_radius) ?? toNumber(branch?.geo_radius);
    const distanceFromRadius = toNumber(branch?.distance_from_radius) ?? 100;

    const latitude = toNumber(body.latitude) ?? undefined;
    const longitude = toNumber(body.longitude) ?? undefined;

    const distance = haversineDistanceMeters(branchLat, branchLon, latitude, longitude);
    
    // Check-in is ONLY allowed within geofence_radius (strict)
    let isWithinGeofence = false;
    // Pulses can be recorded up to geofence_radius + distance_from_radius
    let isWithinPulseRange = false;
    
    if (
      typeof branchLat === 'number' && typeof branchLon === 'number' &&
      typeof configuredRadius === 'number' && configuredRadius > 0 &&
      distance !== null
    ) {
      isWithinGeofence = distance <= configuredRadius;
      const maxPulseDistance = configuredRadius + distanceFromRadius;
      isWithinPulseRange = distance <= maxPulseDistance;
    }
    
    // Check-in validation: must be within geofence OR valid WiFi
    const validationPassed = isWifiValid || isWithinGeofence;

    if (!validationPassed) {
      // Reject check-in if outside allowed range
      return response(403, {
        success: false,
        error: 'لا يمكن تسجيل الحضور - أنت خارج المنطقة المسموح بها',
        message: distance !== null 
          ? `المسافة من الفرع: ${Math.round(distance)} متر. المسموح: ${configuredRadius} متر`
          : 'لم يتم تحديد موقعك بشكل صحيح',
        code: 'OUTSIDE_ALLOWED_AREA',
        distance,
        allowed_radius: configuredRadius,
      });
    }

    // First check for any existing attendance today (regardless of status)
    const todayDate = cairoDateString(cairoNow);
    const { data: existingToday, error: existingTodayError } = await supabase
      .from('attendance')
      .select('id, check_in_time, check_out_time, status, work_hours')
      .eq('employee_id', employeeId)
      .eq('date', todayDate)
      .order('check_in_time', { ascending: false })
      .limit(1);

    if (existingTodayError) {
      console.warn('[attendance-check-in] Failed to check existing attendance by date', existingTodayError);
    }

    // If there's an existing record for today
    const existingRecord = existingToday?.[0];
    if (existingRecord) {
      // If it's active, return already checked in
      if (existingRecord.status === 'active') {
        const checkInTime = new Date(existingRecord.check_in_time);
        const timeDiff = cairoNow.getTime() - checkInTime.getTime();
        const hoursAgo = Math.floor(timeDiff / (1000 * 60 * 60));
        const minutesAgo = Math.floor((timeDiff % (1000 * 60 * 60)) / (1000 * 60));
        
        let timeDisplay = '';
        if (hoursAgo > 0) {
          timeDisplay = `منذ ${hoursAgo} ساعة`;
        } else if (minutesAgo > 0) {
          timeDisplay = `منذ ${minutesAgo} دقيقة`;
        } else {
          timeDisplay = 'منذ لحظات';
        }
        
        console.log(`[attendance-check-in] Employee ${employeeId} already has active attendance: ${existingRecord.id}`);
        
        return response(409, {
          success: false,
          alreadyCheckedIn: true,
          error: '⚠️ لديك حضور نشط بالفعل!',
          message: `تم تسجيل الحضور ${timeDisplay}\nيجب تسجيل الانصراف أولاً`,
          attendance: existingRecord,
          check_in_time: existingRecord.check_in_time,
          time_since_check_in: timeDisplay,
        });
      }
      
      // If it's completed, reactivate it (allow re-check-in after check-out)
      if (existingRecord.status === 'completed' && existingRecord.check_out_time) {
        console.log(`[attendance-check-in] Employee ${employeeId} re-checking in after checkout, updating existing record`);
        
        const eventTimestamp = parseTimestamp(body.timestamp) ?? cairoNow;
        const { data: updatedRecord, error: updateError } = await supabase
          .from('attendance')
          .update({
            check_in_time: eventTimestamp.toISOString(),
            check_out_time: null,
            status: 'active',
            work_hours: null,
          })
          .eq('id', existingRecord.id)
          .select('id, check_in_time, status, employee_id')
          .maybeSingle();
        
        if (updateError) {
          console.error('[attendance-check-in] Failed to reactivate attendance', updateError);
          return response(500, { success: false, error: 'فشل إعادة تسجيل الحضور' });
        }
        
        return response(201, {
          success: true,
          message: 'تم إعادة تسجيل الحضور بنجاح',
          attendance: updatedRecord,
          reactivated: true,
          validation: {
            wifi: isWifiValid,
            location: isWithinGeofence,
            distance: distance !== null ? Math.round(distance) : null,
          },
        });
      }
    }

    const eventTimestamp = parseTimestamp(body.timestamp) ?? cairoNow;

    const insertPayload: JsonRecord = {
      employee_id: employeeId,
      branch_id: branch?.id ?? null,
      check_in_time: eventTimestamp.toISOString(),
      date: todayDate,
      status: 'active',
    };

    if (typeof latitude === 'number') {
      insertPayload.latitude = latitude;
    }
    if (typeof longitude === 'number') {
      insertPayload.longitude = longitude;
    }
    insertPayload.is_within_geofence = Boolean(isWithinGeofence);
    if (normalizedProvidedBssid) {
      insertPayload.check_in_wifi_bssid = normalizedProvidedBssid;
    }

    let { data: insertData, error: insertError } = await supabase
      .from('attendance')
      .insert(insertPayload)
      .select('id, check_in_time, status, employee_id')
      .maybeSingle();

    // Retry on schema mismatches (columns not existing)
    if (insertError && (
      insertError.message?.includes('check_in_wifi_bssid') ||
      insertError.message?.includes('column "date" does not exist') ||
      insertError.message?.includes('branch_id')
    )) {
      console.log('[attendance-check-in] Schema mismatch, retrying without optional columns...');
      delete insertPayload.check_in_wifi_bssid;
      delete insertPayload.date;
      delete insertPayload.branch_id;  // Remove branch_id if column doesn't exist
      const retry = await supabase
        .from('attendance')
        .insert(insertPayload)
        .select('id, check_in_time, status, employee_id')
        .maybeSingle();
      insertData = retry.data;
      insertError = retry.error;
    }

    if (insertError) {
      console.error('[attendance-check-in] Failed to insert attendance', insertError);
      // Surface more diagnostic info while keeping Arabic friendly message
      const dbMessage = insertError.message ?? 'DB insert error';
      const constraintMatch = dbMessage.match(/violates unique constraint "([^"]+)"/);
      const constraint = constraintMatch ? constraintMatch[1] : undefined;
      return response(500, {
        success: false,
        error: 'تعذر تسجيل الحضور',
        message: 'حدث خطأ أثناء حفظ سجل الحضور في قاعدة البيانات',
        code: insertError.code ?? 'ATTENDANCE_INSERT_FAILED',
        db_message: dbMessage,
        constraint,
        payload_attempted: insertPayload,
      });
    }

    if (insertData?.id && branch?.id && isWithinPulseRange) {
      const pulsePayload: JsonRecord = {
        attendance_id: insertData.id,
        employee_id: employeeId,
        branch_id: branch.id,
        timestamp: eventTimestamp.toISOString(),
        is_within_geofence: isWithinGeofence,
        inside_geofence: isWithinGeofence,
      };

      if (typeof latitude === 'number') pulsePayload.latitude = latitude;
      if (typeof longitude === 'number') pulsePayload.longitude = longitude;
      if (typeof distance === 'number') (pulsePayload as any).distance_from_center = distance;
      if (normalizedProvidedBssid) pulsePayload.bssid_address = normalizedProvidedBssid;

      const { error: pulseError } = await supabase.from('pulses').insert(pulsePayload);
      if (pulseError) {
        console.warn('[attendance-check-in] Failed to insert pulse', pulseError.message);
      }

      // Log geofence violation when outside geofence_radius but still within pulse range
      if (
        isWithinGeofence === false &&
        typeof configuredRadius === 'number' && configuredRadius > 0 &&
        typeof distance === 'number'
      ) {
        const violationPayload: JsonRecord = {
          attendance_id: insertData.id,
          employee_id: employeeId,
          branch_id: branch.id,
          timestamp: eventTimestamp.toISOString(),
          latitude,
          longitude,
          distance_from_center: distance,
          radius_meters: configuredRadius,
        };
        if (normalizedProvidedBssid) violationPayload.bssid_address = normalizedProvidedBssid;

        const { error: vioError } = await supabase
          .from('geofence_violations')
          .insert(violationPayload);
        if (vioError) {
          console.warn('[attendance-check-in] Failed to log geofence violation', vioError.message);
        }
      }
    }

    // Upsert daily attendance summary so salary starts counting immediately
    try {
      const attendanceDate = cairoDateString(eventTimestamp);
      const checkInTimeStr = cairoTimeString(eventTimestamp);
      const hourlyRate = Number((employee as any)?.hourly_rate ?? 0) || 0;
      const upsertPayload: JsonRecord = {
        employee_id: employeeId,
        attendance_date: attendanceDate,
        check_in_time: checkInTimeStr,
        hourly_rate: hourlyRate,
        is_absent: false,
        is_on_leave: false,
      };
      const { error: upsertErr } = await supabase
        .from('daily_attendance_summary')
        .upsert(upsertPayload, { onConflict: 'employee_id,attendance_date' });
      if (upsertErr) {
        console.warn('[attendance-check-in] daily_attendance_summary upsert failed', upsertErr.message);
      }
    } catch (e) {
      console.warn('[attendance-check-in] daily_attendance_summary upsert exception', (e as Error).message);
    }

    return response(201, {
      success: true,
      message: 'تم تسجيل الحضور بنجاح',
      attendance: insertData,
      validation: {
        wifi: isWifiValid,
        location: isWithinGeofence,
        distance: distance !== null ? Math.round(distance) : null,
      },
    });
  } catch (error) {
    console.error('[attendance-check-in] Unexpected error', error);
    return response(500, { success: false, error: 'Internal server error' });
  }
});
