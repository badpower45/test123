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
    required double latitude,
    required double longitude,
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
      final response = await _supabase
          .from('attendance')
          .insert({
            'employee_id': employeeId,
            'date': todayDate,
            'check_in_time': today.toUtc().toIso8601String(),
            'check_in_latitude': latitude,
            'check_in_longitude': longitude,
            'notes': reason ?? 'تسجيل حضور يدوي',
          })
          .select()
          .single();

      return response;
    } catch (e) {
      print('Manual check-in error: $e');
      rethrow;
    }
  }

  /// Manual check-out for employee (Owner/Manager can force check-out)
  static Future<bool> manualCheckOut({
    required String employeeId,
    required double latitude,
    required double longitude,
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
      final checkInTime = DateTime.parse(attendance['check_in_time'] as String);
      final totalHours = today.difference(checkInTime).inMinutes / 60.0;

      // Update with check-out
      await _supabase
          .from('attendance')
          .update({
            'check_out_time': today.toUtc().toIso8601String(),
            'check_out_latitude': latitude,
            'check_out_longitude': longitude,
            'total_hours': totalHours,
            'notes': (attendance['notes'] ?? '') + (reason != null ? ' | $reason' : ''),
          })
          .eq('id', attendance['id']);

      return true;
    } catch (e) {
      print('Manual check-out error: $e');
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
      var query = _supabase
          .from('attendance')
          .select('*, employees!inner(id, full_name, branch, role)');

      if (startDate != null) {
        query = query.gte('date', startDate.toIso8601String().split('T')[0]);
      }
      if (endDate != null) {
        query = query.lte('date', endDate.toIso8601String().split('T')[0]);
      }
      if (branchName != null) {
        query = query.eq('employees.branch', branchName);
      }
      if (employeeId != null) {
        query = query.eq('employee_id', employeeId);
      }

      final response = await query.order('date', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get attendance table error: $e');
      return [];
    }
  }
}
