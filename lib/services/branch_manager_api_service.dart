import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';
import '../constants/api_endpoints.dart';
import 'supabase_function_client.dart';

Uri _supabaseFunctionUri(String functionName, [Map<String, String>? queryParameters]) {
  final base = Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/$functionName');
  return queryParameters == null ? base : base.replace(queryParameters: queryParameters);
}

Future<Map<String, String>> _supabaseHeaders() async {
  final session = SupabaseConfig.client.auth.currentSession;
  final token = session?.accessToken ?? SupabaseConfig.supabaseAnonKey;
  
  return {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };
}

class BranchManagerApiService {
  static Future<Map<String, dynamic>> getBranchRequests(String branchName, {String? managerId}) async {
    final queryParams = {'branch': branchName};
    if (managerId != null && managerId.isNotEmpty) {
      queryParams['manager_id'] = managerId;
    }
    
    final response = await http.get(
      _supabaseFunctionUri('branch-requests', queryParams),
      headers: await _supabaseHeaders(),
    );
    print('📥 Branch requests status: ${response.statusCode}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print('❌ Response body: ${response.body}'); // Debug log
      throw Exception('فشل تحميل الطلبات: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> getAttendanceReport(String branchName) async {
    final response = await http.get(
      _supabaseFunctionUri('branch-attendance-report', {'branch': branchName}),
      headers: await _supabaseHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('فشل تحميل تقرير الحضور: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> getBranchPulseSummary(
    String branchName, {
    DateTime? start,
    DateTime? end,
  }) async {
    final queryParams = <String, String>{'branch': branchName};
    if (start != null) {
      queryParams['start'] = start.toIso8601String();
    }
    if (end != null) {
      queryParams['end'] = end.toIso8601String();
    }

    final response = await http.get(
      _supabaseFunctionUri('branch-pulse-summary', queryParams),
      headers: await _supabaseHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      throw Exception(body['error'] ?? 'فشل تحميل إحصائيات النبضات: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> actOnRequest({
    required String type,
    required String id,
    required String action,
    String? managerId,
    String? reviewerId,
  }) async {
    final payload = <String, dynamic>{
      'type': type,
      'id': id,
      'action': action,
      'reviewerId': reviewerId ?? managerId,
    };

    if (managerId != null) {
      payload['managerId'] = managerId;
    }
    if (reviewerId != null) {
      payload['reviewerId'] = reviewerId;
    }

  final result = await SupabaseFunctionClient.post('branch-request-action', payload);

    return (result ?? {})['data'] is Map<String, dynamic>
        ? Map<String, dynamic>.from((result ?? {})['data'] as Map)
        : result ?? {};
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

    final result = await SupabaseFunctionClient.post('branch-request-action', {
      'type': 'break',
      'id': breakId,
      'action': action,
      'managerId': managerId,
    });

    return (result ?? {})['data'] is Map<String, dynamic>
        ? Map<String, dynamic>.from((result ?? {})['data'] as Map)
        : result ?? {};
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

    final result = await SupabaseFunctionClient.post('branch-request-action', {
      'type': 'attendance',
      'id': requestId,
      'action': action,
      'reviewerId': reviewerId,
      if (notes != null) 'notes': notes,
    });

    return (result ?? {})['data'] is Map<String, dynamic>
        ? Map<String, dynamic>.from((result ?? {})['data'] as Map)
        : result ?? {};
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
