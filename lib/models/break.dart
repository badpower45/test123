enum BreakStatus {
  pending,
  approved,
  rejected,
  active,
  completed,
}

class Break {
  Break({
    required this.id,
    required this.employeeId,
    this.shiftId,
    required this.requestedDurationMinutes,
    required this.status,
    this.startTime,
    this.endTime,
    this.approvedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String employeeId;
  final String? shiftId;
  final int requestedDurationMinutes;
  final BreakStatus status;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? approvedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPending => status == BreakStatus.pending;
  bool get isApproved => status == BreakStatus.approved;
  bool get isActive => status == BreakStatus.active;
  bool get isCompleted => status == BreakStatus.completed;

  factory Break.fromJson(Map<String, dynamic> json) {
    return Break(
      id: (json['id'] ?? '') as String,
      employeeId: (json['employeeId'] ?? json['employee_id'] ?? '') as String,
      shiftId: json['shiftId'] as String? ?? json['shift_id'] as String?,
      requestedDurationMinutes: _parseDuration(json['requestedDurationMinutes'] ?? json['requested_duration_minutes']),
      status: _mapStatus(json['status']),
      startTime: _parseDateTime(json['startTime'] ?? json['start_time']),
      endTime: _parseDateTime(json['endTime'] ?? json['end_time']),
      approvedBy: json['approvedBy'] as String? ?? json['approved_by'] as String?,
      createdAt: _parseDateTime(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(json['updatedAt'] ?? json['updated_at']) ?? DateTime.now(),
    );
  }
}

int _parseDuration(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

BreakStatus _mapStatus(Object? value) {
  final normalized = (value?.toString() ?? '').toUpperCase();
  switch (normalized) {
    case 'APPROVED':
      return BreakStatus.approved;
    case 'REJECTED':
      return BreakStatus.rejected;
    case 'ACTIVE':
      return BreakStatus.active;
    case 'COMPLETED':
      return BreakStatus.completed;
    default:
      return BreakStatus.pending;
  }
}

DateTime? _parseDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  final raw = value.toString();
  if (raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}
