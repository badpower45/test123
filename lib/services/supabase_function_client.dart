import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';

class SupabaseFunctionClient {
  const SupabaseFunctionClient._();

  static Uri _uri(String functionName) {
    return Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/$functionName');
  }

  static Future<Map<String, String>> _headers() async {
    // Try to use session token if available, otherwise use anon key
    final session = SupabaseConfig.client.auth.currentSession;
    final token = session?.accessToken ?? SupabaseConfig.supabaseAnonKey;
    
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// ✅ Enhanced post method with better timeout and error handling
  static Future<Map<String, dynamic>?> post(
    String functionName,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 10), // ✅ Shorter default timeout
    bool throwOnError = true, // ✅ Allow silent failures
  }) async {
    try {
      print('📤 [SupabaseFunctionClient] Calling $functionName with payload: $payload');
      
      final headers = await _headers();
      final response = await http.post(
        _uri(functionName),
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(
        timeout,
        onTimeout: () {
          print('⏱️ [SupabaseFunctionClient] Timeout after ${timeout.inSeconds}s for $functionName');
          if (!throwOnError) {
            return http.Response('{"error":"timeout"}', 408);
          }
          throw Exception('Timeout: Request took too long');
        },
      );

      print('📥 [SupabaseFunctionClient] Response status: ${response.statusCode}');
      print('📥 [SupabaseFunctionClient] Response body: ${response.body}');

      final responseBody = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (responseBody is Map<String, dynamic>) {
          // ✅ Return response even if success is false - let caller handle it
          // This allows checking for 'attendance' field or 'alreadyCheckedOut' flag
          if (responseBody['success'] == true || responseBody['attendance'] != null || responseBody['alreadyCheckedOut'] == true) {
            print('✅ [SupabaseFunctionClient] Success: $functionName');
            return responseBody;
          }
          final errorMsg = responseBody['error'] ?? responseBody['message'] ?? 'فشل تنفيذ العملية';
          print('❌ [SupabaseFunctionClient] Error in response: $errorMsg');
          if (!throwOnError) return null;
          throw Exception(errorMsg);
        }
        return {'success': true, 'data': responseBody};
      }

      // ✅ Handle 409 Conflict (already checked in)
      if (response.statusCode == 409 && responseBody is Map<String, dynamic>) {
        final errorMsg = responseBody['error'] ?? responseBody['message'] ?? 'تعارض في البيانات';
        final fullMessage = responseBody['message'] != null 
            ? '${responseBody['error'] ?? ''}\n${responseBody['message']}'
            : errorMsg;
        print('⚠️ [SupabaseFunctionClient] Conflict (409): $fullMessage');
        if (!throwOnError) return null;
        throw Exception(fullMessage);
      }

      final errorMsg = responseBody is Map<String, dynamic>
          ? responseBody['message'] ?? responseBody['error'] ?? 'فشل تنفيذ العملية: ${response.statusCode}'
          : 'فشل تنفيذ العملية: ${response.statusCode}';
      print('❌ [SupabaseFunctionClient] HTTP Error: $errorMsg');
      if (!throwOnError) return null;
      throw Exception(errorMsg);
    } on http.ClientException catch (e) {
      // ✅ Handle network errors (DNS, connection, etc.)
      print('❌ [SupabaseFunctionClient] Network error: $e');
      if (!throwOnError) return null;
      rethrow;
    } catch (e) {
      print('❌ [SupabaseFunctionClient] Exception: $e');
      if (!throwOnError) return null;
      rethrow;
    }
  }
}
