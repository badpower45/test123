import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/employee.dart';

class SupabaseAuthService {
  static final SupabaseClient _supabase = SupabaseConfig.client;

  /// Login with Employee ID and PIN
  static Future<Employee?> login(String employeeId, String pin) async {
    try {
      final response = await _supabase
          .from('employees')
          .select()
          .eq('id', employeeId)
          .eq('pin', pin)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) {
        throw Exception('Invalid Employee ID or PIN');
      }

      return Employee.fromJson(response);
    } catch (e) {
      print('Login error: $e');
      rethrow;
    }
  }

  /// Get employee by ID
  static Future<Employee?> getEmployee(String employeeId) async {
    try {
      final response = await _supabase
          .from('employees')
          .select()
          .eq('id', employeeId)
          .maybeSingle();

      if (response == null) return null;
      return Employee.fromJson(response);
    } catch (e) {
      print('Get employee error: $e');
      return null;
    }
  }

  /// Get all employees (for admin/manager)
  static Future<List<Employee>> getAllEmployees() async {
    try {
      final response = await _supabase
          .from('employees')
          .select()
          .order('full_name', ascending: true);

      return (response as List)
          .map((json) => Employee.fromJson(json))
          .toList();
    } catch (e) {
      print('Get all employees error: $e');
      return [];
    }
  }

  /// Get employees by branch
  static Future<List<Employee>> getEmployeesByBranch(String branchId) async {
    try {
      final response = await _supabase
          .from('employees')
          .select()
          .eq('branch_id', branchId)
          .order('full_name', ascending: true);

      return (response as List)
          .map((json) => Employee.fromJson(json))
          .toList();
    } catch (e) {
      print('Get employees by branch error: $e');
      return [];
    }
  }

  /// Update employee data
  static Future<bool> updateEmployee(String employeeId, Map<String, dynamic> updates) async {
    try {
      await _supabase
          .from('employees')
          .update(updates)
          .eq('id', employeeId);
      return true;
    } catch (e) {
      print('Update employee error: $e');
      return false;
    }
  }

  /// Create new employee
  static Future<Employee?> createEmployee(Map<String, dynamic> employeeData) async {
    try {
      final response = await _supabase
          .from('employees')
          .insert(employeeData)
          .select()
          .single();

      return Employee.fromJson(response);
    } catch (e) {
      print('Create employee error: $e');
      return null;
    }
  }

  /// Delete employee
  static Future<bool> deleteEmployee(String employeeId) async {
    try {
      await _supabase
          .from('employees')
          .delete()
          .eq('id', employeeId);
      return true;
    } catch (e) {
      print('Delete employee error: $e');
      return false;
    }
  }

  /// Change employee PIN
  static Future<bool> changePin(String employeeId, String newPin) async {
    try {
      await _supabase
          .from('employees')
          .update({'pin': newPin})
          .eq('id', employeeId);
      return true;
    } catch (e) {
      print('Change PIN error: $e');
      return false;
    }
  }

  /// Verify employee exists
  static Future<bool> employeeExists(String employeeId) async {
    try {
      final response = await _supabase
          .from('employees')
          .select('id')
          .eq('id', employeeId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      print('Employee exists check error: $e');
      return false;
    }
  }

  /// Update employee profile (onboarding)
  static Future<bool> updateEmployeeProfile({
    required String employeeId,
    required String fullName,
    required String phone,
    required String address,
    required DateTime birthDate,
    String? email,
  }) async {
    try {
      await _supabase.from('employees').update({
        'full_name': fullName,
        'phone': phone,
        'address': address,
        'birth_date': birthDate.toIso8601String().split('T')[0],
        if (email != null) 'email': email,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', employeeId);

      return true;
    } catch (e) {
      print('Update employee profile error: $e');
      rethrow;
    }
  }

  /// Mark onboarding as complete
  static Future<bool> markOnboardingComplete(String employeeId) async {
    try {
      await _supabase.from('employees').update({
        'onboarding_completed': true,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', employeeId);

      return true;
    } catch (e) {
      print('Mark onboarding complete error: $e');
      rethrow;
    }
  }

  /// Check if employee needs onboarding
  static Future<bool> needsOnboarding(String employeeId) async {
    try {
      final response = await _supabase
          .from('employees')
          .select('onboarding_completed, phone, address')
          .eq('id', employeeId)
          .maybeSingle();

      if (response == null) return true;

      // Needs onboarding if flag is false OR missing critical data
      final onboardingCompleted = response['onboarding_completed'] as bool? ?? false;
      final hasPhone = response['phone'] != null && (response['phone'] as String).isNotEmpty;
      final hasAddress = response['address'] != null && (response['address'] as String).isNotEmpty;

      return !onboardingCompleted || !hasPhone || !hasAddress;
    } catch (e) {
      print('Check onboarding error: $e');
      return true; // Default to showing onboarding if check fails
    }
  }
}

