import 'package:hive/hive.dart';

const String leaveRequestsBox = 'leave_requests';

enum LeaveType {
  normal,
  emergency,
}

enum RequestStatus {
  pending,
  approved,
  rejected,
}

class LeaveRequest extends HiveObject {
  LeaveRequest({
    required this.id,
    required this.employeeId,
    required this.startDate,
    required this.endDate,
    required this.type,
    required this.reason,
    this.status = RequestStatus.pending,
    this.daysCount = 0,
    this.allowanceAmount = 0,
    DateTime? createdAt,
    DateTime? reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
  })  : createdAt = createdAt ?? DateTime.now(),
        reviewedAt = reviewedAt;

  String id;
  String employeeId;
  DateTime startDate;
  DateTime endDate;
  LeaveType type;
  String reason;
  RequestStatus status;
  DateTime createdAt;
  DateTime? reviewedAt;
  String? reviewedBy;
  String? rejectionReason;
  int daysCount;
  double allowanceAmount;

  bool get isPending => status == RequestStatus.pending;
  bool get isApproved => status == RequestStatus.approved;
  bool get isRejected => status == RequestStatus.rejected;
  bool get isEmergency => type == LeaveType.emergency;

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    final leaveType = (json['leaveType'] ?? json['leave_type']) as String?;
    final statusValue = (json['status'] ?? '') as String;
    return LeaveRequest(
      id: (json['id'] ?? '') as String,
      employeeId: (json['employeeId'] ?? json['employee_id'] ?? '') as String,
      startDate: DateTime.parse((json['startDate'] ?? json['start_date']) as String),
      endDate: DateTime.parse((json['endDate'] ?? json['end_date']) as String),
      type: _mapLeaveType(leaveType),
      reason: (json['reason'] ?? '') as String,
      status: _mapStatus(statusValue),
      createdAt: DateTime.parse((json['createdAt'] ?? json['created_at']) as String),
      reviewedAt: (json['reviewedAt'] ?? json['reviewed_at']) != null
          ? DateTime.parse((json['reviewedAt'] ?? json['reviewed_at']) as String)
          : null,
      reviewedBy: (json['reviewedBy'] ?? json['reviewed_by']) as String?,
      rejectionReason: (json['reviewNotes'] ?? json['rejection_reason']) as String?,
      daysCount: ((json['daysCount'] ?? json['days_count']) as num?)?.toInt() ?? 0,
      allowanceAmount:
          ((json['allowanceAmount'] ?? json['allowance_amount']) as num?)?.toDouble() ?? 0,
    );
  }
}

class LeaveRequestAdapter extends TypeAdapter<LeaveRequest> {
  @override
  final int typeId = 10;

  @override
  LeaveRequest read(BinaryReader reader) {
    final fieldCount = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
    };

    return LeaveRequest(
      id: fields[0] as String,
      employeeId: fields[1] as String,
      startDate: DateTime.parse(fields[2] as String),
      endDate: fields.containsKey(10)
          ? DateTime.parse(fields[10] as String)
          : DateTime.parse(fields[2] as String),
      type: LeaveType.values[fields[3] as int],
      reason: fields[4] as String,
      status: RequestStatus.values[fields[5] as int? ?? 0],
      createdAt: DateTime.tryParse(fields[6] as String? ?? '') ?? DateTime.now(),
      reviewedAt: fields[7] != null ? DateTime.parse(fields[7] as String) : null,
      reviewedBy: fields[8] as String?,
      rejectionReason: fields[9] as String?,
      daysCount: (fields[11] as num?)?.toInt() ?? 0,
      allowanceAmount: (fields[12] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, LeaveRequest obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.employeeId)
      ..writeByte(2)
      ..write(obj.startDate.toIso8601String())
      ..writeByte(3)
      ..write(obj.type.index)
      ..writeByte(4)
      ..write(obj.reason)
      ..writeByte(5)
      ..write(obj.status.index)
      ..writeByte(6)
      ..write(obj.createdAt.toIso8601String())
      ..writeByte(7)
      ..write(obj.reviewedAt?.toIso8601String())
      ..writeByte(8)
      ..write(obj.reviewedBy)
      ..writeByte(9)
      ..write(obj.rejectionReason)
      ..writeByte(10)
      ..write(obj.endDate.toIso8601String())
      ..writeByte(11)
      ..write(obj.daysCount)
      ..writeByte(12)
      ..write(obj.allowanceAmount);
  }
}

void registerLeaveRequestAdapter() {
  if (!Hive.isAdapterRegistered(10)) {
    Hive.registerAdapter(LeaveRequestAdapter());
  }
}

LeaveType _mapLeaveType(String? value) {
  switch (value?.toLowerCase()) {
    case 'emergency':
      return LeaveType.emergency;
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
