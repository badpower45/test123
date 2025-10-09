import 'package:hive/hive.dart';

const String employeeAdjustmentsBox = 'employee_adjustments';

enum AdjustmentType { deduction, bonus, note }

class EmployeeAdjustment extends HiveObject {
  EmployeeAdjustment({
    required this.id,
    required this.employeeId,
    required this.type,
    required this.reason,
    required this.recordedBy,
    this.amount,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  String id;
  String employeeId;
  AdjustmentType type;
  String reason;
  String recordedBy;
  double? amount;
  DateTime createdAt;
}

class EmployeeAdjustmentAdapter extends TypeAdapter<EmployeeAdjustment> {
  @override
  final int typeId = 4;

  @override
  EmployeeAdjustment read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    final typeIndex = fields[2] as int? ?? 0;
    return EmployeeAdjustment(
      id: fields[0] as String,
      employeeId: fields[1] as String,
      type: AdjustmentType.values[_safeEnumIndex(typeIndex, AdjustmentType.values)],
      reason: fields[3] as String? ?? '',
      recordedBy: fields[4] as String? ?? '',
      amount: (fields[5] as num?)?.toDouble(),
      createdAt: DateTime.tryParse(fields[6] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  @override
  void write(BinaryWriter writer, EmployeeAdjustment obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.employeeId)
      ..writeByte(2)
      ..write(obj.type.index)
      ..writeByte(3)
      ..write(obj.reason)
      ..writeByte(4)
      ..write(obj.recordedBy)
      ..writeByte(5)
      ..write(obj.amount)
      ..writeByte(6)
      ..write(obj.createdAt.toUtc().toIso8601String());
  }
}

int _safeEnumIndex<T>(int index, List<T> values) {
  if (index < 0 || index >= values.length) {
    return 0;
  }
  return index;
}

void registerAdjustmentAdapter() {
  if (!Hive.isAdapterRegistered(4)) {
    Hive.registerAdapter(EmployeeAdjustmentAdapter());
  }
}
