import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_endpoints.dart';

class ApiNotificationService {
  static Future<Map<String, dynamic>> getNotifications(
    String employeeId, {
    bool unreadOnly = false,
  }) async {
    try {
      final uri = Uri.parse('$apiBaseUrl/notifications/$employeeId')
          .replace(queryParameters: {
        if (unreadOnly) 'unreadOnly': 'true',
      });

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get notifications: ${response.statusCode}');
      }
    } catch (e) {
      print('Get notifications error: $e');
      rethrow;
    }
  }

  static Future<void> markAsRead(String notificationId) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/notifications/$notificationId/read'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to mark notification as read: ${response.statusCode}');
      }
    } catch (e) {
      print('Mark notification read error: $e');
      rethrow;
    }
  }

  static Future<int> getUnreadCount(String employeeId) async {
    try {
      final result = await getNotifications(employeeId, unreadOnly: true);
      return (result['unreadCount'] as int?) ?? 0;
    } catch (e) {
      print('Get unread count error: $e');
      return 0;
    }
  }
}
