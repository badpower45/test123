// @ts-nocheck
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

type JsonRecord = Record<string, unknown>;

type PulseInput = {
  employee_id?: string;
  branch_id?: string;
  latitude?: number;
  longitude?: number;
  wifi_bssid?: string;
  validation_method?: string;
  inside_geofence?: boolean;
  timestamp?: string | number;
  status?: string;
  source?: string;
  // Optional distance provided by client in meters
  distance_from_center?: number;
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

function resolveIsoTimestamp(input?: unknown): string {
  if (input instanceof Date) {
    if (!Number.isNaN(input.getTime())) {
      return input.toISOString();
    }
  } else if (typeof input === 'number') {
    const normalized = input < 1e12 ? input * 1000 : input;
    const fromNumber = new Date(normalized);
    if (!Number.isNaN(fromNumber.getTime())) {
      return fromNumber.toISOString();
    }
  } else if (typeof input === 'string') {
    const trimmed = input.trim();
    if (trimmed) {
      const normalized = trimmed.replace(' ', 'T');
      const hasTimezone = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(normalized);
      const fromString = hasTimezone
        ? new Date(normalized)
        : (parseNaiveCairoTimestamp(normalized) ?? new Date(normalized));
      if (!Number.isNaN(fromString.getTime())) {
        return fromString.toISOString();
      }
    }
  }

  return new Date().toISOString();
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

async function fetchBranchBssids(supabase: any, branchId: string): Promise<string[]> {
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
        return [];
      }
      return (fallback.data ?? []).map((record: any) => normalizeBssid(record?.bssid_address ?? record?.bssidAddress ?? record?.wifi_bssid)).filter(Boolean) as string[];
    }

    if (error) {
      return [];
    }

    return (data ?? []).map((record: any) => normalizeBssid(record?.bssid_address ?? record?.bssidAddress ?? record?.wifi_bssid)).filter(Boolean) as string[];
  } catch (_) {
    return [];
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
    const body = await req.json();
    const payload: PulseInput[] = Array.isArray(body?.pulses)
      ? (body.pulses as PulseInput[])
      : Array.isArray(body)
        ? (body as PulseInput[])
        : [body as PulseInput];

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseKey =
      Deno.env.get('SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !supabaseKey) {
      console.error('[sync-pulses] Missing Supabase credentials');
      return response(500, { success: false, error: 'Server configuration error' });
    }

    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: { persistSession: false },
    });

    const employeeCache = new Map<string, any>();
    const branchCache = new Map<string, any>();
    const branchBssidCache = new Map<string, Set<string>>();
    const breakActiveCache = new Map<string, boolean>();

    let inserted = 0;
    const errors: Array<{ employeeId?: string; error: string }> = [];

    for (const item of payload) {
      const employeeId = item?.employee_id?.trim();
      if (!employeeId) {
        errors.push({ error: 'Missing employee_id' });
        continue;
      }

      let employee = employeeCache.get(employeeId);
      if (!employee) {
        const { data, error } = await supabase
          .from('employees')
          .select('id, branch_id, branch, is_active')
          .eq('id', employeeId)
          .maybeSingle();

        if (error || !data) {
          errors.push({ employeeId, error: 'Employee not found' });
          continue;
        }

        if (data.is_active === false) {
          errors.push({ employeeId, error: 'Inactive employee' });
          continue;
        }

        employeeCache.set(employeeId, data);
        employee = data;
      }

      let attendanceIdRaw = (item as any).attendance_id ?? null;
      let attendanceId: string | null = null;
      // Validate attendance_id format (UUID v4 simple check) and ignore invalid placeholder values
      if (typeof attendanceIdRaw === 'string') {
        const trimmed = attendanceIdRaw.trim();
        // Reject obvious placeholders like 'pending_local', 'local', 'temp', or empty
        const isPlaceholder = /(pending|local|temp|dummy)/i.test(trimmed) || trimmed.length < 8;
        const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
        if (!isPlaceholder && uuidRegex.test(trimmed)) {
          attendanceId = trimmed;
        }
      }
      let branchId = item.branch_id ?? employee.branch_id ?? employee.branchId ?? null;
      let branch = branchId ? branchCache.get(branchId) : null;

      if (!branch && branchId) {
        const { data, error } = await supabase
          .from('branches')
          .select('id, name, wifi_bssid, bssid_1, bssid_2, latitude, longitude, geofence_radius')
          .eq('id', branchId)
          .maybeSingle();

        if (!error && data) {
          branchCache.set(branchId, data);
          branch = data;
        }
      }

      if (!branch && !branchId && employee.branch) {
        const { data, error } = await supabase
          .from('branches')
          .select('id, name, wifi_bssid, bssid_1, bssid_2, latitude, longitude, geofence_radius')
          .ilike('name', employee.branch)
          .limit(1)
          .maybeSingle();

        if (!error && data) {
          branchId = data.id;
          branchCache.set(branchId, data);
          branch = data;
        }
      }

      // If attendance_id not provided or invalid, try to link to active attendance for today
      if (!attendanceId) {
        const { data: activeRecords } = await supabase
          .from('attendance')
          .select('id, branch_id, check_in_time, status')
          .eq('employee_id', employeeId)
          .eq('status', 'active')
          .order('check_in_time', { ascending: false })
          .limit(1);
        const active = activeRecords?.[0];
        if (active) {
          attendanceId = active.id;
          if (!branchId) branchId = active.branch_id ?? branchId;
        }
      }

      // Extra fallback: if still no branchId, try the most recent attendance (any status)
      if (!branchId) {
        try {
          const { data: recentAttendances } = await supabase
            .from('attendance')
            .select('id, branch_id, check_in_time')
            .eq('employee_id', employeeId)
            .order('check_in_time', { ascending: false })
            .limit(1);
          const recent = recentAttendances?.[0];
          if (recent?.branch_id) {
            branchId = recent.branch_id;
          }
        } catch (_) {
          // ignore
        }
      }

      const allowedBssids = new Set<string>();
      if (branch?.id) {
        const cacheKey = branch.id as string;
        let cached = branchBssidCache.get(cacheKey);
        if (!cached) {
          const fetched = await fetchBranchBssids(supabase, branch.id);
          cached = new Set(fetched);
          const primary = branch.wifi_bssid ?? branch.bssid_1;
          const secondary = branch.bssid_2;
          const addFromString = (value?: string | null) => {
            if (!value) return;
            value
              .split(/[\s,\n,]+/)
              .map((part: string) => normalizeBssid(part))
              .filter(Boolean)
              .forEach((val) => cached!.add(val as string));
          };
          addFromString(primary);
          addFromString(secondary);
          branchBssidCache.set(cacheKey, cached);
        }
        cached.forEach((value) => allowedBssids.add(value));
      }

      const normalizedBssid = normalizeBssid(item.wifi_bssid);
      let wifiValid = false;
      if (allowedBssids.size === 0) {
        wifiValid = true;
      } else if (normalizedBssid && allowedBssids.has(normalizedBssid)) {
        wifiValid = true;
      }

      const latitude = toNumber(item.latitude) ?? undefined;
      const longitude = toNumber(item.longitude) ?? undefined;

      const branchLat = toNumber(branch?.latitude) ?? toNumber(branch?.geo_lat);
      const branchLon = toNumber(branch?.longitude) ?? toNumber(branch?.geo_lon);
      const radius = toNumber(branch?.geofence_radius) ?? toNumber(branch?.geo_radius) ?? 200;

      const distance = haversineDistanceMeters(branchLat, branchLon, latitude, longitude);
      const locationValid = distance !== null && radius ? distance <= radius : true;

      // If employee is on ACTIVE break, force inside_geofence = true
      let breakActive = breakActiveCache.get(employeeId);
      if (breakActive === undefined) {
        try {
          const { data: activeBreaks, error: breakErr } = await supabase
            .from('breaks')
            .select('id')
            .eq('employee_id', employeeId)
            .eq('status', 'ACTIVE')
            .limit(1);
          breakActive = !!(activeBreaks && activeBreaks.length > 0);
          breakActiveCache.set(employeeId, breakActive);
        } catch (_) {
          breakActive = false;
          breakActiveCache.set(employeeId, false);
        }
      }

      const isWithinGeofence = breakActive
        ? true
        : (typeof item.inside_geofence === 'boolean'
            ? item.inside_geofence
            : (wifiValid || locationValid));

      // Prefer server-computed distance; fall back to client-provided distance if server cannot compute
      const clientDistanceRaw = toNumber((item as any)?.distance_from_center);
      const resolvedDistance =
        typeof distance === 'number'
          ? distance
          : (typeof clientDistanceRaw === 'number'
              ? clientDistanceRaw
              : (isWithinGeofence
                  ? 0
                  : (typeof radius === 'number' && Number.isFinite(radius) ? radius : 0)));

      const timestamp = resolveIsoTimestamp(item.timestamp);

      const validationMethod = (item.validation_method?.toString().trim())
        ? item.validation_method!.toString().trim().toUpperCase()
        : (wifiValid
            ? 'WIFI'
            : (latitude !== undefined && longitude !== undefined
                ? 'LOCATION'
                : 'UNKNOWN'));

      const pulsePayload: JsonRecord = {
        employee_id: employeeId,
        branch_id: branchId ?? branch?.id ?? null,
        timestamp,
      };

      if (attendanceId) (pulsePayload as any).attendance_id = attendanceId;
      if (latitude !== undefined) pulsePayload.latitude = latitude;
      if (longitude !== undefined) pulsePayload.longitude = longitude;
      if (normalizedBssid) pulsePayload.wifi_bssid = normalizedBssid;
      pulsePayload.validation_method = validationMethod;
      // Map to actual column name in schema
      (pulsePayload as any).is_within_geofence = isWithinGeofence;
      (pulsePayload as any).inside_geofence = isWithinGeofence;
      (pulsePayload as any).distance_from_center = resolvedDistance;

      const { error: insertError } = await supabase.from('pulses').insert(pulsePayload);
      if (insertError) {
        console.error('[sync-pulses] Failed to insert pulse', insertError);
        errors.push({ employeeId, error: insertError.message ?? 'Insert failed', code: insertError.code ?? 'INSERT_FAILED', attendance_id_sent: (item as any).attendance_id ?? null });
        continue;
      }

      inserted += 1;
    }

    // 🚀 PHASE 6+: TIME RECONCILIATION
    // Check for time gaps in pulses and auto-close abandoned sessions
    const reconciliationResults = await reconcileAttendanceSessions(supabase, payload);

    return response(200, {
      success: errors.length === 0,
      inserted,
      failed: errors.length,
      errors,
      reconciliation: reconciliationResults,
    });
  } catch (error) {
    console.error('[sync-pulses] Unexpected error', error);
    return response(500, { success: false, error: 'Internal server error' });
  }
});

