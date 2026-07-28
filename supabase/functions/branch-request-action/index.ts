// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

type JsonValue = string | number | boolean | null | JsonValue[] | {
  [key: string]: JsonValue;
};

type ActionType = "approve" | "reject" | "postpone";
type RequestType = "leave" | "advance" | "attendance" | "absence" | "break";

type ApiResponse = {
  success: boolean;
  message?: string;
  error?: string;
  data?: JsonValue;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

const STAFF_ROLES = ["staff", "monitor", "hr"];

class ApiError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function jsonResponse(status: number, payload: ApiResponse) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: corsHeaders,
  });
}

function normalizeStringId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function isUuid(value: string): boolean {
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuidRegex.test(value);
}

function decodeBase64Url(input: string): string {
  const normalized = input.replace(/-/g, "+").replace(/_/g, "/");
  const pad = normalized.length % 4;
  const padded = pad === 0 ? normalized : normalized + "=".repeat(4 - pad);
  return atob(padded);
}

function getReviewerIdFromAuthHeader(req: Request): string | null {
  const authHeader = req.headers.get("authorization") ||
    req.headers.get("Authorization");
  if (!authHeader || !authHeader.toLowerCase().startsWith("bearer ")) {
    return null;
  }

  const token = authHeader.slice(7).trim();
  if (!token) return null;

  const parts = token.split(".");
  if (parts.length < 2) return null;

  try {
    const payloadJson = decodeBase64Url(parts[1]);
    const payload = JSON.parse(payloadJson) as Record<string, unknown>;
    const sub = normalizeStringId(payload.sub);
    return sub && isUuid(sub) ? sub : null;
  } catch (_e) {
    return null;
  }
}

async function canApproveRequest(
  supabase: any,
  reviewerId: string,
  employeeId: string,
) {
  const { data: reviewer, error: reviewerError } = await supabase
    .from("employees")
    .select("id, role, branch_id, branch")
    .eq("id", reviewerId)
    .maybeSingle();

  if (reviewerError) {
    throw new Error(`Failed to fetch reviewer: ${reviewerError.message}`);
  }

  if (!reviewer) {
    return { allowed: false, reason: "Reviewer not found" };
  }

  const { data: employee, error: employeeError } = await supabase
    .from("employees")
    .select("id, role, branch_id, branch")
    .eq("id", employeeId)
    .maybeSingle();

  if (employeeError) {
    throw new Error(`Failed to fetch employee: ${employeeError.message}`);
  }

  if (!employee) {
    return { allowed: false, reason: "Employee not found" };
  }

  const reviewerRole = reviewer.role as string | null;
  const employeeRole = employee.role as string | null;

  if (reviewerRole === "owner" || reviewerRole === "admin") {
    return { allowed: true };
  }

  if (employeeRole === "manager") {
    return {
      allowed: false,
      reason: "Only owner can approve requests from managers",
    };
  }

  if (
    reviewerRole === "manager" && employeeRole &&
    STAFF_ROLES.includes(employeeRole)
  ) {
    if (
      reviewer.branch_id && employee.branch_id &&
      reviewer.branch_id === employee.branch_id
    ) {
      return { allowed: true };
    }
    if (
      reviewer.branch && employee.branch && reviewer.branch === employee.branch
    ) {
      return { allowed: true };
    }
    return {
      allowed: false,
      reason: "Manager can only approve requests for their branch",
    };
  }

  return {
    allowed: false,
    reason: "Insufficient permissions to approve this request",
  };
}

type RequestRecord = {
  employeeId: string;
  [key: string]: JsonValue;
};

async function fetchRequestRecord(
  supabase: any,
  type: RequestType,
  id: string,
): Promise<RequestRecord | null> {
  let table = "";
  let columns = "*";

  switch (type) {
    case "leave":
      table = "leave_requests";
      break;
    case "advance":
      table = "salary_advances";
      break;
    case "attendance":
      table = "attendance_requests";
      break;
    case "absence":
      table = "absence_notifications";
      break;
    case "break":
      table = "breaks";
      break;
  }

  const { data, error } = await supabase
    .from(table)
    .select(columns)
    .eq("id", id)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to fetch ${type} request: ${error.message}`);
  }

  return data as RequestRecord | null;
}

async function updateBreakRequest(
  supabase: any,
  id: string,
  action: ActionType,
  reviewerId?: string | null,
) {
  const statusMap: Record<ActionType, string> = {
    approve: "APPROVED",
    reject: "REJECTED",
    postpone: "POSTPONED",
  };

  const update: Record<string, JsonValue> = {
    status: statusMap[action],
    updated_at: new Date().toISOString(),
  };

  // Keep break updates minimal to avoid touching schema-specific columns
  // (many deployments don't have approved_by/reviewed_by on breaks table).
  // If reviewerId is present, include a lightweight note in update_notes
  // only if such a column exists server-side. To avoid failing when the
  // column doesn't exist, we don't add schema-specific fields here.

  const { data, error } = await supabase
    .from("breaks")
    .update(update)
    .eq("id", id)
    .select()
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to update break request: ${error.message}`);
  }

  return data;
}

