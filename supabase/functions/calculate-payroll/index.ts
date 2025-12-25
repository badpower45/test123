// @ts-nocheck
/**
 * Supabase Edge Function: Calculate Payroll
 *
 * Automatically calculates payroll for employees based on BLV-verified working hours.
 * This function:
 * 1. Retrieves attendance records for the pay period
 * 2. Calculates total hours and BLV-verified hours
 * 3. Fetches employee hourly rates
 * 4. Calculates gross pay (verified hours * hourly rate)
 * 5. Applies deductions (advances, absences, etc.)
 * 6. Persists payroll records to the database
 *
 * Author: Claude Code
 * Date: 2025-11-09
 * Task: 10.2, 10.3, 10.4 - Payroll calculation with all deductions
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

// ============================================================================
// TYPES
// ============================================================================

interface AttendanceRecord {
  id: string;
  employee_id: string;
  check_in_time: string;
  check_out_time: string;
  work_hours: number;
  pause_duration_minutes: number;
  blv_verified_hours: number;
  date: string;
}

interface Employee {
  id: string;
  full_name: string;
  hourly_rate: number | null;
  monthly_salary: number | null;
  branch_id: string;
}

interface SalaryAdvance {
  id: string;
  amount: number;
  request_date: string;
}

interface Deduction {
  id: string;
  amount: number;
  reason: string;
  deduction_date: string;
}

interface PayrollCalculation {
  employee_id: string;
  employee_name: string;
  branch_id: string;
  period_start: string;
  period_end: string;
  total_hours: number;
  pause_duration_minutes: number;
  blv_verified_hours: number;
  work_days: number;
  total_shifts: number;
  hourly_rate: number;
  base_salary: number | null;
  gross_pay: number;
  advances_total: number;
  deductions_total: number;
  absence_deductions: number;
  late_deductions: number;
  net_pay: number;
  calculation_details: any;
}

interface RequestBody {
  period_start?: string; // YYYY-MM-DD
  period_end?: string; // YYYY-MM-DD
  employee_id?: string; // Optional: calculate for specific employee only
  branch_id?: string; // Optional: calculate for specific branch only
  auto_approve?: boolean; // Auto-approve payroll if true
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Calculate hours between two timestamps
 */
function calculateHours(checkIn: string, checkOut: string): number {
  const start = new Date(checkIn);
  const end = new Date(checkOut);
  const diffMs = end.getTime() - start.getTime();
  const hours = diffMs / (1000 * 60 * 60);
  return Math.round(hours * 100) / 100; // Round to 2 decimals
}

/**
 * Get expected work days in a period (excluding Fridays)
 */
function getExpectedWorkDays(startDate: string, endDate: string): number {
  const start = new Date(startDate);
  const end = new Date(endDate);
  let workDays = 0;
  
  const current = new Date(start);
  while (current <= end) {
    // Exclude Fridays (day 5)
    if (current.getDay() !== 5) {
      workDays++;
    }
    current.setDate(current.getDate() + 1);
  }
  
  return workDays;
}

/**
 * Get employee hourly rate (from hourly_rate field or calculated from monthly salary)
 */
function getEmployeeHourlyRate(employee: Employee): number {
  if (employee.hourly_rate && employee.hourly_rate > 0) {
    return employee.hourly_rate;
  }

  if (employee.monthly_salary && employee.monthly_salary > 0) {
    // Assume 26 working days per month, 8 hours per day
    const hourlyRate = employee.monthly_salary / (26 * 8);
    return Math.round(hourlyRate * 100) / 100;
  }

  return 0;
}

/**
 * Get default pay period (last 15 days)
 */
function getDefaultPayPeriod(): { period_start: string; period_end: string } {
  const today = new Date();
  const periodEnd = new Date(today);
  periodEnd.setDate(periodEnd.getDate() - 1); // Yesterday

  const periodStart = new Date(periodEnd);
  periodStart.setDate(periodStart.getDate() - 14); // 15 days ago

  return {
    period_start: periodStart.toISOString().split('T')[0],
    period_end: periodEnd.toISOString().split('T')[0],
  };
}

// ============================================================================
// MAIN HANDLER
// ============================================================================

