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
 * Get Cairo time (UTC+2)
 */
function getCairoNow(): Date {
  const now = new Date();
  // Convert to Cairo time (UTC+2)
  const cairoTime = new Date(now.getTime() + (2 * 60 * 60 * 1000));
  return cairoTime;
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

/**
 * Get owner employee ID
 */
async function getOwnerId(supabase: any): Promise<string | null> {
  try {
    const { data, error } = await supabase
      .from('employees')
      .select('id')
      .eq('role', 'owner')
      .limit(1)
      .single();
    
    if (error || !data) {
      console.error('[check-daily-absences] Error getting owner:', error);
      return null;
    }
    
    return data.id;
  } catch (error) {
    console.error('[check-daily-absences] Exception getting owner:', error);
    return null;
  }
}

/**
 * Send notification
 */
async function sendNotification(
  supabase: any,
  recipientId: string,
  type: string,
  title: string,
  message: string,
  senderId?: string,
  relatedId?: string
): Promise<void> {
  try {
    const { error } = await supabase
      .from('notifications')
      .insert({
        recipient_id: recipientId,
        sender_id: senderId || null,
        type: type,
        title: title,
        message: message,
        related_id: relatedId || null,
        is_read: false,
        created_at: new Date().toISOString(),
      });
    
    if (error) {
      console.error('[check-daily-absences] Error sending notification:', error);
    }
  } catch (error) {
    console.error('[check-daily-absences] Exception sending notification:', error);
  }
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

    const cairoNow = getCairoNow();
    const today = cairoNow.toISOString().split('T')[0]; // YYYY-MM-DD
    const currentHour = cairoNow.getHours();
    const currentMinutes = cairoNow.getMinutes();
    const currentTimeMinutes = currentHour * 60 + currentMinutes;

    console.log(`[check-daily-absences] Checking absences for date: ${today}`);
    console.log(`[check-daily-absences] Current Cairo time: ${cairoNow.toISOString()}`);

    // Get all active employees
    const { data: employees, error: employeesError } = await supabase
      .from('employees')
      .select('id, full_name, role, branch_id, shift_start_time, shift_end_time, hourly_rate')
      .eq('is_active', true);

    if (employeesError) {
      console.error('[check-daily-absences] Error fetching employees:', employeesError);
      return response(500, {
        error: 'Failed to fetch employees',
        details: employeesError.message,
      });
    }

    if (!employees || employees.length === 0) {
      return response(200, {
        message: 'No active employees found',
        absences: [],
      });
    }

    console.log(`[check-daily-absences] Found ${employees.length} active employees`);

    const absences = [];
    const notifications = [];

    // Check each employee
    for (const employee of employees) {
      const shiftEndMinutes = timeToMinutes(employee.shift_end_time);
      
      // Skip if shift end time is not set or hasn't passed yet
      if (shiftEndMinutes === null) {
        console.log(`[check-daily-absences] Skipping ${employee.full_name} - no shift end time`);
        continue;
      }

      // Only check if current time is past shift end time
      if (currentTimeMinutes < shiftEndMinutes) {
        console.log(`[check-daily-absences] Skipping ${employee.full_name} - shift hasn't ended yet`);
        continue;
      }

      // Check if employee has attendance record for today
      const { data: attendance, error: attendanceError } = await supabase
        .from('attendance')
        .select('id, check_in_time')
        .eq('employee_id', employee.id)
        .gte('check_in_time', `${today}T00:00:00`)
        .lt('check_in_time', `${today}T23:59:59`)
        .limit(1);

      if (attendanceError) {
        console.error(`[check-daily-absences] Error checking attendance for ${employee.full_name}:`, attendanceError);
        continue;
      }

      // If employee has attendance, skip
      if (attendance && attendance.length > 0) {
        console.log(`[check-daily-absences] ${employee.full_name} has attendance - skipping`);
        continue;
      }

      // Check if absence already exists for today
      const { data: existingAbsence, error: absenceCheckError } = await supabase
        .from('absences')
        .select('id')
        .eq('employee_id', employee.id)
        .eq('absence_date', today)
        .limit(1);

      if (absenceCheckError) {
        console.error(`[check-daily-absences] Error checking existing absence for ${employee.full_name}:`, absenceCheckError);
        continue;
      }

      if (existingAbsence && existingAbsence.length > 0) {
        console.log(`[check-daily-absences] ${employee.full_name} already has absence record - skipping`);
        continue;
      }

      // Calculate deduction amount (2 days worth)
      const shiftHours = calculateShiftHours(employee.shift_start_time, employee.shift_end_time);
      const hourlyRate = parseFloat(employee.hourly_rate) || 0;
      const dailyAmount = shiftHours * hourlyRate;
      const twoDayDeduction = dailyAmount * 2;

      console.log(`[check-daily-absences] Creating absence for ${employee.full_name}`);
      console.log(`[check-daily-absences] Shift hours: ${shiftHours}, Hourly rate: ${hourlyRate}, Deduction: ${twoDayDeduction}`);

      // Create absence record
      const { data: newAbsence, error: absenceError } = await supabase
        .from('absences')
        .insert({
          employee_id: employee.id,
          branch_id: employee.branch_id,
          absence_date: today,
          shift_start_time: employee.shift_start_time,
          shift_end_time: employee.shift_end_time,
          status: 'pending',
          deduction_amount: twoDayDeduction.toFixed(2),
          created_at: cairoNow.toISOString(),
          updated_at: cairoNow.toISOString(),
        })
        .select()
        .single();

      if (absenceError) {
        console.error(`[check-daily-absences] Error creating absence for ${employee.full_name}:`, absenceError);
        continue;
      }

      absences.push({
        employee_id: employee.id,
        employee_name: employee.full_name,
        absence_id: newAbsence.id,
        deduction_amount: twoDayDeduction,
      });

      // Determine notification recipient
      let notificationRecipientId: string | null = null;
      let notificationTitle = '';
      let notificationMessage = '';

      if (employee.role === 'manager') {
        // If employee is a manager, notify the owner
        notificationRecipientId = await getOwnerId(supabase);
        notificationTitle = 'غياب مدير';
        notificationMessage = `تنبيه: المدير ${employee.full_name} غائب يوم ${today}. يرجى مراجعة الغياب واتخاذ الإجراء المناسب.`;
        console.log(`[check-daily-absences] Manager ${employee.full_name} absent - notifying owner`);
      } else {
        // If employee is staff, notify branch manager
        if (employee.branch_id) {
          const { data: branch, error: branchError } = await supabase
            .from('branches')
            .select('manager_id, name')
            .eq('id', employee.branch_id)
            .single();

          if (!branchError && branch?.manager_id) {
            notificationRecipientId = branch.manager_id;
            notificationTitle = 'غياب موظف';
            notificationMessage = `تنبيه: الموظف ${employee.full_name} في فرع ${branch.name} غائب يوم ${today}. يرجى مراجعة الغياب واتخاذ الإجراء المناسب.`;
            console.log(`[check-daily-absences] Staff ${employee.full_name} absent - notifying branch manager`);
          }
        }

        // If no branch manager found, notify owner as fallback
        if (!notificationRecipientId) {
          notificationRecipientId = await getOwnerId(supabase);
          notificationTitle = 'غياب موظف';
          notificationMessage = `تنبيه: الموظف ${employee.full_name} غائب يوم ${today}. يرجى مراجعة الغياب واتخاذ الإجراء المناسب.`;
          console.log(`[check-daily-absences] No branch manager found - notifying owner as fallback`);
        }
      }

      // Send notification
      if (notificationRecipientId) {
        await sendNotification(
          supabase,
          notificationRecipientId,
          'ABSENCE_ALERT',
          notificationTitle,
          notificationMessage,
          employee.id,
          newAbsence.id
        );
        notifications.push({
          recipient_id: notificationRecipientId,
          employee_name: employee.full_name,
        });
      }
    }

    return response(200, {
      success: true,
      message: `Checked absences for ${today}`,
      absences_found: absences.length,
      absences: absences,
      notifications_sent: notifications.length,
      notifications: notifications,
    });

  } catch (error) {
    console.error('[check-daily-absences] Exception:', error);
    return response(500, {
      error: 'Internal server error',
      details: error instanceof Error ? error.message : String(error),
    });
  }
});

