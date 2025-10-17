import 'package:hive_flutter/hive_flutter.dart';

import '../models/employee.dart';

class EmployeeRepository {
  EmployeeRepository._();

  static Future<Box<Employee>> _box() async {
    registerEmployeeAdapter();
    if (Hive.isBoxOpen(employeesBox)) {
      return Hive.box<Employee>(employeesBox);
    }
    return Hive.openBox<Employee>(employeesBox);
  }

  static Future<List<Employee>> all() async {
    final box = await _box();
    final list = box.values.toList(growable: false);
    list.sort((a, b) => a.fullName.compareTo(b.fullName));
    return list;
  }

  static Future<Employee?> findById(String id) async {
    final box = await _box();
    return box.get(id);
  }

  static Future<void> upsert(Employee employee) async {
    final box = await _box();
    employee.touch();
    await box.put(employee.id, employee);
  }

  /// Alias for upsert - adds or updates employee
  static Future<void> addEmployee(Employee employee) async {
    await upsert(employee);
  }

  /// Clear all locally cached employees (useful to avoid demo data conflicts)
  static Future<void> clearAll() async {
    final box = await _box();
    await box.clear();
  }

  static Future<void> delete(String id) async {
    final box = await _box();
    await box.delete(id);
  }

  static Future<void> toggleActive(String id) async {
    final box = await _box();
    final employee = box.get(id);
    if (employee == null) {
      return;
    }
    employee.isActive = !employee.isActive;
    employee.touch();
    await box.put(employee.id, employee);
  }

  static Future<void> updatePin({required String id, required String pin}) async {
    final box = await _box();
    final employee = box.get(id);
    if (employee == null) {
      return;
    }
    employee.pin = pin;
    employee.touch();
    await box.put(employee.id, employee);
  }
}