serve(async (req) => {
  try {
    // CORS headers
    if (req.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
        },
      });
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey =
      Deno.env.get('SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseKey) {
      throw new Error('Missing service role key in function environment');
    }
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Parse request body
    let body: RequestBody = {};
    if (req.body) {
      body = await req.json();
    }

    // Get pay period (default to last 15 days if not provided)
    const defaultPeriod = getDefaultPayPeriod();
    const periodStart = body.period_start || defaultPeriod.period_start;
    const periodEnd = body.period_end || defaultPeriod.period_end;
    const autoApprove = body.auto_approve || false;

    console.log(`[Payroll Calculation] Period: ${periodStart} to ${periodEnd}`);

    // Build attendance query
    let attendanceQuery = supabase
      .from('attendance')
      .select('*')
      .gte('date', periodStart)
      .lte('date', periodEnd)
      .not('check_out_time', 'is', null); // Only completed shifts

    // Filter by employee if specified
    if (body.employee_id) {
      attendanceQuery = attendanceQuery.eq('employee_id', body.employee_id);
    }

    // Fetch attendance records
    const { data: attendanceRecords, error: attendanceError } = await attendanceQuery;

    if (attendanceError) {
      throw new Error(`Failed to fetch attendance: ${attendanceError.message}`);
    }

    if (!attendanceRecords || attendanceRecords.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          message: 'No attendance records found for the specified period',
          records_processed: 0,
        }),
        { headers: { 'Content-Type': 'application/json' } }
      );
    }

    console.log(`[Payroll Calculation] Found ${attendanceRecords.length} attendance records`);

    // Group attendance by employee
    const employeeAttendance: Map<string, AttendanceRecord[]> = new Map();
    for (const record of attendanceRecords) {
      if (!employeeAttendance.has(record.employee_id)) {
        employeeAttendance.set(record.employee_id, []);
      }
      employeeAttendance.get(record.employee_id)!.push(record);
    }

    // Fetch all employees
    const employeeIds = Array.from(employeeAttendance.keys());
    let employeeQuery = supabase
      .from('employees')
      .select('id, full_name, hourly_rate, monthly_salary, branch_id')
      .in('id', employeeIds);

    // Filter by branch if specified
    if (body.branch_id) {
      employeeQuery = employeeQuery.eq('branch_id', body.branch_id);
    }

    const { data: employees, error: employeeError } = await employeeQuery;

    if (employeeError) {
      throw new Error(`Failed to fetch employees: ${employeeError.message}`);
    }

    console.log(`[Payroll Calculation] Processing ${employees.length} employees`);

    // Calculate payroll for each employee
    const payrollRecords: PayrollCalculation[] = [];
    const errors: string[] = [];

    for (const employee of employees) {
      try {
        const records = employeeAttendance.get(employee.id) || [];

        if (records.length === 0) {
          continue;
        }

        // Calculate totals
        let totalHours = 0;
        let pauseDurationMinutes = 0;
        let blvVerifiedHours = 0;
        const workDaysSet = new Set<string>();

        for (const record of records) {
          // Use database values if available, otherwise calculate
          const hours = record.work_hours || calculateHours(record.check_in_time, record.check_out_time);
          const pauseMins = record.pause_duration_minutes || 0;
          const verifiedHours = record.blv_verified_hours || (hours - pauseMins / 60);

          totalHours += hours;
          pauseDurationMinutes += pauseMins;
          blvVerifiedHours += verifiedHours;
          workDaysSet.add(record.date);
        }

        // Round to 2 decimals
        totalHours = Math.round(totalHours * 100) / 100;
        blvVerifiedHours = Math.round(blvVerifiedHours * 100) / 100;

        const workDays = workDaysSet.size;
        const totalShifts = records.length;

        // Get hourly rate
        const hourlyRate = getEmployeeHourlyRate(employee);
        if (hourlyRate === 0) {
          errors.push(`Employee ${employee.full_name} (${employee.id}) has no hourly rate or monthly salary set`);
          continue;
        }

        // Calculate gross pay
        const grossPay = Math.round(blvVerifiedHours * hourlyRate * 100) / 100;

        // Fetch salary advances to deduct
        // Only fetch advances that are APPROVED and NOT YET DEDUCTED (or deducted in this specific payroll run if re-running)
        // We need to be careful not to double-deduct if we re-run calculation.
        // For now, we fetch all approved advances requested up to periodEnd that are not deducted.
        const { data: advances } = await supabase
          .from('advances')
          .select('id, amount, request_date')
          .eq('employee_id', employee.id)
          .eq('status', 'approved')
          .is('deducted_at', null)
          .lte('request_date', periodEnd);

        const advancesTotal = advances?.reduce((sum, adv) => sum + Number(adv.amount), 0) || 0;

        // Fetch other deductions (penalties, damages, etc.)
        // These are stored in 'deductions' table.
        const { data: deductions } = await supabase
          .from('deductions')
          .select('id, amount, reason, deduction_date')
          .eq('employee_id', employee.id)
          .gte('deduction_date', periodStart)
          .lte('deduction_date', periodEnd);

        const deductionsTotal = deductions?.reduce((sum, ded) => sum + Number(ded.amount), 0) || 0;

        // Calculate absence deductions
        // Count expected work days vs actual work days
        const expectedWorkDays = getExpectedWorkDays(periodStart, periodEnd);
        const absenceDays = Math.max(0, expectedWorkDays - workDays);
        const dailyRate = hourlyRate * 8; // Assuming 8-hour work day
        const absenceDeductions = Math.round(absenceDays * dailyRate * 100) / 100;

        // Calculate late deductions from attendance records
        let totalLateMinutes = 0;
        for (const record of records) {
          const lateMinutes = record.late_minutes || 0;
          totalLateMinutes += lateMinutes;
        }
        // Deduct 1/60 of hourly rate per late minute (after 15 min grace period per day)
        const chargeableLateMinutes = Math.max(0, totalLateMinutes - (workDays * 15));
        const lateDeductions = Math.round((chargeableLateMinutes / 60) * hourlyRate * 100) / 100;

        // Calculate net pay
        // Total Deductions = Advances + Other Deductions + Absences + Lates
        const totalDeductions = advancesTotal + deductionsTotal + absenceDeductions + lateDeductions;
        const netPay = Math.max(0, grossPay - totalDeductions);

        // Build calculation details for transparency
        const calculationDetails = {
          attendance_records: records.length,
          work_days: workDays,
          total_hours: totalHours,
          pause_duration_hours: Math.round((pauseDurationMinutes / 60) * 100) / 100,
          blv_verified_hours: blvVerifiedHours,
          hourly_rate: hourlyRate,
          gross_pay: grossPay,
          deductions: {
            advances: {
              count: advances?.length || 0,
              total: advancesTotal,
              details: advances?.map(a => ({
                id: a.id,
                amount: a.amount,
                date: a.request_date,
              })) || [],
            },
            other_deductions: {
              count: deductions?.length || 0,
              total: deductionsTotal,
              details: deductions?.map(d => ({
                id: d.id,
                amount: d.amount,
                reason: d.reason,
                date: d.deduction_date,
              })) || [],
            },
            absences: {
              expected_days: expectedWorkDays,
              actual_days: workDays,
              absent_days: absenceDays,
              daily_rate: dailyRate,
              total: absenceDeductions,
            },
            late_arrivals: {
              total_late_minutes: totalLateMinutes,
              grace_period_minutes: workDays * 15,
              chargeable_minutes: chargeableLateMinutes,
              total: lateDeductions,
            },
          },
          total_deductions: totalDeductions,
          net_pay: netPay,
          calculation_date: new Date().toISOString(),
        };

        // Create payroll record
        const payrollRecord: PayrollCalculation = {
          employee_id: employee.id,
          employee_name: employee.full_name,
          branch_id: employee.branch_id,
          period_start: periodStart,
          period_end: periodEnd,
          total_hours: totalHours,
          pause_duration_minutes: pauseDurationMinutes,
          blv_verified_hours: blvVerifiedHours,
          work_days: workDays,
          total_shifts: totalShifts,
          hourly_rate: hourlyRate,
          base_salary: employee.monthly_salary,
          gross_pay: grossPay,
          advances_total: advancesTotal,
          deductions_total: deductionsTotal,
          absence_deductions: absenceDeductions,
          late_deductions: lateDeductions,
          net_pay: netPay,
          calculation_details: calculationDetails,
        };

        payrollRecords.push(payrollRecord);

      } catch (error: any) {
        errors.push(`Error processing employee ${employee.full_name}: ${error.message}`);
        console.error(`[Payroll Error] ${error.message}`);
      }
    }

    console.log(`[Payroll Calculation] Calculated ${payrollRecords.length} payroll records`);

    // Insert payroll records into database
    const insertedRecords = [];
    const insertErrors = [];

    for (const record of payrollRecords) {
      try {
        // Check if payroll already exists for this employee and period
        const { data: existing } = await supabase
          .from('payroll')
          .select('id')
          .eq('employee_id', record.employee_id)
          .eq('period_start', record.period_start)
          .eq('period_end', record.period_end)
          .single();

        if (existing) {
          // Update existing record
          const { error: updateError } = await supabase
            .from('payroll')
            .update({
              total_hours: record.total_hours,
              pause_duration_minutes: record.pause_duration_minutes,
              blv_verified_hours: record.blv_verified_hours,
              work_days: record.work_days,
              total_shifts: record.total_shifts,
              hourly_rate: record.hourly_rate,
              base_salary: record.base_salary,
              gross_pay: record.gross_pay,
              advances_total: record.advances_total,
              deductions_total: record.deductions_total,
              absence_deductions: record.absence_deductions,
              late_deductions: record.late_deductions,
              net_pay: record.net_pay,
              calculation_details: JSON.stringify(record.calculation_details),
              is_approved: autoApprove,
              calculated_at: new Date().toISOString(),
              updated_at: new Date().toISOString(),
            })
            .eq('id', existing.id);

          if (updateError) {
            throw updateError;
          }

          insertedRecords.push({ ...record, action: 'updated', id: existing.id });
        } else {
          // Insert new record
          const { data: inserted, error: insertError } = await supabase
            .from('payroll')
            .insert({
              employee_id: record.employee_id,
              branch_id: record.branch_id,
              period_start: record.period_start,
              period_end: record.period_end,
              total_hours: record.total_hours,
              pause_duration_minutes: record.pause_duration_minutes,
              blv_verified_hours: record.blv_verified_hours,
              work_days: record.work_days,
              total_shifts: record.total_shifts,
              hourly_rate: record.hourly_rate,
              base_salary: record.base_salary,
              gross_pay: record.gross_pay,
              advances_total: record.advances_total,
              deductions_total: record.deductions_total,
              absence_deductions: record.absence_deductions,
              late_deductions: record.late_deductions,
              net_pay: record.net_pay,
              calculation_details: JSON.stringify(record.calculation_details),
              is_calculated: true,
              is_approved: autoApprove,
            })
            .select()
            .single();

          if (insertError) {
            throw insertError;
          }

          insertedRecords.push({ ...record, action: 'created', id: inserted.id });

          // Log to payroll history
          await supabase.from('payroll_history').insert({
            payroll_id: inserted.id,
            action: 'CALCULATED',
            change_reason: 'Automatic payroll calculation',
            changed_at: new Date().toISOString(),
          });

          // Mark advances as deducted
          if (record.advances_total > 0) {
            const advanceIds = record.calculation_details.deductions.advances.details.map((a: any) => a.id);
            await supabase
              .from('advances')
              .update({ deducted_at: new Date().toISOString() })
              .in('id', advanceIds);
          }
        }
      } catch (error: any) {
        insertErrors.push(`Failed to save payroll for ${record.employee_name}: ${error.message}`);
        console.error(`[Insert Error] ${error.message}`);
      }
    }

    // Return results
    return new Response(
      JSON.stringify({
        success: true,
        period: {
          start: periodStart,
          end: periodEnd,
        },
        summary: {
          employees_processed: employees.length,
          payroll_records_created: insertedRecords.filter(r => r.action === 'created').length,
          payroll_records_updated: insertedRecords.filter(r => r.action === 'updated').length,
          total_gross_pay: insertedRecords.reduce((sum, r) => sum + r.gross_pay, 0),
          total_deductions: insertedRecords.reduce(
            (sum, r) => sum + r.advances_total + r.deductions_total + r.absence_deductions + r.late_deductions,
            0
          ),
          total_net_pay: insertedRecords.reduce((sum, r) => sum + r.net_pay, 0),
        },
        records: insertedRecords,
        errors: [...errors, ...insertErrors],
      }),
      {
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      }
    );
  } catch (error: any) {
    console.error('[Payroll Calculation Error]', error);
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
        stack: error.stack,
      }),
      {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      }
    );
  }
});
