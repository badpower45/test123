import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meta/meta.dart';
import '../config/supabase_config.dart';
import 'supabase_function_client.dart';

typedef LeaveRequestInsertHandler =
    Future<Map<String, dynamic>?> Function(Map<String, dynamic> payload);

class SupabaseRequestsService {
  static final SupabaseClient _supabase = SupabaseConfig.client;
  static LeaveRequestInsertHandler? _leaveRequestInsertHandler;

  @visibleForTesting
  static void setLeaveRequestInsertHandlerForTesting(
    LeaveRequestInsertHandler? handler,
  ) {
    _leaveRequestInsertHandler = handler;
  }

  /// Resolve the manager ID for an employee based on their branch
  static Future<String?> _resolveManagerId(String employeeId) async {
    try {
      // Get employee data
      final employee = await _supabase
          .from('employees')
          .select('id, branch_id, branch')
          .eq('id', employeeId)
          .maybeSingle();

      if (employee == null) {
        print('[SupabaseRequestsService] Employee not found: $employeeId');
        return null;
      }

      // Try to find manager by branch_id
      if (employee['branch_id'] != null) {
        // First check if branches table has manager_id
        final branch = await _supabase
            .from('branches')
            .select('manager_id')
            .eq('id', employee['branch_id'])
            .maybeSingle();

        if (branch != null && branch['manager_id'] != null) {
          final managerId = branch['manager_id'].toString();
          if (managerId.isNotEmpty && managerId != employeeId) {
            print('[SupabaseRequestsService] Found manager by branch.manager_id: $managerId');
            return managerId;
          }
        }

        // Fallback to any active manager in the same branch_id
        final manager = await _supabase
            .from('employees')
            .select('id')
            .eq('role', 'manager')
            .eq('is_active', true)
            .eq('branch_id', employee['branch_id'])
            .neq('id', employeeId)
            .limit(1)
            .maybeSingle();

        if (manager != null) {
          print('[SupabaseRequestsService] Found manager by branch_id: ${manager['id']}');
          return manager['id']?.toString();
        }
      }

      // Try to find manager by branch (string field)
      if (employee['branch'] != null) {
        final manager = await _supabase
            .from('employees')
            .select('id')
            .eq('role', 'manager')
            .eq('is_active', true)
            .eq('branch', employee['branch'])
            .neq('id', employeeId)
            .limit(1)
            .maybeSingle();

        if (manager != null) {
          print('[SupabaseRequestsService] Found manager by branch string: ${manager['id']}');
          return manager['id']?.toString();
        }
      }

      print('[SupabaseRequestsService] No manager found for employee: $employeeId');
      return null;
    } catch (e) {
      print('[SupabaseRequestsService] Error resolving manager: $e');
      return null;
    }
  }

  // ==================== ATTENDANCE REQUESTS ====================

