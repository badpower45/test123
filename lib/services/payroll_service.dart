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

  // Fetch approved salary advances for an employee within a period
  Future<List<Map<String, dynamic>>> getEmployeeApprovedAdvances({
    required String employeeId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      // Prefer approved_at; fallback to created_at if approved_at is null
      final startIsoDate = startDate.toIso8601String().split('T')[0];
      final endIsoDate = endDate.toIso8601String().split('T')[0];

      // First, try approved_at window
      final approved = await _supabase
          .from('salary_advances')
          .select('id, amount, status, created_at, approved_at')
          .eq('employee_id', employeeId)
          .eq('status', 'approved')
          .gte('approved_at', '${startIsoDate}T00:00:00.000Z')
          .lte('approved_at', '${endIsoDate}T23:59:59.999Z')
          .order('approved_at', ascending: true);
      final approvedList = List<Map<String, dynamic>>.from(approved);
      // If none found by approved_at, try created_at
      if (approvedList.isNotEmpty) {
        return approvedList;
      }

        final created = await _supabase
          .from('salary_advances')
          .select('id, amount, status, created_at, approved_at')
          .eq('employee_id', employeeId)
          .eq('status', 'approved')
          .gte('created_at', '${startIsoDate}T00:00:00.000Z')
          .lte('created_at', '${endIsoDate}T23:59:59.999Z')
          .order('created_at', ascending: true);

        return List<Map<String, dynamic>>.from(created);
    } catch (e) {
      print('Error fetching approved advances: $e');
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
      print('📊 Fetching attendance report for employee: $employeeId');
      print('   📅 Date range: ${startDate.toIso8601String().split('T')[0]} to ${endDate.toIso8601String().split('T')[0]}');
      
      final response = await _supabase
        .from('daily_attendance_summary')
        .select('*')
        .eq('employee_id', employeeId)
        .gte('attendance_date', startDate.toIso8601String().split('T')[0])
        .lte('attendance_date', endDate.toIso8601String().split('T')[0])
        .order('attendance_date', ascending: true);

      final data = List<Map<String, dynamic>>.from(response);
      print('   ✅ Found ${data.length} attendance records');

      // If no data in daily_attendance_summary, try to get from attendance table
      if (data.isEmpty) {
        print('   ⚠️ No data in daily_attendance_summary, checking attendance table...');
        final attendanceResponse = await _supabase
            .from('attendance')
            .select('*')
            .eq('employee_id', employeeId)
            .gte('check_in_time', startDate.toIso8601String())
            .lte('check_in_time', endDate.add(const Duration(days: 1)).toIso8601String())
            .order('check_in_time', ascending: true);

        final attendanceData = List<Map<String, dynamic>>.from(attendanceResponse);
        print('   📋 Found ${attendanceData.length} records in attendance table');

        // Convert attendance records to daily_attendance_summary format
        final convertedData = <Map<String, dynamic>>[];
        for (var record in attendanceData) {
          final checkInTime = record['check_in_time'] != null
              ? DateTime.tryParse(record['check_in_time'])
              : null;
          final checkOutTime = record['check_out_time'] != null
              ? DateTime.tryParse(record['check_out_time'])
              : null;

          final dateStr = checkInTime != null
              ? checkInTime.toIso8601String().split('T')[0]
              : (record['attendance_date'] ?? '--');
          // Store full ISO timestamp so TimeUtils can handle Cairo timezone conversion
          final checkInTimeStr = checkInTime != null
              ? checkInTime.toIso8601String()
              : '--';
          final checkOutTimeStr = checkOutTime != null
              ? checkOutTime.toIso8601String()
              : '--';

          double workHours = 0.0;
          if (record['work_hours'] != null) {
            if (record['work_hours'] is num) {
              workHours = (record['work_hours'] as num).toDouble();
            } else {
              workHours = double.tryParse(record['work_hours'].toString()) ?? 0.0;
            }
          } else if (checkInTime != null && checkOutTime != null) {
            // Calculate from times if work_hours is not available
            workHours = checkOutTime.difference(checkInTime).inMinutes / 60.0;
          }

          final hourlyRate = record['hourly_rate'] != null
              ? ((record['hourly_rate'] is num)
                  ? (record['hourly_rate'] as num).toDouble()
                  : double.tryParse(record['hourly_rate'].toString()) ?? 0.0)
              : 0.0;

          convertedData.add({
            'employee_id': employeeId,
            'attendance_date': dateStr,
            'check_in_time': checkInTimeStr,
            'check_out_time': checkOutTimeStr,
            'total_hours': workHours,
            'hourly_rate': hourlyRate,
            'daily_salary': workHours * hourlyRate,
            'is_absent': false,
            'is_on_leave': false,
          });
        }

        return convertedData;
      }

      // Ensure check_in_time and check_out_time are always present in daily_attendance_summary data
      for (final row in data) {
        bool missingCheckIn = row['check_in_time'] == null || row['check_in_time'].toString().isEmpty || row['check_in_time'] == '--';
        bool missingCheckOut = row['check_out_time'] == null || row['check_out_time'].toString().isEmpty || row['check_out_time'] == '--';

        if (missingCheckIn || missingCheckOut) {
          // Try to fetch from attendance table for this employee and date
          final attendanceResp = await _supabase
              .from('attendance')
              .select('check_in_time, check_out_time')
              .eq('employee_id', employeeId)
              .gte('check_in_time', row['attendance_date'] + 'T00:00:00')
              .lte('check_in_time', row['attendance_date'] + 'T23:59:59')
              .order('check_in_time', ascending: true);
          final attendanceList = List<Map<String, dynamic>>.from(attendanceResp);
          if (attendanceList.isNotEmpty) {
            final att = attendanceList.first;
            // Store full ISO timestamp so TimeUtils can handle Cairo timezone conversion
            if (missingCheckIn && att['check_in_time'] != null) {
              row['check_in_time'] = att['check_in_time'].toString();
            }
            if (missingCheckOut && att['check_out_time'] != null) {
              row['check_out_time'] = att['check_out_time'].toString();
            }
          }
        }
        row['check_in_time'] = (row['check_in_time'] != null && row['check_in_time'].toString().isNotEmpty)
            ? row['check_in_time']
            : '--';
        row['check_out_time'] = (row['check_out_time'] != null && row['check_out_time'].toString().isNotEmpty)
            ? row['check_out_time']
            : '--';
      }

      return data;
    } catch (e) {
      print('❌ Error getting attendance report: $e');
      print('   Stack trace: ${StackTrace.current}');
      return [];
    }
  }

  // 3b. Get employee attendance report in old API format (for compatibility)
  Future<Map<String, dynamic>> getEmployeeAttendanceReportLegacyFormat({
    required String employeeId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      // Get attendance records
      final attendanceRecords = await getEmployeeAttendanceReport(
        employeeId: employeeId,
        startDate: startDate,
        endDate: endDate,
      );

      // Get salary advances for this period
      final advances = await getEmployeeApprovedAdvances(
        employeeId: employeeId,
        startDate: startDate,
        endDate: endDate,
      );
      
      // Get deductions for this period
      final deductionsResponse = await _supabase
        .from('deductions')
        .select('*')
        .eq('employee_id', employeeId)
        .gte('deduction_date', startDate.toIso8601String().split('T')[0])
        .lte('deduction_date', endDate.toIso8601String().split('T')[0]);
      
      final deductions = List<Map<String, dynamic>>.from(deductionsResponse);

      // Get leave requests for this period
      final leavesResponse = await _supabase
        .from('leave_requests')
        .select('*')
        .eq('employee_id', employeeId)
        .eq('status', 'approved')
        .gte('start_date', startDate.toIso8601String().split('T')[0])
        .lte('end_date', endDate.toIso8601String().split('T')[0]);
      
      final leaves = List<Map<String, dynamic>>.from(leavesResponse);

      // Build table rows
      final tableRows = <Map<String, dynamic>>[];
      double totalWorkHours = 0.0;
      double totalAdvances = 0.0;
      double totalLeaveAllowances = 0.0;
      double totalDeductions = 0.0;
      double grossSalary = 0.0;

      // Create a map of dates to track data
      final dateMap = <String, Map<String, dynamic>>{};
      
      // Fill attendance data
      for (var record in attendanceRecords) {
        final date = record['attendance_date'] as String;
        final hours = (record['total_hours'] ?? 0.0) is num
            ? (record['total_hours'] as num).toDouble()
            : double.tryParse(record['total_hours'].toString()) ?? 0.0;
        final hourlyRate = (record['hourly_rate'] ?? 0.0) is num
            ? (record['hourly_rate'] as num).toDouble()
            : double.tryParse(record['hourly_rate'].toString()) ?? 0.0;

        totalWorkHours += hours;
        grossSalary += hours * hourlyRate;

        // ✅ Times are now full ISO strings - display as-is (TimeUtils will handle in UI)
        final checkInTime = record['check_in_time'] as String? ?? '--';
        final checkOutTime = record['check_out_time'] as String? ?? '--';

        dateMap[date] = {
          'date': date,
          'checkIn': checkInTime,
          'checkOut': checkOutTime,
          'workHours': hours.toStringAsFixed(2),
          'advances': '0.00',
          'leaveAllowance': '0.00',
          'deductions': '0.00',
          'hasLeave': false,
        };
      }

      // Add advances
      for (var advance in advances) {
        final amount = (advance['amount'] ?? 0.0) is num
            ? (advance['amount'] as num).toDouble()
            : double.tryParse(advance['amount'].toString()) ?? 0.0;
        totalAdvances += amount;
        
        // Try to map to a date (use approved_at or created_at)
        final dateStr = advance['approved_at'] != null
            ? (advance['approved_at'] as String).split('T')[0]
            : (advance['created_at'] as String).split('T')[0];
        
        if (dateMap.containsKey(dateStr)) {
          dateMap[dateStr]!['advances'] = amount.toStringAsFixed(2);
        }
      }

      // Add deductions
      for (var deduction in deductions) {
        final amount = (deduction['amount'] ?? 0.0) is num
            ? (deduction['amount'] as num).toDouble()
            : double.tryParse(deduction['amount'].toString()) ?? 0.0;
        totalDeductions += amount;
        
        final dateStr = (deduction['deduction_date'] as String).split('T')[0];
        if (dateMap.containsKey(dateStr)) {
          final existing = double.tryParse(dateMap[dateStr]!['deductions']) ?? 0.0;
          dateMap[dateStr]!['deductions'] = (existing + amount).toStringAsFixed(2);
        }
      }

      // Add leave allowances
      for (var leave in leaves) {
        // ✅ FIX: Safe date parsing for leaves
        final startDateStr = leave['start_date']?.toString();
        final endDateStr = leave['end_date']?.toString();
        
        if (startDateStr == null || startDateStr.isEmpty || 
            endDateStr == null || endDateStr.isEmpty) {
          print('⚠️ Skipping leave with invalid dates: $leave');
          continue;
        }
        
        DateTime leaveStart;
        DateTime leaveEnd;
        try {
          leaveStart = DateTime.parse(startDateStr);
          leaveEnd = DateTime.parse(endDateStr);
        } catch (e) {
          print('⚠️ Error parsing leave dates: $e');
          continue;
        }
        
        // Calculate leave allowance (assuming daily rate based on hourly_rate * 8 hours)
        // We'll need to get the employee's hourly rate
        final employeeData = await _supabase
          .from('employees')
          .select('hourly_rate, shift_start_time, shift_end_time')
          .eq('id', employeeId)
          .single();
        
        final hourlyRate = (employeeData['hourly_rate'] ?? 0.0) is num
            ? (employeeData['hourly_rate'] as num).toDouble()
            : double.tryParse(employeeData['hourly_rate'].toString()) ?? 0.0;
        
        // Calculate shift hours
        double shiftHours = 8.0; // default
        if (employeeData['shift_start_time'] != null && employeeData['shift_end_time'] != null) {
          final startTime = _parseTime(employeeData['shift_start_time']);
          final endTime = _parseTime(employeeData['shift_end_time']);
          if (startTime != null && endTime != null) {
            shiftHours = endTime.difference(startTime).inMinutes / 60.0;
          }
        }
        
        final dailyAllowance = hourlyRate * shiftHours;
        
        // Mark each day of leave
        for (var date = leaveStart; date.isBefore(leaveEnd.add(const Duration(days: 1))); date = date.add(const Duration(days: 1))) {
          final dateStr = date.toIso8601String().split('T')[0];
          if (!dateMap.containsKey(dateStr)) {
            dateMap[dateStr] = {
              'date': dateStr,
              'checkIn': '--',
              'checkOut': '--',
              'workHours': '0.00',
              'advances': '0.00',
              'leaveAllowance': dailyAllowance.toStringAsFixed(2),
              'deductions': '0.00',
              'hasLeave': true,
            };
          } else {
            dateMap[dateStr]!['leaveAllowance'] = dailyAllowance.toStringAsFixed(2);
            dateMap[dateStr]!['hasLeave'] = true;
          }
          totalLeaveAllowances += dailyAllowance;
        }
      }

      // Convert map to sorted list
      final sortedDates = dateMap.keys.toList()..sort();
      for (var date in sortedDates) {
        tableRows.add(dateMap[date]!);
      }

      // Calculate summary
      final netAfterAdvances = grossSalary + totalLeaveAllowances - totalAdvances - totalDeductions;

      return {
        'tableRows': tableRows,
        'summary': {
          'totalWorkDays': attendanceRecords.length,
          'totalWorkHours': totalWorkHours.toStringAsFixed(2),
          'totalAdvances': totalAdvances.toStringAsFixed(2),
          'totalLeaveAllowances': totalLeaveAllowances.toStringAsFixed(2),
          'totalDeductions': totalDeductions.toStringAsFixed(2),
          'grossSalary': grossSalary.toStringAsFixed(2),
          'netAfterAdvances': netAfterAdvances.toStringAsFixed(2),
        },
      };
    } catch (e) {
      print('❌ Error getting legacy format attendance report: $e');
      print('   Stack trace: ${StackTrace.current}');
      return {
        'tableRows': [],
        'summary': {
          'totalWorkDays': 0,
          'totalWorkHours': '0.00',
          'totalAdvances': '0.00',
          'totalLeaveAllowances': '0.00',
          'totalDeductions': '0.00',
          'grossSalary': '0.00',
          'netAfterAdvances': '0.00',
        },
      };
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
