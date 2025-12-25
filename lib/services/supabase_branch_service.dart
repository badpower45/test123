import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class SupabaseBranchService {
  static final SupabaseClient _supabase = SupabaseConfig.client;

  // ==================== BRANCHES MANAGEMENT ====================

  /// Get all branches
  static Future<List<Map<String, dynamic>>> getAllBranches() async {
    try {
      final response = await _supabase
          .from('branches')
          .select()
          .order('name', ascending: true);
      
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get all branches error: $e');
      return [];
    }
  }

  /// Get branch by ID
  static Future<Map<String, dynamic>?> getBranchById(String branchId) async {
    try {
      final response = await _supabase
          .from('branches')
          .select()
          .eq('id', branchId)
          .single();
      
      return response;
    } catch (e) {
      print('Get branch by ID error: $e');
      return null;
    }
  }

  /// Get branch by name
  static Future<Map<String, dynamic>?> getBranchByName(String branchName) async {
    try {
      final response = await _supabase
          .from('branches')
          .select()
          .eq('name', branchName)
          .maybeSingle();
      return response;
    } catch (e) {
      print('Get branch by name error: $e');
      return null;
    }
  }

  

  /// Create new branch
  static Future<Map<String, dynamic>?> createBranch({
    required String name,
    String? address,
    String? wifiBssid,
    double? latitude,
    double? longitude,
    double? geofenceRadius,
    double? distanceFromRadius,
    String? managerId,
  }) async {
    try {
      final response = await _supabase
          .from('branches')
          .insert({
            'name': name,
            'address': address,
            'wifi_bssid': wifiBssid,
            'latitude': latitude,
            'longitude': longitude,
            'geofence_radius': geofenceRadius != null ? geofenceRadius.toInt() : 100,
            'distance_from_radius': distanceFromRadius != null ? distanceFromRadius.toInt() : 100,
            'manager_id': managerId,
            'is_active': true,
          })
          .select()
          .single();
      
      return response;
    } catch (e) {
      print('Create branch error: $e');
      rethrow;
    }
  }

  /// Update branch
  static Future<bool> updateBranch({
    required String branchId,
    String? name,
    String? address,
    String? wifiBssid,
    double? latitude,
    double? longitude,
    double? geofenceRadius,
    double? distanceFromRadius,
    String? managerId,
    bool? isActive,
  }) async {
    try {
      final Map<String, dynamic> updates = {};
      
      if (name != null) updates['name'] = name;
      if (address != null) updates['address'] = address;
      if (wifiBssid != null) updates['wifi_bssid'] = wifiBssid;
      if (latitude != null) updates['latitude'] = latitude;
      if (longitude != null) updates['longitude'] = longitude;
      if (geofenceRadius != null) updates['geofence_radius'] = geofenceRadius.toInt();
      if (distanceFromRadius != null) updates['distance_from_radius'] = distanceFromRadius.toInt();
      if (managerId != null) updates['manager_id'] = managerId;
      if (isActive != null) updates['is_active'] = isActive;

      if (updates.isEmpty) return false;

      await _supabase
          .from('branches')
          .update(updates)
          .eq('id', branchId);
      
      return true;
    } catch (e) {
      print('Update branch error: $e');
      return false;
    }
  }

  /// Delete branch (unlinks employees automatically)
  static Future<bool> deleteBranch(String branchId) async {
    try {
      // First, try to unlink employees manually
      try {
        // Unlink employees from this branch
        await _supabase
            .from('employees')
            .update({
              'branch_id': null,
              'branch': null,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('branch_id', branchId);
        
        print('✅ Unlinked employees from branch: $branchId');
      } catch (e) {
        print('⚠️ Warning: Could not unlink employees: $e');
        // Continue anyway
      }
      
      // Try to delete branch BSSIDs
      try {
        await _supabase
            .from('branch_bssids')
            .delete()
            .eq('branch_id', branchId);
        print('✅ Deleted branch BSSIDs for branch: $branchId');
      } catch (e) {
        print('⚠️ Warning: Could not delete branch BSSIDs: $e');
        // Continue anyway - table might not exist
      }
      
      // Try to delete branch managers
      try {
        await _supabase
            .from('branch_managers')
            .delete()
            .eq('branch_id', branchId);
        print('✅ Deleted branch managers for branch: $branchId');
      } catch (e) {
        print('⚠️ Warning: Could not delete branch managers: $e');
        // Continue anyway - table might not exist
      }
      
      // Try RPC function first (if it exists)
      try {
        final response = await _supabase.rpc(
          'delete_branch_with_unlink',
          params: {'branch_id_to_delete': branchId},
        );
        
        if (response != null && response is Map) {
          final success = response['success'] as bool? ?? false;
          if (success) {
            print('✅ Delete branch success via RPC: ${response['message']}');
            return true;
          } else {
            final error = response['error'] as String? ?? 'فشل في حذف الفرع';
            print('❌ Delete branch error from RPC: $error');
            // Fall through to direct delete
          }
        }
      } catch (rpcError) {
        print('⚠️ RPC function not available or failed: $rpcError');
        print('   Falling back to direct delete...');
        // Fall through to direct delete
      }
      
      // Fallback: Direct delete
      await _supabase
          .from('branches')
          .delete()
          .eq('id', branchId);
      
      print('✅ Branch deleted successfully: $branchId');
      return true;
    } catch (e) {
      print('❌ Delete branch error: $e');
      rethrow;
    }
  }

  /// Assign manager to branch
  static Future<bool> assignManager({
    required String branchId,
    required String managerId,
  }) async {
    try {
      await _supabase
          .from('branches')
          .update({'manager_id': managerId})
          .eq('id', branchId);
      
      return true;
    } catch (e) {
      print('Assign manager error: $e');
      return false;
    }
  }

  // ==================== EMPLOYEES BY BRANCH ====================

  /// Get all employees in a branch
  static Future<List<Map<String, dynamic>>> getEmployeesByBranch(String branchName) async {
    try {
      final response = await _supabase
          .from('employees')
          .select()
          .eq('branch', branchName)
          .order('full_name', ascending: true);
      
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get employees by branch error: $e');
      return [];
    }
  }

  /// Get active employees count by branch
  static Future<int> getActiveEmployeesCount(String branchName) async {
    try {
      final response = await _supabase
          .from('employees')
          .select('id')
          .eq('branch', branchName)
          .eq('is_active', true);
      
      // Count the returned list
      return response.length;
    } catch (e) {
      print('Get active employees count error: $e');
      return 0;
    }
  }

  // ==================== CURRENTLY PRESENT EMPLOYEES ====================

  /// Get employees currently checked in (present now)
  static Future<List<Map<String, dynamic>>> getCurrentlyPresentEmployees({
    String? branchName,
  }) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      var query = _supabase
          .from('attendance')
          .select('*, employees!inner(id, full_name, branch, role)')
          .eq('date', today)
          .isFilter('check_out_time', null); // Still checked in
      
      if (branchName != null) {
        query = query.eq('employees.branch', branchName);
      }

      final response = await query.order('check_in_time', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get currently present employees error: $e');
      return [];
    }
  }

  /// Get count of currently present employees
  static Future<int> getCurrentlyPresentCount({String? branchName}) async {
    try {
      final employees = await getCurrentlyPresentEmployees(branchName: branchName);
      return employees.length;
    } catch (e) {
      print('Get currently present count error: $e');
      return 0;
    }
  }

  /// Get daily attendance status for all employees in branch (after 12:00)
  /// Returns: employees with attendance status (present/absent) and calculated deduction
  static Future<List<Map<String, dynamic>>> getDailyAttendanceStatus({
    required String branchName,
  }) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final now = DateTime.now();
      
      // Get all active employees in the branch
      final employeesResponse = await _supabase
          .from('employees')
          .select('id, full_name, branch, hourly_rate, shift_start_time, shift_end_time')
          .eq('branch', branchName)
          .eq('is_active', true)
          .order('full_name', ascending: true);
      
      final employees = (employeesResponse as List).cast<Map<String, dynamic>>();
      
      // Get today's attendance records
      final attendanceResponse = await _supabase
          .from('attendance')
          .select('employee_id, check_in_time, check_out_time')
          .gte('check_in_time', '$today 00:00:00')
          .lte('check_in_time', '$today 23:59:59');
      
      final attendanceMap = <String, Map<String, dynamic>>{};
      for (final att in (attendanceResponse as List)) {
        attendanceMap[att['employee_id']] = att;
      }
      
      // Build result with attendance status and deduction calculation
      final result = <Map<String, dynamic>>[];
      for (final emp in employees) {
        final employeeId = emp['id'] as String;
        final attendance = attendanceMap[employeeId];
        final hasAttendance = attendance != null;
        
        // Calculate deduction if absent (2 days penalty)
        double deductionAmount = 0.0;
        if (!hasAttendance && now.hour >= 12) {
          final hourlyRate = (emp['hourly_rate'] as num?)?.toDouble() ?? 0.0;
          final shiftHours = _calculateShiftHours(
            emp['shift_start_time'] as String?,
            emp['shift_end_time'] as String?,
          );
          // خصم يومين: (ساعات الشيفت × سعر الساعة) × 2
          deductionAmount = shiftHours * hourlyRate * 2;
        }
        
        result.add({
          'employee_id': employeeId,
          'full_name': emp['full_name'],
          'hourly_rate': emp['hourly_rate'],
          'shift_start_time': emp['shift_start_time'],
          'shift_end_time': emp['shift_end_time'],
          'is_present': hasAttendance,
          'check_in_time': attendance?['check_in_time'],
          'check_out_time': attendance?['check_out_time'],
          'can_deduct': !hasAttendance && now.hour >= 12,
          'deduction_amount': deductionAmount,
        });
      }
      
      return result;
    } catch (e) {
      print('Get daily attendance status error: $e');
      return [];
    }
  }

  /// Calculate shift hours from start and end time strings
  static double _calculateShiftHours(String? startTime, String? endTime) {
    if (startTime == null || endTime == null) return 8.0; // Default 8 hours
    
    try {
      // Parse time strings like "09:00" or "09:00:00"
      final startParts = startTime.split(':');
      final endParts = endTime.split(':');
      
      final startHour = int.parse(startParts[0]);
      final startMinute = startParts.length > 1 ? int.parse(startParts[1]) : 0;
      
      final endHour = int.parse(endParts[0]);
      final endMinute = endParts.length > 1 ? int.parse(endParts[1]) : 0;
      
      final startMinutes = startHour * 60 + startMinute;
      final endMinutes = endHour * 60 + endMinute;
      
      final diffMinutes = endMinutes - startMinutes;
      return diffMinutes / 60.0; // Convert to hours
    } catch (e) {
      print('Calculate shift hours error: $e');
      return 8.0; // Default 8 hours
    }
  }

  /// Apply deduction for absent employee
  static Future<Map<String, dynamic>> applyAbsenceDeduction({
    required String employeeId,
    required String managerId,
    required String branchId,
    required double deductionAmount,
  }) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      // Get employee details
      final empResponse = await _supabase
          .from('employees')
          .select('full_name, shift_start_time, shift_end_time')
          .eq('id', employeeId)
          .single();
      
      // 1. Create absence record
      final absenceResponse = await _supabase
          .from('absences')
          .insert({
            'employee_id': employeeId,
            'branch_id': branchId,
            'manager_id': managerId,
            'absence_date': today,
            'shift_start_time': empResponse['shift_start_time'],
            'shift_end_time': empResponse['shift_end_time'],
            'status': 'approved', // Manager approved the deduction
            'manager_response': 'خصم تلقائي بسبب الغياب (يومين)',
            'deduction_amount': deductionAmount,
          })
          .select()
          .single();
      
      final absenceId = absenceResponse['id'];
      
      // 2. Create deduction record
      await _supabase
          .from('deductions')
          .insert({
            'employee_id': employeeId,
            'absence_id': absenceId,
            'amount': -deductionAmount, // Negative value
            'reason': 'غياب بدون إذن - خصم يومين ($today)',
            'deduction_date': today,
          });
      
      return {
        'success': true,
        'message': 'تم خصم ${deductionAmount.toStringAsFixed(2)} جنيه من ${empResponse['full_name']}',
        'absence_id': absenceId,
      };
    } catch (e) {
      print('Apply absence deduction error: $e');
      return {
        'success': false,
        'message': 'فشل تطبيق الخصم: ${e.toString()}',
      };
    }
  }
}