async function updateStandardRequest(
  supabase: any,
  type: Exclude<RequestType, "break">,
  id: string,
  action: ActionType,
  reviewerId: string,
  notes?: string,
) {
  const statusMap: Record<ActionType, string> = {
    approve: "approved",
    reject: "rejected",
    postpone: "pending",
  };

  if (action === "postpone") {
    throw new Error("Postpone action is not supported for this request type");
  }

  // Build update payload depending on request type.
  // Note: `salary_advances` uses `approved_by` / `approved_at` instead of `reviewed_by` / `reviewed_at`.
  const update: Record<string, JsonValue> = { status: statusMap[action] };

  const nowIso = new Date().toISOString();

  if (type === 'advance') {
    // For advances, set approved fields on approve, and store notes in `notes`.
    if (action === 'approve') {
      update.approved_at = nowIso;
      if (reviewerId && isUuid(reviewerId)) update.approved_by = reviewerId;
    } else {
      // For reject/postpone, update updated_at
      update.updated_at = nowIso;
    }

    if (notes) update.notes = notes;
  } else {
    // Default path for leave/attendance/absence
    update.reviewed_at = nowIso;
    if (reviewerId && isUuid(reviewerId)) update.reviewed_by = reviewerId;
    if (notes && (type === 'leave' || type === 'attendance')) {
      update.review_notes = notes;
    }
  }

  // For absence notifications: approve = apply deduction, reject = excuse (no deduction)
  if (type === "absence") {
    if (action === "approve") {
      // Approve means apply deduction - get the notification first to get deduction amount
      const { data: absenceNotif } = await supabase
        .from("absence_notifications")
        .select("*")
        .eq("id", id)
        .maybeSingle();

      if (absenceNotif && absenceNotif.deduction_amount) {
        update.deduction_applied = true;
        // Create deduction record
        const { data: employee } = await supabase
          .from("employees")
          .select("id")
          .eq("id", absenceNotif.employee_id)
          .maybeSingle();

        if (employee) {
          await supabase.from("deductions").insert({
            employee_id: absenceNotif.employee_id,
            amount: absenceNotif.deduction_amount.toString(),
            reason: notes || `خصم غياب يوم ${absenceNotif.absence_date}`,
            deduction_date: absenceNotif.absence_date,
            deduction_type: "absence",
            applied_by: reviewerId,
          });
        }
      }
    } else if (action === "reject") {
      // Reject means excuse (no deduction)
      update.deduction_applied = false;
    }
  }

  // ✅ ATTENDANCE CORRECTION LOGIC (COMPLETE & ROBUST)
  if (type === "attendance" && action === "approve") {
    const { data: attRequest } = await supabase
      .from("attendance_requests")
      .select("*")
      .eq("id", id)
      .single();

    if (attRequest) {
      // Flexible field handling: accept multiple possible property names
      const requestedTimeRaw = attRequest.requested_time ?? attRequest.requestedTime ?? attRequest.requested_at ?? attRequest.time;
      if (!requestedTimeRaw) {
        throw new ApiError(400, "Missing requested_time in attendance request");
      }
      const requestedTime = new Date(requestedTimeRaw);

      const requestTypeRaw = attRequest.request_type ?? attRequest.requestType ?? attRequest.type;
      const requestType = (requestTypeRaw || "").toString();

      console.log(
        `Processing attendance request: ${requestType} at ${requestedTime.toISOString()}`,
      );

      const rt = requestType.toLowerCase();
      if (rt.includes("check") && rt.includes("in")) {
        // ✅ CREATE COMPLETE CLOSED ATTENDANCE RECORD
        console.log(
          "🆕 Creating COMPLETE attendance record for Check-in request (forgot to check-in)",
        );

        // 1. جلب آخر سجل حضور للموظف (سواء active أو completed)
        const { data: latestRecord } = await supabase
          .from("attendance")
          .select("*")
          .eq("employee_id", attRequest.employee_id)
          .order("check_in_time", { ascending: false })
          .limit(1)
          .maybeSingle();

        if (!latestRecord) {
          console.warn(
            "⚠️ No existing attendance record found. Creating active check-in only.",
          );
          // إذا مافيش سجل، نعمل سجل عادي (active)
          const checkInDate = requestedTime.toISOString().split("T")[0]; // Extract date in YYYY-MM-DD format
          const { error: insertError } = await supabase.from("attendance")
            .insert({
              employee_id: attRequest.employee_id,
              check_in_time: requestedTime.toISOString(),
              date: checkInDate,
              status: "active",
              notes:
                "تم إنشاء السجل بناءً على طلب تصحيح حضور (نسيت الحضور) - لا يوجد سجل سابق",
            });

          if (insertError) {
            console.error(
              "❌ Failed to create attendance record:",
              insertError,
            );
            throw new Error(
              `Failed to create attendance record: ${insertError.message}`,
            );
          }
          console.log("✅ New active attendance record created successfully");
        } else {
          // 2. استخدام check_in_time من السجل الموجود كـ check_out_time للسجل الجديد
          const actualCheckInTime = new Date(latestRecord.check_in_time);
          console.log(
            `✅ Found latest record with check-in at ${actualCheckInTime.toISOString()}`,
          );

          // التأكد من أن requested_time قبل actual check-in time
          if (requestedTime >= actualCheckInTime) {
            throw new ApiError(
              400,
              "الوقت المطلوب يجب أن يكون قبل وقت التسجيل الفعلي",
            );
          }

          // ✅ NEW: Reject request if there is any real attendance between requested and actual times
          const intervalStartIso = requestedTime.toISOString();
          const intervalEndIso = actualCheckInTime.toISOString();
          const { data: overlappingRecords, error: overlapError } =
            await supabase
              .from("attendance")
              .select("id, check_in_time")
              .eq("employee_id", attRequest.employee_id)
              .neq("id", latestRecord.id)
              .gt("check_in_time", intervalStartIso)
              .lt("check_in_time", intervalEndIso)
              .limit(1);

          if (overlapError) {
            console.error(
              "❌ Failed to validate overlapping attendance records:",
              overlapError,
            );
            throw new Error(
              "Failed to validate overlapping attendance records",
            );
          }

          if (overlappingRecords && overlappingRecords.length > 0) {
            const conflictMessage =
              "تم رفض طلب تسجيل الحضور تلقائياً لوجود تسجيل فعلي داخل الفترة المطلوبة.";

            await supabase
              .from("attendance_requests")
              .update({
                status: "rejected",
                reviewed_by: reviewerId,
                reviewed_at: new Date().toISOString(),
                review_notes: conflictMessage,
              })
              .eq("id", id);

            throw new ApiError(409, conflictMessage);
          }

          // 3. حساب عدد الساعات
          const totalHours =
            (actualCheckInTime.getTime() - requestedTime.getTime()) /
            (1000 * 60 * 60);

          // 4. إنشاء سجل كامل مقفول
          const checkInDate = requestedTime.toISOString().split("T")[0]; // Extract date in YYYY-MM-DD format
          const insertData: any = {
            employee_id: attRequest.employee_id,
            check_in_time: requestedTime.toISOString(),
            check_out_time: actualCheckInTime.toISOString(),
            date: checkInDate,
            work_hours: parseFloat(totalHours.toFixed(2)),
            status: "completed",
            notes: "تم إنشاء سجل كامل بناءً على طلب تصحيح حضور (نسيت الحضور)",
          };

          // Add optional fields only if they exist
          if (latestRecord.branch_id) {
            insertData.branch_id = latestRecord.branch_id;
          }
          if (latestRecord.latitude != null) {
            insertData.latitude = latestRecord.latitude;
          }
          if (latestRecord.longitude != null) {
            insertData.longitude = latestRecord.longitude;
          }

          console.log("📝 Insert data:", JSON.stringify(insertData));

          const { error: insertError } = await supabase.from("attendance")
            .insert(insertData);

          if (insertError) {
            console.error(
              "❌ Failed to create complete attendance record:",
              insertError,
            );
            throw new Error(
              `Failed to create attendance record: ${insertError.message}`,
            );
          }
          console.log(
            `✅ Complete attendance record created: ${
              totalHours.toFixed(2)
            } hours`,
          );
          console.log(
            `ℹ️ Old record (${latestRecord.id}) remains active/unchanged as requested`,
          );
        }
      } else if (rt.includes("check") && rt.includes("out")) {
        // ✅ CLOSE ACTIVE SESSION
        console.log("🔎 Looking for ACTIVE attendance record to close...");

        const { data: activeRecord } = await supabase
          .from("attendance")
          .select("*")
          .eq("employee_id", attRequest.employee_id)
          .eq("status", "active")
          .order("check_in_time", { ascending: false })
          .limit(1)
          .maybeSingle();

        if (activeRecord) {
          console.log(
            `✅ Found active record: ${activeRecord.id}. Closing it...`,
          );

          // حساب عدد الساعات
          const checkInTime = new Date(activeRecord.check_in_time);
          const totalHours = (requestedTime.getTime() - checkInTime.getTime()) /
            (1000 * 60 * 60);

          const { error: updateError } = await supabase
            .from("attendance")
            .update({
              check_out_time: requestedTime.toISOString(),
              work_hours: parseFloat(totalHours.toFixed(2)),
              status: "completed",
              notes: `تم تصحيح وقت الانصراف من قبل المدير (${
                totalHours.toFixed(2)
              } ساعات)`,
            })
            .eq("id", activeRecord.id);

          if (updateError) {
            console.error(
              "❌ Failed to update attendance record:",
              updateError,
            );
            throw new Error(
              `Failed to update attendance record: ${updateError.message}`,
            );
          }
          console.log(
            `✅ Active session closed successfully (${
              totalHours.toFixed(2)
            } hours)`,
          );
        } else {
          console.warn("⚠️ No active session found to close.");
        }
      }
    }
  }

  const tableMap: Record<typeof type, string> = {
    leave: "leave_requests",
    advance: "salary_advances",
    attendance: "attendance_requests",
    absence: "absence_notifications",
  };

  const { data, error } = await supabase
    .from(tableMap[type])
    .update(update)
    .eq("id", id)
    .select()
    .maybeSingle();

  if (error) {
    console.error(`[branch-request-action] DB update error for ${type} id=${id}`, {
      update,
      error,
    });
    throw new Error(`Failed to update ${type} request: ${error.message}`);
  }

  return data;
}

