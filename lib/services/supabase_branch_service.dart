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

  /// Create new branch
  static Future<Map<String, dynamic>?> createBranch({
    required String name,
    String? address,
    String? wifiBssid,
    double? latitude,
    double? longitude,
    double? geofenceRadius,
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

  /// Delete branch
  static Future<bool> deleteBranch(String branchId) async {
    try {
      await _supabase
          .from('branches')
          .delete()
          .eq('id', branchId);
      
      return true;
    } catch (e) {
      print('Delete branch error: $e');
      return false;
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
}
