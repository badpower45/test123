import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_endpoints.dart';
import '../models/advance_request.dart';
import '../models/attendance_request.dart';
import '../models/break.dart';
import '../models/leave_request.dart';
import '../models/shift_status.dart';

class RequestsApiService {
  static Future<void> deleteRejectedBreaks(String employeeId) async {
    final uri = Uri.parse('$breaksEndpoint/delete-rejected');
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({'employee_id': employeeId}),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final body = _decodeBody(response.body);
    throw Exception(body['error'] ?? 'تعذر حذف الطلبات المرفوضة (${response.statusCode})');
  }

  static Future<void> deleteRejectedLeaves(String employeeId) async {
    final uri = Uri.parse(leaveRequestsDeleteRejectedEndpoint);
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({'employee_id': employeeId}),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final body = _decodeBody(response.body);
    throw Exception(body['error'] ?? 'تعذر حذف طلبات الإجازة المرفوضة (${response.statusCode})');
  }

  static Future<void> deleteRejectedAdvances(String employeeId) async {
    final uri = Uri.parse(advancesDeleteRejectedEndpoint);
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({'employee_id': employeeId}),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final body = _decodeBody(response.body);
    throw Exception(body['error'] ?? 'تعذر حذف طلبات السلفة المرفوضة (${response.statusCode})');
  }

  static Future<ShiftStatus> fetchShiftStatus(String employeeId) async {
    final uri = Uri.parse('$shiftStatusEndpoint/$employeeId');
    final response = await http.get(uri);
    final body = _decodeBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final payload = body['shift'] ?? body['status'] ?? body['data'] ?? body;
      if (payload is Map<String, dynamic>) {
        return ShiftStatus.fromJson(payload);
      }
      if (payload is Map) {
        return ShiftStatus.fromJson(Map<String, dynamic>.from(payload));
      }
      return ShiftStatus.inactive();
    }

