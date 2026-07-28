// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

type JsonRecord = Record<string, unknown>;

type BreakAction =
  | "request"
  | "approve"
  | "reject"
  | "start"
  | "end"
  | "list"
  | "get_one"
  | "pending"
  | "delete_rejected";

type BreakPayload = {
  action?: BreakAction;
  employee_id?: string;
  assigned_manager_id?: string;
  duration_minutes?: number;
  reason?: string;
  break_id?: string;
  timestamp?: string | number;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

function jsonResponse(status: number, body: JsonRecord) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function getSupabase() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseKey = Deno.env.get("SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !supabaseKey) {
    throw new Error("Missing Supabase credentials");
  }

  return createClient(supabaseUrl, supabaseKey, {
    auth: { persistSession: false },
  });
}

function getCairoNow(): Date {
  return new Date();
}

function parseTimestamp(input: unknown): Date | null {
  if (!input) return null;
  if (input instanceof Date) {
    return Number.isNaN(input.getTime()) ? null : input;
  }
  if (typeof input === "number") {
    const date = new Date(input);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (typeof input === "string") {
    const trimmed = input.trim();
    if (!trimmed) return null;
    const date = new Date(trimmed);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function cairoDateString(date: Date = new Date()): string {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Cairo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const parts = formatter.formatToParts(date);
  const values = Object.fromEntries(
    parts.map((part) => [part.type, part.value]),
  );
  return `${values.year}-${values.month}-${values.day}`;
}

function addMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60 * 1000);
}

function mapBreakRow(row: any): Record<string, unknown> {
  if (!row) return {};
  const normalizedStatus = normalizeBreakStatus(row.status);
  return {
    id: row.id,
    employee_id: row.employee_id,
    requested_duration_minutes: row.duration_minutes ?? null,
    actual_duration_minutes:
      normalizedStatus === "COMPLETED" && row.break_end && row.break_start
        ? Math.max(
          0,
          Math.round(
            (new Date(row.break_end).getTime() -
              new Date(row.break_start).getTime()) / (1000 * 60),
          ),
        )
        : null,
    status: row.status,
    start_time: row.break_start ?? null,
    end_time: row.break_end ?? null,
    reason: row.reason ?? row.notes ?? null,
    notes: row.notes ?? null,
    approved_by: row.approved_by ?? null,
    assigned_manager_id: row.assigned_manager_id ?? null,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

function normalizeBreakStatus(value: unknown): string {
  return String(value ?? "").trim().toUpperCase();
}

async function getActiveAttendanceForToday(supabase: any, employeeId: string) {
  // Consider rows with explicit active status or rows without a check_out_time (not checked out yet).
  const { data, error } = await supabase
    .from("attendance")
    .select("id, status, date, check_in_time, check_out_time")
    .eq("employee_id", employeeId)
    .or("status.eq.active,status.eq.ACTIVE,check_out_time.is.null")
    .order("check_in_time", { ascending: false })
    .limit(1)
    .maybeSingle();

  console.log("[employee-break][getActiveAttendanceForToday]", {
    employeeId,
    found: data ? "YES" : "NO",
    data,
    error: error ? error.message : null,
  });

  if (error || !data) {
    return null;
  }

  const attendanceDate = data.date?.toString().split("T")[0] ||
    (data.check_in_time ? cairoDateString(new Date(data.check_in_time)) : "");

  console.log("[employee-break][getActiveAttendanceForToday] Comparing dates:", {
    attendanceDate,
    todayDate: cairoDateString(),
    matches: attendanceDate === cairoDateString(),
  });

  return attendanceDate === cairoDateString() ? data : null;
}

async function autoCompleteExpiredBreaks(
  supabase: any,
  options: { employeeId?: string; breakId?: string } = {},
) {
  let query = supabase
    .from("breaks")
    .select("id")
    .eq("status", "ACTIVE")
    .not("break_end", "is", null)
    .lte("break_end", getCairoNow().toISOString())
    .limit(100);

  if (options.employeeId) {
    query = query.eq("employee_id", options.employeeId);
  }

  if (options.breakId) {
    query = query.eq("id", options.breakId);
  }

  const { data, error } = await query;
  if (error || !Array.isArray(data) || data.length === 0) {
    return;
  }

  const ids = data.map((row: any) => row.id).filter(Boolean);
  if (ids.length === 0) {
    return;
  }

  await supabase
    .from("breaks")
    .update({
      status: "COMPLETED",
      updated_at: getCairoNow().toISOString(),
    })
    .in("id", ids);
}

async function resolveAssignedManagerId(
  supabase: any,
  employeeId: string,
): Promise<string | null> {
  try {
    const { data: employee, error: employeeError } = await supabase
      .from("employees")
      .select("id, role, branch_id, branch")
      .eq("id", employeeId)
      .maybeSingle();

    if (employeeError || !employee) {
      console.warn("[employee-break] employee lookup error for:", employeeId, employeeError);
      return null;
    }

    console.log("[employee-break] Resolving manager for employee:", { 
      employeeId, 
      branch_id: employee.branch_id, 
      branch: employee.branch 
    });

    // Try to find manager by branch_id (checking both branch_id and branch fields on manager)
    if (employee.branch_id) {
      // 1) First try: managers with same branch_id
      const { data: managerByBranchId, error: managerByBranchIdError } = await supabase
        .from("employees")
        .select("id, full_name, branch_id, branch")
        .eq("role", "manager")
        .eq("is_active", true)
        .eq("branch_id", employee.branch_id)
        .neq("id", employeeId)
        .limit(1)
        .maybeSingle();

      if (managerByBranchId) {
        console.log("[employee-break] Found manager by branch_id match:", managerByBranchId.id);
        return managerByBranchId.id?.toString() ?? null;
      }

      // 2) Second try: check if branches table has manager_id
      const { data: branch, error: branchError } = await supabase
        .from("branches")
        .select("id, manager_id")
        .eq("id", employee.branch_id)
        .maybeSingle();

      if (branchError) {
        console.warn("[employee-break] branch lookup failed:", branchError.message);
      } else if (branch?.manager_id) {
        const branchManagerId = branch.manager_id.toString();
        if (branchManagerId && branchManagerId !== employeeId) {
          console.log("[employee-break] Found manager by branches.manager_id:", branchManagerId);
          return branchManagerId;
        }
      }
    }

    // Try to find manager by branch (string field)
    if (employee.branch) {
      // Try matching by branch string field
      const { data: managerByBranch, error: managerByBranchError } = await supabase
        .from("employees")
        .select("id, full_name, branch_id, branch")
        .eq("role", "manager")
        .eq("is_active", true)
        .eq("branch", employee.branch)
        .neq("id", employeeId)
        .limit(1)
        .maybeSingle();

      if (managerByBranch) {
        console.log("[employee-break] Found manager by branch string match:", managerByBranch.id);
        return managerByBranch.id?.toString() ?? null;
      }
    }

    // Fallback: any active manager in the system
    const { data: anyManager, error: anyManagerError } = await supabase
      .from("employees")
      .select("id, full_name")
      .eq("role", "manager")
      .eq("is_active", true)
      .neq("id", employeeId)
      .limit(1)
      .maybeSingle();

    if (anyManager) {
      console.log("[employee-break] Assigned fallback manager:", anyManager.id);
      return anyManager.id?.toString() ?? null;
    }

    console.warn("[employee-break] No active managers found for employee:", employeeId);
    return null;
  } catch (error) {
    console.error("[employee-break] manager assignment error:", error);
    return null;
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse(405, { success: false, error: "Method not allowed" });
  }

  try {
    let payload: BreakPayload;
    try {
      payload = (await req.json()) as BreakPayload;
    } catch (_err) {
      return jsonResponse(400, {
        success: false,
        error: "Invalid JSON body",
      });
    }

    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      return jsonResponse(400, {
        success: false,
        error: "Request body must be a JSON object",
      });
    }

    const action = payload.action ?? "request";

    let supabase: any;
    try {
      supabase = getSupabase();
    } catch (err) {
      console.error("[employee-break] failed to init supabase client:", err);
      return jsonResponse(500, {
        success: false,
        error: "Supabase credentials are not configured",
      });
    }

    switch (action) {
      case "request": {
        const employeeId = payload.employee_id?.trim();
        const duration = Number(payload.duration_minutes ?? 0);
        const reason = payload.reason?.trim() ?? null;

        if (!employeeId) {
          return jsonResponse(400, {
            success: false,
            error: "Employee ID is required",
          });
        }
        if (!Number.isFinite(duration) || duration <= 0) {
          return jsonResponse(400, {
            success: false,
            error: "مدة الاستراحة مطلوبة ويجب أن تكون أطول من صفر",
          });
        }

        try {
          console.log("[employee-break][request] Starting break request for employee:", employeeId, "duration:", duration);
          
          const activeAttendance = await getActiveAttendanceForToday(
            supabase,
            employeeId,
          );
          
          console.log("[employee-break][request] Active attendance found:", activeAttendance ? "YES" : "NO");
          
          if (!activeAttendance) {
            console.error("[employee-break][request] No active attendance for employee:", employeeId);
            return jsonResponse(400, {
              success: false,
              error: "يمكن طلب الاستراحة فقط أثناء حضور نشط في تاريخ اليوم",
            });
          }
          
          console.log("[employee-break][request] Active attendance details:", activeAttendance);

          await autoCompleteExpiredBreaks(supabase, { employeeId });

          const { data: existingOpenBreak, error: existingOpenBreakError } =
            await supabase
              .from("breaks")
              .select("*")
              .eq("employee_id", employeeId)
              .in("status", [
                "PENDING",
                "APPROVED",
                "ACTIVE",
                "pending",
                "approved",
                "active",
              ])
              .order("created_at", { ascending: false })
              .limit(1)
              .maybeSingle();

          if (existingOpenBreakError) {
            console.error(
              "[employee-break][request] open-break lookup error",
              existingOpenBreakError,
            );
            return jsonResponse(500, {
              success: false,
              error: "تعذر التحقق من طلبات الاستراحة الحالية",
              details: existingOpenBreakError.message ?? null,
              code: existingOpenBreakError.code ?? null,
            });
          }

          if (existingOpenBreak) {
            let resolvedOpenBreak = existingOpenBreak;

            // Ensure open requests are assigned so they appear in manager pending queue.
            const currentAssignedManagerId =
              existingOpenBreak.assigned_manager_id?.toString().trim() || null;
            if (!currentAssignedManagerId) {
              const backfillManagerId = await resolveAssignedManagerId(
                supabase,
                employeeId,
              );
              if (backfillManagerId) {
                const { data: updatedOpenBreak, error: updateOpenBreakError } =
                  await supabase
                    .from("breaks")
                    .update({
                      assigned_manager_id: backfillManagerId,
                      updated_at: getCairoNow().toISOString(),
                    })
                    .eq("id", existingOpenBreak.id)
                    .select("*")
                    .maybeSingle();

                if (!updateOpenBreakError && updatedOpenBreak) {
                  resolvedOpenBreak = updatedOpenBreak;
                } else if (updateOpenBreakError) {
                  console.warn(
                    "[employee-break][request] could not backfill assigned manager for open break",
                    {
                      breakId: existingOpenBreak.id,
                      employeeId,
                      error: updateOpenBreakError.message,
                    },
                  );
                }
              }
            }

            return jsonResponse(200, {
              success: true,
              duplicate: true,
              break: mapBreakRow(resolvedOpenBreak),
              message: "يوجد طلب استراحة قائم بالفعل",
            });
          }

          const now = getCairoNow().toISOString();
          const assignedManagerId = await resolveAssignedManagerId(
            supabase,
            employeeId,
          );

          console.log("[employee-break][request] Resolved manager:", assignedManagerId);
          console.log("[employee-break][request] Creating break with:", {
            employee_id: employeeId,
            duration_minutes: Math.round(duration),
            status: "PENDING",
            assigned_manager_id: assignedManagerId,
            reason,
          });

          const { data, error } = await supabase
            .from("breaks")
            .insert({
              employee_id: employeeId,
              duration_minutes: Math.round(duration),
              status: "PENDING",
              assigned_manager_id: assignedManagerId,
              reason,
              break_start: null,
              break_end: null,
            })
            .select("*")
            .maybeSingle();

          if (error) {
            console.error("[employee-break][request] insert error:", error);
            return jsonResponse(500, {
              success: false,
              error: "تعذر إنشاء طلب الاستراحة",
              details: error.message ?? null,
              code: error.code ?? null,
            });
          }

          if (!data) {
            console.error("[employee-break][request] no data returned from insert");
            return jsonResponse(500, {
              success: false,
              error: "فشل في إرجاع بيانات الاستراحة",
            });
          }

          console.log("[employee-break][request] Break created successfully:", data.id);
          return jsonResponse(201, {
            success: true,
            break: mapBreakRow(data),
            message: "تم إرسال طلب الاستراحة بنجاح",
          });
        } catch (err) {
          console.error("[employee-break][request] exception occurred:", err);
          const errorMsg = err instanceof Error ? err.message : String(err);
          console.error("[employee-break][request] error message:", errorMsg);
          return jsonResponse(500, {
            success: false,
            error: "خطأ غير متوقع",
            details: errorMsg,
          });
        }
      }

      case "approve": {
        const breakId = payload.break_id?.trim();
        if (!breakId) {
          return jsonResponse(400, {
            success: false,
            error: "Break ID is required",
          });
        }

        try {
          await autoCompleteExpiredBreaks(supabase, { breakId });

          const { data: existing, error: existingError } = await supabase
            .from("breaks")
            .select("id, status, employee_id, duration_minutes")
            .eq("id", breakId)
            .maybeSingle();

          if (existingError || !existing) {
            return jsonResponse(404, {
              success: false,
              error: "لم يتم العثور على الاستراحة",
            });
          }

          if (normalizeBreakStatus(existing.status) !== "PENDING") {
            return jsonResponse(400, {
              success: false,
              error: `لا يمكن الموافقة على استراحة برقم ${existing.status}`,
            });
          }

          const { data, error } = await supabase
            .from("breaks")
            .update({
              status: "APPROVED",
              updated_at: getCairoNow().toISOString(),
            })
            .eq("id", breakId)
            .select("*")
            .maybeSingle();

          if (error || !data) {
            return jsonResponse(500, {
              success: false,
              error: "تعذر الموافقة على الاستراحة",
            });
          }

          console.log("[employee-break][approve] Break approved:", breakId);
          return jsonResponse(200, {
            success: true,
            break: mapBreakRow(data),
            message: "تمت الموافقة على الاستراحة",
          });
        } catch (err) {
          console.error("[employee-break][approve] exception", err);
          return jsonResponse(500, { success: false, error: "خطأ غير متوقع" });
        }
      }

      case "reject": {
        const breakId = payload.break_id?.trim();
        if (!breakId) {
          return jsonResponse(400, {
            success: false,
            error: "Break ID is required",
          });
        }

        try {
          const { data: existing, error: existingError } = await supabase
            .from("breaks")
            .select("id, status, employee_id")
            .eq("id", breakId)
            .maybeSingle();

          if (existingError || !existing) {
            return jsonResponse(404, {
              success: false,
              error: "لم يتم العثور على الاستراحة",
            });
          }

          if (normalizeBreakStatus(existing.status) !== "PENDING") {
            return jsonResponse(400, {
              success: false,
              error: `لا يمكن رفض استراحة برقم ${existing.status}`,
            });
          }

          const { data, error } = await supabase
            .from("breaks")
            .update({
              status: "REJECTED",
              updated_at: getCairoNow().toISOString(),
            })
            .eq("id", breakId)
            .select("*")
            .maybeSingle();

          if (error || !data) {
            return jsonResponse(500, {
              success: false,
              error: "تعذر رفض الاستراحة",
            });
          }

          console.log("[employee-break][reject] Break rejected:", breakId);
          return jsonResponse(200, {
            success: true,
            break: mapBreakRow(data),
            message: "تم رفض الاستراحة",
          });
        } catch (err) {
          console.error("[employee-break][reject] exception", err);
          return jsonResponse(500, { success: false, error: "خطأ غير متوقع" });
        }
      }

      case "start": {
        const breakId = payload.break_id?.trim();
        const eventTimestamp = parseTimestamp(payload.timestamp) ??
          getCairoNow();

        if (!breakId) {
          return jsonResponse(400, {
            success: false,
            error: "Break ID is required",
          });
        }

        try {
          const { data: existing, error: existingError } = await supabase
            .from("breaks")
            .select("id, status, employee_id")
            .eq("id", breakId)
            .maybeSingle();

          if (existingError || !existing) {
            return jsonResponse(404, {
              success: false,
              error: "لم يتم العثور على الاستراحة",
            });
          }

          if (normalizeBreakStatus(existing.status) !== "APPROVED") {
            return jsonResponse(400, {
              success: false,
              error: "يجب أن يوافق المدير على الاستراحة أولاً",
            });
          }

          const activeAttendance = await getActiveAttendanceForToday(
            supabase,
            existing.employee_id,
          );
          if (!activeAttendance) {
            return jsonResponse(400, {
              success: false,
              error: "لا يمكن تفعيل الاستراحة إلا أثناء حضور اليوم الحالي",
            });
          }

          const plannedEnd = addMinutes(
            eventTimestamp,
            Number(existing.duration_minutes ?? 0),
          );

          const { data, error } = await supabase
            .from("breaks")
            .update({
              status: "ACTIVE",
              break_start: eventTimestamp.toISOString(),
              break_end: plannedEnd.toISOString(),
              updated_at: getCairoNow().toISOString(),
            })
            .eq("id", breakId)
            .select("*")
            .maybeSingle();

          if (error || !data) {
            return jsonResponse(500, {
              success: false,
              error: "تعذر بدء الاستراحة",
            });
          }

          console.log("[employee-break][start] Break started:", breakId);
          return jsonResponse(200, {
            success: true,
            break: mapBreakRow(data),
            message: "تم بدء الاستراحة",
          });
        } catch (err) {
          console.error("[employee-break][start] exception", err);
          return jsonResponse(500, { success: false, error: "خطأ غير متوقع" });
        }
      }

      case "end": {
        const breakId = payload.break_id?.trim();
        const eventTimestamp = parseTimestamp(payload.timestamp) ??
          getCairoNow();

        if (!breakId) {
          return jsonResponse(400, {
            success: false,
            error: "Break ID is required",
          });
        }

        try {
          const { data: existing, error: existingError } = await supabase
            .from("breaks")
            .select("id, status, employee_id")
            .eq("id", breakId)
            .maybeSingle();

          if (existingError || !existing) {
            return jsonResponse(404, {
              success: false,
              error: "لم يتم العثور على الاستراحة",
            });
          }

          if (normalizeBreakStatus(existing.status) !== "ACTIVE") {
            return jsonResponse(400, {
              success: false,
              error: `لا يمكن إنهاء استراحة في حالة ${existing.status}`,
            });
          }

          const { data, error } = await supabase
            .from("breaks")
            .update({
              status: "COMPLETED",
              break_end: eventTimestamp.toISOString(),
              updated_at: getCairoNow().toISOString(),
            })
            .eq("id", breakId)
            .select("*")
            .maybeSingle();

          if (error || !data) {
            return jsonResponse(500, {
              success: false,
              error: "تعذر إنهاء الاستراحة",
            });
          }

          console.log("[employee-break][end] Break ended:", breakId);
          return jsonResponse(200, {
            success: true,
            break: mapBreakRow(data),
            message: "تم إنهاء الاستراحة",
          });
        } catch (err) {
          console.error("[employee-break][end] exception", err);
          return jsonResponse(500, { success: false, error: "خطأ غير متوقع" });
        }
      }

      case "list": {
        const employeeId = payload.employee_id?.trim();
        if (!employeeId) {
          return jsonResponse(400, {
            success: false,
            error: "Employee ID is required",
          });
        }

        try {
          await autoCompleteExpiredBreaks(supabase, { employeeId });

          const { data, error } = await supabase
            .from("breaks")
            .select("*")
            .eq("employee_id", employeeId)
            .order("created_at", { ascending: false })
            .limit(100);

          if (error) {
            return jsonResponse(500, {
              success: false,
              error: "تعذر تحميل الاستراحات",
            });
          }

          const breaks = Array.isArray(data) ? data.map(mapBreakRow) : [];
          return jsonResponse(200, { success: true, breaks: breaks });
        } catch (err) {
          console.error("[employee-break][list] exception", err);
          return jsonResponse(500, { success: false, error: "خطأ غير متوقع" });
        }
      }

      case "get_one": {
        const breakId = payload.break_id?.trim();
        if (!breakId) {
          return jsonResponse(400, {
            success: false,
            error: "Break ID is required",
          });
        }

        try {
          await autoCompleteExpiredBreaks(supabase, { breakId });

          const { data, error } = await supabase
            .from("breaks")
            .select("*")
            .eq("id", breakId)
            .maybeSingle();

          if (error || !data) {
            return jsonResponse(404, {
              success: false,
              error: "لم يتم العثور على الاستراحة",
            });
          }

          return jsonResponse(200, { success: true, break: mapBreakRow(data) });
        } catch (err) {
          console.error("[employee-break][get_one] exception", err);
          return jsonResponse(500, { success: false, error: "خطأ غير متوقع" });
        }
      }

      case "pending": {
        const managerId = payload.assigned_manager_id?.trim();
        if (!managerId) {
          return jsonResponse(400, {
            success: false,
            error: "Manager ID is required",
          });
        }

        try {
          const { data, error } = await supabase
            .from("breaks")
            .select("*")
            .eq("assigned_manager_id", managerId)
            .in("status", ["PENDING", "pending"])
            .order("created_at", { ascending: true })
            .limit(100);

          if (error) {
            return jsonResponse(500, {
              success: false,
              error: "تعذر تحميل الإجازات المعلقة",
            });
          }

          const breaks = Array.isArray(data) ? data.map(mapBreakRow) : [];
          console.log(
            "[employee-break][pending] Retrieved",
            breaks.length,
            "pending breaks for manager:",
            managerId,
          );
          return jsonResponse(200, {
            success: true,
            breaks: breaks,
            count: breaks.length,
          });
        } catch (err) {
          console.error("[employee-break][pending] exception", err);
          return jsonResponse(500, { success: false, error: "خطأ غير متوقع" });
        }
      }

      case "delete_rejected": {
        const employeeId = payload.employee_id?.trim();
        if (!employeeId) {
          return jsonResponse(400, {
            success: false,
            error: "Employee ID is required",
          });
        }

        try {
          const { error } = await supabase
            .from("breaks")
            .delete()
            .eq("employee_id", employeeId)
            .eq("status", "REJECTED");

          if (error) {
            return jsonResponse(500, {
              success: false,
              error: "تعذر حذف الاستراحات المرفوضة",
            });
          }

          console.log(
            "[employee-break][delete] Deleted rejected breaks for employee:",
            employeeId,
          );
          return jsonResponse(200, {
            success: true,
            message: "تم حذف الاستراحات المرفوضة",
          });
        } catch (err) {
          console.error("[employee-break][delete] exception", err);
          return jsonResponse(500, { success: false, error: "خطأ غير متوقع" });
        }
      }

      default:
        return jsonResponse(400, {
          success: false,
          error: "Unsupported action",
        });
    }
  } catch (error) {
    console.error("[employee-break] unexpected error", error);
    const message = error instanceof Error
      ? error.message
      : "Internal server error";
    return jsonResponse(500, {
      success: false,
      error: "Internal server error",
      details: message,
    });
  }
});
