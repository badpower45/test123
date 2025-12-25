// @ts-nocheck
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

type JsonRecord = Record<string, unknown>;

type BreakAction = 'request' | 'start' | 'end' | 'list' | 'delete_rejected';

type BreakPayload = {
  action?: BreakAction;
  employee_id?: string;
  duration_minutes?: number;
  reason?: string;
  break_id?: string;
  timestamp?: string | number;
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

function jsonResponse(status: number, body: JsonRecord) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function getSupabase() {
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseKey =
    Deno.env.get('SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!supabaseUrl || !supabaseKey) {
    throw new Error('Missing Supabase credentials');
  }

  return createClient(supabaseUrl, supabaseKey, { auth: { persistSession: false } });
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

function mapBreakRow(row: any): Record<string, unknown> {
  if (!row) return {};
  return {
    id: row.id,
    employee_id: row.employee_id,
    // Map database duration_minutes to requested_duration_minutes for client
    requested_duration_minutes: row.duration_minutes ?? null,
    // Calculate actual duration from break_start and break_end (actual schema columns)
    actual_duration_minutes: row.break_end && row.break_start
      ? Math.max(
          0,
          Math.round(
            (new Date(row.break_end).getTime() - new Date(row.break_start).getTime()) /
              (1000 * 60),
          ),
        )
      : null,
    status: row.status,
    // Map database columns (break_start/break_end) to client-expected names (start_time/end_time)
    start_time: row.break_start ?? null,
    end_time: row.break_end ?? null,
    reason: row.reason ?? null,
    notes: row.notes ?? null,
    approved_by: row.approved_by ?? null,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse(405, { success: false, error: 'Method not allowed' });
  }

  try {
    const payload = (await req.json()) as BreakPayload;
    const action = payload.action ?? 'request';

    const supabase = getSupabase();

    switch (action) {
      case 'request': {
        const employeeId = payload.employee_id?.trim();
        const duration = Number(payload.duration_minutes ?? 0);
            // 'reason' column does not exist in current breaks schema; ignore if provided
            const reason = undefined;

        if (!employeeId) {
          return jsonResponse(400, { success: false, error: 'Employee ID is required' });
        }
        if (!Number.isFinite(duration) || duration <= 0) {
          return jsonResponse(400, {
            success: false,
            error: 'مدة الاستراحة مطلوبة ويجب أن تكون أطول من صفر',
          });
        }

        // ✅ FIX: Use correct column names from actual schema
        // Note: break_start is NOT NULL in schema, so we set it to request time
        // The actual break start will be recorded in a separate tracking system or via start_time later
        const now = getCairoNow().toISOString();
        const { data, error } = await supabase
          .from('breaks')
          .insert({
            employee_id: employeeId,
            break_start: now, // Required by schema (NOT NULL) - represents request time
            duration_minutes: Math.round(duration), // Correct column name in schema
            status: 'PENDING', // Explicitly set status to PENDING (waiting for approval)
          })
          .select('*')
          .maybeSingle();

        if (error) {
          console.error('[employee-break][request] insert error', error);
          return jsonResponse(500, { success: false, error: 'تعذر إنشاء طلب الاستراحة' });
        }

        return jsonResponse(201, {
          success: true,
          break: mapBreakRow(data),
          message: 'تم إرسال طلب الاستراحة بنجاح',
        });
      }
      case 'start': {
        const breakId = payload.break_id?.trim();
        const eventTimestamp = parseTimestamp(payload.timestamp) ?? getCairoNow();
        if (!breakId) {
          return jsonResponse(400, { success: false, error: 'Break ID is required' });
        }

        const { data: existing, error: existingError } = await supabase
          .from('breaks')
          .select('id, status, break_start')
          .eq('id', breakId)
          .maybeSingle();

        if (existingError) {
          console.error('[employee-break][start] fetch error', existingError);
          return jsonResponse(500, { success: false, error: 'تعذر تحميل بيانات الاستراحة' });
        }

        if (!existing) {
          return jsonResponse(404, { success: false, error: 'لم يتم العثور على الاستراحة' });
        }

        // ✅ Only allow starting if status is APPROVED (owner/manager must approve first!)
        if (existing.status !== 'APPROVED') {
          return jsonResponse(400, {
            success: false,
            error: 'يجب أن يوافق المدير على الاستراحة أولاً'
          });
        }

        if (existing.status === 'COMPLETED') {
          return jsonResponse(200, { success: true, message: 'تم إنهاء الاستراحة بالفعل' });
        }

        const { data, error } = await supabase
          .from('breaks')
          .update({
            status: 'ACTIVE',
            break_start: eventTimestamp.toISOString(), // ✅ Update actual start time when employee starts break
          })
          .eq('id', breakId)
          .select('*')
          .maybeSingle();

        if (error) {
          console.error('[employee-break][start] update error', error);
          return jsonResponse(500, { success: false, error: 'تعذر بدء الاستراحة' });
        }

        return jsonResponse(200, {
          success: true,
          break: mapBreakRow(data),
          message: 'تم بدء الاستراحة',
        });
      }
      case 'end': {
        const breakId = payload.break_id?.trim();
        const eventTimestamp = parseTimestamp(payload.timestamp) ?? getCairoNow();
        if (!breakId) {
          return jsonResponse(400, { success: false, error: 'Break ID is required' });
        }

        const { data: existing, error: existingError } = await supabase
          .from('breaks')
          .select('id, status, break_start')
          .eq('id', breakId)
          .maybeSingle();

        if (existingError) {
          console.error('[employee-break][end] fetch error', existingError);
          return jsonResponse(500, { success: false, error: 'تعذر تحميل بيانات الاستراحة' });
        }

        if (!existing) {
          return jsonResponse(404, { success: false, error: 'لم يتم العثور على الاستراحة' });
        }

        const startTime = existing.break_start ? new Date(existing.break_start) : null;
        let actualMinutes: number | null = null;
        if (startTime && !Number.isNaN(startTime.getTime())) {
          const diffMs = eventTimestamp.getTime() - startTime.getTime();
          actualMinutes = diffMs > 0 ? Math.round(diffMs / (1000 * 60)) : 0;
        }

        const { data, error } = await supabase
          .from('breaks')
          .update({
            status: 'COMPLETED',
            break_end: eventTimestamp.toISOString(), // ✅ Use correct column name from schema
            // duration_minutes remains unchanged; actual is computed in mapBreakRow
          })
          .eq('id', breakId)
          .select('*')
          .maybeSingle();

        if (error) {
          console.error('[employee-break][end] update error', error);
          return jsonResponse(500, { success: false, error: 'تعذر إنهاء الاستراحة' });
        }

        return jsonResponse(200, {
          success: true,
          break: mapBreakRow(data),
          message: 'تم إنهاء الاستراحة',
        });
      }
      case 'list': {
        const employeeId = payload.employee_id?.trim();
        if (!employeeId) {
          return jsonResponse(400, { success: false, error: 'Employee ID is required' });
        }

        const { data, error } = await supabase
          .from('breaks')
          .select('*')
          .eq('employee_id', employeeId)
          .order('created_at', { ascending: false })
          .limit(100);

        if (error) {
          console.error('[employee-break][list] query error', error);
          return jsonResponse(500, { success: false, error: 'تعذر تحميل الاستراحات' });
        }

        return jsonResponse(200, {
          success: true,
          breaks: Array.isArray(data) ? data.map(mapBreakRow) : [],
        });
      }
      case 'delete_rejected': {
        const employeeId = payload.employee_id?.trim();
        if (!employeeId) {
          return jsonResponse(400, { success: false, error: 'Employee ID is required' });
        }

        const { error } = await supabase
          .from('breaks')
          .delete()
          .eq('employee_id', employeeId)
          .eq('status', 'REJECTED');

        if (error) {
          console.error('[employee-break][delete] delete error', error);
          return jsonResponse(500, { success: false, error: 'تعذر حذف الاستراحات المرفوضة' });
        }

        return jsonResponse(200, {
          success: true,
          message: 'تم حذف الاستراحات المرفوضة',
        });
      }
      default:
        return jsonResponse(400, { success: false, error: 'Unsupported action' });
    }
  } catch (error) {
    console.error('[employee-break] unexpected error', error);
    return jsonResponse(500, { success: false, error: 'Internal server error' });
  }
});
