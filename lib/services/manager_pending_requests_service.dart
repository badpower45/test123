import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';

class ManagerPendingRequestsService {
  static Future<Map<String, dynamic>> getAllPendingRequests(String managerId) async {
    final supabaseUrl = SupabaseConfig.supabaseUrl;
    final session = SupabaseConfig.client.auth.currentSession;
    final token = session?.accessToken ?? '';
    final url = '$supabaseUrl/functions/v1/manager-pending-requests?manager_id=$managerId';
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'apikey': SupabaseConfig.supabaseAnonKey,
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('فشل تحميل الطلبات: ${response.statusCode}');
    }
  }
}
