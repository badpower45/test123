import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/leave_request.dart';
import '../models/advance_request.dart';
import '../models/attendance_request.dart';
import '../config/app_config.dart';

class RequestsApiService {
  static const String _baseUrl = AppConfig.apiBaseUrl;

  static Future<Map<String, dynamic>> createLeaveRequest({
    required String employeeId,
    required DateTime leaveDate,
    required LeaveType type,
    required String reason,
  }) async {
    final url = Uri.parse('$_baseUrl/api/requests/leave');
    
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'employee_id': employeeId,
        'leave_date': leaveDate.toIso8601String(),
        'type': type == LeaveType.normal ? 'normal' : 'emergency',
        'reason': reason,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('فشل إنشاء طلب الإجازة: ${response.body}');
    }
  }

  static Future<List<LeaveRequest>> getLeaveRequests(String employeeId) async {
    final url = Uri.parse('$_baseUrl/api/requests/leave?employee_id=$employeeId');
    
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data.map((json) => _parseLeaveRequest(json as Map<String, dynamic>)).toList();
    } else {
      throw Exception('فشل تحميل طلبات الإجازة');
    }
  }

  static Future<Map<String, dynamic>> createAdvanceRequest({
    required String employeeId,
    required double amount,
    required double currentEarnings,
  }) async {
    final url = Uri.parse('$_baseUrl/api/requests/advance');
    
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'employee_id': employeeId,
        'amount': amount,
        'current_earnings': currentEarnings,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('فشل إنشاء طلب السلفة: ${response.body}');
    }
  }

  static Future<List<AdvanceRequest>> getAdvanceRequests(String employeeId) async {
    final url = Uri.parse('$_baseUrl/api/requests/advance?employee_id=$employeeId');
    
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data.map((json) => _parseAdvanceRequest(json as Map<String, dynamic>)).toList();
    } else {
      throw Exception('فشل تحميل طلبات السلف');
    }
  }

  static Future<Map<String, dynamic>> createAttendanceRequest({
    required String employeeId,
    required DateTime forgottenTime,
    required String reason,
  }) async {
    final url = Uri.parse('$_baseUrl/api/requests/attendance');
    
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'employee_id': employeeId,
        'forgotten_time': forgottenTime.toIso8601String(),
        'reason': reason,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('فشل إنشاء طلب الحضور: ${response.body}');
    }
  }

  static Future<double> getCurrentEarnings(String employeeId) async {
    final url = Uri.parse('$_baseUrl/api/me/earnings?employee_id=$employeeId');
    
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['current_earnings'] as num).toDouble();
    } else {
      throw Exception('فشل تحميل المرتب الحالي');
    }
  }

  static LeaveRequest _parseLeaveRequest(Map<String, dynamic> json) {
    return LeaveRequest(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      leaveDate: DateTime.parse(json['leave_date'] as String),
      type: json['type'] == 'emergency' ? LeaveType.emergency : LeaveType.normal,
      reason: json['reason'] as String,
      status: _parseRequestStatus(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: json['reviewed_at'] != null 
          ? DateTime.parse(json['reviewed_at'] as String) 
          : null,
      reviewedBy: json['reviewed_by'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
    );
  }

  static AdvanceRequest _parseAdvanceRequest(Map<String, dynamic> json) {
    return AdvanceRequest(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      currentEarnings: (json['current_earnings'] as num).toDouble(),
      status: _parseAdvanceStatus(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: json['reviewed_at'] != null 
          ? DateTime.parse(json['reviewed_at'] as String) 
          : null,
      reviewedBy: json['reviewed_by'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
    );
  }

  static RequestStatus _parseRequestStatus(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return RequestStatus.approved;
      case 'rejected':
        return RequestStatus.rejected;
      default:
        return RequestStatus.pending;
    }
  }

  static advance.RequestStatus _parseAdvanceStatus(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return advance.RequestStatus.approved;
      case 'rejected':
        return advance.RequestStatus.rejected;
      default:
        return advance.RequestStatus.pending;
    }
  }
}
