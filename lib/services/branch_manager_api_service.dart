import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_endpoints.dart';

class BranchManagerApiService {
  static Future<Map<String, dynamic>> getBranchRequests(String branchName) async {
    final encodedBranch = Uri.encodeComponent(branchName);
    final url = '$apiBaseUrl/branch/$encodedBranch/requests';
    print('🔍 Fetching requests from: $url'); // Debug log
    final response = await http.get(Uri.parse(url));
    print('📥 Response status: ${response.statusCode}'); // Debug log
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print('❌ Response body: ${response.body}'); // Debug log
      throw Exception('فشل تحميل الطلبات: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> getAttendanceReport(String branchName) async {
    final encodedBranch = Uri.encodeComponent(branchName);
    final url = '$apiBaseUrl/branch/$encodedBranch/attendance-report';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('فشل تحميل تقرير الحضور: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> actOnRequest({
    required String type,
    required String id,
    required String action,
  }) async {
    final url = '$apiBaseUrl/branch/request/$type/$id/$action';
    final response = await http.post(Uri.parse(url));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('فشل تنفيذ العملية: ${response.statusCode}');
    }
  }

  // Review break request (approve/reject/postpone)
  static Future<Map<String, dynamic>> reviewBreakRequest({
    required String breakId,
    required String action, // approve, reject, or postpone
    required String managerId,
  }) async {
    if (breakId.isEmpty || managerId.isEmpty) {
      throw Exception('معرف طلب الاستراحة أو معرف المدير مطلوب');
    }

    final url = '$apiBaseUrl/breaks/$breakId/review';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': action,
        'manager_id': managerId,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorBody = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      throw Exception(errorBody['error'] ?? 'فشل مراجعة طلب الاستراحة: ${response.statusCode}');
    }
  }

  // Review attendance request (approve/reject)
  static Future<Map<String, dynamic>> reviewAttendanceRequest({
    required String requestId,
    required String action, // approve or reject
    required String reviewerId,
    String? notes,
  }) async {
    if (requestId.isEmpty || reviewerId.isEmpty) {
      throw Exception('معرف طلب الحضور أو معرف المراجع مطلوب');
    }

    final url = '$apiBaseUrl/attendance/requests/$requestId/review';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': action,
        'reviewer_id': reviewerId,
        'notes': notes ?? '',
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorBody = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      throw Exception(errorBody['error'] ?? 'فشل مراجعة طلب الحضور: ${response.statusCode}');
    }
  }

  // Get manager dashboard with all pending requests
  static Future<Map<String, dynamic>> getManagerDashboard() async {
    final url = managerDashboardEndpoint;
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('فشل تحميل لوحة المدير: ${response.statusCode}');
    }
  }
}
