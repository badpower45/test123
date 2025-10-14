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
    required this.leaveDate,
    required this.type,
    required this.reason,
    this.status = RequestStatus.pending,
    DateTime? createdAt,
    DateTime? reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
  })  : createdAt = createdAt ?? DateTime.now(),
        reviewedAt = reviewedAt;

  String id;
  String employeeId;
  DateTime leaveDate;
  LeaveType type;
  String reason;
  RequestStatus status;
  DateTime createdAt;
  DateTime? reviewedAt;
  String? reviewedBy;
  String? rejectionReason;

  bool get isPending => status == RequestStatus.pending;
  bool get isApproved => status == RequestStatus.approved;
  bool get isRejected => status == RequestStatus.rejected;
  bool get isEmergency => type == LeaveType.emergency;
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
      leaveDate: DateTime.parse(fields[2] as String),
      type: LeaveType.values[fields[3] as int],
      reason: fields[4] as String,
      status: RequestStatus.values[fields[5] as int? ?? 0],
      createdAt: DateTime.tryParse(fields[6] as String? ?? '') ?? DateTime.now(),
      reviewedAt: fields[7] != null ? DateTime.parse(fields[7] as String) : null,
      reviewedBy: fields[8] as String?,
      rejectionReason: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, LeaveRequest obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.employeeId)
      ..writeByte(2)
      ..write(obj.leaveDate.toIso8601String())
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
      ..write(obj.rejectionReason);
  }
}

void registerLeaveRequestAdapter() {
  if (!Hive.isAdapterRegistered(10)) {
    Hive.registerAdapter(LeaveRequestAdapter());
  }
}
