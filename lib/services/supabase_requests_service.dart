import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class SupabaseRequestsService {
  static final SupabaseClient _supabase = SupabaseConfig.client;

  // ==================== ATTENDANCE REQUESTS ====================

  /// Create attendance request (forgot check-in/out, late arrival, etc.)
  static Future<Map<String, dynamic>?> createAttendanceRequest({
    required String employeeId,
    required String requestType,
    required String reason,
    DateTime? requestedTime,
  }) async {
    try {
      final response = await _supabase
          .from('attendance_requests')
          .insert({
            'employee_id': employeeId,
            'request_type': requestType,
            'reason': reason,
            'requested_time': requestedTime?.toUtc().toIso8601String(),
            'status': 'pending',
          })
          .select()
          .single();

      return response;
    } catch (e) {
      print('Create attendance request error: $e');
      return null;
    }
  }

  /// Get attendance requests (only pending by default for employees)
  static Future<List<Map<String, dynamic>>> getAttendanceRequests({
    String? employeeId,
    String? status,
    bool includeAll = false, // For managers/admins
  }) async {
    try {
      var query = _supabase.from('attendance_requests').select();

      if (employeeId != null) {
        query = query.eq('employee_id', employeeId);
        // للموظف: نعرض pending فقط (إلا لو includeAll = true)
        if (!includeAll && status == null) {
          query = query.eq('status', 'pending');
        }
      }
      if (status != null) {
        query = query.eq('status', status);
      }

      final response = await query.order('created_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get attendance requests error: $e');
      return [];
    }
  }

  /// Review attendance request (approve/reject)
  static Future<bool> reviewAttendanceRequest({
    required String requestId,
    required String reviewedBy,
    required String status, // 'approved' or 'rejected'
    String? reviewNotes,
  }) async {
    try {
      await _supabase
          .from('attendance_requests')
          .update({
            'status': status,
            'reviewed_by': reviewedBy,
            'reviewed_at': DateTime.now().toUtc().toIso8601String(),
            'review_notes': reviewNotes,
          })
          .eq('id', requestId);

      return true;
    } catch (e) {
      print('Review attendance request error: $e');
      return false;
    }
  }

  // ==================== LEAVE REQUESTS ====================

  /// Create leave request
  static Future<Map<String, dynamic>?> createLeaveRequest({
    required String employeeId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    try {
      final response = await _supabase
          .from('leave_requests')
          .insert({
            'employee_id': employeeId,
            'leave_type': leaveType,
            'start_date': startDate.toIso8601String().split('T')[0],
            'end_date': endDate.toIso8601String().split('T')[0],
            'reason': reason,
            'status': 'pending',
          })
          .select()
          .single();

      return response;
    } catch (e) {
      print('Create leave request error: $e');
      return null;
    }
  }

  /// Get leave requests (only pending by default for employees)
  static Future<List<Map<String, dynamic>>> getLeaveRequests({
    String? employeeId,
    String? status,
    bool includeAll = false, // For managers/admins
  }) async {
    try {
      var query = _supabase
          .from('leave_requests')
          .select('*, employees(id, full_name, branch)');

      if (employeeId != null) {
        query = query.eq('employee_id', employeeId);
        // للموظف: نعرض pending فقط (إلا لو includeAll = true)
        if (!includeAll && status == null) {
          query = query.eq('status', 'pending');
        }
      }
      if (status != null) {
        query = query.eq('status', status);
      }

      final response = await query.order('created_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get leave requests error: $e');
      return [];
    }
  }

  /// Review leave request
  static Future<bool> reviewLeaveRequest({
    required String requestId,
    required String reviewedBy,
    required String status,
    String? reviewNotes,
  }) async {
    try {
      await _supabase
          .from('leave_requests')
          .update({
            'status': status,
            'reviewed_by': reviewedBy,
            'reviewed_at': DateTime.now().toUtc().toIso8601String(),
            'review_notes': reviewNotes,
          })
          .eq('id', requestId);

      return true;
    } catch (e) {
      print('Review leave request error: $e');
      return false;
    }
  }

  // ==================== SALARY ADVANCE REQUESTS ====================

  /// Create salary advance request with validations
  static Future<Map<String, dynamic>?> createSalaryAdvanceRequest({
    required String employeeId,
    required double amount,
    required String reason,
  }) async {
    try {
      // 1. جلب بيانات الموظف للتحقق من المرتب
      final employee = await _supabase
          .from('employees')
          .select('monthly_salary')
          .eq('id', employeeId)
          .single();

      final monthlySalary = (employee['monthly_salary'] as num?)?.toDouble() ?? 0;
      final maxAllowed = monthlySalary * 0.30; // 30% من المرتب

      // 2. التحقق من المبلغ المطلوب
      if (amount > maxAllowed) {
        throw Exception('المبلغ المطلوب ($amount ج.م) يتجاوز 30% من مرتبك ($maxAllowed ج.م)');
      }

      // 3. التحقق من آخر سلفة (مرة كل 5 أيام)
      final fiveDaysAgo = DateTime.now().subtract(const Duration(days: 5));
      final recentAdvances = await _supabase
          .from('salary_advances')
          .select()
          .eq('employee_id', employeeId)
          .gte('created_at', fiveDaysAgo.toUtc().toIso8601String());

      if (recentAdvances.isNotEmpty) {
        throw Exception('لا يمكن طلب سلفة جديدة قبل مرور 5 أيام من آخر طلب');
      }

      // 4. إنشاء الطلب
      final response = await _supabase
          .from('salary_advances')
          .insert({
            'employee_id': employeeId,
            'amount': amount,
            'reason': reason,
            'status': 'pending',
          })
          .select()
          .single();

      return response;
    } catch (e) {
      print('Create salary advance request error: $e');
      rethrow; // نرجع الخطأ للـ UI علشان يعرضه
    }
  }

  /// Get employee salary information and max advance
  static Future<Map<String, dynamic>> getEmployeeSalaryInfo(String employeeId) async {
    try {
      final employee = await _supabase
          .from('employees')
          .select('monthly_salary')
          .eq('id', employeeId)
          .single();

      final monthlySalary = (employee['monthly_salary'] as num?)?.toDouble() ?? 0;
      final maxAdvance = monthlySalary * 0.30;

      return {
        'currentEarnings': monthlySalary,
        'maxAdvance': maxAdvance,
      };
    } catch (e) {
      print('Get employee salary info error: $e');
      return {'currentEarnings': 0, 'maxAdvance': 0};
    }
  }

  /// Get salary advance requests (only pending by default for employees)
  static Future<List<Map<String, dynamic>>> getSalaryAdvanceRequests({
    String? employeeId,
    String? status,
    bool includeAll = false, // For managers/admins
  }) async {
    try {
      var query = _supabase
          .from('salary_advances')
          .select('*, employees(id, full_name, branch)');

      if (employeeId != null) {
        query = query.eq('employee_id', employeeId);
        // للموظف: نعرض pending فقط (إلا لو includeAll = true)
        if (!includeAll && status == null) {
          query = query.eq('status', 'pending');
        }
      }
      if (status != null) {
        query = query.eq('status', status);
      }

      final response = await query.order('created_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get salary advance requests error: $e');
      return [];
    }
  }

  /// Review salary advance request
  static Future<bool> reviewSalaryAdvanceRequest({
    required String requestId,
    required String approvedBy,
    required String status,
    String? notes,
  }) async {
    try {
      await _supabase
          .from('salary_advances')
          .update({
            'status': status,
            'approved_by': approvedBy,
            'approved_at': DateTime.now().toUtc().toIso8601String(),
            'notes': notes,
          })
          .eq('id', requestId);

      return true;
    } catch (e) {
      print('Review salary advance request error: $e');
      return false;
    }
  }

  // ==================== PENDING REQUESTS COUNT ====================

  /// Get count of pending requests (for admin dashboard)
  static Future<Map<String, int>> getPendingRequestsCount() async {
    try {
      final attendanceRequests = await _supabase
          .from('attendance_requests')
          .select()
          .eq('status', 'pending');

      final leaveRequests = await _supabase
          .from('leave_requests')
          .select()
          .eq('status', 'pending');

      final salaryRequests = await _supabase
          .from('salary_advances')
          .select()
          .eq('status', 'pending');

      return {
        'attendance': (attendanceRequests as List).length,
        'leave': (leaveRequests as List).length,
        'salary': (salaryRequests as List).length,
        'total': (attendanceRequests as List).length +
            (leaveRequests as List).length +
            (salaryRequests as List).length,
      };
    } catch (e) {
      print('Get pending requests count error: $e');
      return {'attendance': 0, 'leave': 0, 'salary': 0, 'total': 0};
    }
  }

  // ==================== OWNER/MANAGER VIEWS ====================

  /// Get all attendance requests with employee details (for owner/manager)
  static Future<List<Map<String, dynamic>>> getAllAttendanceRequestsWithEmployees({
    String? status,
    String? branchName,
  }) async {
    try {
      var query = _supabase
          .from('attendance_requests')
          .select('*, employees!inner(id, full_name, branch, role)');

      if (status != null) {
        query = query.eq('status', status);
      }
      if (branchName != null) {
        query = query.eq('employees.branch', branchName);
      }

      final response = await query.order('created_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get all attendance requests error: $e');
      return [];
    }
  }

  /// Get all leave requests with employee details (for owner/manager)
  static Future<List<Map<String, dynamic>>> getAllLeaveRequestsWithEmployees({
    String? status,
    String? branchName,
  }) async {
    try {
      var query = _supabase
          .from('leave_requests')
          .select('*, employees!inner(id, full_name, branch, role)');

      if (status != null) {
        query = query.eq('status', status);
      }
      if (branchName != null) {
        query = query.eq('employees.branch', branchName);
      }

      final response = await query.order('created_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get all leave requests error: $e');
      return [];
    }
  }

  /// Get all salary advance requests with employee details (for owner/manager)
  static Future<List<Map<String, dynamic>>> getAllSalaryAdvanceRequestsWithEmployees({
    String? status,
    String? branchName,
  }) async {
    try {
      var query = _supabase
          .from('salary_advances')
          .select('*, employees!inner(id, full_name, branch, role, monthly_salary)');

      if (status != null) {
        query = query.eq('status', status);
      }
      if (branchName != null) {
        query = query.eq('employees.branch', branchName);
      }

      final response = await query.order('created_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get all salary advance requests error: $e');
      return [];
    }
  }
}
