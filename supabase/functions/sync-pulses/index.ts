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

function resolveIsoTimestamp(input?: unknown): string {
  if (input instanceof Date) {
    if (!Number.isNaN(input.getTime())) {
      return input.toISOString();
    }
  } else if (typeof input === 'number') {
    const fromNumber = new Date(input);
    if (!Number.isNaN(fromNumber.getTime())) {
      return fromNumber.toISOString();
    }
  } else if (typeof input === 'string') {
    const trimmed = input.trim();
    if (trimmed) {
      const fromString = new Date(trimmed);
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

      const pulsePayload: JsonRecord = {
        employee_id: employeeId,
        branch_id: branchId ?? branch?.id ?? null,
        timestamp,
      };

      if (attendanceId) (pulsePayload as any).attendance_id = attendanceId;
      if (latitude !== undefined) pulsePayload.latitude = latitude;
      if (longitude !== undefined) pulsePayload.longitude = longitude;
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

    return response(200, {
      success: errors.length === 0,
      inserted,
      failed: errors.length,
      errors,
    });
  } catch (error) {
    console.error('[sync-pulses] Unexpected error', error);
    return response(500, { success: false, error: 'Internal server error' });
  }
});
