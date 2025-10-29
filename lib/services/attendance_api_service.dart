import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_endpoints.dart';
import '../models/attendance_report.dart';

class AttendanceApiService {
  static Future<Map<String, dynamic>> fetchEmployeeStatus(String employeeId) async {
    final uri = Uri.parse('$apiBaseUrl/employees/$employeeId/status');
    final response = await http.get(uri, headers: _jsonHeaders);
    final body = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }
    throw Exception(body['error'] ?? 'تعذر تحميل حالة الموظف (${response.statusCode})');
  }
  AttendanceApiService._();

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };

  static Future<Map<String, dynamic>> checkIn({
    required String employeeId,
    required double latitude,
    required double longitude,
    String? wifiBssid,
  }) async {
    late http.Response response;
    late Map<String, dynamic> body;

    try {
      response = await http.post(
        Uri.parse(checkInEndpoint),
        headers: _jsonHeaders,
        body: jsonEncode({
          'employee_id': employeeId,
          'latitude': latitude,
          'longitude': longitude,
          if (wifiBssid != null) 'wifi_bssid': wifiBssid,
        }),
      );
      body = _decodeBody(response.body);
    } on FormatException {
      throw Exception('استجابة غير متوقعة من الخادم عند تسجيل الحضور');
    } on Exception catch (error) {
      throw Exception('تعذر الاتصال بالخادم لتسجيل الحضور: $error');
    } catch (error) {
      throw Exception('حدث خطأ غير متوقع أثناء تسجيل الحضور: $error');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }
    throw Exception(body['error'] ?? 'تعذر تسجيل الحضور (${response.statusCode})');
  }

  static Future<Map<String, dynamic>> checkOut({
    required String employeeId,
    required double latitude,
    required double longitude,
    // Note: wifiBssid is no longer required for check-out
  }) async {
    late http.Response response;
    late Map<String, dynamic> body;

    try {
      response = await http.post(
        Uri.parse(checkOutEndpoint),
        headers: _jsonHeaders,
        body: jsonEncode({
          'employee_id': employeeId,
          'latitude': latitude,
          'longitude': longitude,
          // No wifi_bssid parameter - it's optional now
        }),
      );
      body = _decodeBody(response.body);
    } on FormatException {
      throw Exception('استجابة غير متوقعة من الخادم عند تسجيل الانصراف');
    } on Exception catch (error) {
      throw Exception('تعذر الاتصال بالخادم لتسجيل الانصراف: $error');
    } catch (error) {
      throw Exception('حدث خطأ غير متوقع أثناء تسجيل الانصراف: $error');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }
    throw Exception(body['error'] ?? 'تعذر تسجيل الانصراف (${response.statusCode})');
  }

  static Future<AttendanceReport> fetchAttendanceReport({
    required String employeeId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final uri = Uri.parse('$attendanceReportEndpoint/$employeeId').replace(
      queryParameters: {
        'start_date': _formatDate(startDate),
        'end_date': _formatDate(endDate),
      },
    );

    final response = await http.get(uri);
    final body = _decodeBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return AttendanceReport.fromJson(body);
    }

    throw Exception(body['error'] ?? 'تعذر تحميل تقرير الحضور (${response.statusCode})');
  }

  static Map<String, dynamic> _decodeBody(String rawBody) {
    if (rawBody.isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(rawBody) as Map<String, dynamic>;
  }

  static Future<void> forceCheckOut() async {
    final url = Uri.parse('$apiBaseUrl/attendance/force-checkout');
    final response = await http.post(
      url,
      headers: _jsonHeaders,
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      print('Force checkout successful.');
    } else {
      print('Failed to force checkout: ${response.body}');
      throw Exception('Failed to force checkout: ${response.body}');
    }
  }

  static String _formatDate(DateTime value) => value.toIso8601String().split('T').first;
}
