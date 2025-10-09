import 'dart:math';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/employee_adjustment.dart';

class EmployeeAdjustmentRepository {
  EmployeeAdjustmentRepository._();

  static final Random _random = Random();

  static Future<Box<EmployeeAdjustment>> _box() async {
    registerAdjustmentAdapter();
    if (Hive.isBoxOpen(employeeAdjustmentsBox)) {
      return Hive.box<EmployeeAdjustment>(employeeAdjustmentsBox);
    }
    return Hive.openBox<EmployeeAdjustment>(employeeAdjustmentsBox);
  }

  static Future<List<EmployeeAdjustment>> forEmployee(String employeeId) async {
    final box = await _box();
    final items = box
        .values
        .where((adjustment) => adjustment.employeeId == employeeId)
        .toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  static Future<List<EmployeeAdjustment>> recent({int limit = 20}) async {
    final box = await _box();
    final items = box.values.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (items.length <= limit) {
      return items;
    }
    return items.sublist(0, limit);
  }

  static Future<EmployeeAdjustment> create({
    required String employeeId,
    required AdjustmentType type,
    required String reason,
    required String recordedBy,
    double? amount,
  }) async {
    final box = await _box();
    final adjustment = EmployeeAdjustment(
      id: _generateId(),
      employeeId: employeeId,
      type: type,
      reason: reason,
      recordedBy: recordedBy,
      amount: amount,
    );
    await box.put(adjustment.id, adjustment);
    return adjustment;
  }

  static Future<void> remove(String id) async {
    final box = await _box();
    await box.delete(id);
  }

  static String _generateId() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 24);
    return '${timestamp.toRadixString(16)}-${salt.toRadixString(16)}';
  }
}
