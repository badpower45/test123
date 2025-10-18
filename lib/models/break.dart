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
    this.branchId,
    this.shiftId,
    required this.requestedDurationMinutes,
    this.actualDurationMinutes,
    required this.status,
    this.reason,
    this.notes,
    this.startTime,
    this.endTime,
    this.approvedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String employeeId;
  final String? branchId;
  final String? shiftId;
  final int requestedDurationMinutes;
  final int? actualDurationMinutes;
  final BreakStatus status;
  final String? reason;
  final String? notes;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? approvedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  Duration get requestedDuration => Duration(minutes: requestedDurationMinutes);
  Duration? get actualDuration =>
      actualDurationMinutes != null ? Duration(minutes: actualDurationMinutes!) : null;

  bool get isPending => status == BreakStatus.pending;
  bool get isApproved => status == BreakStatus.approved;
  bool get isActive => status == BreakStatus.active;
  bool get isCompleted => status == BreakStatus.completed;

  factory Break.fromJson(Map<String, dynamic> json) {
    return Break(
      id: _readString(json, 'id') ?? '',
      employeeId:
          _readString(json, 'employeeId') ?? _readString(json, 'employee_id') ?? '',
      branchId: _readString(json, 'branchId') ?? _readString(json, 'branch_id'),
      shiftId: _readString(json, 'shiftId') ?? _readString(json, 'shift_id'),
      requestedDurationMinutes: _readInt(json, 'requestedDurationMinutes') ??
          _readInt(json, 'requested_duration_minutes') ??
          0,
      actualDurationMinutes: _readInt(json, 'actualDurationMinutes') ??
          _readInt(json, 'actual_duration_minutes'),
      status: _mapStatus(json['status']),
      reason: _readString(json, 'reason'),
      notes: _readString(json, 'notes') ?? _readString(json, 'note'),
      startTime: _readDate(json, 'startTime') ?? _readDate(json, 'start_time'),
      endTime: _readDate(json, 'endTime') ?? _readDate(json, 'end_time'),
      approvedBy: _readString(json, 'approvedBy') ?? _readString(json, 'approved_by'),
      createdAt:
          _readDate(json, 'createdAt') ?? _readDate(json, 'created_at') ?? DateTime.now(),
      updatedAt:
          _readDate(json, 'updatedAt') ?? _readDate(json, 'updated_at') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'employee_id': employeeId,
      if (branchId != null) 'branch_id': branchId,
      if (shiftId != null) 'shift_id': shiftId,
      'requested_duration_minutes': requestedDurationMinutes,
      if (actualDurationMinutes != null)
        'actual_duration_minutes': actualDurationMinutes,
      'status': status.name.toUpperCase(),
      if (reason != null) 'reason': reason,
      if (notes != null) 'notes': notes,
      if (startTime != null) 'start_time': startTime!.toIso8601String(),
      if (endTime != null) 'end_time': endTime!.toIso8601String(),
      if (approvedBy != null) 'approved_by': approvedBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

String? _readString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  return value.toString();
}

int? _readInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    // Try parsing the string as int
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
    
    // If it fails, try as double first then convert to int
    final doubleValue = double.tryParse(value);
    return doubleValue?.toInt();
  }
  // Fallback: try converting to string then parse
  return int.tryParse(value.toString());
}

DateTime? _readDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  final raw = value.toString();
  if (raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}

BreakStatus _mapStatus(Object? value) {
  final normalized = (value ?? '').toString().trim().toUpperCase();
  switch (normalized) {
    case 'APPROVED':
      return BreakStatus.approved;
    case 'REJECTED':
      return BreakStatus.rejected;
    case 'ACTIVE':
    case 'IN_PROGRESS':
    case 'STARTED':
      return BreakStatus.active;
    case 'COMPLETED':
    case 'DONE':
      return BreakStatus.completed;
    default:
      return BreakStatus.pending;
  }
}
