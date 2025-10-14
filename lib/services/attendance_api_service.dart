import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/attendance_report.dart';
import '../config/app_config.dart';

class AttendanceApiService {
  static const String _baseUrl = AppConfig.apiBaseUrl;

  static Future<Map<String, dynamic>> checkIn(String employeeId) async {
    final url = Uri.parse('$_baseUrl/api/shifts/check-in');
    
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'employee_id': employeeId,
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('فشل تسجيل الحضور: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> checkOut(String employeeId, String shiftId) async {
    final url = Uri.parse('$_baseUrl/api/shifts/check-out');
    
    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'employee_id': employeeId,
        'shift_id': shiftId,
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('فشل تسجيل الانصراف: ${response.body}');
    }
  }

  static Future<AttendanceReport> getReport({
    required String employeeId,
    required String period,
  }) async {
    final url = Uri.parse('$_baseUrl/api/me/report?employee_id=$employeeId&period=$period');
    
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return AttendanceReport.fromJson(data);
    } else {
      throw Exception('فشل تحميل التقرير');
    }
  }

  static Future<List<Map<String, dynamic>>> getRecentShifts({
    required String employeeId,
    int limit = 10,
  }) async {
    final url = Uri.parse('$_baseUrl/api/shifts/recent?employee_id=$employeeId&limit=$limit');
    
    final response = await http.get(url);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body) as List);
    } else {
      throw Exception('فشل تحميل الورديات الأخيرة');
    }
  }
}
