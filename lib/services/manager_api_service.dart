import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_endpoints.dart';
import '../models/absence_notification_details.dart';
import 'supabase_function_client.dart';

class ManagerApiService {
  static Future<List<AbsenceNotificationDetails>> getAbsenceNotifications(String managerId) async {
    final url = '$apiBaseUrl/manager/absence-notifications?manager_id=$managerId';
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
    final url = '$apiBaseUrl/manager/absence-notifications/$notificationId/apply-deduction';
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
    final url = '$apiBaseUrl/manager/absence-notifications/$notificationId/excuse';
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

  /// NEW: Review absence notification (approve or reject with automatic deduction)
  static Future<Map<String, dynamic>> reviewAbsenceNotification({
    required String notificationId,
    required String managerId,
    required String action, // 'approve' or 'reject'
    String? notes,
  }) async {
    final result = await SupabaseFunctionClient.post('branch-request-action', {
      'type': 'absence',
      'id': notificationId,
      'action': action,
      'reviewerId': managerId,
      if (notes != null) 'notes': notes,
    });

    return (result ?? {})['data'] is Map<String, dynamic>
        ? Map<String, dynamic>.from((result ?? {})['data'] as Map)
        : result ?? {};
  }

  /// دالة لمراجعة (قبول/رفض) طلبات الاستراحة
  static Future<Map<String, dynamic>> reviewLeaveRequest({
    required String requestId,
    required String managerId,
    required bool approve,
    String? notes,
  }) async {
    if (requestId.isEmpty || managerId.isEmpty) {
      throw Exception('معرف طلب الإجازة أو معرف المدير مطلوب');
    }

    final result = await SupabaseFunctionClient.post('branch-request-action', {
      'type': 'leave',
      'id': requestId,
      'action': approve ? 'approve' : 'reject',
      'reviewerId': managerId,
      if (notes != null) 'notes': notes,
    });

    return (result ?? {})['data'] is Map<String, dynamic>
        ? Map<String, dynamic>.from((result ?? {})['data'] as Map)
        : result ?? {};
  }

  // دالة لمراجعة (قبول/رفض) طلبات السلف
  static Future<Map<String, dynamic>> reviewAdvanceRequest({
    required String advanceId,
    required String managerId,
    required bool approve,
    String? notes,
  }) async {
    if (advanceId.isEmpty || managerId.isEmpty) {
      throw Exception('معرف طلب السلفة أو معرف المدير مطلوب');
    }

    final result = await SupabaseFunctionClient.post('branch-request-action', {
      'type': 'advance',
      'id': advanceId,
      'action': approve ? 'approve' : 'reject',
      'reviewerId': managerId,
      if (notes != null) 'notes': notes,
    });

    return (result ?? {})['data'] is Map<String, dynamic>
        ? Map<String, dynamic>.from((result ?? {})['data'] as Map)
        : result ?? {};
  }

  // دالة لمراجعة (قبول/رفض) طلبات الحضور
  static Future<Map<String, dynamic>> reviewAttendanceRequest({
    required String requestId,
    required String managerId,
    required bool approve,
    String? notes,
  }) async {
    if (requestId.isEmpty || managerId.isEmpty) {
      throw Exception('معرف طلب الحضور أو معرف المدير مطلوب');
    }

    final result = await SupabaseFunctionClient.post('branch-request-action', {
      'type': 'attendance',
      'id': requestId,
      'action': approve ? 'approve' : 'reject',
      'reviewerId': managerId,
      if (notes != null) 'notes': notes,
    });

    return (result ?? {})['data'] is Map<String, dynamic>
        ? Map<String, dynamic>.from((result ?? {})['data'] as Map)
        : result ?? {};
  }
}