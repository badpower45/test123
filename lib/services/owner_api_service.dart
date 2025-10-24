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
    final uri = Uri.parse(OWNER_DASHBOARD_ENDPOINT).replace(
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
    final uri = Uri.parse(OWNER_EMPLOYEES_OVERVIEW_ENDPOINT).replace(
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
    final endpoint = OWNER_EMPLOYEE_HOURLY_RATE_ENDPOINT.replaceFirst(
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
    required String branch,
    required double hourlyRate,
  }) async {
    final uri = Uri.parse(EMPLOYEES_ENDPOINT);
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'employeeId': employeeId,
        'fullName': fullName,
        'pin': pin,
        'branch': branch,
        'hourlyRate': hourlyRate.toString(),
        'role': 'staff',
        'active': 'true',
      },
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('فشل إضافة الموظف: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> getPayrollSummary({
    required String ownerId,
    required String startDate,
    required String endDate,
  }) async {
    final uri = Uri.parse(OWNER_PAYROLL_SUMMARY_ENDPOINT).replace(
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
