import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_endpoints.dart';

class BranchManagerApiService {
  static Future<Map<String, dynamic>> getBranchRequests(String branchName) async {
    final encodedBranch = Uri.encodeComponent(branchName);
    final url = '$API_BASE_URL/branch/$encodedBranch/requests';
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
    final url = '$API_BASE_URL/branch/$encodedBranch/attendance-report';
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
    final url = '$API_BASE_URL/branch/request/$type/$id/$action';
    final response = await http.post(Uri.parse(url));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('فشل تنفيذ العملية: ${response.statusCode}');
    }
  }
}
