import 'package:hive/hive.dart';

const String attendanceRequestsBox = 'attendance_requests';

enum RequestStatus {
  pending,
  approved,
  rejected,
}

class AttendanceRequest extends HiveObject {
  AttendanceRequest({
    required this.id,
    required this.employeeId,
    required this.forgottenTime,
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
  DateTime forgottenTime;
  String reason;
  RequestStatus status;
  DateTime createdAt;
  DateTime? reviewedAt;
  String? reviewedBy;
  String? rejectionReason;

  bool get isPending => status == RequestStatus.pending;
  bool get isApproved => status == RequestStatus.approved;
  bool get isRejected => status == RequestStatus.rejected;
}

class AttendanceRequestAdapter extends TypeAdapter<AttendanceRequest> {
  @override
  final int typeId = 12;

  @override
  AttendanceRequest read(BinaryReader reader) {
    final fieldCount = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
    };

    return AttendanceRequest(
      id: fields[0] as String,
      employeeId: fields[1] as String,
      forgottenTime: DateTime.parse(fields[2] as String),
      reason: fields[3] as String,
      status: RequestStatus.values[fields[4] as int? ?? 0],
      createdAt: DateTime.tryParse(fields[5] as String? ?? '') ?? DateTime.now(),
      reviewedAt: fields[6] != null ? DateTime.parse(fields[6] as String) : null,
      reviewedBy: fields[7] as String?,
      rejectionReason: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AttendanceRequest obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.employeeId)
      ..writeByte(2)
      ..write(obj.forgottenTime.toIso8601String())
      ..writeByte(3)
      ..write(obj.reason)
      ..writeByte(4)
      ..write(obj.status.index)
      ..writeByte(5)
      ..write(obj.createdAt.toIso8601String())
      ..writeByte(6)
      ..write(obj.reviewedAt?.toIso8601String())
      ..writeByte(7)
      ..write(obj.reviewedBy)
      ..writeByte(8)
      ..write(obj.rejectionReason);
  }
}

void registerAttendanceRequestAdapter() {
  if (!Hive.isAdapterRegistered(12)) {
    Hive.registerAdapter(AttendanceRequestAdapter());
  }
}
