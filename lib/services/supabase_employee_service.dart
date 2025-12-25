import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/employee.dart';

class SupabaseEmployeeService {
  SupabaseEmployeeService._();

  static final _supabase = SupabaseConfig.client;
  static final _random = Random();

  /// Create a new employee record tied to a specific branch.
  static Future<Map<String, dynamic>> createEmployee({
    required String fullName,
    required String pin,
    required String branchId,
    required String branchName,
    double hourlyRate = 0,
    EmployeeRole role = EmployeeRole.staff,
    String? email,
    String? phone,
    String? shiftStartTime,
    String? shiftEndTime,
    String? address,
  }) async {
    final employeeId = _generateEmployeeId(fullName);

    final rawPayload = <String, dynamic>{
      'id': employeeId,
      'full_name': fullName,
      'pin': pin,
      'role': role.name,
      'branch': branchName,
      'branch_id': branchId,
      'hourly_rate': hourlyRate,
      'email': email,
      'phone': phone,
      'shift_start_time': shiftStartTime,
      'shift_end_time': shiftEndTime,
      'address': address,
      'is_active': true,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final payload = Map<String, dynamic>.from(rawPayload)
      ..removeWhere((key, value) => value == null);

    try {
      final response = await _supabase
          .from('employees')
          .insert(payload)
          .select()
          .single();

      return Map<String, dynamic>.from(response as Map);
    } on PostgrestException catch (error) {
      print('❌ Postgrest error while creating employee: ${error.message}');
      rethrow;
    } catch (e) {
      print('❌ Failed to create employee: $e');
      rethrow;
    }
  }

  static String _generateEmployeeId(String fullName) {
    final sanitized = fullName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .toLowerCase();

    final prefix = sanitized.isEmpty
        ? 'emp'
        : sanitized.substring(0, sanitized.length.clamp(0, 12));

    final randomSuffix = _random.nextInt(99999).toString().padLeft(5, '0');
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);

    return '${prefix}_$timestamp$randomSuffix';
  }
}

