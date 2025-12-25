import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_endpoints.dart';
import '../models/attendance_report.dart';
import '../config/supabase_config.dart';
import 'supabase_function_client.dart';
import 'auth_service.dart';

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
    try {
      final response = await SupabaseFunctionClient.post('attendance-check-in', {
        'employee_id': employeeId,
        'latitude': latitude,
        'longitude': longitude,
        if (wifiBssid != null) 'wifi_bssid': wifiBssid,
      });
      return response ?? {};
    } on Exception catch (error) {
      throw Exception('تعذر تسجيل الحضور: $error');
    }
  }

  static Map<String, dynamic> _decodeBody(String rawBody) {
    if (rawBody.isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(rawBody) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> checkOut({
    required String employeeId,
    required double latitude,
    required double longitude,
    String? wifiBssid,
  }) async {
    try {
      final response = await SupabaseFunctionClient.post('attendance-check-out', {
        'employee_id': employeeId,
        'latitude': latitude,
        'longitude': longitude,
        if (wifiBssid != null) 'wifi_bssid': wifiBssid,
      });
      return response ?? {};
    } on Exception catch (error) {
      throw Exception('تعذر تسجيل الانصراف: $error');
    }
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

  static Future<void> forceCheckOut() async {
    try {
      // Get employee ID from saved login data
      final loginData = await AuthService.getLoginData();
      final employeeId = loginData['employeeId'];
      
      if (employeeId == null) {
        print('⚠️ [Force Checkout] No employee ID found');
        return;
      }
      
      // Try using Supabase directly first
      try {
        final supabase = SupabaseConfig.client;
        
        // Find active attendance (any active attendance, not just today)
        final activeAttendance = await supabase
            .from('attendance')
            .select('id, check_in_time, employee_id')
            .eq('employee_id', employeeId)
            .eq('status', 'active')
            .order('check_in_time', ascending: false)
            .limit(1)
            .maybeSingle();
        
        if (activeAttendance != null) {
          DateTime checkInTime;
          try {
            checkInTime = DateTime.parse(activeAttendance['check_in_time'].toString());
          } catch (e) {
            checkInTime = DateTime.now().toUtc().subtract(const Duration(hours: 8));
          }
          final checkOutTime = DateTime.now().toUtc();
          final totalHours = checkOutTime.difference(checkInTime).inMinutes / 60.0;
          
          // Update attendance to completed
          await supabase
              .from('attendance')
              .update({
                'check_out_time': checkOutTime.toIso8601String(),
                'status': 'completed',
                // Schema uses total_hours, not work_hours
                'total_hours': totalHours,
              })
              .eq('id', activeAttendance['id']);
          
          print('✅ [Force Checkout] Successfully checked out via Supabase');
          return;
        } else {
          print('ℹ️ [Force Checkout] No active attendance found');
          return;
        }
      } catch (supabaseError) {
        print('⚠️ [Force Checkout] Supabase method failed: $supabaseError');
        // Fallback to API endpoint
      }
      
      // Fallback to API endpoint
      final url = Uri.parse('$apiBaseUrl/shifts/auto-checkout');
      final response = await http.post(
        url,
        headers: _jsonHeaders,
        body: jsonEncode({'employee_id': employeeId, 'reason': 'Logout forced checkout'}),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('✅ [Force Checkout] Success via API endpoint');
      } else {
        print('⚠️ [Force Checkout] API endpoint failed: ${response.statusCode} - ${response.body}');
        // Don't throw error, just log it
      }
    } catch (e) {
      print('❌ [Force Checkout] Error: $e');
      // Don't throw error, allow logout to continue
    }
  }

  static String _formatDate(DateTime value) => value.toIso8601String().split('T').first;
}