  /// Create attendance request (forgot check-in/out, late arrival, etc.)
  static Future<Map<String, dynamic>?> createAttendanceRequest({
    required String employeeId,
    required String requestType,
    required String reason,
    DateTime? requestedTime,
  }) async {
    try {
      // Resolve manager ID for this employee
      final managerId = await _resolveManagerId(employeeId);
      print('[createAttendanceRequest] Resolved managerId: $managerId for employee: $employeeId');

      final response = await _supabase
          .from('attendance_requests')
          .insert({
            'employee_id': employeeId,
            'request_type': requestType,
            'reason': reason,
            'requested_time': requestedTime?.toUtc().toIso8601String(),
            'status': 'pending',
            if (managerId != null) 'assigned_manager_id': managerId,
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
      // Fetch request details first so we can apply approved corrections
      final request = await _supabase
          .from('attendance_requests')
          .select()
          .eq('id', requestId)
          .maybeSingle();

      if (request == null) {
        throw Exception('طلب الحضور غير موجود');
      }

      await _supabase
          .from('attendance_requests')
          .update({
            'status': status,
            'reviewed_by': reviewedBy,
            'reviewed_at': DateTime.now().toUtc().toIso8601String(),
            'review_notes': reviewNotes,
          })
          .eq('id', requestId);

      // When approved, update the attendance record to the requested time
      if (status == 'approved') {
        final requestedTimeStr =
            (request['requested_time'] ?? request['requestedTime'])?.toString();
        final employeeId = (request['employee_id'] ?? request['employeeId'])
            ?.toString();
        final requestType =
            (request['request_type'] ?? request['requestType'] ?? '')
                .toString()
                .toLowerCase();

        if (employeeId != null && requestedTimeStr != null) {
          final requestedTime = DateTime.tryParse(requestedTimeStr);
          if (requestedTime != null) {
            await _applyApprovedAttendanceRequest(
              employeeId: employeeId,
              requestType: requestType,
              requestedTime: requestedTime,
              originalReason: request['reason']?.toString(),
            );
          }
        }
      }

      return true;
    } catch (e) {
      print('Review attendance request error: $e');
      return false;
    }
  }

  /// Apply the approved attendance request by updating/creating attendance row
  static Future<void> _applyApprovedAttendanceRequest({
    required String employeeId,
    required String requestType,
    required DateTime requestedTime,
    String? originalReason,
  }) async {
    final dateStr = requestedTime.toIso8601String().split('T').first;
    final requestedUtc = requestedTime.toUtc();

    final existing = await _supabase
        .from('attendance')
        .select()
        .eq('employee_id', employeeId)
        .eq('date', dateStr)
        .maybeSingle();

    final isCheckout = requestType.contains('out');
    final noteSuffix = 'تم التعديل بواسطة طلب حضور معتمد';

    if (existing != null) {
      final updateData = <String, dynamic>{};

      if (isCheckout) {
        updateData['check_out_time'] = requestedUtc.toIso8601String();

        final checkInStr = existing['check_in_time']?.toString();
        final checkIn = checkInStr != null
            ? DateTime.tryParse(checkInStr)
            : null;
        if (checkIn != null) {
          final hours = _calculateTotalHours(checkIn, requestedUtc);
          updateData['total_hours'] = hours;
        }
      } else {
        updateData['check_in_time'] = requestedUtc.toIso8601String();

        final checkOutStr = existing['check_out_time']?.toString();
        final checkOut = checkOutStr != null
            ? DateTime.tryParse(checkOutStr)
            : null;
        if (checkOut != null) {
          final hours = _calculateTotalHours(requestedUtc, checkOut);
          updateData['total_hours'] = hours;
        }
      }

      updateData['notes'] = _mergeNotes(
        existing['notes']?.toString(),
        noteSuffix,
        originalReason,
      );

      await _supabase
          .from('attendance')
          .update(updateData)
          .eq('id', existing['id']);
    } else {
      final insertData = <String, dynamic>{
        'employee_id': employeeId,
        'date': dateStr,
        'notes': _mergeNotes(null, noteSuffix, originalReason),
      };

      if (isCheckout) {
        insertData['check_out_time'] = requestedUtc.toIso8601String();
      } else {
        insertData['check_in_time'] = requestedUtc.toIso8601String();
      }

      await _supabase.from('attendance').insert(insertData);
    }
  }

  static double _calculateTotalHours(DateTime start, DateTime end) {
    final minutes = end.difference(start).inMinutes;
    return minutes <= 0 ? 0 : minutes / 60.0;
  }

  static String _mergeNotes(String? existing, String suffix, String? reason) {
    final buffer = StringBuffer();
    if (existing != null && existing.trim().isNotEmpty) {
      buffer.write(existing.trim());
      buffer.write(' | ');
    }
    buffer.write(suffix);
    if (reason != null && reason.trim().isNotEmpty) {
      buffer.write(' | سبب الطلب: ');
      buffer.write(reason.trim());
    }
    return buffer.toString();
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
      // Resolve manager ID for this employee
      final managerId = await _resolveManagerId(employeeId);
      print('[createLeaveRequest] Resolved managerId: $managerId for employee: $employeeId');

      final payload = {
        'employee_id': employeeId,
        'leave_type': leaveType,
        'start_date': startDate.toIso8601String().split('T')[0],
        'end_date': endDate.toIso8601String().split('T')[0],
        'reason': reason,
        'status': 'pending',
        if (managerId != null) 'assigned_manager_id': managerId,
      };

      final handler = _leaveRequestInsertHandler;
      if (handler != null) {
        return await handler(payload);
      }

      final response = await _supabase
          .from('leave_requests')
          .insert(payload)
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
          .select(
            '*, employees!leave_requests_employee_id_fkey(id, full_name, branch)',
          );

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
      final action = status == 'approved' ? 'approve' : 'reject';
      final response = await SupabaseFunctionClient.post(
        'branch-request-action',
        {
          'type': 'leave',
          'id': requestId,
          'action': action,
          'reviewerId': reviewedBy,
          if (reviewNotes != null && reviewNotes.trim().isNotEmpty)
            'notes': reviewNotes.trim(),
        },
      );

      return response != null && response['success'] != false;
    } catch (e) {
      print('Review leave request error: $e');
      return false;
    }
  }

  static Future<void> deleteRejectedLeaveRequests(String employeeId) async {
    await _supabase
        .from('leave_requests')
        .delete()
        .eq('employee_id', employeeId)
        .eq('status', 'rejected');
  }

  // ==================== SALARY ADVANCE REQUESTS ====================

  /// Create salary advance request with validations
  static Future<Map<String, dynamic>?> createSalaryAdvanceRequest({
    required String employeeId,
    required double amount,
    required String reason,
  }) async {
    try {
      // 1. جلب الراتب الحالي بعد خصم السلف المعتمدة (current_salary)
      final currentSalaryResult = await _supabase.rpc(
        'get_current_salary_info',
        params: {'p_employee_id': employeeId},
      );

      // RPC returns array with single row
      final currentData =
          (currentSalaryResult is List && currentSalaryResult.isNotEmpty)
          ? currentSalaryResult[0]
          : null;

      final currentSalary =
          (currentData?['current_salary'] as num?)?.toDouble() ?? 0;
      final availableAdvance =
          (currentData?['available_advance'] as num?)?.toDouble() ?? 0;
      final totalNetSalary =
          (currentData?['total_net_salary'] as num?)?.toDouble() ?? 0;
      final totalAdvances =
          (currentData?['total_approved_advances'] as num?)?.toDouble() ?? 0;

      print(
        '💰 Validation: CurrentSalary=$currentSalary, Available=$availableAdvance, Requested=$amount',
      );
      print(
        '📊 Breakdown: TotalNet=$totalNetSalary, TotalAdvances=$totalAdvances',
      );

      // Check if there's available salary
      if (currentSalary <= 0) {
        throw Exception('لا يوجد رصيد متاح حالياً');
      }

      // 2. التحقق من إمكانية طلب سلفة (5 أيام)
      final eligibilityResult = await _supabase.rpc(
        'get_employee_salary_info',
        params: {'p_employee_id': employeeId},
      );
      final eligibilityData =
          (eligibilityResult is List && eligibilityResult.isNotEmpty)
          ? eligibilityResult[0]
          : null;

      final canRequest =
          eligibilityData?['can_request_advance'] as bool? ?? false;

      if (!canRequest) {
        final daysSince =
            eligibilityData?['days_since_last_advance'] as int? ?? 999;
        final remainingDays = 5 - daysSince;
        throw Exception(
          'لا يمكن طلب سلفة جديدة قبل مرور $remainingDays أيام من آخر طلب',
        );
      }

      // 3. التحقق من المبلغ المطلوب ضد المتاح للسحب (30% من الراتب الحالي)
      if (amount > availableAdvance) {
        throw Exception(
          'المبلغ المطلوب ($amount ج.م) يتجاوز المتاح للسحب ($availableAdvance ج.م)\n'
          'رصيدك الحالي: $currentSalary ج.م (بعد خصم السلف المعتمدة)',
        );
      }

      // 4. إنشاء الطلب
      // Resolve manager ID for this employee
      final managerId = await _resolveManagerId(employeeId);
      print('[createSalaryAdvanceRequest] Resolved managerId: $managerId for employee: $employeeId');

      final response = await _supabase
          .from('salary_advances')
          .insert({
            'employee_id': employeeId,
            'amount': amount,
            'reason': reason,
            'status': 'pending',
            if (managerId != null) 'assigned_manager_id': managerId,
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
  static Future<Map<String, dynamic>> getEmployeeSalaryInfo(
    String employeeId,
  ) async {
    try {
      // Get current salary (after deducting approved advances)
      final currentResult = await _supabase.rpc(
        'get_current_salary_info',
        params: {'p_employee_id': employeeId},
      );

      print('🔍 RPC get_current_salary_info result: $currentResult');

      // RPC returns an array with single row
      final currentData = (currentResult is List && currentResult.isNotEmpty)
          ? currentResult[0]
          : currentResult;

      final currentSalary =
          (currentData?['current_salary'] as num?)?.toDouble() ?? 0;
      final availableAdvance =
          (currentData?['available_advance'] as num?)?.toDouble() ?? 0;
      final totalNetSalary =
          (currentData?['total_net_salary'] as num?)?.toDouble() ?? 0;
      final totalApprovedAdvances =
          (currentData?['total_approved_advances'] as num?)?.toDouble() ?? 0;

      // Get eligibility info (5-day rule)
      final eligibilityResult = await _supabase.rpc(
        'get_employee_salary_info',
        params: {'p_employee_id': employeeId},
      );
      final eligibilityData =
          (eligibilityResult is List && eligibilityResult.isNotEmpty)
          ? eligibilityResult[0]
          : eligibilityResult;

      final lastAdvDate = eligibilityData?['last_advance_date'] as String?;
      final daysSince = eligibilityData?['days_since_last_advance'] as int?;
      final canRequest =
          eligibilityData?['can_request_advance'] as bool? ?? false;

      print(
        '💰 Current: $currentSalary, Available: $availableAdvance, TotalNet: $totalNetSalary, Approved: $totalApprovedAdvances, Days: $daysSince, Can: $canRequest',
      );

      return {
        'currentEarnings': currentSalary, // الراتب الحالي بعد خصم السلف
        'maxAdvance': availableAdvance, // المتاح للسحب (30% من الراتب الحالي)
        'total_net_salary': totalNetSalary, // إجمالي الراتب الصافي
        'total_approved_advances':
            totalApprovedAdvances, // إجمالي السلف المعتمدة
        'last_advance_date': lastAdvDate,
        'days_since_last_advance': daysSince,
        'can_request_advance': canRequest,
      };
    } catch (e) {
      print('Get employee salary info error: $e');
      return {
        'currentEarnings': 0,
        'maxAdvance': 0,
        'remaining_balance': 0,
        'can_request_advance': false,
      };
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
          .select(
            '*, employees!salary_advances_employee_id_fkey(id, full_name, branch)',
          );

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
      final action = status == 'approved' ? 'approve' : 'reject';
      final response = await SupabaseFunctionClient.post(
        'branch-request-action',
        {
          'type': 'advance',
          'id': requestId,
          'action': action,
          'reviewerId': approvedBy,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );

      return response != null && response['success'] != false;
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
        'total':
            (attendanceRequests as List).length +
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
  static Future<List<Map<String, dynamic>>>
  getAllAttendanceRequestsWithEmployees({
    String? status,
    String? branchName,
    String? managerId,
  }) async {
    try {
      var query = _supabase
          .from('attendance_requests')
          .select(
            '*, employees:employees!attendance_requests_employee_id_fkey(id, full_name, branch, role)',
          );

      if (status != null) {
        query = query.eq('status', status);
      }
      if (managerId != null) {
        query = query.eq('assigned_manager_id', managerId);
      }

      final response = await query.order('created_at', ascending: false);
      var list = (response as List).cast<Map<String, dynamic>>();

      // ✅ Filter by branch on client side (Supabase doesn't support filtering on joined columns)
      if (branchName != null && branchName.isNotEmpty) {
        list = list.where((item) {
          final emp = item['employees'] as Map<String, dynamic>?;
          final itemAssignedManagerId = item['assigned_manager_id']
              ?.toString()
              .trim();
          final itemBranch = emp?['branch']?.toString().trim();

          if (managerId != null && managerId.isNotEmpty) {
            final assignedToThisManager = itemAssignedManagerId == managerId;
            final unassignedSameBranch =
                (itemAssignedManagerId == null || itemAssignedManagerId.isEmpty) &&
                itemBranch == branchName;
            return assignedToThisManager || unassignedSameBranch;
          }

          return itemBranch == branchName;
        }).toList();
      }

      return list;
    } catch (e) {
      print('Get all attendance requests error: $e');
      return [];
    }
  }

  /// Get all leave requests with employee details (for owner/manager)
  static Future<List<Map<String, dynamic>>> getAllLeaveRequestsWithEmployees({
    String? status,
    String? branchName,
    String? managerId,
  }) async {
    try {
      var query = _supabase
          .from('leave_requests')
          .select(
            '*, employees:employees!leave_requests_employee_id_fkey(id, full_name, branch, role)',
          );

      if (status != null) {
        query = query.eq('status', status);
      }
      if (managerId != null) {
        query = query.eq('assigned_manager_id', managerId);
      }

      final response = await query.order('created_at', ascending: false);
      var list = (response as List).cast<Map<String, dynamic>>();

      // ✅ Filter by branch on client side (Supabase doesn't support filtering on joined columns)
      if (branchName != null && branchName.isNotEmpty) {
        list = list.where((item) {
          final emp = item['employees'] as Map<String, dynamic>?;
          final itemAssignedManagerId = item['assigned_manager_id']
              ?.toString()
              .trim();
          final itemBranch = emp?['branch']?.toString().trim();

          if (managerId != null && managerId.isNotEmpty) {
            final assignedToThisManager = itemAssignedManagerId == managerId;
            final unassignedSameBranch =
                (itemAssignedManagerId == null || itemAssignedManagerId.isEmpty) &&
                itemBranch == branchName;
            return assignedToThisManager || unassignedSameBranch;
          }

          return itemBranch == branchName;
        }).toList();
      }

      return list;
    } catch (e) {
      print('Get all leave requests error: $e');
      return [];
    }
  }

  /// Get all salary advance requests with employee details (for owner/manager)
  static Future<List<Map<String, dynamic>>>
  getAllSalaryAdvanceRequestsWithEmployees({
    String? status,
    String? branchName,
    String? managerId,
  }) async {
    try {
      var query = _supabase
          .from('salary_advances')
          .select(
            '*, employees:employees!salary_advances_employee_id_fkey(id, full_name, branch, role, monthly_salary)',
          );

      if (status != null) {
        query = query.eq('status', status);
      }
      if (managerId != null) {
        query = query.eq('assigned_manager_id', managerId);
      }

      final response = await query.order('created_at', ascending: false);
      var list = (response as List).cast<Map<String, dynamic>>();

      // ✅ Filter by branch on client side
      if (branchName != null && managerId == null) {
        list = list.where((item) {
          final emp = item['employees'] as Map<String, dynamic>?;
          return emp?['branch'] == branchName;
        }).toList();
      }

      return list;
    } catch (e) {
      print('Get all salary advance requests error: $e');
      return [];
    }
  }

  /// Get all breaks with employee details (for owner/manager)
  static Future<List<Map<String, dynamic>>> getAllBreaksWithEmployees({
    String? status,
    String? branchName,
    String? managerId,
  }) async {
    try {
      var query = _supabase
          .from('breaks')
          .select(
            '*, employees:employees!breaks_employee_id_fkey(id, full_name, branch, role)',
          );

      final response = await query.order('created_at', ascending: false);
      var list = (response as List).cast<Map<String, dynamic>>();

      if (status != null && status.trim().isNotEmpty) {
        final normalizedStatus = status.trim().toLowerCase();
        list = list.where((item) {
          final itemStatus = (item['status'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          return itemStatus == normalizedStatus;
        }).toList();
      }

      if (managerId != null) {
        list = list.where((item) {
          final assignedManagerId = item['assigned_manager_id']
              ?.toString()
              .trim();
          if (assignedManagerId == managerId) {
            return true;
          }

          final employee = item['employees'] as Map<String, dynamic>?;
          final employeeBranch = employee?['branch']?.toString().trim();

            return (assignedManagerId == null || assignedManagerId.isEmpty) &&
              branchName != null &&
              branchName.isNotEmpty &&
              employeeBranch == branchName;
        }).toList();
      } else if (branchName != null && branchName.isNotEmpty) {
        list = list.where((item) {
          final employee = item['employees'] as Map<String, dynamic>?;
          return employee?['branch'] == branchName;
        }).toList();
      }

      return list;
    } catch (e) {
      print('Get all breaks error: $e');
      return [];
    }
  }

  // ==================== BREAK REQUESTS ====================

  /// Create break request directly in database
  static Future<Map<String, dynamic>?> createBreakRequest({
    required String employeeId,
    required int durationMinutes,
    String? reason,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      final managerId = await _resolveManagerId(employeeId);
      final payload = <String, dynamic>{
        'employee_id': employeeId,
        'attendance_id': null,
        'break_start': now.toIso8601String(),
        'break_end': null,
        'duration_minutes': durationMinutes,
        'reason': reason ?? 'استراحة',
        'status': 'PENDING',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        if (managerId != null) 'assigned_manager_id': managerId,
      };
      print('📝 [createBreakRequest] Payload: $payload');
      final response = await _supabase
          .from('breaks')
          .insert(payload)
          .select()
          .single();
      print('✅ Break created: ${response['id']}');
      return response;
    } catch (e) {
      print('Create break error: $e');
      rethrow;
    }
  }


  /// Get break requests
  static Future<List<Map<String, dynamic>>> getBreakRequests({
    String? employeeId,
    String? status,
  }) async {
    try {
      var query = _supabase.from('breaks')
          .select('*, employees!breaks_employee_id_fkey(id, full_name, branch)');
      if (employeeId != null) query = query.eq('employee_id', employeeId);
      if (status != null) query = query.eq('status', status);
      final response = await query.order('created_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get breaks error: $e');
      return [];
    }
  }

  /// Review break request
  static Future<bool> reviewBreakRequest({
    required String requestId,
    required String reviewedBy,
    required String status,
  }) async {
    try {
      final action = status == 'approved' ? 'approve' : 'reject';
      final response = await SupabaseFunctionClient.post('branch-request-action', {
        'type': 'break',
        'id': requestId,
        'action': action,
        'reviewerId': reviewedBy,
      });
      return response != null && response['success'] != false;
    } catch (e) {
      print('Review break error: $e');
      return false;
    }
  }

}
