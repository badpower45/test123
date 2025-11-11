import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class SupabasePulseService {
  static final SupabaseClient _supabase = SupabaseConfig.client;

  /// Send pulse (heartbeat) to track employee location
  static Future<bool> sendPulse({
    required String employeeId,
    String? attendanceId,
    required double latitude,
    required double longitude,
    bool isWithinGeofence = true,
  }) async {
    try {
      await _supabase.from('pulses').insert({
        'employee_id': employeeId,
        'attendance_id': attendanceId,
        'latitude': latitude,
        'longitude': longitude,
        'is_within_geofence': isWithinGeofence,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      return true;
    } catch (e) {
      print('Send pulse error: $e');
      return false;
    }
  }

  /// Send bulk pulses (for offline sync)
  static Future<int> sendBulkPulses(List<Map<String, dynamic>> pulses) async {
    try {
      await _supabase.from('pulses').insert(pulses);
      return pulses.length;
    } catch (e) {
      print('Send bulk pulses error: $e');
      return 0;
    }
  }

  /// Get recent pulses for employee
  static Future<List<Map<String, dynamic>>> getRecentPulses({
    required String employeeId,
    int limit = 50,
  }) async {
    try {
      final response = await _supabase
          .from('pulses')
          .select()
          .eq('employee_id', employeeId)
          .order('timestamp', ascending: false)
          .limit(limit);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get recent pulses error: $e');
      return [];
    }
  }

  /// Get pulses for specific attendance
  static Future<List<Map<String, dynamic>>> getPulsesForAttendance(String attendanceId) async {
    try {
      final response = await _supabase
          .from('pulses')
          .select()
          .eq('attendance_id', attendanceId)
          .order('timestamp', ascending: true);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get pulses for attendance error: $e');
      return [];
    }
  }

  /// Track geofence entry/exit
  static Future<bool> trackGeofence({
    required String employeeId,
    required String branchId,
    required double latitude,
    required double longitude,
    required double distanceFromBranch,
    required bool isWithinGeofence,
  }) async {
    try {
      await _supabase.from('geofence_tracking').insert({
        'employee_id': employeeId,
        'branch_id': branchId,
        'latitude': latitude,
        'longitude': longitude,
        'distance_from_branch': distanceFromBranch,
        'is_within_geofence': isWithinGeofence,
      });

      return true;
    } catch (e) {
      print('Track geofence error: $e');
      return false;
    }
  }

  /// Get geofence violations
  static Future<List<Map<String, dynamic>>> getGeofenceViolations({
    required String employeeId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _supabase
          .from('geofence_tracking')
          .select()
          .eq('employee_id', employeeId)
          .eq('is_within_geofence', false);

      if (startDate != null) {
        query = query.gte('created_at', startDate.toUtc().toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('created_at', endDate.toUtc().toIso8601String());
      }

      final response = await query.order('created_at', ascending: false);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get geofence violations error: $e');
      return [];
    }
  }
}
