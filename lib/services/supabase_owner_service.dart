import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Owner-specific operations for managing employees and attendance
class SupabaseOwnerService {
  static final SupabaseClient _supabase = SupabaseConfig.client;

  // ==================== ATTENDANCE MANAGEMENT ====================

  /// Get all employees with their current attendance status
  static Future<List<Map<String, dynamic>>> getEmployeeAttendanceStatus({
    String? branchName,
  }) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      var query = _supabase
          .from('employees')
          .select('*, attendance!left(id, date, check_in_time, check_out_time, total_hours)')
          .eq('is_active', true);

      if (branchName != null) {
        query = query.eq('branch', branchName);
      }

      final response = await query;
      
      // Process to include attendance info
      final List<Map<String, dynamic>> employeesWithStatus = [];
      
      for (final employee in response as List) {
        final attendanceList = employee['attendance'] as List?;
        final todayAttendance = attendanceList?.firstWhere(
          (att) => att['date'] == today,
          orElse: () => null,
        );

        employeesWithStatus.add({
          ...employee,
          'current_attendance': todayAttendance,
          'is_checked_in': todayAttendance != null && todayAttendance['check_out_time'] == null,
        });
      }

      return employeesWithStatus;
    } catch (e) {
      print('Get employee attendance status error: $e');
      return [];
    }
  }

  /// Manual check-in for employee (Owner/Manager can force check-in)
  static Future<Map<String, dynamic>?> manualCheckIn({
    required String employeeId,
    double? latitude,
    double? longitude,
    String? reason,
  }) async {
    try {
      final today = DateTime.now();
      final todayDate = today.toIso8601String().split('T')[0];

      // Check if already checked in today
      final existing = await _supabase
          .from('attendance')
          .select()
          .eq('employee_id', employeeId)
          .eq('date', todayDate)
          .maybeSingle();

      if (existing != null) {
        throw Exception('الموظف مسجل حضور بالفعل اليوم');
      }

      // Create attendance record
      final insertData = <String, dynamic>{
        'employee_id': employeeId,
        'date': todayDate,
        'check_in_time': today.toUtc().toIso8601String(),
        'notes': reason ?? 'تسجيل حضور يدوي',
      };
      
      if (latitude != null) insertData['check_in_latitude'] = latitude;
      if (longitude != null) insertData['check_in_longitude'] = longitude;

      final response = await _supabase
          .from('attendance')
          .insert(insertData)
          .select()
          .single();

      return response;
    } catch (e) {
      print('Manual check-in error: $e');
      rethrow;
    }
  }

  /// Simple manual check-in without location (for compatibility)
  static Future<void> simpleManualCheckIn(String employeeId, {String? reason}) async {
    await manualCheckIn(employeeId: employeeId, reason: reason);
  }

  /// Manual check-out for employee (Owner/Manager can force check-out)
  static Future<bool> manualCheckOut({
    required String employeeId,
    double? latitude,
    double? longitude,
    String? reason,
  }) async {
    try {
      final today = DateTime.now();
      final todayDate = today.toIso8601String().split('T')[0];

      // Get today's attendance
      final attendanceList = await _supabase
          .from('attendance')
          .select()
          .eq('employee_id', employeeId)
          .eq('date', todayDate);
      
      // Filter for records without check_out_time
      Map<String, dynamic> attendance;
      try {
        attendance = (attendanceList as List).cast<Map<String, dynamic>>().firstWhere(
          (att) => att['check_out_time'] == null,
        );
      } catch (e) {
        throw Exception('الموظف غير مسجل حضور اليوم');
      }

      // Calculate total hours
      DateTime checkInTime;
      try {
        checkInTime = DateTime.parse(attendance['check_in_time'] as String);
      } catch (e) {
        throw Exception('وقت الحضور غير صالح');
      }
      final totalHours = today.difference(checkInTime).inMinutes / 60.0;

      // Update with check-out
      final updateData = <String, dynamic>{
        'check_out_time': today.toUtc().toIso8601String(),
        'total_hours': totalHours,
        'notes': (attendance['notes'] ?? '') + (reason != null ? ' | $reason' : ''),
      };
      
      if (latitude != null) updateData['check_out_latitude'] = latitude;
      if (longitude != null) updateData['check_out_longitude'] = longitude;

      await _supabase
          .from('attendance')
          .update(updateData)
          .eq('id', attendance['id']);

      return true;
    } catch (e) {
      print('Manual check-out error: $e');
      rethrow;
    }
  }

  /// Simple manual check-out without location (for compatibility)
  static Future<void> simpleManualCheckOut(String employeeId, {String? reason}) async {
    await manualCheckOut(employeeId: employeeId, reason: reason);
  }

  /// Get employee attendance status for owner/manager (replacement for OwnerApiService.getEmployeeAttendanceStatus)
  static Future<Map<String, dynamic>> getEmployeeAttendanceStatusResult({
    String? branchId,
    DateTime? date,
  }) async {
    try {
      final targetDate = date ?? DateTime.now();
      final dateStr = targetDate.toIso8601String().split('T')[0];

      // Get all employees
      var employeeQuery = _supabase
          .from('employees')
          .select('id, full_name, role, branch, branch_id')
          .eq('is_active', true)
          .neq('role', 'owner');

      if (branchId != null && branchId.isNotEmpty) {
        employeeQuery = employeeQuery.eq('branch_id', branchId);
      }

      final employees = await employeeQuery;

      // Get today's attendance
      final attendanceResponse = await _supabase
          .from('attendance')
          .select()
          .eq('date', dateStr);

      final attendanceMap = <String, Map<String, dynamic>>{};
      for (final att in (attendanceResponse as List)) {
        attendanceMap[att['employee_id']] = att;
      }

      // Get leaves for today
      final leaveResponse = await _supabase
          .from('leave_requests')
          .select()
          .eq('status', 'approved')
          .lte('start_date', dateStr)
          .gte('end_date', dateStr);

      final leaveEmployeeIds = <String>{};
      for (final leave in (leaveResponse as List)) {
        leaveEmployeeIds.add(leave['employee_id']);
      }

      // Build result
      final List<Map<String, dynamic>> employeeStatuses = [];
      int presentCount = 0;
      int absentCount = 0;
      int checkedOutCount = 0;
      int onLeaveCount = 0;

      for (final emp in (employees as List)) {
        final empId = emp['id'];
        final attendance = attendanceMap[empId];
        final isOnLeave = leaveEmployeeIds.contains(empId);

        String status;
        DateTime? checkInTime;
        DateTime? checkOutTime;
        String? attendanceRecordId;

        if (isOnLeave) {
          status = 'on_leave';
          onLeaveCount++;
        } else if (attendance != null) {
          attendanceRecordId = attendance['id']?.toString();
          if (attendance['check_in_time'] != null) {
            try {
              checkInTime = DateTime.parse(attendance['check_in_time'].toString());
            } catch (e) {
              checkInTime = null;
            }
          }
          if (attendance['check_out_time'] != null) {
            try {
              checkOutTime = DateTime.parse(attendance['check_out_time'].toString());
            } catch (e) {
              checkOutTime = null;
            }
          }

          if (checkOutTime != null) {
            status = 'checked_out';
            checkedOutCount++;
          } else {
            status = 'present';
            presentCount++;
          }
        } else {
          status = 'absent';
          absentCount++;
        }

        employeeStatuses.add({
          'employeeId': empId,
          'employeeName': emp['full_name'],
          'employeeRole': emp['role'],
          'branchName': emp['branch'],
          'status': status,
          'checkInTime': checkInTime?.toIso8601String(),
          'checkOutTime': checkOutTime?.toIso8601String(),
          'attendanceRecordId': attendanceRecordId,
        });
      }

      return {
        'summary': {
          'totalEmployees': employeeStatuses.length,
          'presentCount': presentCount,
          'absentCount': absentCount,
          'checkedOutCount': checkedOutCount,
          'onLeaveCount': onLeaveCount,
        },
        'employees': employeeStatuses,
      };
    } catch (e) {
      print('Get employee attendance status error: $e');
      rethrow;
    }
  }

  // ==================== PAYROLL & STATISTICS ====================

  /// Get payroll summary for a specific month
  static Future<Map<String, dynamic>> getPayrollSummary({
    required int year,
    required int month,
    String? branchName,
  }) async {
    try {
      // Get all employees
      var employeeQuery = _supabase
          .from('employees')
          .select('id, full_name, branch, monthly_salary, hourly_rate')
          .eq('is_active', true);

      if (branchName != null) {
        employeeQuery = employeeQuery.eq('branch', branchName);
      }

      final employees = await employeeQuery;

      // Get attendance for the month
      final startDate = DateTime(year, month, 1).toIso8601String().split('T')[0];
      final endDate = DateTime(year, month + 1, 0).toIso8601String().split('T')[0];

      final attendance = await _supabase
          .from('attendance')
          .select()
          .gte('date', startDate)
          .lte('date', endDate);

      // Get salary advances for the month
      final advances = await _supabase
          .from('salary_advances')
          .select()
          .gte('created_at', startDate)
          .lte('created_at', endDate)
          .eq('status', 'approved');

      // Calculate payroll for each employee
      final List<Map<String, dynamic>> payrollDetails = [];
      double totalPayroll = 0;

      for (final employee in employees as List) {
        final employeeId = employee['id'] as String;
        final monthlySalary = (employee['monthly_salary'] as num?)?.toDouble() ?? 0;
        
        // Get employee's attendance
        final empAttendance = (attendance as List).where((att) => att['employee_id'] == employeeId).toList();
        final totalHours = empAttendance.fold<double>(
          0,
          (sum, att) => sum + ((att['total_hours'] as num?)?.toDouble() ?? 0),
        );

        // Get employee's advances
        final empAdvances = (advances as List).where((adv) => adv['employee_id'] == employeeId).toList();
        final totalAdvances = empAdvances.fold<double>(
          0,
          (sum, adv) => sum + ((adv['amount'] as num?)?.toDouble() ?? 0),
        );

        final netSalary = monthlySalary - totalAdvances;
        totalPayroll += netSalary;

        payrollDetails.add({
          'employee_id': employeeId,
          'employee_name': employee['full_name'],
          'branch': employee['branch'],
          'monthly_salary': monthlySalary,
          'total_hours': totalHours,
          'days_worked': empAttendance.length,
          'total_advances': totalAdvances,
          'net_salary': netSalary,
        });
      }

      return {
        'year': year,
        'month': month,
        'total_employees': employees.length,
        'total_payroll': totalPayroll,
        'payroll_details': payrollDetails,
      };
    } catch (e) {
      print('Get payroll summary error: $e');
      return {};
    }
  }

  /// Get dashboard statistics
  static Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      // Total employees
      final totalEmployees = await _supabase
          .from('employees')
          .select()
          .eq('is_active', true);

      // Today's attendance
      final todayAttendance = await _supabase
          .from('attendance')
          .select()
          .eq('date', today);

      // Currently present (checked in but not out)
      final allTodayAttendance = await _supabase
          .from('attendance')
          .select()
          .eq('date', today);
      
      final currentlyPresent = (allTodayAttendance as List).where((att) => att['check_out_time'] == null).toList();

      // Pending requests
      final pendingLeave = await _supabase
          .from('leave_requests')
          .select()
          .eq('status', 'pending');

      final pendingAttendance = await _supabase
          .from('attendance_requests')
          .select()
          .eq('status', 'pending');

      final pendingAdvances = await _supabase
          .from('salary_advances')
          .select()
          .eq('status', 'pending');

      return {
        'total_employees': (totalEmployees as List).length,
        'today_attendance': (todayAttendance as List).length,
        'currently_present': currentlyPresent.length,
        'pending_leave_requests': (pendingLeave as List).length,
        'pending_attendance_requests': (pendingAttendance as List).length,
        'pending_advance_requests': (pendingAdvances as List).length,
        'total_pending_requests': (pendingLeave as List).length + 
                                 (pendingAttendance as List).length + 
                                 (pendingAdvances as List).length,
      };
    } catch (e) {
      print('Get dashboard stats error: $e');
      return {};
    }
  }

  /// Get attendance table data with filters
  static Future<List<Map<String, dynamic>>> getAttendanceTable({
    DateTime? startDate,
    DateTime? endDate,
    String? branchName,
    String? employeeId,
  }) async {
    try {
      // إذا كان في فلتر فرع، نجيب الموظفين في الفرع أولاً
      List<String>? employeeIdsInBranch;
      if (branchName != null && branchName.isNotEmpty) {
        try {
          final employeesInBranch = await _supabase
              .from('employees')
              .select('id')
              .eq('branch', branchName)
              .eq('is_active', true);
          
          employeeIdsInBranch = (employeesInBranch as List)
              .map((e) => e['id'] as String)
              .where((id) => id.isNotEmpty)
              .toList();
          
          print('🔍 [Attendance Table] Found ${employeeIdsInBranch.length} employees in branch: $branchName');
          
          if (employeeIdsInBranch.isEmpty) {
            // لا يوجد موظفين في هذا الفرع
            return [];
          }
        } catch (e) {
          print('❌ [Attendance Table] Error filtering by branch: $e');
          return [];
        }
      }

      var query = _supabase
          .from('daily_attendance_summary')
          .select('*, employees!inner(id, full_name, branch, role, hourly_rate)');

      if (startDate != null) {
        query = query.gte('attendance_date', startDate.toIso8601String().split('T')[0]);
      }
      if (endDate != null) {
        query = query.lte('attendance_date', endDate.toIso8601String().split('T')[0]);
      }
      
      // فلترة حسب الفرع باستخدام employee_id
      // في Supabase Dart SDK، نستخدم or مع multiple eq
      if (employeeIdsInBranch != null && employeeIdsInBranch.isNotEmpty) {
        if (employeeIdsInBranch.length == 1) {
          query = query.eq('employee_id', employeeIdsInBranch.first);
        } else {
          // استخدام or مع multiple eq
          query = query.or(employeeIdsInBranch.map((id) => 'employee_id.eq.$id').join(','));
        }
      }
      
      if (employeeId != null) {
        query = query.eq('employee_id', employeeId);
      }

      final response = await query.order('attendance_date', ascending: false);
      final records = (response as List).cast<Map<String, dynamic>>();

      if (records.isNotEmpty) {
        return _withComputedDailySalary(records);
      }

      // Fallback to legacy attendance table if summary is empty
      var legacyQuery = _supabase
          .from('attendance')
          .select('*, employees!inner(id, full_name, branch, role, hourly_rate)');

      if (startDate != null) {
        legacyQuery = legacyQuery.gte('date', startDate.toIso8601String().split('T')[0]);
      }
      if (endDate != null) {
        legacyQuery = legacyQuery.lte('date', endDate.toIso8601String().split('T')[0]);
      }
      
      // فلترة حسب الفرع باستخدام employee_id
      // في Supabase Dart SDK، نستخدم or مع multiple eq
      if (employeeIdsInBranch != null && employeeIdsInBranch.isNotEmpty) {
        if (employeeIdsInBranch.length == 1) {
          legacyQuery = legacyQuery.eq('employee_id', employeeIdsInBranch.first);
        } else {
          // استخدام or مع multiple eq
          legacyQuery = legacyQuery.or(employeeIdsInBranch.map((id) => 'employee_id.eq.$id').join(','));
        }
      }
      
      if (employeeId != null) {
        legacyQuery = legacyQuery.eq('employee_id', employeeId);
      }

      final legacyResponse = await legacyQuery.order('date', ascending: false);
      return _withComputedDailySalary(
        (legacyResponse as List).cast<Map<String, dynamic>>(),
        isLegacy: true,
      );
    } catch (e) {
      print('Get attendance table error: $e');
      return [];
    }
  }

  static List<Map<String, dynamic>> _withComputedDailySalary(
    List<Map<String, dynamic>> records, {
    bool isLegacy = false,
  }) {
    return records.map((record) {
      final map = Map<String, dynamic>.from(record);

      if (!map.containsKey('daily_salary') || (map['daily_salary'] as num?) == null) {
        final totalHours = (map['total_hours'] as num?)?.toDouble() ?? 0;
        double hourlyRate = 0;

        final employee = map['employees'];
        if (employee is Map<String, dynamic>) {
          hourlyRate = (employee['hourly_rate'] as num?)?.toDouble() ?? 0;
        }

        if (hourlyRate == 0 && map.containsKey('hourly_rate')) {
          hourlyRate = (map['hourly_rate'] as num?)?.toDouble() ?? 0;
        }

        map['daily_salary'] = (totalHours * hourlyRate);
      }

      if (isLegacy && !map.containsKey('attendance_date')) {
        map['attendance_date'] = map['date'];
      }

      return map;
    }).toList();
  }

  /// Get full owner dashboard with all pending requests (replacement for OwnerApiService.getDashboard)
  /// This returns data in the same format as the old API for compatibility
  static Future<Map<String, dynamic>> getOwnerDashboard({
    required String ownerId,
  }) async {
    try {
      // Verify owner exists and has owner role
      final ownerRecord = await _supabase
          .from('employees')
          .select('id, full_name, role')
          .eq('id', ownerId)
          .eq('role', 'owner')
          .maybeSingle();

      if (ownerRecord == null) {
        throw Exception('لا توجد صلاحيات للوصول إلى لوحة المالك');
      }

      // Get pending leave requests from managers only
      final pendingLeaveRequests = await _supabase
          .from('leave_requests')
          .select('*, employees!inner(id, full_name, role, branch)')
          .eq('status', 'pending')
          .eq('employees.role', 'manager')
          .order('created_at', ascending: false);

      // Get pending advance requests from managers only
      final pendingAdvances = await _supabase
          .from('salary_advances')
          .select('*, employees!inner(id, full_name, role, branch)')
          .eq('status', 'pending')
          .eq('employees.role', 'manager')
          .order('request_date', ascending: false);

      // Get pending absence notifications for managers
      final pendingAbsences = await _supabase
          .from('absence_notifications')
          .select('*, employees!inner(id, full_name, role, branch)')
          .eq('status', 'pending')
          .eq('employees.role', 'manager')
          .order('notified_at', ascending: false);

      // Get pending break requests from managers
      List<dynamic> pendingBreaks = [];
      try {
        pendingBreaks = await _supabase
            .from('break_requests')
            .select('*, employees!inner(id, full_name, role, branch)')
            .eq('status', 'pending')
            .eq('employees.role', 'manager')
            .order('created_at', ascending: false);
      } catch (e) {
        // break_requests table might not exist
        print('Break requests query failed: $e');
      }

      // Get pending attendance requests from managers
      final pendingAttendanceRequests = await _supabase
          .from('attendance_requests')
          .select('*, employees!inner(id, full_name, role, branch)')
          .eq('status', 'pending')
          .eq('employees.role', 'manager')
          .order('created_at', ascending: false);

      // Format the data to match old API format
      final formattedLeaveRequests = (pendingLeaveRequests as List).map((req) {
        final employee = req['employees'] as Map<String, dynamic>?;
        return {
          'id': req['id'],
          'employeeId': req['employee_id'],
          'employeeName': employee?['full_name'] ?? 'غير معروف',
          'employeeRole': employee?['role'] ?? 'manager',
          'employeeBranch': employee?['branch'],
          'startDate': req['start_date'],
          'endDate': req['end_date'],
          'leaveType': req['leave_type'],
          'reason': req['reason'],
          'daysCount': req['days_count'],
          'status': req['status'],
          'createdAt': req['created_at'],
        };
      }).toList();

      final formattedAdvances = (pendingAdvances as List).map((req) {
        final employee = req['employees'] as Map<String, dynamic>?;
        return {
          'id': req['id'],
          'employeeId': req['employee_id'],
          'employeeName': employee?['full_name'] ?? 'غير معروف',
          'employeeRole': employee?['role'] ?? 'manager',
          'employeeBranch': employee?['branch'],
          'amount': req['amount'],
          'status': req['status'],
          'requestDate': req['request_date'],
        };
      }).toList();

      final formattedAbsences = (pendingAbsences as List).map((req) {
        final employee = req['employees'] as Map<String, dynamic>?;
        return {
          'id': req['id'],
          'employeeId': req['employee_id'],
          'employeeName': employee?['full_name'] ?? 'غير معروف',
          'absenceDate': req['absence_date'],
          'status': req['status'],
          'deductionApplied': req['deduction_applied'],
          'notifiedAt': req['notified_at'],
        };
      }).toList();

      final formattedBreaks = (pendingBreaks as List).map((req) {
        final employee = req['employees'] as Map<String, dynamic>?;
        return {
          'id': req['id'],
          'employeeId': req['employee_id'],
          'employeeName': employee?['full_name'] ?? 'غير معروف',
          'employeeRole': employee?['role'] ?? 'manager',
          'employeeBranch': employee?['branch'],
          'requestedDurationMinutes': req['requested_duration_minutes'],
          'status': req['status'],
          'createdAt': req['created_at'],
        };
      }).toList();

      final formattedAttendance = (pendingAttendanceRequests as List).map((req) {
        final employee = req['employees'] as Map<String, dynamic>?;
        return {
          'id': req['id'],
          'employeeId': req['employee_id'],
          'employeeName': employee?['full_name'] ?? 'غير معروف',
          'employeeRole': employee?['role'] ?? 'manager',
          'employeeBranch': employee?['branch'],
          'requestType': req['request_type'],
          'requestedTime': req['requested_time'],
          'reason': req['reason'],
          'status': req['status'],
          'createdAt': req['created_at'],
        };
      }).toList();

      return {
        'success': true,
        'owner': {
          'id': ownerRecord['id'],
          'name': ownerRecord['full_name'],
          'role': ownerRecord['role'],
        },
        'dashboard': {
          'attendanceRequests': formattedAttendance,
          'leaveRequests': formattedLeaveRequests,
          'advances': formattedAdvances,
          'absences': formattedAbsences,
          'breakRequests': formattedBreaks,
          'summary': {
            'totalPendingRequests': formattedAttendance.length +
                formattedLeaveRequests.length +
                formattedAdvances.length +
                formattedAbsences.length +
                formattedBreaks.length,
            'attendanceRequestsCount': formattedAttendance.length,
            'leaveRequestsCount': formattedLeaveRequests.length,
            'advancesCount': formattedAdvances.length,
            'absencesCount': formattedAbsences.length,
            'breakRequestsCount': formattedBreaks.length,
          },
        },
      };
    } catch (e) {
      print('Get owner dashboard error: $e');
      rethrow;
    }
  }

  /// Get all employees for owner (replacement for OwnerApiService.getEmployees)
  /// Returns data in the same format as the old API for compatibility
  static Future<Map<String, dynamic>> getOwnerEmployees({
    required String ownerId,
  }) async {
    try {
      // Verify owner exists and has owner role
      final ownerRecord = await _supabase
          .from('employees')
          .select('id, full_name, role')
          .eq('id', ownerId)
          .eq('role', 'owner')
          .maybeSingle();

      if (ownerRecord == null) {
        throw Exception('لا توجد صلاحيات للوصول إلى قائمة الموظفين');
      }

      // Get all employees except owner
      final employeesResponse = await _supabase
          .from('employees')
          .select('*')
          .neq('role', 'owner')
          .order('full_name', ascending: true);

      final List<Map<String, dynamic>> formattedEmployees = [];
      int activeEmployees = 0;
      int managersCount = 0;
      double totalHourlyRateAssigned = 0;
      double totalMonthlySalary = 0;

      for (final emp in (employeesResponse as List)) {
        final isActive = emp['is_active'] == true;
        if (isActive) activeEmployees++;
        if (emp['role'] == 'manager') managersCount++;
        
        final hourlyRate = (emp['hourly_rate'] as num?)?.toDouble() ?? 0;
        final monthlySalary = (emp['monthly_salary'] as num?)?.toDouble() ?? 0;
        totalHourlyRateAssigned += hourlyRate;
        totalMonthlySalary += monthlySalary;

        formattedEmployees.add({
          'id': emp['id'],
          'fullName': emp['full_name'],
          'branch': emp['branch'],
          'branchId': emp['branch_id'],
          'role': emp['role'],
          'hourlyRate': hourlyRate,
          'monthlySalary': monthlySalary,
          'active': isActive,
          'shiftStartTime': emp['shift_start_time'],
          'shiftEndTime': emp['shift_end_time'],
          'shiftType': emp['shift_type'],
          'createdAt': emp['created_at'],
          'updatedAt': emp['updated_at'],
        });
      }

      return {
        'success': true,
        'owner': {
          'id': ownerRecord['id'],
          'name': ownerRecord['full_name'],
        },
        'employees': formattedEmployees,
        'summary': {
          'totalEmployees': formattedEmployees.length,
          'activeEmployees': activeEmployees,
          'managersCount': managersCount,
          'totalHourlyRateAssigned': (totalHourlyRateAssigned * 100).round() / 100,
          'totalMonthlySalary': (totalMonthlySalary * 100).round() / 100,
        },
      };
    } catch (e) {
      print('Get owner employees error: $e');
      rethrow;
    }
  }

  /// Update employee data (replacement for OwnerApiService.updateEmployee)
  static Future<Map<String, dynamic>> updateEmployee({
    required String employeeId,
    String? fullName,
    String? pin,
    String? role,
    String? branch,
    String? branchId,
    double? hourlyRate,
    bool? active,
    String? shiftStartTime,
    String? shiftEndTime,
    String? shiftType,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (fullName != null) updates['full_name'] = fullName;
      if (pin != null) updates['pin'] = pin;
      if (role != null) updates['role'] = role;
      if (branch != null) updates['branch'] = branch;
      if (branchId != null) updates['branch_id'] = branchId;
      if (hourlyRate != null) updates['hourly_rate'] = hourlyRate;
      if (active != null) updates['is_active'] = active;
      if (shiftStartTime != null) updates['shift_start_time'] = shiftStartTime;
      if (shiftEndTime != null) updates['shift_end_time'] = shiftEndTime;
      if (shiftType != null) updates['shift_type'] = shiftType;
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();

      final response = await _supabase
          .from('employees')
          .update(updates)
          .eq('id', employeeId)
          .select()
          .single();

      return {
        'success': true,
        'employee': response,
      };
    } catch (e) {
      print('Update employee error: $e');
      throw Exception('فشل تحديث الموظف: $e');
    }
  }

  /// Delete employee (replacement for OwnerApiService.deleteEmployee)
  static Future<Map<String, dynamic>> deleteEmployee({
    required String employeeId,
  }) async {
    try {
      // Delete related records first
      await _supabase.from('attendance').delete().eq('employee_id', employeeId);
      await _supabase.from('attendance_requests').delete().eq('employee_id', employeeId);
      await _supabase.from('leave_requests').delete().eq('employee_id', employeeId);
      await _supabase.from('salary_advances').delete().eq('employee_id', employeeId);
      await _supabase.from('absence_notifications').delete().eq('employee_id', employeeId);
      
      // Try to delete from break_requests if exists
      try {
        await _supabase.from('break_requests').delete().eq('employee_id', employeeId);
      } catch (_) {}

      // Delete the employee
      await _supabase.from('employees').delete().eq('id', employeeId);

      return {
        'success': true,
        'message': 'تم حذف الموظف بنجاح',
      };
    } catch (e) {
      print('Delete employee error: $e');
      throw Exception('فشل حذف الموظف: $e');
    }
  }

  /// Create new employee (replacement for OwnerApiService.createEmployee)
  static Future<Map<String, dynamic>> createEmployee({
    required String ownerId,
    required String employeeId,
    required String fullName,
    required String pin,
    String? branchId,
    String? branch,
    required double hourlyRate,
    String? shiftStartTime,
    String? shiftEndTime,
    String? shiftType,
    String role = 'staff',
  }) async {
    try {
      // Check if employee ID already exists
      final existing = await _supabase
          .from('employees')
          .select('id')
          .eq('id', employeeId)
          .maybeSingle();

      if (existing != null) {
        throw Exception('معرف الموظف مستخدم بالفعل');
      }

      final response = await _supabase
          .from('employees')
          .insert({
            'id': employeeId,
            'full_name': fullName,
            'pin': pin,
            'branch_id': branchId,
            'branch': branch,
            'hourly_rate': hourlyRate,
            'shift_start_time': shiftStartTime,
            'shift_end_time': shiftEndTime,
            'shift_type': shiftType,
            'role': role,
            'is_active': true,
          })
          .select()
          .single();

      return {
        'success': true,
        'employee': response,
      };
    } catch (e) {
      print('Create employee error: $e');
      if (e.toString().contains('معرف الموظف مستخدم')) {
        rethrow;
      }
      throw Exception('فشل إضافة الموظف: $e');
    }
  }

  /// Get payroll summary (replacement for OwnerApiService.getPayrollSummary)
  static Future<Map<String, dynamic>> getPayrollSummaryForPeriod({
    required String ownerId,
    required String startDate,
    required String endDate,
  }) async {
    try {
      // Get all employees
      final employees = await _supabase
          .from('employees')
          .select('id, full_name, branch, hourly_rate, monthly_salary')
          .eq('is_active', true)
          .neq('role', 'owner');

      // Get attendance for the period
      final attendance = await _supabase
          .from('attendance')
          .select('employee_id, total_hours')
          .gte('date', startDate)
          .lte('date', endDate);

      // Build payroll data
      final Map<String, double> hoursMap = {};
      for (final att in (attendance as List)) {
        final empId = att['employee_id'];
        final hours = (att['total_hours'] as num?)?.toDouble() ?? 0;
        hoursMap[empId] = (hoursMap[empId] ?? 0) + hours;
      }

      final List<Map<String, dynamic>> payroll = [];
      for (final emp in (employees as List)) {
        final empId = emp['id'];
        final totalHours = hoursMap[empId] ?? 0;
        final hourlyRate = (emp['hourly_rate'] as num?)?.toDouble() ?? 0;
        final earnings = totalHours * hourlyRate;

        payroll.add({
          'id': empId,
          'fullName': emp['full_name'],
          'branch': emp['branch'],
          'hourlyRate': hourlyRate,
          'totalHours': totalHours,
          'earnings': earnings,
        });
      }

      return {
        'success': true,
        'payroll': payroll,
        'period': {
          'start': startDate,
          'end': endDate,
        },
      };
    } catch (e) {
      print('Get payroll summary error: $e');
      rethrow;
    }
  }
}
