import 'package:hive/hive.dart';

const String advanceRequestsBox = 'advance_requests';

enum RequestStatus {
  pending,
  approved,
  rejected,
}

class AdvanceRequest extends HiveObject {
  AdvanceRequest({
    required this.id,
    required this.employeeId,
    required this.amount,
    required this.currentEarnings,
    this.status = RequestStatus.pending,
    DateTime? createdAt,
    DateTime? reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
  })  : createdAt = createdAt ?? DateTime.now(),
        reviewedAt = reviewedAt;

  String id;
  String employeeId;
  double amount;
  double currentEarnings;
  RequestStatus status;
  DateTime createdAt;
  DateTime? reviewedAt;
  String? reviewedBy;
  String? rejectionReason;

  bool get isPending => status == RequestStatus.pending;
  bool get isApproved => status == RequestStatus.approved;
  bool get isRejected => status == RequestStatus.rejected;
  
  double get maxAllowedAmount => currentEarnings * 0.30;
}

class AdvanceRequestAdapter extends TypeAdapter<AdvanceRequest> {
  @override
  final int typeId = 11;

  @override
  AdvanceRequest read(BinaryReader reader) {
    final fieldCount = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
    };

    return AdvanceRequest(
      id: fields[0] as String,
      employeeId: fields[1] as String,
      amount: (fields[2] as num).toDouble(),
      currentEarnings: (fields[3] as num).toDouble(),
      status: RequestStatus.values[fields[4] as int? ?? 0],
      createdAt: DateTime.tryParse(fields[5] as String? ?? '') ?? DateTime.now(),
      reviewedAt: fields[6] != null ? DateTime.parse(fields[6] as String) : null,
      reviewedBy: fields[7] as String?,
      rejectionReason: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AdvanceRequest obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.employeeId)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.currentEarnings)
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

void registerAdvanceRequestAdapter() {
  if (!Hive.isAdapterRegistered(11)) {
    Hive.registerAdapter(AdvanceRequestAdapter());
  }
}
