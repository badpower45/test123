import 'package:hive/hive.dart';

const String attendanceRequestsBox = 'attendance_requests';

enum RequestStatus {
  pending,
  approved,
  rejected,
}

enum AttendanceRequestType {
  checkIn,
  checkOut,
}

class AttendanceRequest extends HiveObject {
  AttendanceRequest({
    required this.id,
    required this.employeeId,
    required this.requestedTime,
    required this.reason,
    this.requestType = AttendanceRequestType.checkIn,
    this.status = RequestStatus.pending,
    DateTime? createdAt,
    DateTime? reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
  })  : createdAt = createdAt ?? DateTime.now(),
        reviewedAt = reviewedAt;

  String id;
  String employeeId;
  DateTime requestedTime;
  String reason;
  AttendanceRequestType requestType;
  RequestStatus status;
  DateTime createdAt;
  DateTime? reviewedAt;
  String? reviewedBy;
  String? rejectionReason;

  bool get isPending => status == RequestStatus.pending;
  bool get isApproved => status == RequestStatus.approved;
  bool get isRejected => status == RequestStatus.rejected;

  factory AttendanceRequest.fromJson(Map<String, dynamic> json) {
    // ✅ FIX: Safe date parsing with null checks
    DateTime requestedTime;
    DateTime createdAt;
    DateTime? reviewedAt;
    
    try {
      final requestedTimeStr = (json['requestedTime'] ?? json['requested_time'])?.toString();
      if (requestedTimeStr == null || requestedTimeStr.isEmpty) {
        requestedTime = DateTime.now();
      } else {
        requestedTime = DateTime.parse(requestedTimeStr);
      }
    } catch (e) {
      requestedTime = DateTime.now();
    }
    
    try {
      final createdAtStr = (json['createdAt'] ?? json['created_at'])?.toString();
      if (createdAtStr == null || createdAtStr.isEmpty) {
        createdAt = DateTime.now();
      } else {
        createdAt = DateTime.parse(createdAtStr);
      }
    } catch (e) {
      createdAt = DateTime.now();
    }
    
    try {
      final reviewedAtStr = (json['reviewedAt'] ?? json['reviewed_at'])?.toString();
      if (reviewedAtStr != null && reviewedAtStr.isNotEmpty) {
        reviewedAt = DateTime.parse(reviewedAtStr);
      }
    } catch (e) {
      reviewedAt = null;
    }
    
    return AttendanceRequest(
      id: (json['id'] ?? '') as String,
      employeeId: (json['employeeId'] ?? json['employee_id'] ?? '') as String,
      requestedTime: requestedTime,
      reason: (json['reason'] ?? '') as String,
      requestType: _mapRequestType(json['requestType'] ?? json['request_type']),
      status: _mapStatus(json['status'] as String? ?? ''),
      createdAt: createdAt,
      reviewedAt: reviewedAt,
      reviewedBy: (json['reviewedBy'] ?? json['reviewed_by']) as String?,
      rejectionReason: (json['reviewNotes'] ?? json['rejection_reason']) as String?,
    );
  }
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
      requestedTime: DateTime.parse(fields[2] as String),
      reason: fields[3] as String,
      requestType: fields.containsKey(9)
          ? AttendanceRequestType.values[fields[9] as int? ?? 0]
          : AttendanceRequestType.checkIn,
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
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.employeeId)
      ..writeByte(2)
      ..write(obj.requestedTime.toIso8601String())
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
      ..write(obj.rejectionReason)
      ..writeByte(9)
      ..write(obj.requestType.index);
  }
}

void registerAttendanceRequestAdapter() {
  if (!Hive.isAdapterRegistered(12)) {
    Hive.registerAdapter(AttendanceRequestAdapter());
  }
}

AttendanceRequestType _mapRequestType(Object? value) {
  final normalized = (value?.toString() ?? '').toLowerCase();
  switch (normalized) {
    case 'check-out':
    case 'checkout':
      return AttendanceRequestType.checkOut;
    default:
      return AttendanceRequestType.checkIn;
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
