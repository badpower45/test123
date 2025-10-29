class EmployeeAttendanceStatus {
  final String employeeId;
  final String employeeName;
  final String employeeRole;
  final String? branchName;
  final String status; // 'absent', 'present', 'checked_out', 'on_leave'
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String? attendanceRecordId;

  EmployeeAttendanceStatus({
    required this.employeeId,
    required this.employeeName,
    required this.employeeRole,
    this.branchName,
    required this.status,
    this.checkInTime,
    this.checkOutTime,
    this.attendanceRecordId,
  });

  factory EmployeeAttendanceStatus.fromJson(Map<String, dynamic> json) {
    return EmployeeAttendanceStatus(
      employeeId: json['employeeId'] as String,
      employeeName: json['employeeName'] as String,
      employeeRole: json['employeeRole'] as String,
      branchName: json['branchName'] as String?,
      status: json['status'] as String,
      checkInTime: json['checkInTime'] != null ? DateTime.parse(json['checkInTime'] as String) : null,
      checkOutTime: json['checkOutTime'] != null ? DateTime.parse(json['checkOutTime'] as String) : null,
      attendanceRecordId: json['attendanceRecordId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'employeeId': employeeId,
      'employeeName': employeeName,
      'employeeRole': employeeRole,
      'branchName': branchName,
      'status': status,
      'checkInTime': checkInTime?.toIso8601String(),
      'checkOutTime': checkOutTime?.toIso8601String(),
      'attendanceRecordId': attendanceRecordId,
    };
  }

  // Helper methods
  bool get isPresent => status == 'present';
  bool get isAbsent => status == 'absent';
  bool get isCheckedOut => status == 'checked_out';
  bool get isOnLeave => status == 'on_leave';

  // Get status color (moved to widget level to avoid import issues)
  // Get status icon (moved to widget level to avoid import issues)

  // Get status text in Arabic
  String get statusTextArabic {
    switch (status) {
      case 'present':
        return 'حاضر';
      case 'checked_out':
        return 'منصرف';
      case 'absent':
        return 'غائب';
      case 'on_leave':
        return 'إجازة';
      default:
        return 'غير محدد';
    }
  }
}