import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../constants/api_endpoints.dart';
import '../models/employee.dart';

class AuthApiService {
  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json; charset=utf-8',
  };

  /// Login with employee ID and PIN
  /// Returns Employee object if successful, throws exception otherwise
  static Future<Employee> login({
    required String employeeId,
    required String pin,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse(LOGIN_ENDPOINT),
        headers: _jsonHeaders,
        body: jsonEncode({
          'employee_id': employeeId,
          'pin': pin,
        }),
      )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        dynamic decoded;
        try {
          decoded = jsonDecode(response.body);
        } catch (_) {
          throw Exception('رد الخادم غير مفهوم. حاول مرة أخرى.');
        }
        final data = decoded as Map<String, dynamic>;
        if (data['success'] == true && data['employee'] != null) {
          final employeeData = data['employee'];
          
          // Map server response to Employee model
          return Employee(
            id: employeeData['id'] ?? employeeId,
            fullName: employeeData['fullName'] ?? '',
            pin: pin, // Store locally for future use
            role: _mapRoleFromString(employeeData['role']),
            permissions: const [], // Server doesn't return permissions yet
            branch: employeeData['branch'] ?? '',
            monthlySalary: 0, // Server doesn't return salary in login
          );
        } else {
          throw Exception('معرّف الموظف أو الرقم السري غير صحيح');
        }
      } else if (response.statusCode == 401) {
        throw Exception('معرف الموظف أو الرقم السري غير صحيح');
      } else if (response.statusCode == 404) {
        throw Exception('الموظف غير موجود');
      } else if (response.statusCode == 400) {
        try {
          final data = jsonDecode(response.body);
          throw Exception(data['error'] ?? 'خطأ في البيانات المدخلة');
        } catch (_) {
          throw Exception('خطأ في البيانات المدخلة');
        }
      } else {
        throw Exception('خطأ في الاتصال بالخادم: ${response.statusCode}');
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('انتهت مهلة الاتصال بالخادم. تحقق من الإنترنت وحاول مجدداً.');
      }
      if (e is Exception) rethrow;
      throw Exception('فشل الاتصال بالخادم');
    }
  }

  /// Login for branch manager with email and password
  /// Returns Employee object if successful, throws exception otherwise
  static Future<Employee> loginManager({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse(LOGIN_ENDPOINT),
        headers: _jsonHeaders,
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        dynamic decoded;
        try {
          decoded = jsonDecode(response.body);
        } catch (_) {
          throw Exception('رد الخادم غير مفهوم. حاول مرة أخرى.');
        }
        final data = decoded as Map<String, dynamic>;
        if (data['success'] == true && data['manager'] != null) {
          final managerData = data['manager'];
          return Employee(
            id: managerData['id'] ?? '',
            fullName: managerData['fullName'] ?? '',
            pin: password,
            role: _mapRoleFromString(managerData['role']),
            permissions: const [],
            branch: managerData['branch'] ?? '',
            monthlySalary: 0,
          );
        } else {
          throw Exception('البريد الإلكتروني أو كلمة المرور غير صحيحة');
        }
      } else if (response.statusCode == 401) {
        throw Exception('البريد الإلكتروني أو كلمة المرور غير صحيحة');
      } else if (response.statusCode == 404) {
        throw Exception('المدير غير موجود');
      } else if (response.statusCode == 400) {
        try {
          final data = jsonDecode(response.body);
          throw Exception(data['error'] ?? 'خطأ في البيانات المدخلة');
        } catch (_) {
          throw Exception('خطأ في البيانات المدخلة');
        }
      } else {
        throw Exception('خطأ في الاتصال بالخادم: ${response.statusCode}');
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('انتهت مهلة الاتصال بالخادم. تحقق من الإنترنت وحاول مجدداً.');
      }
      if (e is Exception) rethrow;
      throw Exception('فشل الاتصال بالخادم');
    }
  }

  /// Map server role string to EmployeeRole enum
  static EmployeeRole _mapRoleFromString(String? role) {
    switch (role?.toLowerCase()) {
      case 'admin':
        return EmployeeRole.admin;
      case 'hr':
        return EmployeeRole.hr;
      case 'monitor':
        return EmployeeRole.monitor;
      case 'manager':
        return EmployeeRole.manager;
      case 'staff':
      default:
        return EmployeeRole.staff;
    }
  }
}
