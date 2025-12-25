/// Model for session validation requests
/// Used when employee has a gap in pulse tracking > 5.5 minutes
class SessionValidationRequest {
  final String? id;
  final String employeeId;
  final String? attendanceId;
  final String? branchId;
  final String? managerId;
  final DateTime gapStartTime;
  final DateTime gapEndTime;
  final int gapDurationMinutes;
  final int expectedPulsesCount;
  final String status; // 'pending', 'approved', 'rejected'
  final DateTime? managerResponseTime;
  final String? managerNotes;
  final DateTime createdAt;

  SessionValidationRequest({
    this.id,
    required this.employeeId,
    this.attendanceId,
    this.branchId,
    this.managerId,
    required this.gapStartTime,
    required this.gapEndTime,
    required this.gapDurationMinutes,
    required this.expectedPulsesCount,
    this.status = 'pending',
    this.managerResponseTime,
    this.managerNotes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Convert to JSON for Supabase
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'employee_id': employeeId,
      'attendance_id': attendanceId,
      'branch_id': branchId,
      'manager_id': managerId,
      'gap_start_time': gapStartTime.toIso8601String(),
      'gap_end_time': gapEndTime.toIso8601String(),
      'gap_duration_minutes': gapDurationMinutes,
      'expected_pulses_count': expectedPulsesCount,
      'status': status,
      'manager_response_time': managerResponseTime?.toIso8601String(),
      'manager_notes': managerNotes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Create from JSON (Supabase response)
  factory SessionValidationRequest.fromJson(Map<String, dynamic> json) {
    return SessionValidationRequest(
      id: json['id'] as String?,
      employeeId: json['employee_id'] as String,
      attendanceId: json['attendance_id'] as String?,
      branchId: json['branch_id'] as String?,
      managerId: json['manager_id'] as String?,
      gapStartTime: DateTime.parse(json['gap_start_time'] as String),
      gapEndTime: DateTime.parse(json['gap_end_time'] as String),
      gapDurationMinutes: json['gap_duration_minutes'] as int,
      expectedPulsesCount: json['expected_pulses_count'] as int,
      status: json['status'] as String? ?? 'pending',
      managerResponseTime: json['manager_response_time'] != null
          ? DateTime.parse(json['manager_response_time'] as String)
          : null,
      managerNotes: json['manager_notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  /// Copy with new values
  SessionValidationRequest copyWith({
    String? id,
    String? employeeId,
    String? attendanceId,
    String? branchId,
    String? managerId,
    DateTime? gapStartTime,
    DateTime? gapEndTime,
    int? gapDurationMinutes,
    int? expectedPulsesCount,
    String? status,
    DateTime? managerResponseTime,
    String? managerNotes,
    DateTime? createdAt,
  }) {
    return SessionValidationRequest(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      attendanceId: attendanceId ?? this.attendanceId,
      branchId: branchId ?? this.branchId,
      managerId: managerId ?? this.managerId,
      gapStartTime: gapStartTime ?? this.gapStartTime,
      gapEndTime: gapEndTime ?? this.gapEndTime,
      gapDurationMinutes: gapDurationMinutes ?? this.gapDurationMinutes,
      expectedPulsesCount: expectedPulsesCount ?? this.expectedPulsesCount,
      status: status ?? this.status,
      managerResponseTime: managerResponseTime ?? this.managerResponseTime,
      managerNotes: managerNotes ?? this.managerNotes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
