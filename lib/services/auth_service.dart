import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../models/shift_status.dart';
import 'attendance_api_service.dart';
import 'offline_data_service.dart';
import 'supabase_attendance_service.dart';

class AuthService with ChangeNotifier {
  static late SharedPreferences _prefs;
  static AuthService? _instance;

  Employee? _employee;
  ShiftStatus _shiftStatus = ShiftStatus.inactive();

  Employee? get employee => _employee;
  ShiftStatus get shiftStatus => _shiftStatus;

  static const String _keyEmployeeId = 'employee_id';
  static const String _keyRole = 'role';
  static const String _keyBranch = 'branch';
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyFullName = 'full_name';

  factory AuthService() {
    _instance ??= AuthService._();
    return _instance!;
  }

  AuthService._() {
    _initializePrefs();
  }

  static Future<void> _initializePrefs() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Save login credentials
  static Future<void> saveLoginData({
    required String employeeId,
    required String role,
    String? branch,
    String? fullName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmployeeId, employeeId);
    await prefs.setString(_keyRole, role);
    if (branch != null) await prefs.setString(_keyBranch, branch);
    if (fullName != null) await prefs.setString(_keyFullName, fullName);
    await prefs.setBool(_keyIsLoggedIn, true);
  }

  // Static logout method for backward compatibility
  static Future<void> logout() async {
    final instance = AuthService();
    await instance.logoutInstance();
  }

  // Get saved login data
  static Future<Map<String, String?>> getLoginData() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;
    
    if (!isLoggedIn) {
      return {};
    }

    return {
      'employeeId': prefs.getString(_keyEmployeeId),
      'role': prefs.getString(_keyRole),
      'branch': prefs.getString(_keyBranch),
      'fullName': prefs.getString(_keyFullName),
    };
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  // --- الدالة المعدلة ---
  Future<void> logoutInstance() async {
    // Get employee ID before clearing
    final loginData = await getLoginData();
    final employeeId = loginData['employeeId'];
    
    // 1. التحقق إذا كان المستخدم "حاضر" حالياً (من Supabase مباشرة)
    if (employeeId != null) {
      try {
        // Check active attendance from Supabase
        final hasActiveAttendance = await _checkActiveAttendance(employeeId);
        
        if (hasActiveAttendance) {
          // 2. إذا كان كذلك، قم بتشغيل الانصراف الإجباري
          print('⚠️ [Logout] Active attendance found, forcing checkout...');
          try {
            await AttendanceApiService.forceCheckOut();
            print('✅ [Logout] Force checkout successful');
          } catch (e) {
            print('❌ [Logout] Error during force checkout: $e');
            // لا نرسل throw error، يجب أن تتم عملية تسجيل الخروج محلياً
          }
        } else {
          print('ℹ️ [Logout] No active attendance found, proceeding with logout');
        }
      } catch (e) {
        print('⚠️ [Logout] Error checking active attendance: $e');
        // Continue with logout even if check fails
      }
    }

    // 3. Clear employee-specific offline data
    if (employeeId != null) {
      try {
        final offlineService = OfflineDataService();
        await offlineService.clearBranchDataForEmployee(employeeId);
        print('🗑️ Cleared offline data for employee: $employeeId');
      } catch (e) {
        print('⚠️ Error clearing employee offline data: $e');
      }
    }

    // 4. متابعة عملية تسجيل الخروج المحلية كالمعتاد
    _employee = null;
    _shiftStatus = ShiftStatus.inactive();

    // مسح جميع البيانات المحلية (التوكن، بيانات الموظف، إلخ)
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    notifyListeners();
  }

  /// Check if employee has active attendance from Supabase
  Future<bool> _checkActiveAttendance(String employeeId) async {
    try {
      final status = await SupabaseAttendanceService.getEmployeeStatus(employeeId);
      final attendance = status['attendance'] as Map<String, dynamic>?;
      
      if (attendance != null) {
        final attendanceStatus = attendance['status'] as String?;
        final isActive = attendanceStatus == 'active';
        print('🔍 [Logout] Attendance status: $attendanceStatus, isActive: $isActive');
        return isActive;
      }
      
      return false;
    } catch (e) {
      print('⚠️ [Logout] Error checking attendance status: $e');
      // Fallback to local status if Supabase check fails
      return _shiftStatus.isCheckedIn;
    }
  }
}
