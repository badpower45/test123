import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';
import '../models/employee.dart';

class SupabaseAuthService {
  static final SupabaseClient _supabase = SupabaseConfig.client;
  
  // Retry configuration
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);
  static const Duration _requestTimeout = Duration(seconds: 30);

  /// Generic retry wrapper for database operations
  static Future<T> _withRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = _maxRetries,
    Duration retryDelay = _retryDelay,
  }) async {
    int attempt = 0;
    Exception? lastException;
    
    while (attempt < maxRetries) {
      try {
        attempt++;
        print('🔄 [Supabase] Attempt $attempt of $maxRetries');
        
        // Add timeout to the operation
        final result = await operation().timeout(
          _requestTimeout,
          onTimeout: () {
            throw TimeoutException('Request timed out after ${_requestTimeout.inSeconds} seconds');
          },
        );
        
        if (attempt > 1) {
          print('✅ [Supabase] Request succeeded on attempt $attempt');
        }
        return result;
      } on TimeoutException catch (e) {
        lastException = e;
        print('⏱️ [Supabase] Timeout on attempt $attempt: $e');
        if (attempt < maxRetries) {
          print('⏳ [Supabase] Waiting ${retryDelay.inSeconds}s before retry...');
          await Future.delayed(retryDelay * attempt); // Exponential backoff
        }
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        final errorStr = e.toString().toLowerCase();
        
        // Check if error is retryable
        final isRetryable = errorStr.contains('clientconnection') ||
            errorStr.contains('connection closed') ||
            errorStr.contains('socket') ||
            errorStr.contains('network') ||
            errorStr.contains('timeout') ||
            errorStr.contains('eof') ||
            errorStr.contains('connection reset') ||
            errorStr.contains('handshake');
        
        print('❌ [Supabase] Error on attempt $attempt: $e');
        print('   Retryable: $isRetryable');
        
        if (isRetryable && attempt < maxRetries) {
          print('⏳ [Supabase] Waiting ${retryDelay.inSeconds * attempt}s before retry...');
          await Future.delayed(retryDelay * attempt); // Exponential backoff
        } else if (!isRetryable) {
          // Non-retryable error, throw immediately
          rethrow;
        }
      }
    }
    
    print('❌ [Supabase] All $maxRetries attempts failed');
    throw lastException ?? Exception('Operation failed after $maxRetries attempts');
  }

  /// Login with Employee ID and PIN
  static Future<Employee?> login(String employeeId, String pin) async {
    try {
      final response = await _withRetry(() async {
        return await _supabase
            .from('employees')
            .select()
            .eq('id', employeeId)
            .eq('pin', pin)
            .eq('is_active', true)
            .maybeSingle();
      });

      if (response == null) {
        throw Exception('Invalid Employee ID or PIN');
      }

      print('✅ [Login] Successfully logged in: $employeeId');
      return Employee.fromJson(response);
    } catch (e) {
      print('❌ [Login] Error: $e');
      rethrow;
    }
  }

  /// Get employee by ID
  static Future<Employee?> getEmployee(String employeeId) async {
    try {
      final response = await _withRetry(() async {
        return await _supabase
            .from('employees')
            .select()
            .eq('id', employeeId)
            .maybeSingle();
      });

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

  /// Delete employee with all related records
  /// Uses Supabase Edge Function to delete employee and all related records
  static Future<bool> deleteEmployee(String employeeId) async {
    try {
      // First, verify the employee exists
      final existingEmployee = await _supabase
          .from('employees')
          .select('id, full_name')
          .eq('id', employeeId)
          .maybeSingle();
      
      if (existingEmployee == null) {
        print('Delete employee: Employee with ID $employeeId not found');
        return false;
      }
      
      print('Delete employee: Found employee ${existingEmployee['full_name']} (ID: $employeeId), proceeding with deletion...');
      
      // Try to use Edge Function first, then fallback to manual deletion
      try {
        final session = _supabase.auth.currentSession;
        final token = session?.accessToken ?? '';
        
        final supabaseUrl = SupabaseConfig.supabaseUrl;
        final functionUrl = '$supabaseUrl/functions/v1/delete-employee?employee_id=$employeeId';
        
        final httpResponse = await http.delete(
          Uri.parse(functionUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'apikey': SupabaseConfig.supabaseAnonKey,
          },
        );
        
        if (httpResponse.statusCode == 200) {
          final result = jsonDecode(httpResponse.body) as Map<String, dynamic>;
          if (result['success'] == true) {
            print('Delete employee: Successfully deleted employee $employeeId via Edge Function');
            return true;
          }
        }
        
        print('Delete employee: Edge Function returned status ${httpResponse.statusCode}: ${httpResponse.body}');
        // Fallback to manual deletion
        return await _deleteEmployeeManually(employeeId);
      } catch (e) {
        print('Delete employee: Edge Function error: $e, falling back to manual deletion');
        // Fallback to manual deletion
        return await _deleteEmployeeManually(employeeId);
      }
    } catch (e) {
      print('Delete employee error: $e');
      // Fallback to manual deletion
      return await _deleteEmployeeManually(employeeId);
    }
  }

  /// Manual deletion of employee with all related records
  static Future<bool> _deleteEmployeeManually(String employeeId) async {
    try {
      print('Delete employee: Attempting manual deletion...');
      
      // Delete all related records manually
      final tablesToDelete = [
        {'table': 'pulses', 'column': 'employee_id'},
        {'table': 'breaks', 'column': 'employee_id'},
        {'table': 'attendance', 'column': 'employee_id'},
        {'table': 'device_sessions', 'column': 'employee_id'},
        {'table': 'notifications', 'column': 'recipient_id'},
        {'table': 'salary_calculations', 'column': 'employee_id'},
        {'table': 'attendance_requests', 'column': 'employee_id'},
        {'table': 'leave_requests', 'column': 'employee_id'},
        {'table': 'salary_advances', 'column': 'employee_id'},
        {'table': 'deductions', 'column': 'employee_id'},
        {'table': 'absences', 'column': 'employee_id'}, // Add absences table
        {'table': 'absence_notifications', 'column': 'employee_id'},
        {'table': 'branch_managers', 'column': 'employee_id'},
      ];

      // Delete from each table
      for (final tableInfo in tablesToDelete) {
        try {
          await _supabase
              .from(tableInfo['table'] as String)
              .delete()
              .eq(tableInfo['column'] as String, employeeId);
          print('Delete employee: Deleted from ${tableInfo['table']}');
        } catch (e) {
          print('Delete employee: Warning - could not delete from ${tableInfo['table']}: $e');
          // Continue with other tables
        }
      }

      // Unlink manager from branches
      try {
        await _supabase
            .from('branches')
            .update({'manager_id': null, 'updated_at': DateTime.now().toIso8601String()})
            .eq('manager_id', employeeId);
        print('Delete employee: Unlinked from branches');
      } catch (e) {
        print('Delete employee: Warning - could not unlink from branches: $e');
      }

      // Finally, delete the employee
      await _supabase
          .from('employees')
          .delete()
          .eq('id', employeeId);
      
      // Verify deletion
      final verify = await _supabase
          .from('employees')
          .select('id')
          .eq('id', employeeId)
          .maybeSingle();
      
      if (verify == null) {
        print('Delete employee: Successfully deleted employee $employeeId (manual method)');
        return true;
      } else {
        print('Delete employee: Employee still exists after manual deletion attempt');
        return false;
      }
    } catch (e) {
      print('Delete employee manual error: $e');
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