async function resolveReviewerForBreak(
  supabase: any,
  requestRecord: RequestRecord,
  reviewerIdRaw: string | null,
  reviewerIdFromToken: string | null,
): Promise<string | null> {
  if (reviewerIdRaw && isUuid(reviewerIdRaw)) return reviewerIdRaw;
  if (reviewerIdFromToken && isUuid(reviewerIdFromToken)) {
    return reviewerIdFromToken;
  }

  const assignedManagerId = normalizeStringId(
    (requestRecord as any).assigned_manager_id,
  );
  if (assignedManagerId && isUuid(assignedManagerId)) {
    return assignedManagerId;
  }

  const employeeId = normalizeStringId(
    (requestRecord as any).employee_id || (requestRecord as any).employeeId,
  );
  if (!employeeId || !isUuid(employeeId)) return null;

  const { data: employee } = await supabase
    .from("employees")
    .select("id, branch_id, branch")
    .eq("id", employeeId)
    .maybeSingle();

  if (employee?.branch_id) {
    const { data: managerByBranchId } = await supabase
      .from("employees")
      .select("id")
      .eq("role", "manager")
      .eq("is_active", true)
      .eq("branch_id", employee.branch_id)
      .limit(1)
      .maybeSingle();

    if (managerByBranchId?.id && isUuid(managerByBranchId.id)) {
      return managerByBranchId.id;
    }
  }

  if (employee?.branch) {
    const { data: managerByBranchName } = await supabase
      .from("employees")
      .select("id")
      .eq("role", "manager")
      .eq("is_active", true)
      .eq("branch", employee.branch)
      .limit(1)
      .maybeSingle();

    if (managerByBranchName?.id && isUuid(managerByBranchName.id)) {
      return managerByBranchName.id;
    }
  }

  const { data: anyManager } = await supabase
    .from("employees")
    .select("id")
    .eq("role", "manager")
    .eq("is_active", true)
    .limit(1)
    .maybeSingle();

  if (anyManager?.id && isUuid(anyManager.id)) {
    return anyManager.id;
  }

  return null;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse(405, { success: false, error: "Method not allowed" });
  }

  try {
    const body = await req.json();
    const type = (body.type ?? "").toString().toLowerCase() as RequestType;
    const action = (body.action ?? "").toString().toLowerCase() as ActionType;
    const id = (body.id ?? "").toString().trim();
    const reviewerInput = body.reviewerId || body.managerId || body.approvedBy;
    const reviewerIdRaw = normalizeStringId(reviewerInput);
    const reviewerIdFromToken = getReviewerIdFromAuthHeader(req);
    const notes = body.notes || body.reviewNotes;

    if (
      !type ||
      !["leave", "advance", "attendance", "absence", "break"].includes(type)
    ) {
      return jsonResponse(400, {
        success: false,
        error: "Invalid request type",
      });
    }

    if (!id) {
      return jsonResponse(400, {
        success: false,
        error: "Request id is required",
      });
    }

    if (!isUuid(id)) {
      return jsonResponse(400, {
        success: false,
        error: "Request id must be a valid UUID",
      });
    }

    if (!action || !["approve", "reject", "postpone"].includes(action)) {
      return jsonResponse(400, { success: false, error: "Invalid action" });
    }

    if (!reviewerIdRaw && !reviewerIdFromToken) {
      return jsonResponse(400, {
        success: false,
        error: "Reviewer ID is required",
      });
    }

    if (type !== "break" && action === "postpone") {
      return jsonResponse(400, {
        success: false,
        error: "Postpone action is only valid for break requests",
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SERVICE_ROLE_KEY") ??
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseKey) {
      console.error("[branch-request-action] Missing Supabase credentials");
      return jsonResponse(500, {
        success: false,
        error: "Server configuration error",
      });
    }

    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: { persistSession: false },
    });

    const requestRecord = await fetchRequestRecord(supabase, type, id);
    if (!requestRecord) {
      return jsonResponse(404, { success: false, error: "Request not found" });
    }

    // Prefer explicit reviewerId from body, otherwise token.
    // Accept non-UUID reviewer IDs as well (legacy numeric/string ids),
    // because the employees table may use non-UUID primary keys in some deployments.
    let reviewerId: string | null = reviewerIdRaw ?? reviewerIdFromToken;

    // If still missing and this is a break, try to resolve a reviewer via fallback strategy.
    if (!reviewerId && type === "break") {
      const resolvedReviewerId = await resolveReviewerForBreak(
        supabase,
        requestRecord,
        reviewerIdRaw,
        reviewerIdFromToken,
      );

      if (resolvedReviewerId) {
        console.warn(
          "[branch-request-action] Resolved break reviewer from fallback strategy",
          {
            reviewerIdRaw,
            reviewerIdFromToken,
            resolvedReviewerId,
            requestId: id,
          },
        );
        reviewerId = resolvedReviewerId;
      } else {
        console.warn(
          "[branch-request-action] Proceeding break action without reviewer id",
          { reviewerIdRaw, reviewerIdFromToken, requestId: id },
        );
        reviewerId = null;
      }
    }

    const targetEmployeeId = requestRecord.employee_id ||
      requestRecord.employeeId;
    if (!targetEmployeeId || typeof targetEmployeeId !== "string") {
      return jsonResponse(400, {
        success: false,
        error: "Request is missing employee reference",
      });
    }

    if (reviewerId && isUuid(reviewerId)) {
      const approval = await canApproveRequest(
        supabase,
        reviewerId,
        targetEmployeeId,
      );
      if (!approval.allowed) {
        return jsonResponse(403, {
          success: false,
          error: "Forbidden",
          message: approval.reason ??
            "You do not have permission to approve this request",
        });
      }
    }

      // If reviewerId is present but not a UUID, still attempt permission check
      if (reviewerId && !isUuid(reviewerId)) {
        const approval = await canApproveRequest(
          supabase,
          reviewerId,
          targetEmployeeId,
        );
        if (!approval.allowed) {
          return jsonResponse(403, {
            success: false,
            error: "Forbidden",
            message: approval.reason ??
              "You do not have permission to approve this request",
          });
        }
      }

    const updated = type === "break"
      ? await updateBreakRequest(supabase, id, action, reviewerId)
      : await updateStandardRequest(
        supabase,
        type,
        id,
        action,
        reviewerId,
        notes,
      );

    return jsonResponse(200, {
      success: true,
      message: action === "approve"
        ? "تمت الموافقة بنجاح"
        : action === "reject"
        ? "تم الرفض بنجاح"
        : "تم تأجيل الطلب",
      data: updated,
    });
  } catch (error) {
    if (error instanceof ApiError) {
      return jsonResponse(error.status, {
        success: false,
        error: error.message,
      });
    }

    console.error("[branch-request-action] Unexpected error", error);

    const debug = (Deno.env.get("DEBUG") || "").toLowerCase() === "true";
    const errMsg = debug ? (error && error.message ? error.message : String(error)) : "Internal server error";
    const payload: ApiResponse = { success: false, error: errMsg };
    if (debug && error && (error as any).stack) {
      // Include stack for debugging in non-production environments
      (payload as any).data = { stack: (error as any).stack };
    }

    return jsonResponse(500, payload);
  }
});
