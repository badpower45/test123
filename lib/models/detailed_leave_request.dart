import 'leave_request.dart';

/// This model is used for displaying detailed leave requests to the owner
/// It includes employee information from the joined tables
class DetailedLeaveRequest {
  final String requestId;
  final DateTime startDate;
  final DateTime endDate;
  final LeaveType type;
  final String? reason;
  final RequestStatus status;
  final int daysCount;
  final double allowanceAmount;
  final DateTime createdAt;

  // Additional employee details for owner view
  final String employeeId;
  final String employeeName;
  final String employeeRole;
  final String? employeeSalary;
  final String? branchName;

  DetailedLeaveRequest({
    required this.requestId,
    required this.startDate,
    required this.endDate,
    required this.type,
    this.reason,
    required this.status,
    required this.daysCount,
    required this.allowanceAmount,
    required this.createdAt,
    required this.employeeId,
    required this.employeeName,
    required this.employeeRole,
    this.employeeSalary,
    this.branchName,
  });

  factory DetailedLeaveRequest.fromJson(Map<String, dynamic> json) {
    // Handle nested employee data from Supabase join
    final employeeData = json['employees'] as Map<String, dynamic>?;
    
    return DetailedLeaveRequest(
      // Original fields
      requestId: (json['requestId'] ?? json['id']) as String,
      startDate: DateTime.parse((json['startDate'] ?? json['start_date']) as String),
      endDate: DateTime.parse((json['endDate'] ?? json['end_date']) as String),
      type: _mapLeaveType((json['leaveType'] ?? json['leave_type']) as String?),
      reason: (json['reason'] ?? '') as String,
      status: _mapStatus((json['status'] ?? '') as String),
      daysCount: ((json['daysCount'] ?? json['days_count']) as num?)?.toInt() ?? 0,
      allowanceAmount: ((json['allowanceAmount'] ?? json['allowance_amount']) as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse((json['createdAt'] ?? json['created_at']) as String),

      // Employee details (from nested 'employees' object or direct fields)
      employeeId: (employeeData?['id'] ?? json['employeeId'] ?? json['employee_id']) as String,
      employeeName: (employeeData?['full_name'] ?? json['employeeName'] ?? json['employee_name'] ?? 'غير معروف') as String,
      employeeRole: (employeeData?['role'] ?? json['employeeRole'] ?? json['employee_role'] ?? 'staff') as String,
      employeeSalary: json['employeeSalary'] as String?,
      branchName: (employeeData?['branch'] ?? json['branchName']) as String?,
    );
  }
}

// Helper functions copied from leave_request.dart
LeaveType _mapLeaveType(String? value) {
  switch (value?.toLowerCase()) {
    case 'emergency':
      return LeaveType.emergency;
    case 'regular':
    default:
      return LeaveType.normal;
  }
}

RequestStatus _mapStatus(String value) {
  switch (value.toLowerCase()) {
    case 'approved':
      return RequestStatus.approved;
    case 'rejected':
      return RequestStatus.rejected;
    default:
      return RequestStatus.pending;
  }
}