    throw Exception(body['error'] ?? 'تعذر تحميل حالة المناوبة (${response.statusCode})');
  }

  static Future<bool> checkActiveShift(String employeeId) async {
    try {
      final status = await fetchShiftStatus(employeeId);
      return status.hasActiveShift;
    } catch (_) {
      return false;
    }
  }
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
      Uri.parse(leaveRequestEndpoint),
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
    final uri = Uri.parse(leaveRequestsEndpoint).replace(
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
      Uri.parse(advanceRequestEndpoint),
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
    final uri = Uri.parse(advancesEndpoint).replace(
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
    final uri = Uri.parse('$currentEarningsEndpoint/$employeeId/current-earnings');
    final response = await http.get(uri);
    final body = _decodeBody(response.body);

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(body);
    }

    throw Exception(body['error'] ?? 'Failed to fetch current earnings');
  }

  static Future<void> submitBreakRequest({
    required String employeeId,
    required int durationMinutes,
  }) async {
    final response = await http.post(
      Uri.parse(breaksRequestEndpoint),
      headers: _jsonHeaders,
      body: jsonEncode({
        'employee_id': employeeId,
        'duration_minutes': durationMinutes,
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    final body = _decodeBody(response.body);
    throw Exception(body['error'] ?? 'Failed to submit break request');
  }

  static Future<void> startBreak({required String breakId}) async {
    final uri = Uri.parse('$breaksEndpoint/$breakId/start');
    final response = await http.post(uri, headers: _jsonHeaders);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    final body = _decodeBody(response.body);
    throw Exception(body['error'] ?? 'Failed to start break');
  }

  static Future<void> endBreak({required String breakId}) async {
    final uri = Uri.parse('$breaksEndpoint/$breakId/end');
    final response = await http.post(uri, headers: _jsonHeaders);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    final body = _decodeBody(response.body);
    throw Exception(body['error'] ?? 'Failed to end break');
  }

  static Future<List<Break>> fetchBreaks({required String employeeId}) async {
    final uri = Uri.parse(breaksEndpoint).replace(
      queryParameters: {'employee_id': employeeId},
    );
    final response = await http.get(uri);
    final body = _decodeBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final rawList = body['breaks'] ?? body['data'] ?? body['items'] ?? body;
      if (rawList is List) {
        return rawList
            .map((item) => Break.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
      return const <Break>[];
    }

    throw Exception(body['error'] ?? 'Failed to fetch breaks');
  }

  static Future<AttendanceRequest> submitAttendanceRequest({
    required String employeeId,
    required DateTime requestedTime,
    required String reason,
    AttendanceRequestType requestType = AttendanceRequestType.checkIn,
  }) async {
    final endpoint = requestType == AttendanceRequestType.checkIn
        ? attendanceRequestCheckinEndpoint
        : attendanceRequestCheckoutEndpoint;

    print('🔍 ATTENDANCE REQUEST DEBUG:');
    print('  - Endpoint: $endpoint');
    print('  - Employee ID: $employeeId');
    print('  - Requested Time: ${requestedTime.toIso8601String()}');
    print('  - Reason: $reason');

    final response = await http.post(
      Uri.parse(endpoint),
      headers: _jsonHeaders,
      body: jsonEncode({
        'employee_id': employeeId,
        'requested_time': requestedTime.toIso8601String(),
        'reason': reason,
      }),
    );

    print('🔍 ATTENDANCE REQUEST RESPONSE:');
    print('  - Status Code: ${response.statusCode}');
    print('  - Response Body: ${response.body}');

    final body = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final payload = body['request'] ?? body;
      return AttendanceRequest.fromJson(Map<String, dynamic>.from(payload as Map));
    }

    // Enhanced error message
    final errorMsg = body['error'] ?? body['message'] ?? 'تعذر إرسال طلب الحضور';
    print('🔍 ATTENDANCE REQUEST ERROR: $errorMsg (Status: ${response.statusCode})');
    throw Exception('$errorMsg (${response.statusCode})');
  }

  static Future<List<AttendanceRequest>> fetchAttendanceRequests(
      String employeeId) async {
    final uri = Uri.parse(attendanceRequestsEndpoint).replace(
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

  static Future<Map<String, dynamic>> getComprehensiveReport({
    required String employeeId,
    required String startDate,
    required String endDate,
  }) async {
    final endpoint = comprehensiveReportEndpoint.replaceAll(':employeeId', employeeId);
    final uri = Uri.parse(endpoint).replace(
      queryParameters: {
        'start_date': startDate,
        'end_date': endDate,
      },
    );

    final response = await http.get(uri);
    final body = _decodeBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(body);
    }

    throw Exception(body['error'] ?? 'تعذر تحميل التقرير الشامل (${response.statusCode})');
  }

  static Map<String, dynamic> _decodeBody(String rawBody) {
    if (rawBody.isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(rawBody);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is List) {
      return <String, dynamic>{'data': decoded};
    }

    return <String, dynamic>{'data': decoded};
  }
  static Future<List<Map<String, dynamic>>> fetchOwnerPendingAttendanceRequests() async {
    final uri = Uri.parse(ownerPendingAttendanceRequestsEndpoint).replace(
      queryParameters: {'owner_id': 'OWNER001'}, // TODO: Get from auth
    );
    final response = await http.get(uri);
    final body = _decodeBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = body['requests'] ?? body;
      return (list as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
    throw Exception(body['error'] ?? 'تعذر تحميل طلبات الحضور (${response.statusCode})');
  }

  static Future<void> approveOwnerAttendanceRequest(String requestId) async {
    if (requestId.isEmpty) {
      throw Exception('معرف طلب الحضور مطلوب');
    }

    final uri = Uri.parse(ownerAttendanceRequestApprovalEndpoint.replaceAll(':id', requestId));
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': 'approve',
        'owner_user_id': 'OWNER001', // TODO: Get from auth
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    final body = _decodeBody(response.body);
    final errorMessage = body['error'] ?? body['message'] ?? 'تعذر الموافقة على الطلب';
    throw Exception('$errorMessage (${response.statusCode})');
  }
}
