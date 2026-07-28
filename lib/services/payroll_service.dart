import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class PayrollService {
  final _supabase = Supabase.instance.client;

  // 1. Get all branches with pending payrolls
  Future<List<Map<String, dynamic>>> getBranchPayrollSummary() async {
    try {
      // Get current month cycle for all branches
      final startOfMonth = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        1,
      );
      final endOfMonth = DateTime(
        DateTime.now().year,
        DateTime.now().month + 1,
        0,
      );

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
  Future<List<Map<String, dynamic>>> getBranchEmployeesPayroll(
    String cycleId,
  ) async {
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
      print(
        '   📅 Date range: ${startDate.toIso8601String().split('T')[0]} to ${endDate.toIso8601String().split('T')[0]}',
      );

      final employeeResp = await _supabase
          .from('employees')
          .select('hourly_rate')
          .eq('id', employeeId)
          .maybeSingle();

      final employeeHourlyRate = (employeeResp?['hourly_rate'] is num)
          ? (employeeResp?['hourly_rate'] as num).toDouble()
          : double.tryParse(employeeResp?['hourly_rate']?.toString() ?? '') ??
                0.0;

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
        print(
          '   ⚠️ No data in daily_attendance_summary, checking attendance table...',
        );

        final startDateStr = startDate.toIso8601String().split('T')[0];
        final endDateStr = endDate.toIso8601String().split('T')[0];

        final attendanceResponse = await _supabase
            .from('attendance')
            .select('*')
            .eq('employee_id', employeeId)
            .gte('date', startDateStr)
            .lte('date', endDateStr)
            .order('date', ascending: true);

        final attendanceData = List<Map<String, dynamic>>.from(
          attendanceResponse,
        );
        print(
          '   📋 Found ${attendanceData.length} records in attendance table',
        );

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
              : (record['date'] ?? record['attendance_date'] ?? '--');
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
              workHours =
                  double.tryParse(record['work_hours'].toString()) ?? 0.0;
            }
          } else if (checkInTime != null && checkOutTime != null) {
            // Calculate from times if work_hours is not available
            workHours = checkOutTime.difference(checkInTime).inMinutes / 60.0;
          }

          final hourlyRate = record['hourly_rate'] != null
              ? ((record['hourly_rate'] is num)
                    ? (record['hourly_rate'] as num).toDouble()
                    : double.tryParse(record['hourly_rate'].toString()) ?? 0.0)
              : employeeHourlyRate;

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
        bool missingCheckIn =
            row['check_in_time'] == null ||
            row['check_in_time'].toString().isEmpty ||
            row['check_in_time'] == '--';
        bool missingCheckOut =
            row['check_out_time'] == null ||
            row['check_out_time'].toString().isEmpty ||
            row['check_out_time'] == '--';

        if (missingCheckIn || missingCheckOut) {
          // Try to fetch from attendance table for this employee and date
          final attendanceResp = await _supabase
              .from('attendance')
              .select('check_in_time, check_out_time, work_hours, hourly_rate')
              .eq('employee_id', employeeId)
              .eq('date', row['attendance_date'])
              .order('check_in_time', ascending: true);
          final attendanceList = List<Map<String, dynamic>>.from(
            attendanceResp,
          );
          if (attendanceList.isNotEmpty) {
            final att = attendanceList.first;
            // Store full ISO timestamp so TimeUtils can handle Cairo timezone conversion
            if (missingCheckIn && att['check_in_time'] != null) {
              row['check_in_time'] = att['check_in_time'].toString();
            }
            if (missingCheckOut && att['check_out_time'] != null) {
              row['check_out_time'] = att['check_out_time'].toString();
            }
            // Also fill in work hours and hourly rate if missing
            if ((row['total_hours'] ?? 0) == 0 && att['work_hours'] != null) {
              row['total_hours'] = att['work_hours'];
            }
            if ((row['hourly_rate'] ?? 0) == 0) {
              if (att['hourly_rate'] != null) {
                row['hourly_rate'] = att['hourly_rate'];
              } else {
                row['hourly_rate'] = employeeHourlyRate;
              }
            }
          }
        }
        if ((row['hourly_rate'] ?? 0) == 0) {
          row['hourly_rate'] = employeeHourlyRate;
        }
        if ((row['daily_salary'] ?? 0) == 0) {
          final hours = (row['total_hours'] is num)
              ? (row['total_hours'] as num).toDouble()
              : double.tryParse(row['total_hours']?.toString() ?? '') ?? 0.0;
          final rate = (row['hourly_rate'] is num)
              ? (row['hourly_rate'] as num).toDouble()
              : double.tryParse(row['hourly_rate']?.toString() ?? '') ?? 0.0;
          row['daily_salary'] = hours * rate;
        }
        row['check_in_time'] =
            (row['check_in_time'] != null &&
                row['check_in_time'].toString().isNotEmpty)
            ? row['check_in_time']
            : '--';
        row['check_out_time'] =
            (row['check_out_time'] != null &&
                row['check_out_time'].toString().isNotEmpty)
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
      // Get leave requests for this period
      final leavesResponse = await _supabase
          .from('leave_requests')
          .select('*')
          .eq('employee_id', employeeId)
          .eq('status', 'approved')
          .gte('start_date', startDate.toIso8601String().split('T')[0])
          .lte('end_date', endDate.toIso8601String().split('T')[0]);

      final leaves = List<Map<String, dynamic>>.from(leavesResponse);

      // Get bonuses and manual deductions for this period
      final bonusesResponse = await _supabase
          .from('bonuses')
          .select('*')
          .eq('employee_id', employeeId)
          .gte('bonus_date', startDate.toIso8601String().split('T')[0])
          .lte('bonus_date', endDate.toIso8601String().split('T')[0]);

      final deductionsResponse = await _supabase
          .from('deductions')
          .select('*')
          .eq('employee_id', employeeId)
          .gte('deduction_date', startDate.toIso8601String().split('T')[0])
          .lte('deduction_date', endDate.toIso8601String().split('T')[0]);

      final bonuses = List<Map<String, dynamic>>.from(bonusesResponse);
      final deductions = List<Map<String, dynamic>>.from(deductionsResponse);

      // Build table rows
      final tableRows = <Map<String, dynamic>>[];
      double totalWorkHours = 0.0;
      double totalAdvances = 0.0;
      double totalLeaveAllowances = 0.0;
      double totalBonuses = 0.0;
      double totalDeductions = 0.0;
      double totalPenalties = 0.0;
      double grossSalary = 0.0;

      // Create a map of dates to track data
      final dateMap = <String, Map<String, dynamic>>{};

      double _asDouble(dynamic value) {
        if (value is num) return value.toDouble();
        return double.tryParse(value?.toString() ?? '') ?? 0.0;
      }

      // Fill attendance data
      for (var record in attendanceRecords) {
        final date =
            record['attendance_date']?.toString() ??
            record['date']?.toString() ??
            '--';
        final hours = _asDouble(record['total_hours']);
        final hourlyRate = _asDouble(record['hourly_rate']);
        final leaveAllowance = _asDouble(record['leave_allowance']);
        final isOnLeave = record['is_on_leave'] == true || leaveAllowance > 0.0;

        totalWorkHours += hours;
        grossSalary += hours * hourlyRate;
        if (leaveAllowance > 0) {
          totalLeaveAllowances += leaveAllowance;
        }

        // ✅ Times are now full ISO strings - display as-is (TimeUtils will handle in UI)
        final checkInTime = record['check_in_time'] as String? ?? '--';
        final checkOutTime = record['check_out_time'] as String? ?? '--';

        dateMap[date] = {
          'date': date,
          'checkIn': checkInTime,
          'checkOut': checkOutTime,
          'workHours': hours.toStringAsFixed(2),
          'dailySalary': (hours * hourlyRate).toStringAsFixed(2),
          'advances': '0.00',
          'leaveAllowance': leaveAllowance.toStringAsFixed(2),
          'bonuses': '0.00',
          'deductions': '0.00',
          'penalties': '0.00',
          'hasLeave': isOnLeave,
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

      // Add bonuses
      for (var bonus in bonuses) {
        final amount = (bonus['amount'] ?? 0.0) is num
            ? (bonus['amount'] as num).toDouble()
            : double.tryParse(bonus['amount'].toString()) ?? 0.0;
        totalBonuses += amount;

        final dateStr = (bonus['bonus_date'] ?? bonus['created_at'] ?? '')
            .toString()
            .split('T')[0];
        if (dateMap.containsKey(dateStr)) {
          final existing = double.tryParse(dateMap[dateStr]!['bonuses']) ?? 0.0;
          dateMap[dateStr]!['bonuses'] = (existing + amount).toStringAsFixed(2);
        }
      }

      // Add deductions
      for (var deduction in deductions) {
        final amount = (deduction['amount'] ?? 0.0) is num
            ? (deduction['amount'] as num).toDouble()
            : double.tryParse(deduction['amount'].toString()) ?? 0.0;

        final typeValue =
            (deduction['deduction_type'] ?? deduction['type'] ?? '')
                .toString()
                .toLowerCase();
        final isPenalty =
            typeValue.contains('penalty') ||
            typeValue.contains('جزاء') ||
            typeValue.contains('disciplinary');

        totalDeductions += amount;
        if (isPenalty) {
          totalPenalties += amount;
        }

        final dateStr = (deduction['deduction_date'] as String).split('T')[0];
        if (dateMap.containsKey(dateStr)) {
          final existing =
              double.tryParse(dateMap[dateStr]!['deductions']) ?? 0.0;
          dateMap[dateStr]!['deductions'] = (existing + amount).toStringAsFixed(
            2,
          );
          if (isPenalty) {
            final existingPenalty =
                double.tryParse(dateMap[dateStr]!['penalties']) ?? 0.0;
            dateMap[dateStr]!['penalties'] = (existingPenalty + amount)
                .toStringAsFixed(2);
          }
        }
      }

      // Add leave allowances
      for (var leave in leaves) {
        // ✅ FIX: Safe date parsing for leaves
        final startDateStr = leave['start_date']?.toString();
        final endDateStr = leave['end_date']?.toString();

        if (startDateStr == null ||
            startDateStr.isEmpty ||
            endDateStr == null ||
            endDateStr.isEmpty) {
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
        if (employeeData['shift_start_time'] != null &&
            employeeData['shift_end_time'] != null) {
          final startTime = _parseTime(employeeData['shift_start_time']);
          final endTime = _parseTime(employeeData['shift_end_time']);
          if (startTime != null && endTime != null) {
            shiftHours = endTime.difference(startTime).inMinutes / 60.0;
          }
        }

        final dailyAllowance = hourlyRate * shiftHours;

        // Mark each day of leave
        for (
          var date = leaveStart;
          date.isBefore(leaveEnd.add(const Duration(days: 1)));
          date = date.add(const Duration(days: 1))
        ) {
          final dateStr = date.toIso8601String().split('T')[0];
          if (!dateMap.containsKey(dateStr)) {
            dateMap[dateStr] = {
              'date': dateStr,
              'checkIn': '--',
              'checkOut': '--',
              'workHours': '0.00',
              'dailySalary': '0.00',
              'advances': '0.00',
              'leaveAllowance': dailyAllowance.toStringAsFixed(2),
              'deductions': '0.00',
              'penalties': '0.00',
              'hasLeave': true,
            };
            totalLeaveAllowances += dailyAllowance;
          } else {
            final existing =
                double.tryParse(dateMap[dateStr]!['leaveAllowance']) ?? 0.0;
            dateMap[dateStr]!['hasLeave'] = true;
            if (existing <= 0) {
              dateMap[dateStr]!['leaveAllowance'] = dailyAllowance
                  .toStringAsFixed(2);
              totalLeaveAllowances += dailyAllowance;
            }
          }
        }
      }

      // Convert map to sorted list
      final sortedDates = dateMap.keys.toList()..sort();
      for (var date in sortedDates) {
        tableRows.add(dateMap[date]!);
      }

      // Calculate summary
      final netAfterAdvances =
          grossSalary +
          totalLeaveAllowances +
          totalBonuses -
          totalAdvances -
          totalDeductions;

      return {
        'tableRows': tableRows,
        'summary': {
          'totalWorkDays': attendanceRecords.length,
          'totalWorkHours': totalWorkHours.toStringAsFixed(2),
          'totalAdvances': totalAdvances.toStringAsFixed(2),
          'totalLeaveAllowances': totalLeaveAllowances.toStringAsFixed(2),
          'totalBonuses': totalBonuses.toStringAsFixed(2),
          'totalDeductions': totalDeductions.toStringAsFixed(2),
          'totalPenalties': totalPenalties.toStringAsFixed(2),
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
          'totalBonuses': '0.00',
          'totalDeductions': '0.00',
          'totalPenalties': '0.00',
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
      for (final employeeId in employeeIds) {
        await _supabase.rpc(
          'calculate_employee_payroll',
          params: {'p_payroll_cycle_id': cycleId, 'p_employee_id': employeeId},
        );
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
      await _supabase
          .from('payroll_cycles')
          .update({
            'status': 'paid',
            'paid_at': DateTime.now().toIso8601String(),
            'paid_by': paidBy,
          })
          .eq('id', cycleId);

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
      await _supabase
          .from('employee_payrolls')
          .update({
            'status': 'paid',
            'paid_at': DateTime.now().toIso8601String(),
          })
          .eq('id', payrollId);

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
    double? workHoursOverride,
  }) async {
    try {
      double totalHours = 0;

      if (workHoursOverride != null) {
        totalHours = workHoursOverride;
      } else if (checkInTime != null && checkOutTime != null) {
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
        'total_hours': double.parse(totalHours.toStringAsFixed(2)),
        'hourly_rate': hourlyRate,
        'daily_salary': double.parse(dailySalary.toStringAsFixed(2)),
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
      final startStr = startDate.toIso8601String().split('T')[0];
      final endStr = endDate.toIso8601String().split('T')[0];

      // 1. Fetch all active employees
      final employeesResponse = await supabase
          .from('employees')
          .select('id, full_name, branch, hourly_rate, is_active')
          .eq('is_active', true);

      final employees = List<Map<String, dynamic>>.from(employeesResponse);
      final employeeIds = employees.map((e) => e['id'] as String).toList();

      if (employeeIds.isEmpty) return [];

      // 2. Fetch all required payroll records in parallel
      final results = await Future.wait([
        supabase
            .from('daily_attendance_summary')
            .select()
            .inFilter('employee_id', employeeIds)
            .gte('attendance_date', startStr)
            .lte('attendance_date', endStr),
        supabase
            .from('attendance')
            .select('employee_id, work_hours')
            .inFilter('employee_id', employeeIds)
            .gte('date', startStr)
            .lte('date', endStr)
            .eq('status', 'completed'),
        supabase
            .from('salary_advances')
            .select('employee_id, amount, approved_at, created_at')
            .inFilter('employee_id', employeeIds)
            .eq('status', 'approved'),
        supabase
            .from('deductions')
            .select('employee_id, amount, deduction_date')
            .inFilter('employee_id', employeeIds)
            .gte('deduction_date', startStr)
            .lte('deduction_date', endStr),
      ]);

      final allSummaryRecords = List<Map<String, dynamic>>.from(results[0]);
      final allRawAttendance = List<Map<String, dynamic>>.from(results[1]);
      final allAdvances = List<Map<String, dynamic>>.from(results[2]);
      final allDeductions = List<Map<String, dynamic>>.from(results[3]);

      // 3. Group records by employee in memory
      final summaryByEmployee = <String, List<Map<String, dynamic>>>{};
      for (final r in allSummaryRecords) {
        final empId = r['employee_id'] as String;
        summaryByEmployee.putIfAbsent(empId, () => []).add(r);
      }

      final rawAttendanceByEmployee = <String, List<Map<String, dynamic>>>{};
      for (final r in allRawAttendance) {
        final empId = r['employee_id'] as String;
        rawAttendanceByEmployee.putIfAbsent(empId, () => []).add(r);
      }

      final advancesByEmployee = <String, List<Map<String, dynamic>>>{};
      for (final r in allAdvances) {
        final empId = r['employee_id'] as String;
        advancesByEmployee.putIfAbsent(empId, () => []).add(r);
      }

      final deductionsByEmployee = <String, List<Map<String, dynamic>>>{};
      for (final r in allDeductions) {
        final empId = r['employee_id'] as String;
        deductionsByEmployee.putIfAbsent(empId, () => []).add(r);
      }

      final List<Map<String, dynamic>> result = [];

      for (var employee in employees) {
        final employeeId = employee['id'] as String;
        final employeeName = employee['full_name'] as String? ?? 'موظف';
        final branch = employee['branch'] as String? ?? 'غير محدد';
        final hourlyRate = (employee['hourly_rate'] as num?)?.toDouble() ?? 0;

        final summaryRecords = summaryByEmployee[employeeId] ?? [];
        final rawAttendanceRecords = rawAttendanceByEmployee[employeeId] ?? [];
        final employeeAdvances = advancesByEmployee[employeeId] ?? [];
        final employeeDeductions = deductionsByEmployee[employeeId] ?? [];

        double totalHours = 0;
        double totalAdvances = 0;
        double totalDeductions = 0;
        int absenceDays = 0;

        if (summaryRecords.isNotEmpty) {
          for (var record in summaryRecords) {
            totalHours += (record['total_hours'] as num?)?.toDouble() ?? 0;
            totalAdvances += (record['advance_amount'] as num?)?.toDouble() ?? 0;
            totalDeductions +=
                (record['deduction_amount'] as num?)?.toDouble() ?? 0;
            if (record['is_absent'] == true) {
              absenceDays++;
            }
          }
        } else {
          // Fallback calculations using in-memory filtered collections
          for (var record in rawAttendanceRecords) {
            totalHours += (record['work_hours'] as num?)?.toDouble() ?? 0;
          }

          for (var row in employeeAdvances) {
            final approvedAt = row['approved_at']?.toString();
            final createdAt = row['created_at']?.toString();
            final dateValue = (approvedAt != null && approvedAt.isNotEmpty)
                ? approvedAt
                : (createdAt ?? '');
            if (dateValue.isEmpty) continue;
            final dateOnly = dateValue.split('T')[0];
            if (dateOnly.compareTo(startStr) >= 0 && dateOnly.compareTo(endStr) <= 0) {
              totalAdvances += (row['amount'] as num?)?.toDouble() ?? 0.0;
            }
          }

          for (var row in employeeDeductions) {
            totalDeductions += (row['amount'] as num?)?.toDouble() ?? 0.0;
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
          'attendance_records': summaryRecords,
        });
      }

      return result;
    } catch (e) {
      print('Error getting all employees attendance report: $e');
      return [];
    }
  }

  // Calculate leave allowance using edge function
  Future<double> calculateLeaveAllowance({
    required String employeeId,
    String? employeeName,
    int? month,
    int? year,
  }) async {
    try {
      print('📊 Calculating leave allowance for employee: $employeeId');
      if (employeeName != null) {
        print('   Employee name: $employeeName');
      }

      // Try to invoke the edge function
      print('   Invoking calculate-leave-allowance function...');
      final response = await _supabase.functions
          .invoke(
            'calculate-leave-allowance',
            body: {
              'employee_id': employeeId,
              if (employeeName != null) 'employee_name': employeeName,
              if (month != null) 'month': month,
              if (year != null) 'year': year,
            },
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('   ⏱️ Function call timeout after 10 seconds');
              throw TimeoutException('Function timeout');
            },
          );

      print('✅ Function invoked successfully');
      print('   Response type: ${response.runtimeType}');
      print('   Raw response: $response');

      // Get the data from response
      dynamic responseData = response;

      print('   Parsed data type: ${responseData.runtimeType}');

      // Extract leave_allowance from response
      double allowance = 0.0;

      if (responseData is Map<String, dynamic>) {
        // Check for success flag
        final success = responseData['success'];
        print('   Success flag: $success');

        if (success == true || success == 'true') {
          final allowanceValue = responseData['leave_allowance'];
          print(
            '   Leave allowance value: $allowanceValue (type: ${allowanceValue.runtimeType})',
          );

          if (allowanceValue != null) {
            allowance = (allowanceValue as num).toDouble();
            print(
              '✅ Leave allowance calculated: ${allowance.toStringAsFixed(2)} EGP',
            );
            print('   Leave count: ${responseData['leave_request_count']}');
            print('   Period: ${responseData['period_name']}');
            return allowance;
          }
        } else {
          print('⚠️ Function returned success=false');
          print('   Error: ${responseData['error']}');
          print('   Details: ${responseData['details']}');
          // Don't return 0 yet - check if we can extract the value anyway
          final allowanceValue = responseData['leave_allowance'];
          if (allowanceValue != null &&
              allowanceValue is num &&
              allowanceValue > 0) {
            allowance = (allowanceValue as num).toDouble();
            print('   ✓ But found leave_allowance value: $allowance');
            return allowance;
          }
        }
      } else if (responseData is Map) {
        final allowanceValue = responseData['leave_allowance'];
        if (allowanceValue != null && allowanceValue is num) {
          allowance = allowanceValue.toDouble();
          print(
            '✅ Leave allowance extracted from untyped map: ${allowance.toStringAsFixed(2)} EGP',
          );
          return allowance;
        }
      }

      print('⚠️ Could not extract leave_allowance from response, returning 0');
      return 0.0;
    } on TimeoutException catch (e) {
      print('❌ Function call timeout: $e');
      return 0.0;
    } on Exception catch (e) {
      print('❌ Exception calculating leave allowance: $e');
      print('   Exception type: ${e.runtimeType}');
      print('   Stack: ${StackTrace.current}');

      // Try to extract more details from the exception
      final errorStr = e.toString();
      print('   Error string: $errorStr');

      if (errorStr.contains('404') ||
          errorStr.contains('not found') ||
          errorStr.contains('Function not found')) {
        print('⚠️ Function not found or employee not found - using fallback');
      }

      return 0.0;
    } catch (e) {
      print('❌ Unexpected error calculating leave allowance: $e');
      print('   Type: ${e.runtimeType}');
      return 0.0;
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
