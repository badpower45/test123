import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_endpoints.dart';

class AttendanceStatsService {
  static Future<Map<String, dynamic>> getStats(
    String employeeId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final uri = Uri.parse('$apiBaseUrl/attendance/stats/$employeeId')
          .replace(queryParameters: {
        'startDate': startDate.toIso8601String().split('T')[0],
        'endDate': endDate.toIso8601String().split('T')[0],
      });

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['stats'] as Map<String, dynamic>;
      } else {
        throw Exception('Failed to get stats: ${response.statusCode}');
      }
    } catch (e) {
      print('Get attendance stats error: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getMonthlyStats(String employeeId) async {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final lastDay = DateTime(now.year, now.month + 1, 0);
    return getStats(employeeId, firstDay, lastDay);
  }
}
