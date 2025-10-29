import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_endpoints.dart';
import '../models/attendance_summary.dart';
import '../models/detailed_attendance_request.dart';
import '../models/detailed_leave_request.dart';
import '../models/employee_attendance_status.dart';
import '../services/auth_service.dart';

class OwnerApiService {
  OwnerApiService._();

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json; charset=utf-8',
  };

  static Future<Map<String, dynamic>> getDashboard({
    required String ownerId,
  }) async {
    final uri = Uri.parse(ownerDashboardEndpoint).replace(
      queryParameters: {'owner_id': ownerId},
    );
    final response = await http.get(uri, headers: _jsonHeaders);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('فشل تحميل لوحة المالك: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> getEmployees({
    required String ownerId,
  }) async {
    final uri = Uri.parse(ownerEmployeesOverviewEndpoint).replace(
      queryParameters: {'owner_id': ownerId},
    );
    final response = await http.get(uri, headers: _jsonHeaders);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('فشل تحميل قائمة الموظفين: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> updateHourlyRate({
    required String ownerId,
    required String employeeId,
    required double hourlyRate,
  }) async {
    final endpoint = ownerEmployeeHourlyRateEndpoint.replaceFirst(
      ':employeeId',
      employeeId,
    );
    final uri = Uri.parse(endpoint).replace(
      queryParameters: {'owner_id': ownerId},
    );
    final response = await http.put(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({'hourly_rate': hourlyRate}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('فشل تحديث سعر الساعة: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> createEmployee({
    required String ownerId,
    required String employeeId,
    required String fullName,
    required String pin,
    String? branchId,  // Changed to branchId (UUID)
    String? branch,    // Optional: branch name for backward compatibility
    required double hourlyRate,
    String? shiftStartTime,  // Format: "HH:mm"
    String? shiftEndTime,    // Format: "HH:mm"
    String? shiftType,       // "AM" or "PM"
    String role = 'staff',   // NEW: Role (staff or manager)
  }) async {
    final uri = Uri.parse(employeesEndpoint);
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'id': employeeId,
        'ownerId': ownerId,
        'fullName': fullName,
        'pin': pin,
        'branchId': branchId,  // Send branchId (UUID)
        'branch': branch,      // Optional: send branch name
        'hourlyRate': hourlyRate,
        'role': role,  // Send role
        'active': true,
        'shiftStartTime': shiftStartTime,
        'shiftEndTime': shiftEndTime,
        'shiftType': shiftType,
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    if (response.statusCode == 409) {
      throw Exception('معرف الموظف مستخدم بالفعل');
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final message = data['error'] ?? 'خطأ غير معروف';
      throw Exception('فشل إضافة الموظف: $message');
    } catch (_) {
      throw Exception('فشل إضافة الموظف: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> getPayrollSummary({
    required String ownerId,
    required String startDate,
    required String endDate,
  }) async {
    final uri = Uri.parse(ownerPayrollSummaryEndpoint).replace(
      queryParameters: {
        'owner_id': ownerId,
        'start_date': startDate,
        'end_date': endDate,
      },
    );
    final response = await http.get(uri, headers: _jsonHeaders);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('فشل تحميل ملخص الرواتب: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> updateEmployee({
    required String employeeId,
    String? fullName,
    String? pin,
    String? role,
    String? branch,
    String? branchId,
    double? hourlyRate,
    bool? active,
    String? shiftStartTime,
    String? shiftEndTime,
    String? shiftType,
  }) async {
    final endpoint = employeesEndpoint.endsWith('/')
        ? '${employeesEndpoint}$employeeId'
        : '$employeesEndpoint/$employeeId';
    final uri = Uri.parse(endpoint);

    final body = <String, dynamic>{};
    if (fullName != null) body['fullName'] = fullName;
    if (pin != null) body['pin'] = pin;
    if (role != null) body['role'] = role;
    if (branch != null) body['branch'] = branch;
    if (branchId != null) body['branchId'] = branchId;
    if (hourlyRate != null) body['hourlyRate'] = hourlyRate;
    if (active != null) body['active'] = active;
    if (shiftStartTime != null) body['shiftStartTime'] = shiftStartTime;
    if (shiftEndTime != null) body['shiftEndTime'] = shiftEndTime;
    if (shiftType != null) body['shiftType'] = shiftType;

    final response = await http.put(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final message = data['error'] ?? 'خطأ غير معروف';
      throw Exception('فشل تحديث الموظف: $message');
    } catch (_) {
      throw Exception('فشل تحديث الموظف: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> deleteEmployee({
    required String employeeId,
  }) async {
    final endpoint = employeesEndpoint.endsWith('/')
        ? '${employeesEndpoint}$employeeId'
        : '$employeesEndpoint/$employeeId';
    final uri = Uri.parse(endpoint);

    final response = await http.delete(uri, headers: _jsonHeaders);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    if (response.statusCode == 404) {
      throw Exception('الموظف غير موجود');
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final message = data['error'] ?? 'خطأ غير معروف';
      throw Exception('فشل حذف الموظف: $message');
    } catch (_) {
      throw Exception('فشل حذف الموظف: ${response.statusCode}');
    }
  }

  // Leave request management for owner
  static Future<List<DetailedLeaveRequest>> getPendingLeaveRequests(
    String ownerId,
  ) async {
    final uri = Uri.parse(ownerLeaveRequestsEndpoint).replace(
      queryParameters: {'owner_id': ownerId},
    );
    final response = await http.get(uri, headers: _jsonHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final requests = data['requests'] as List<dynamic>;
      return requests.map((json) => DetailedLeaveRequest.fromJson(json)).toList();
    }
    throw Exception('فشل تحميل طلبات الإجازة: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> approveLeaveRequest({
    required String leaveRequestId,
    required String ownerUserId,
  }) async {
    final uri = Uri.parse(ownerLeaveApprovalEndpoint);
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'leave_request_id': leaveRequestId,
        'owner_user_id': ownerUserId,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('فشل الموافقة على طلب الإجازة: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> rejectLeaveRequest({
    required String leaveRequestId,
    required String ownerUserId,
    String? reason,
  }) async {
    final uri = Uri.parse(ownerLeaveApprovalEndpoint);
    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'leave_request_id': leaveRequestId,
        'owner_user_id': ownerUserId,
        'action': 'reject',
        'notes': reason,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('فشل رفض طلب الإجازة: ${response.statusCode}');
  }

  // Attendance request management for owner
static Future<List<DetailedAttendanceRequest>> getPendingAttendanceRequests(
  String ownerId,
) async {
  final uri = Uri.parse(ownerPendingAttendanceRequestsEndpoint).replace(
    queryParameters: {'owner_id': ownerId},
  );
  final response = await http.get(uri, headers: _jsonHeaders);
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final requests = data['requests'] as List<dynamic>;
    return requests.map((json) => DetailedAttendanceRequest.fromJson(json)).toList();
  }
  throw Exception('فشل تحميل طلبات الحضور: ${response.statusCode}');
}

static Future<Map<String, dynamic>> approveAttendanceRequest({
  required String requestId,
  required String ownerUserId,
}) async {
  final endpoint = ownerAttendanceRequestApprovalEndpoint.replaceAll(':id', requestId);
  final uri = Uri.parse(endpoint);
  final response = await http.post(
    uri,
    headers: _jsonHeaders,
    body: jsonEncode({
      'action': 'approve',
      'owner_user_id': ownerUserId,
    }),
  );
  if (response.statusCode == 200) {
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
  throw Exception('فشل الموافقة على طلب الحضور: ${response.statusCode}');
}

static Future<Map<String, dynamic>> rejectAttendanceRequest({
  required String requestId,
  required String ownerUserId,
  String? reason,
}) async {
  final endpoint = ownerAttendanceRequestApprovalEndpoint.replaceAll(':id', requestId);
  final uri = Uri.parse(endpoint);
  final response = await http.post(
    uri,
    headers: _jsonHeaders,
    body: jsonEncode({
      'action': 'reject',
      'owner_user_id': ownerUserId,
      'notes': reason,
    }),
  );
  if (response.statusCode == 200) {
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
  throw Exception('فشل رفض طلب الحضور: ${response.statusCode}');
}

// Attendance Control APIs - Updated to support date filtering
static Future<EmployeeStatusResult> getEmployeeAttendanceStatus({
  String? branchId,
  DateTime? date,
}) async {
  final queryParams = <String, String>{};
  if (branchId != null) queryParams['branchId'] = branchId;
  if (date != null) {
    // Format date as YYYY-MM-DD
    queryParams['date'] = "${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}";
  }

  final uri = Uri.parse(ownerAttendanceStatusEndpoint).replace(queryParameters: queryParams);
  final response = await http.get(uri, headers: _jsonHeaders);

  if (response.statusCode == 200) {
    final Map<String, dynamic> jsonResponse = json.decode(response.body);
    return EmployeeStatusResult.fromJson(jsonResponse);
  } else {
    throw Exception('فشل تحميل حالة الحضور: ${response.statusCode}');
  }
}

static Future<void> manualCheckIn(String employeeId, {String? reason}) async {
  final uri = Uri.parse(ownerManualCheckInEndpoint);
  final response = await http.post(
    uri,
    headers: _jsonHeaders,
    body: json.encode({'employeeId': employeeId, 'reason': reason}),
  );
  if (response.statusCode != 200) {
    final error = json.decode(response.body)['message'] ?? 'فشل تسجيل الحضور اليدوي';
    throw Exception(error);
  }
}

static Future<void> manualCheckOut(String employeeId, {String? reason}) async {
  final uri = Uri.parse(ownerManualCheckOutEndpoint);
  final response = await http.post(
    uri,
    headers: _jsonHeaders,
    body: json.encode({'employeeId': employeeId, 'reason': reason}),
  );
  if (response.statusCode != 200) {
    final error = json.decode(response.body)['message'] ?? 'فشل تسجيل الانصراف اليدوي';
    throw Exception(error);
  }
}

/// Updates the BSSID for a specific branch
static Future<void> updateBranchBssid(String branchId, String bssid) async {
  final url = Uri.parse('$apiBaseUrl/owner/branches/$branchId/bssid');
  final response = await http.put(
    url,
    headers: _jsonHeaders,
    body: jsonEncode({'bssid': bssid, 'owner_id': 'OWNER001'}), // Using default owner ID
  );

  if (response.statusCode != 200) {
    final error = json.decode(response.body)['message'] ?? 'فشل تحديث BSSID';
    throw Exception(error);
  }
}
}
