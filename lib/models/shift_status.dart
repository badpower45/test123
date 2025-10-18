class ShiftStatus {
  ShiftStatus({
    required this.hasActiveShift,
    this.status,
    this.shiftId,
    this.checkInAt,
    this.lastActivityAt,
    this.canRequestBreak = false,
    this.activeBreakId,
    this.activeBreakEndsAt,
  });

  final bool hasActiveShift;
  final String? status;
  final String? shiftId;
  final DateTime? checkInAt;
  final DateTime? lastActivityAt;
  final bool canRequestBreak;
  final String? activeBreakId;
  final DateTime? activeBreakEndsAt;

  bool get isCheckedIn => hasActiveShift;
  bool get isOnBreak => (status ?? '').toLowerCase() == 'on_break';

  Duration? get elapsedSinceCheckIn {
    if (checkInAt == null) {
      return null;
    }
    return DateTime.now().difference(checkInAt!);
  }

  factory ShiftStatus.inactive() => ShiftStatus(hasActiveShift: false);

  factory ShiftStatus.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? json['state'] ?? json['shiftStatus'] ?? '')
        .toString()
        .toLowerCase();

    final checkInKey = json['checkInAt'] ?? json['check_in_at'] ?? json['checkedInAt'];
    final lastActivityKey =
        json['lastActivityAt'] ?? json['last_activity_at'] ?? json['updatedAt'];
    final activeBreak = json['activeBreak'] ?? json['active_break'];
    final activeBreakId = (activeBreak is Map)
        ? activeBreak['id']?.toString()
        : json['activeBreakId'] ?? json['active_break_id'];
    final activeBreakEndsAtRaw = (activeBreak is Map)
        ? activeBreak['endsAt'] ?? activeBreak['ends_at']
        : json['activeBreakEndsAt'] ?? json['active_break_ends_at'];

    return ShiftStatus(
      hasActiveShift: _parseBool(json['hasActiveShift']) ??
          _parseBool(json['active']) ??
          (rawStatus == 'checked_in' || rawStatus == 'on_break'),
      status: rawStatus.isEmpty ? null : rawStatus,
      shiftId: json['shiftId']?.toString() ?? json['shift_id']?.toString(),
      checkInAt: _parseDate(checkInKey),
      lastActivityAt: _parseDate(lastActivityKey),
      canRequestBreak: _parseBool(json['canRequestBreak']) ??
          _parseBool(json['allowBreak']) ??
          _parseBool(json['can_request_break']) ??
          false,
      activeBreakId: activeBreakId?.toString(),
      activeBreakEndsAt: _parseDate(activeBreakEndsAtRaw),
    );
  }

  ShiftStatus copyWith({
    bool? hasActiveShift,
    String? status,
    String? shiftId,
    DateTime? checkInAt,
    DateTime? lastActivityAt,
    bool? canRequestBreak,
    String? activeBreakId,
    DateTime? activeBreakEndsAt,
  }) {
    return ShiftStatus(
      hasActiveShift: hasActiveShift ?? this.hasActiveShift,
      status: status ?? this.status,
      shiftId: shiftId ?? this.shiftId,
      checkInAt: checkInAt ?? this.checkInAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      canRequestBreak: canRequestBreak ?? this.canRequestBreak,
      activeBreakId: activeBreakId ?? this.activeBreakId,
      activeBreakEndsAt: activeBreakEndsAt ?? this.activeBreakEndsAt,
    );
  }
}

bool? _parseBool(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  final normalized = value.toString().toLowerCase();
  if (normalized == 'true' || normalized == '1') {
    return true;
  }
  if (normalized == 'false' || normalized == '0') {
    return false;
  }
  return null;
}

DateTime? _parseDate(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is int) {
    final seconds = value.toString().length <= 10;
    return seconds
        ? DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true).toLocal()
        : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
  }
  final raw = value.toString();
  if (raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw)?.toLocal();
}
