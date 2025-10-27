import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _keyEmployeeId = 'employee_id';
  static const String _keyRole = 'role';
  static const String _keyBranch = 'branch';
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyFullName = 'full_name';

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

  // Logout - clear all saved data
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
