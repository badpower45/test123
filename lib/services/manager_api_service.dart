import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_endpoints.dart';
import '../models/absence_notification_details.dart';

class ManagerApiService {
  static Future<List<AbsenceNotificationDetails>> getAbsenceNotifications(String managerId) async {
    final url = '$apiBaseUrl/api/manager/absence-notifications?manager_id=$managerId';
    print('🔍 Fetching absence notifications from: $url');

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['notifications'] is List) {
        return (data['notifications'] as List)
            .map((item) => AbsenceNotificationDetails.fromJson(item))
            .toList();
      } else {
        throw Exception('Invalid response format');
      }
    } else {
      print('❌ Response body: ${response.body}');
      throw Exception('فشل تحميل إشعارات الغياب: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> applyAbsenceDeduction({
    required String notificationId,
    required String managerId,
    required double deductionAmount,
    String? reason,
  }) async {
    final url = '$apiBaseUrl/api/manager/absence-notifications/$notificationId/apply-deduction';
    print('💰 Applying deduction for notification: $notificationId');

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'managerId': managerId,
        'deductionAmount': deductionAmount.toString(),
        'reason': reason ?? 'خصم غياب',
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorBody = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      throw Exception(errorBody['error'] ?? 'فشل تطبيق الخصم: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> excuseAbsence({
    required String notificationId,
    required String managerId,
    String? reason,
  }) async {
    final url = '$apiBaseUrl/api/manager/absence-notifications/$notificationId/excuse';
    print('✅ Excusing absence for notification: $notificationId');

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'managerId': managerId,
        'reason': reason ?? 'عذر مقبول',
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorBody = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      throw Exception(errorBody['error'] ?? 'فشل قبول العذر: ${response.statusCode}');
    }
  }

  // دالة لمراجعة (قبول/رفض) طلبات الإجازة
  static Future<Map<String, dynamic>> reviewLeaveRequest({
    required String requestId,
    required String managerId,
    required bool approve,
    String? notes,
  }) async {
    final url = '$apiBaseUrl/api/leave/requests/$requestId/review';
    print('📝 Reviewing leave request: $requestId, approve: $approve');

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': approve ? 'approve' : 'reject',
        'reviewer_id': managerId,
        if (notes != null) 'notes': notes,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorBody = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      throw Exception(errorBody['error'] ?? 'فشل مراجعة طلب الإجازة: ${response.statusCode}');
    }
  }

  // دالة لمراجعة (قبول/رفض) طلبات السلف
  static Future<Map<String, dynamic>> reviewAdvanceRequest({
    required String advanceId,
    required String managerId,
    required bool approve,
    String? notes,
  }) async {
    final url = '$apiBaseUrl/api/advances/$advanceId/review';
    print('💰 Reviewing advance request: $advanceId, approve: $approve');

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': approve ? 'approve' : 'reject',
        'reviewer_id': managerId,
        if (notes != null) 'notes': notes,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorBody = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      throw Exception(errorBody['error'] ?? 'فشل مراجعة طلب السلفة: ${response.statusCode}');
    }
  }

  // دالة لمراجعة (قبول/رفض) طلبات الحضور
  static Future<Map<String, dynamic>> reviewAttendanceRequest({
    required String requestId,
    required String managerId,
    required bool approve,
    String? notes,
  }) async {
    final url = '$apiBaseUrl/api/attendance/requests/$requestId/review';
    print('⏰ Reviewing attendance request: $requestId, approve: $approve');

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': approve ? 'approve' : 'reject',
        'reviewer_id': managerId,
        if (notes != null) 'notes': notes,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorBody = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      throw Exception(errorBody['error'] ?? 'فشل مراجعة طلب الحضور: ${response.statusCode}');
    }
  }
}