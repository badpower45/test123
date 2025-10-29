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
    return DetailedAttendanceRequest(
      requestId: json['requestId'] as String,
      requestType: json['requestType'] as String,
      requestedTime: DateTime.parse(json['requestedTime'] as String),
      reason: json['reason'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      employeeId: json['employeeId'] as String,
      employeeName: json['employeeName'] as String,
      employeeRole: json['employeeRole'] as String,
      branchName: json['branchName'] as String?,
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