/**
 * 🚀 TIME RECONCILIATION: Auto-close only when last pulse is stale
 *
 * Logic:
 * 1. For each unique employee in uploaded pulses
 * 2. Get their active attendance session
 * 3. Get latest pulse timestamp for that session
 * 4. If (now - latestPulse) > 10 minutes, close at latestPulse
 *
 * NOTE:
 * We intentionally ignore historical internal gaps to avoid false closures when
 * connectivity resumes later in the same session.
 */
async function reconcileAttendanceSessions(
  supabase: any,
  uploadedPulses: PulseInput[]
): Promise<{ checked: number; closed: number; sessions: string[] }> {
  const uniqueEmployees = new Set<string>();
  uploadedPulses.forEach(pulse => {
    if (pulse.employee_id) uniqueEmployees.add(pulse.employee_id);
  });

  let checkedCount = 0;
  let closedCount = 0;
  const closedSessions: string[] = [];

  for (const employeeId of uniqueEmployees) {
    try {
      // Get active attendance for this employee
      const { data: activeAttendance } = await supabase
        .from('attendance')
        .select('id, check_in_time, employee_id')
        .eq('employee_id', employeeId)
        .eq('status', 'active')
        .order('check_in_time', { ascending: false })
        .limit(1)
        .maybeSingle();

      if (!activeAttendance) continue;

      checkedCount++;
      const attendanceId = activeAttendance.id;
      const checkInTime = new Date(activeAttendance.check_in_time);

      // Get ALL pulses for this session, sorted by time
      const { data: pulses } = await supabase
        .from('pulses')
        .select('id, timestamp, is_within_geofence, distance_from_center')
        .eq('attendance_id', attendanceId)
        .order('timestamp', { ascending: true });

      if (!pulses || pulses.length === 0) continue;

      const MAX_GAP_MS = 10 * 60 * 1000;
      const latestPulse = pulses[pulses.length - 1];
      const latestPulseTime = new Date(latestPulse.timestamp);

      if (Number.isNaN(latestPulseTime.getTime())) {
        console.warn(`[Reconciliation] Invalid latest pulse timestamp for session ${attendanceId}`);
        continue;
      }

      const gapFromNowMs = Date.now() - latestPulseTime.getTime();
      if (gapFromNowMs <= MAX_GAP_MS) {
        console.log(`[Reconciliation] ✅ Session ${attendanceId} latest pulse is fresh - OK`);
        continue;
      }

      if (!Number.isNaN(checkInTime.getTime()) && latestPulseTime < checkInTime) {
        console.warn(
          `[Reconciliation] Skipping auto-close: latest pulse (${latestPulseTime.toISOString()}) before check-in (${checkInTime.toISOString()})`
        );
        continue;
      }

      const closeAt = !Number.isNaN(checkInTime.getTime()) && latestPulseTime < checkInTime
        ? checkInTime
        : latestPulseTime;

      console.log(`[Reconciliation] Stale session detected for employee ${employeeId}: ${gapFromNowMs / 1000 / 60} min since latest pulse`);
      console.log(`[Reconciliation] Closing session at latest pulse: ${closeAt.toISOString()}`);

      const { error: updateError } = await supabase
        .from('attendance')
        .update({
          check_out_time: closeAt.toISOString(),
          status: 'completed',
          notes: `Auto-closed by Time Reconciliation: ${gapFromNowMs / 1000 / 60} min stale since latest pulse`,
        })
        .eq('id', attendanceId);

      if (!updateError) {
        closedCount++;
        closedSessions.push(attendanceId);
        console.log(`[Reconciliation] ✅ Session ${attendanceId} auto-closed`);
      } else {
        console.error(`[Reconciliation] ❌ Failed to close session ${attendanceId}:`, updateError);
      }

    } catch (err) {
      console.error(`[Reconciliation] Error processing employee ${employeeId}:`, err);
    }
  }

  return {
    checked: checkedCount,
    closed: closedCount,
    sessions: closedSessions,
  };
}
