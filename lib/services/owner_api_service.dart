import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_endpoints.dart';

class OwnerApiService {
  OwnerApiService._();

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json; charset=utf-8',
  };

  static Future<Map<String, dynamic>> getDashboard({
    required String ownerId,
  }) async {
    final uri = Uri.parse(ownerDashboardEndpoint).replace(
      queryParameters: {'owner_id': ownerId},
    );
    final response = await http.get(uri, headers: _jsonHeaders);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('فشل تحميل لوحة المالك: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> getEmployees({
    required String ownerId,
  }) async {
    final uri = Uri.parse(ownerEmployeesOverviewEndpoint).replace(
      queryParameters: {'owner_id': ownerId},
    );
    final response = await http.get(uri, headers: _jsonHeaders);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('فشل تحميل قائمة الموظفين: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> updateHourlyRate({
    required String ownerId,
    required String employeeId,
    required double hourlyRate,
  }) async {
    final endpoint = ownerEmployeeHourlyRateEndpoint.replaceFirst(
      ':employeeId',
      employeeId,
    );
    final uri = Uri.parse(endpoint).replace(
      queryParameters: {'owner_id': ownerId},
    );
    final response = await http.put(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({'hourly_rate': hourlyRate}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('فشل تحديث سعر الساعة: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> createEmployee({
    required String ownerId,
    required String employeeId,
    required String fullName,
    required String pin,
    String? branchId,  // Changed to branchId (UUID)
    String? branch,    // Optional: branch name for backward compatibility
    required double hourlyRate,
    String? shiftStartTime,  // Format: "HH:mm"
    String? shiftEndTime,    // Format: "HH:mm"
    String? shiftType,       // "AM" or "PM"
  }) async {
    final uri = Uri.parse(employeesEndpoint);
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'id': employeeId,
        'ownerId': ownerId,
        'fullName': fullName,
        'pin': pin,
        'branchId': branchId,  // Send branchId (UUID)
        'branch': branch,      // Optional: send branch name
        'hourlyRate': hourlyRate,
        'role': 'staff',
        'active': true,
        'shiftStartTime': shiftStartTime,
        'shiftEndTime': shiftEndTime,
        'shiftType': shiftType,
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    if (response.statusCode == 409) {
      throw Exception('معرف الموظف مستخدم بالفعل');
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final message = data['error'] ?? 'خطأ غير معروف';
      throw Exception('فشل إضافة الموظف: $message');
    } catch (_) {
      throw Exception('فشل إضافة الموظف: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> getPayrollSummary({
    required String ownerId,
    required String startDate,
    required String endDate,
  }) async {
    final uri = Uri.parse(ownerPayrollSummaryEndpoint).replace(
      queryParameters: {
        'owner_id': ownerId,
        'start_date': startDate,
        'end_date': endDate,
      },
    );
    final response = await http.get(uri, headers: _jsonHeaders);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('فشل تحميل ملخص الرواتب: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> updateEmployee({
    required String employeeId,
    String? fullName,
    String? pin,
    String? role,
    String? branch,
    String? branchId,
    double? hourlyRate,
    bool? active,
  }) async {
    final endpoint = employeesEndpoint.endsWith('/')
        ? '${employeesEndpoint}$employeeId'
        : '$employeesEndpoint/$employeeId';
    final uri = Uri.parse(endpoint);

    final body = <String, dynamic>{};
    if (fullName != null) body['fullName'] = fullName;
    if (pin != null) body['pin'] = pin;
    if (role != null) body['role'] = role;
    if (branch != null) body['branch'] = branch;
    if (branchId != null) body['branchId'] = branchId;
    if (hourlyRate != null) body['hourlyRate'] = hourlyRate;
    if (active != null) body['active'] = active;

    final response = await http.put(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final message = data['error'] ?? 'خطأ غير معروف';
      throw Exception('فشل تحديث الموظف: $message');
    } catch (_) {
      throw Exception('فشل تحديث الموظف: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> deleteEmployee({
    required String employeeId,
  }) async {
    final endpoint = employeesEndpoint.endsWith('/')
        ? '${employeesEndpoint}$employeeId'
        : '$employeesEndpoint/$employeeId';
    final uri = Uri.parse(endpoint);

    final response = await http.delete(uri, headers: _jsonHeaders);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    if (response.statusCode == 404) {
      throw Exception('الموظف غير موجود');
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final message = data['error'] ?? 'خطأ غير معروف';
      throw Exception('فشل حذف الموظف: $message');
    } catch (_) {
      throw Exception('فشل حذف الموظف: ${response.statusCode}');
    }
  }
}
