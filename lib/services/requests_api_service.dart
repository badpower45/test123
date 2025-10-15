import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_endpoints.dart';
import '../models/advance_request.dart';
import '../models/attendance_request.dart';
import '../models/break.dart';
import '../models/leave_request.dart';

class RequestsApiService {
  RequestsApiService._();

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };

  static Future<LeaveRequest> submitLeaveRequest({
    required String employeeId,
    required DateTime startDate,
    required DateTime endDate,
    String? reason,
  }) async {
    final response = await http.post(
      Uri.parse(LEAVE_REQUEST_ENDPOINT),
      headers: _jsonHeaders,
      body: jsonEncode({
        'employee_id': employeeId,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      }),
    );

    final body = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final payload = body['leaveRequest'] ?? body['request'] ?? body;
      return LeaveRequest.fromJson(Map<String, dynamic>.from(payload as Map));
    }
    throw Exception(body['error'] ?? 'تعذر إرسال طلب الإجازة (${response.statusCode})');
  }

  static Future<List<LeaveRequest>> fetchLeaveRequests(String employeeId) async {
    final uri = Uri.parse(LEAVE_REQUESTS_ENDPOINT).replace(
      queryParameters: {'employee_id': employeeId},
    );
    final response = await http.get(uri);
    final body = _decodeBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = body['requests'] ?? body;
      return (list as List)
          .map((item) => LeaveRequest.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    }
    throw Exception(body['error'] ?? 'تعذر تحميل طلبات الإجازة (${response.statusCode})');
  }

  static Future<AdvanceRequest> submitAdvanceRequest({
    required String employeeId,
    required double amount,
  }) async {
    final response = await http.post(
      Uri.parse(ADVANCE_REQUEST_ENDPOINT),
      headers: _jsonHeaders,
      body: jsonEncode({
        'employee_id': employeeId,
        'amount': amount,
      }),
    );

    final body = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final payload = body['advance'] ?? body['request'] ?? body;
      return AdvanceRequest.fromJson(Map<String, dynamic>.from(payload as Map));
    }
    throw Exception(body['error'] ?? 'تعذر إرسال طلب السلفة (${response.statusCode})');
  }

  static Future<List<AdvanceRequest>> fetchAdvanceRequests(String employeeId) async {
    final uri = Uri.parse(ADVANCES_ENDPOINT).replace(
      queryParameters: {'employee_id': employeeId},
    );
    final response = await http.get(uri);
    final body = _decodeBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = body['advances'] ?? body;
      return (list as List)
          .map((item) => AdvanceRequest.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    }
    throw Exception(body['error'] ?? 'تعذر تحميل طلبات السلفة (${response.statusCode})');
  }

  static Future<Map<String, dynamic>> fetchCurrentEarnings(String employeeId) async {
    final endpoint =
        EMPLOYEE_CURRENT_EARNINGS_ENDPOINT.replaceFirst(':employeeId', employeeId);
    final response = await http.get(Uri.parse(endpoint));
    final body = _decodeBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final totalRaw = body['totalEarnings'] ?? body['total_earnings'];
      final eligibleRaw = body['eligibleAdvance'] ?? body['eligible_advance'];
      final result = {
        'totalEarnings': totalRaw is num ? totalRaw.toDouble() : totalRaw,
        'eligibleAdvance': eligibleRaw is num ? eligibleRaw.toDouble() : eligibleRaw,
      }..removeWhere((_, value) => value == null);

      if (result.isNotEmpty) {
        return result;
      }
      return Map<String, dynamic>.from(body);
    }
    throw Exception(body['error'] ?? 'تعذر تحميل بيانات المستحقات (${response.statusCode})');
  }

  static Future<void> submitBreakRequest({
    required String employeeId,
    required int durationMinutes,
  }) async {
    final response = await http.post(
      Uri.parse(BREAK_REQUEST_ENDPOINT),
      headers: _jsonHeaders,
      body: jsonEncode({
        'employee_id': employeeId,
        'duration_minutes': durationMinutes,
      }),
    );

    final body = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw Exception(body['error'] ?? 'تعذر إرسال طلب الاستراحة (${response.statusCode})');
  }

  static Future<void> startBreak({required String breakId}) async {
    final endpoint = BREAK_START_ENDPOINT.replaceFirst(':breakId', breakId);
    final response = await http.post(
      Uri.parse(endpoint),
      headers: _jsonHeaders,
      body: jsonEncode(const {}),
    );

    final body = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw Exception(body['error'] ?? 'تعذر بدء الاستراحة (${response.statusCode})');
  }

  static Future<void> endBreak({required String breakId}) async {
    final endpoint = BREAK_END_ENDPOINT.replaceFirst(':breakId', breakId);
    final response = await http.post(
      Uri.parse(endpoint),
      headers: _jsonHeaders,
      body: jsonEncode(const {}),
    );

    final body = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw Exception(body['error'] ?? 'تعذر إنهاء الاستراحة (${response.statusCode})');
  }

  static Future<List<Break>> fetchBreaks({required String employeeId}) async {
    final uri = Uri.parse(BREAKS_ENDPOINT).replace(
      queryParameters: {'employee_id': employeeId},
    );
    final response = await http.get(uri);
    final body = _decodeBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final rawList = body['breaks'] ?? body['data'] ?? body;
      if (rawList is List) {
        return rawList
            .map((item) => Break.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
      return <Break>[];
    }
    throw Exception(body['error'] ?? 'تعذر تحميل الاستراحات (${response.statusCode})');
  }

  static Future<AttendanceRequest> submitAttendanceRequest({
    required String employeeId,
    required DateTime requestedTime,
    required String reason,
    AttendanceRequestType requestType = AttendanceRequestType.checkIn,
  }) async {
    final endpoint = requestType == AttendanceRequestType.checkIn
        ? ATTENDANCE_REQUEST_CHECKIN_ENDPOINT
        : ATTENDANCE_REQUEST_CHECKOUT_ENDPOINT;

    final response = await http.post(
      Uri.parse(endpoint),
      headers: _jsonHeaders,
      body: jsonEncode({
        'employee_id': employeeId,
        'requested_time': requestedTime.toIso8601String(),
        'reason': reason,
      }),
    );

    final body = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final payload = body['request'] ?? body;
      return AttendanceRequest.fromJson(Map<String, dynamic>.from(payload as Map));
    }
    throw Exception(body['error'] ?? 'تعذر إرسال طلب الحضور (${response.statusCode})');
  }

  static Future<List<AttendanceRequest>> fetchAttendanceRequests(
      String employeeId) async {
    final uri = Uri.parse(ATTENDANCE_REQUESTS_ENDPOINT).replace(
      queryParameters: {'employee_id': employeeId},
    );
    final response = await http.get(uri);
    final body = _decodeBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = body['requests'] ?? body;
      return (list as List)
          .map((item) =>
              AttendanceRequest.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    }
    throw Exception(body['error'] ?? 'تعذر تحميل طلبات الحضور (${response.statusCode})');
  }

  static Map<String, dynamic> _decodeBody(String rawBody) {
    if (rawBody.isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(rawBody) as Map<String, dynamic>;
  }
}
