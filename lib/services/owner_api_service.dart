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
}
