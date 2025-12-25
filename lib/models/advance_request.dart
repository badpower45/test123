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
    this.eligibleAmount,
    DateTime? requestDate,
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
  double? eligibleAmount;
  DateTime? requestDate;
  DateTime createdAt;
  DateTime? reviewedAt;
  String? reviewedBy;
  String? rejectionReason;

  bool get isPending => status == RequestStatus.pending;
  bool get isApproved => status == RequestStatus.approved;
  bool get isRejected => status == RequestStatus.rejected;

  double get maxAllowedAmount => currentEarnings * 0.30;

  factory AdvanceRequest.fromJson(Map<String, dynamic> json) {
    final statusValue = (json['status'] ?? '') as String;
    
    // ✅ FIX: Safe date parsing with null checks
    DateTime? requestDate;
    DateTime createdAt;
    DateTime? reviewedAt;
    
    try {
      final requestDateStr = (json['requestDate'] ?? json['request_date'])?.toString();
      if (requestDateStr != null && requestDateStr.isNotEmpty) {
        requestDate = DateTime.parse(requestDateStr);
      }
    } catch (e) {
      requestDate = null;
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
    
    return AdvanceRequest(
      id: (json['id'] ?? '') as String,
      employeeId: (json['employeeId'] ?? json['employee_id'] ?? '') as String,
      amount: ((json['amount']) as num).toDouble(),
      currentEarnings:
          ((json['currentSalary'] ?? json['current_earnings'] ?? 0) as num).toDouble(),
      eligibleAmount: (json['eligibleAmount'] != null)
          ? (json['eligibleAmount'] as num).toDouble()
          : ((json['eligible_amount']) as num?)?.toDouble(),
      status: _mapStatus(statusValue),
      requestDate: requestDate,
      createdAt: createdAt,
      reviewedAt: reviewedAt,
      reviewedBy: (json['reviewedBy'] ?? json['reviewed_by']) as String?,
      rejectionReason: (json['reviewNotes'] ?? json['rejection_reason']) as String?,
    );
  }
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
      eligibleAmount: (fields[9] as num?)?.toDouble(),
      requestDate: fields[10] != null ? DateTime.parse(fields[10] as String) : null,
      createdAt: DateTime.tryParse(fields[5] as String? ?? '') ?? DateTime.now(),
      reviewedAt: fields[6] != null ? DateTime.parse(fields[6] as String) : null,
      reviewedBy: fields[7] as String?,
      rejectionReason: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AdvanceRequest obj) {
    writer
      ..writeByte(11)
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
      ..write(obj.rejectionReason)
      ..writeByte(9)
      ..write(obj.eligibleAmount)
      ..writeByte(10)
      ..write(obj.requestDate?.toIso8601String());
  }
}

void registerAdvanceRequestAdapter() {
  if (!Hive.isAdapterRegistered(11)) {
    Hive.registerAdapter(AdvanceRequestAdapter());
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
