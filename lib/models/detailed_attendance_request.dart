class DetailedAttendanceRequest {
  final String requestId;
  final String requestType;
  final DateTime requestedTime;
  final String reason;
  final String status;
  final DateTime createdAt;

  // Employee details
  final String employeeId;
  final String employeeName;
  final String employeeRole;

  // Branch details
  final String? branchName;

  DetailedAttendanceRequest({
    required this.requestId,
    required this.requestType,
    required this.requestedTime,
    required this.reason,
    required this.status,
    required this.createdAt,
    required this.employeeId,
    required this.employeeName,
    required this.employeeRole,
    this.branchName,
  });

  factory DetailedAttendanceRequest.fromJson(Map<String, dynamic> json) {
    // Handle nested employee data from Supabase join
    final employeeData = json['employees'] as Map<String, dynamic>?;
    
    return DetailedAttendanceRequest(
      requestId: (json['requestId'] ?? json['id']) as String,
      requestType: (json['requestType'] ?? json['request_type']) as String,
      requestedTime: DateTime.parse((json['requestedTime'] ?? json['requested_time']) as String),
      reason: (json['reason'] ?? '') as String,
      status: (json['status'] ?? 'pending') as String,
      createdAt: DateTime.parse((json['createdAt'] ?? json['created_at']) as String),
      employeeId: (employeeData?['id'] ?? json['employeeId'] ?? json['employee_id']) as String,
      employeeName: (employeeData?['full_name'] ?? json['employeeName'] ?? json['employee_name'] ?? 'غير معروف') as String,
      employeeRole: (employeeData?['role'] ?? json['employeeRole'] ?? json['employee_role'] ?? 'staff') as String,
      branchName: (employeeData?['branch'] ?? json['branchName']) as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'requestType': requestType,
      'requestedTime': requestedTime.toIso8601String(),
      'reason': reason,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'employeeId': employeeId,
      'employeeName': employeeName,
      'employeeRole': employeeRole,
      'branchName': branchName,
    };
  }
}