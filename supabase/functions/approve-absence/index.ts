// @ts-nocheck
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

type JsonRecord = Record<string, unknown>;

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

/**
 * Parse time string (HH:MM) to minutes
 */
function timeToMinutes(timeStr: string | null | undefined): number | null {
  if (!timeStr) return null;
  const parts = timeStr.split(':');
  if (parts.length !== 2) return null;
  const hours = parseInt(parts[0], 10);
  const minutes = parseInt(parts[1], 10);
  if (isNaN(hours) || isNaN(minutes)) return null;
  return hours * 60 + minutes;
}

/**
 * Calculate shift hours from start and end time
 */
function calculateShiftHours(startTime: string | null, endTime: string | null): number {
  const startMinutes = timeToMinutes(startTime);
  const endMinutes = timeToMinutes(endTime);
  
  if (startMinutes === null || endMinutes === null) {
    return 8; // Default 8 hours if times are not set
  }
  
  let hours = (endMinutes - startMinutes) / 60;
  
  // Handle overnight shifts (e.g., 21:00 to 05:00)
  if (hours < 0) {
    hours += 24;
  }
  
  return hours;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return response(200, {});
  }

  try {
    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    
    if (!supabaseUrl || !supabaseServiceKey) {
      return response(500, {
        error: 'Missing Supabase configuration',
      });
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Parse request body
    const body = await req.json();
    const { absence_id, reviewer_id, action, reason } = body;

    if (!absence_id || !reviewer_id || !action) {
      return response(400, {
        error: 'Missing required fields: absence_id, reviewer_id, action',
      });
    }

    if (action !== 'approve' && action !== 'reject') {
      return response(400, {
        error: 'Invalid action. Must be "approve" or "reject"',
      });
    }

    console.log(`[approve-absence] Processing ${action} for absence ${absence_id} by ${reviewer_id}`);

    // Get absence record
    const { data: absence, error: absenceError } = await supabase
      .from('absences')
      .select('*')
      .eq('id', absence_id)
      .single();

    if (absenceError || !absence) {
      console.error('[approve-absence] Error fetching absence:', absenceError);
      return response(404, {
        error: 'Absence not found',
        details: absenceError?.message,
      });
    }

    // Get employee info
    const { data: employee, error: employeeError } = await supabase
      .from('employees')
      .select('id, full_name, hourly_rate, shift_start_time, shift_end_time')
      .eq('id', absence.employee_id)
      .single();

    if (employeeError || !employee) {
      console.error('[approve-absence] Error fetching employee:', employeeError);
      return response(404, {
        error: 'Employee not found',
        details: employeeError?.message,
      });
    }

    const hourlyRate = parseFloat(employee.hourly_rate) || 0;
    const shiftHours = calculateShiftHours(
      absence.shift_start_time || employee.shift_start_time,
      absence.shift_end_time || employee.shift_end_time
    );

    // Calculate deduction: 2 days worth
    const dailyAmount = shiftHours * hourlyRate;
    const twoDayDeduction = dailyAmount * 2;

    console.log(`[approve-absence] Shift hours: ${shiftHours}, Hourly rate: ${hourlyRate}`);
    console.log(`[approve-absence] Daily amount: ${dailyAmount}, Two-day deduction: ${twoDayDeduction}`);

    // Update absence status
    const newStatus = action === 'approve' ? 'approved' : 'rejected';
    const managerResponse = reason || (action === 'approve' 
      ? 'موافق على الغياب - سيتم خصم يومين' 
      : 'مرفوض - خصم يومين');

    const { error: updateError } = await supabase
      .from('absences')
      .update({
        status: newStatus,
        manager_response: managerResponse,
        manager_id: reviewer_id,
        deduction_amount: twoDayDeduction.toFixed(2),
        updated_at: new Date().toISOString(),
      })
      .eq('id', absence_id);

    if (updateError) {
      console.error('[approve-absence] Error updating absence:', updateError);
      return response(500, {
        error: 'Failed to update absence',
        details: updateError.message,
      });
    }

    // If approved, apply deduction
    if (action === 'approve') {
      // Create deduction record
      const { data: deduction, error: deductionError } = await supabase
        .from('deductions')
        .insert({
          employee_id: absence.employee_id,
          absence_id: absence_id,
          amount: -twoDayDeduction, // Negative value
          reason: `خصم غياب يوم ${absence.absence_date} - ${twoDayDeduction.toFixed(2)} جنيه (يومين عمل)`,
          deduction_date: absence.absence_date,
          created_at: new Date().toISOString(),
        })
        .select()
        .single();

      if (deductionError) {
        console.error('[approve-absence] Error creating deduction:', deductionError);
        return response(500, {
          error: 'Failed to create deduction record',
          details: deductionError.message,
        });
      }

      // Update or create daily_attendance_summary record
      const absenceDate = absence.absence_date;
      
      // Check if daily_attendance_summary record exists
      const { data: existingSummary, error: summaryCheckError } = await supabase
        .from('daily_attendance_summary')
        .select('*')
        .eq('employee_id', absence.employee_id)
        .eq('attendance_date', absenceDate)
        .maybeSingle();

      if (summaryCheckError && summaryCheckError.code !== 'PGRST116') {
        console.error('[approve-absence] Error checking daily summary:', summaryCheckError);
      }

      const summaryData = {
        employee_id: absence.employee_id,
        attendance_date: absenceDate,
        check_in_time: null,
        check_out_time: null,
        total_hours: 0,
        hourly_rate: hourlyRate,
        daily_salary: 0,
        advance_amount: 0,
        leave_allowance: 0,
        deduction_amount: twoDayDeduction,
        is_absent: true,
        is_on_leave: false,
        created_at: new Date().toISOString(),
      };

      if (existingSummary) {
        // Update existing record
        const { error: updateSummaryError } = await supabase
          .from('daily_attendance_summary')
          .update({
            deduction_amount: twoDayDeduction,
            is_absent: true,
          })
          .eq('employee_id', absence.employee_id)
          .eq('attendance_date', absenceDate);

        if (updateSummaryError) {
          console.error('[approve-absence] Error updating daily summary:', updateSummaryError);
          return response(500, {
            error: 'Failed to update daily attendance summary',
            details: updateSummaryError.message,
          });
        }
      } else {
        // Create new record
        const { error: insertSummaryError } = await supabase
          .from('daily_attendance_summary')
          .insert(summaryData);

        if (insertSummaryError) {
          console.error('[approve-absence] Error creating daily summary:', insertSummaryError);
          return response(500, {
            error: 'Failed to create daily attendance summary',
            details: insertSummaryError.message,
          });
        }
      }

      console.log(`[approve-absence] Successfully applied deduction: ${twoDayDeduction.toFixed(2)} EGP`);
      console.log(`[approve-absence] Updated daily_attendance_summary for ${absenceDate}`);

      return response(200, {
        success: true,
        message: `تم الموافقة على الغياب وتم خصم ${twoDayDeduction.toFixed(2)} جنيه (يومين عمل)`,
        absence: {
          id: absence_id,
          status: newStatus,
          deduction_amount: twoDayDeduction,
        },
        deduction: {
          id: deduction.id,
          amount: -twoDayDeduction,
          reason: deduction.reason,
        },
        daily_summary_updated: true,
      });
    } else {
      // Rejected - no deduction applied
      return response(200, {
        success: true,
        message: 'تم رفض الغياب',
        absence: {
          id: absence_id,
          status: newStatus,
        },
      });
    }

  } catch (error) {
    console.error('[approve-absence] Exception:', error);
    return response(500, {
      error: 'Internal server error',
      details: error instanceof Error ? error.message : String(error),
    });
  }
});

