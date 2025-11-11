import 'package:supabase_flutter/supabase_flutter.dart';

class PayrollService {
  final _supabase = Supabase.instance.client;

  // 1. Get all branches with pending payrolls
  Future<List<Map<String, dynamic>>> getBranchPayrollSummary() async {
    try {
      // Get current month cycle for all branches
      final startOfMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
      final endOfMonth = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
      
      final response = await _supabase
          .from('payroll_cycles')
          .select('''
            id,
            branch_id,
            branches!inner(id, name, location),
            start_date,
            end_date,
            total_amount,
            status,
            paid_at
          ''')
          .gte('end_date', startOfMonth.toIso8601String().split('T')[0])
          .lte('start_date', endOfMonth.toIso8601String().split('T')[0])
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting branch payroll summary: $e');
      return [];
    }
  }

  // 2. Get employees payroll for a specific branch cycle
  Future<List<Map<String, dynamic>>> getBranchEmployeesPayroll(String cycleId) async {
    try {
      final response = await _supabase
          .from('employee_payrolls')
          .select('''
            id,
            employee_id,
            employees!inner(id, name, email),
            total_hours,
            hourly_rate,
            base_salary,
            leave_allowance,
            total_advances,
            absence_days,
            total_deductions,
            net_salary,
            status,
            paid_at
          ''')
          .eq('payroll_cycle_id', cycleId)
          .order('net_salary', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting employees payroll: $e');
      return [];
    }
  }

  // 3. Get employee attendance details for report
  Future<List<Map<String, dynamic>>> getEmployeeAttendanceReport({
    required String employeeId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await _supabase
          .from('daily_attendance_summary')
          .select('*')
          .eq('employee_id', employeeId)
          .gte('attendance_date', startDate.toIso8601String().split('T')[0])
          .lte('attendance_date', endDate.toIso8601String().split('T')[0])
          .order('attendance_date', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting attendance report: $e');
      return [];
    }
  }

  // 4. Create or update payroll cycle for a branch
  Future<String?> createOrUpdatePayrollCycle({
    required String branchId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      // Check if cycle exists
      final existing = await _supabase
          .from('payroll_cycles')
          .select('id')
          .eq('branch_id', branchId)
          .eq('start_date', startDate.toIso8601String().split('T')[0])
          .eq('end_date', endDate.toIso8601String().split('T')[0])
          .maybeSingle();

      if (existing != null) {
        return existing['id'] as String;
      }

      // Create new cycle
      final response = await _supabase
          .from('payroll_cycles')
          .insert({
            'branch_id': branchId,
            'start_date': startDate.toIso8601String().split('T')[0],
            'end_date': endDate.toIso8601String().split('T')[0],
            'status': 'pending',
          })
          .select('id')
          .single();

      return response['id'] as String;
    } catch (e) {
      print('Error creating payroll cycle: $e');
      return null;
    }
  }

  // 5. Calculate payroll for all employees in a branch
  Future<bool> calculateBranchPayroll({
    required String cycleId,
    required List<String> employeeIds,
  }) async {
    try {
      // Call database function for each employee
      for (final employeeId in employeeIds) {
        await _supabase.rpc('calculate_employee_payroll', params: {
          'p_payroll_cycle_id': cycleId,
          'p_employee_id': employeeId,
        });
      }

      // Update cycle total
      final employeePayrolls = await _supabase
          .from('employee_payrolls')
          .select('net_salary')
          .eq('payroll_cycle_id', cycleId);

      final total = employeePayrolls.fold<double>(
        0,
        (sum, item) => sum + ((item['net_salary'] as num?)?.toDouble() ?? 0),
      );

      await _supabase
          .from('payroll_cycles')
          .update({'total_amount': total})
          .eq('id', cycleId);

      return true;
    } catch (e) {
      print('Error calculating branch payroll: $e');
      return false;
    }
  }

  // 6. Mark branch payroll as paid
  Future<bool> markBranchPayrollPaid({
    required String cycleId,
    required String paidBy,
  }) async {
    try {
      await _supabase.from('payroll_cycles').update({
        'status': 'paid',
        'paid_at': DateTime.now().toIso8601String(),
        'paid_by': paidBy,
      }).eq('id', cycleId);

      return true;
    } catch (e) {
      print('Error marking payroll as paid: $e');
      return false;
    }
  }

  // 7. Mark individual employee payroll as paid
  Future<bool> markEmployeePayrollPaid({
    required String payrollId,
    required String cycleId,
  }) async {
    try {
      // Update employee payroll
      await _supabase.from('employee_payrolls').update({
        'status': 'paid',
        'paid_at': DateTime.now().toIso8601String(),
      }).eq('id', payrollId);

      // Recalculate cycle total (only unpaid employees)
      final unpaidPayrolls = await _supabase
          .from('employee_payrolls')
          .select('net_salary')
          .eq('payroll_cycle_id', cycleId)
          .eq('status', 'pending');

      final total = unpaidPayrolls.fold<double>(
        0,
        (sum, item) => sum + ((item['net_salary'] as num?)?.toDouble() ?? 0),
      );

      await _supabase
          .from('payroll_cycles')
          .update({'total_amount': total})
          .eq('id', cycleId);

      return true;
    } catch (e) {
      print('Error marking employee payroll as paid: $e');
      return false;
    }
  }

  // 8. Sync daily attendance (called after check-in/check-out)
  Future<bool> syncDailyAttendance({
    required String employeeId,
    required DateTime date,
    required String? checkInTime,
    required String? checkOutTime,
    required double hourlyRate,
  }) async {
    try {
      double totalHours = 0;
      
      if (checkInTime != null && checkOutTime != null) {
        final checkIn = _parseTime(checkInTime);
        final checkOut = _parseTime(checkOutTime);
        if (checkIn != null && checkOut != null) {
          totalHours = (checkOut.difference(checkIn).inMinutes / 60.0);
        }
      }

      final dailySalary = totalHours * hourlyRate;

      await _supabase.from('daily_attendance_summary').upsert({
        'employee_id': employeeId,
        'attendance_date': date.toIso8601String().split('T')[0],
        'check_in_time': checkInTime,
        'check_out_time': checkOutTime,
        'total_hours': totalHours,
        'hourly_rate': hourlyRate,
        'daily_salary': dailySalary,
        'is_absent': false,
      }, onConflict: 'employee_id,attendance_date');

      return true;
    } catch (e) {
      print('Error syncing daily attendance: $e');
      return false;
    }
  }

  // 9. Mark day as absent
  Future<bool> markDayAbsent({
    required String employeeId,
    required DateTime date,
  }) async {
    try {
      await _supabase.from('daily_attendance_summary').upsert({
        'employee_id': employeeId,
        'attendance_date': date.toIso8601String().split('T')[0],
        'is_absent': true,
        'total_hours': 0,
        'daily_salary': 0,
      }, onConflict: 'employee_id,attendance_date');

      return true;
    } catch (e) {
      print('Error marking absent: $e');
      return false;
    }
  }

  // 10. Get all employees attendance report for Owner (comprehensive view)
  static Future<List<Map<String, dynamic>>> getAllEmployeesAttendanceReport({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      
      // Get all employees
      final employeesResponse = await supabase
          .from('employees')
          .select('id, fullName, branch, hourlyRate, isActive')
          .eq('isActive', true);
      
      final employees = List<Map<String, dynamic>>.from(employeesResponse);
      final List<Map<String, dynamic>> result = [];

      for (var employee in employees) {
        final employeeId = employee['id'] as String;
        final employeeName = employee['fullName'] as String? ?? 'موظف';
        final branch = employee['branch'] as String? ?? 'غير محدد';
        final hourlyRate = (employee['hourlyRate'] as num?)?.toDouble() ?? 0;

        // Get attendance data for this employee
        final attendanceResponse = await supabase
            .from('daily_attendance_summary')
            .select()
            .eq('employee_id', employeeId)
            .gte('attendance_date', startDate.toIso8601String().split('T')[0])
            .lte('attendance_date', endDate.toIso8601String().split('T')[0])
            .order('attendance_date', ascending: true);

        final attendanceRecords = List<Map<String, dynamic>>.from(attendanceResponse);

        // Calculate summary
        double totalHours = 0;
        double totalAdvances = 0;
        double totalDeductions = 0;
        int absenceDays = 0;

        for (var record in attendanceRecords) {
          totalHours += (record['total_hours'] as num?)?.toDouble() ?? 0;
          totalAdvances += (record['advance_amount'] as num?)?.toDouble() ?? 0;
          totalDeductions += (record['deduction_amount'] as num?)?.toDouble() ?? 0;
          if (record['is_absent'] == true) {
            absenceDays++;
          }
        }

        final baseSalary = totalHours * hourlyRate;
        final leaveAllowance = (absenceDays > 0 && absenceDays < 3) ? 100.0 : 0.0;
        final netSalary = baseSalary + leaveAllowance - totalAdvances - totalDeductions;

        result.add({
          'employee_id': employeeId,
          'employee_name': employeeName,
          'branch': branch,
          'summary': {
            'total_hours': totalHours,
            'hourly_rate': hourlyRate,
            'base_salary': baseSalary,
            'leave_allowance': leaveAllowance,
            'total_advances': totalAdvances,
            'total_deductions': totalDeductions,
            'absence_days': absenceDays,
            'net_salary': netSalary,
          },
          'attendance_records': attendanceRecords,
        });
      }

      return result;
    } catch (e) {
      print('Error getting all employees attendance report: $e');
      return [];
    }
  }

  // Helper: Parse time string to DateTime
  DateTime? _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      final now = DateTime.now();
      return DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
    } catch (e) {
      return null;
    }
  }
}
