import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class SupabaseAttendanceService {
  static final SupabaseClient _supabase = SupabaseConfig.client;

  /// Check-in employee
  static Future<Map<String, dynamic>?> checkIn({
    required String employeeId,
    double? latitude,
    double? longitude,
    String? wifiBssid,
  }) async {
    try {
      print('📥 Inserting check-in: employee=$employeeId, lat=$latitude, lng=$longitude, wifi=$wifiBssid');
      
      final response = await _supabase
          .from('attendance')
          .insert({
            'employee_id': employeeId,
            'check_in_time': DateTime.now().toUtc().toIso8601String(),
            'status': 'active',
            // ✅ إزالة الأعمدة غير الموجودة
            // 'check_in_latitude': latitude,
            // 'check_in_longitude': longitude,
            // 'wifi_bssid': wifiBssid,
          })
          .select()
          .single();

      print('✅ Check-in saved: ${response['id']}');

      // If location provided, create first pulse in location_pulses
      if (latitude != null && longitude != null && response['id'] != null) {
        print('📍 Creating first location pulse...');
        await _supabase.from('location_pulses').insert({
          'employee_id': employeeId,
          'attendance_id': response['id'],
          'latitude': latitude,
          'longitude': longitude,
          'wifi_bssid': wifiBssid,
          'is_within_geofence': true,
          'distance_from_center': 0.0,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });
        print('✅ First pulse created with WiFi data');
      }

      return response;
    } catch (e) {
      print('❌ Check-in error: $e');
      return null;
    }
  }

  /// Check-out employee
  static Future<bool> checkOut({
    required String attendanceId,
    double? latitude,
    double? longitude,
  }) async {
    try {
      // Get check-in time to calculate hours
      final attendance = await _supabase
          .from('attendance')
          .select('check_in_time')
          .eq('id', attendanceId)
          .single();

      final checkInTime = DateTime.parse(attendance['check_in_time']);
      final checkOutTime = DateTime.now().toUtc();
      final totalHours = checkOutTime.difference(checkInTime).inMinutes / 60;

      await _supabase
          .from('attendance')
          .update({
            'check_out_time': checkOutTime.toIso8601String(),
            'status': 'completed',
            'total_hours': totalHours,
          })
          .eq('id', attendanceId);

      return true;
    } catch (e) {
      print('Check-out error: $e');
      return false;
    }
  }

  /// Get active attendance for employee
  static Future<Map<String, dynamic>?> getActiveAttendance(String employeeId) async {
    try {
      final response = await _supabase
          .from('attendance')
          .select()
          .eq('employee_id', employeeId)
          .eq('status', 'active')
          .order('check_in_time', ascending: false)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Get active attendance error: $e');
      return null;
    }
  }

  /// Get attendance history for employee
  static Future<List<Map<String, dynamic>>> getAttendanceHistory({
    required String employeeId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _supabase
          .from('attendance')
          .select()
          .eq('employee_id', employeeId);

      if (startDate != null) {
        query = query.gte('check_in_time', startDate.toUtc().toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('check_in_time', endDate.toUtc().toIso8601String());
      }

      final response = await query.order('check_in_time', ascending: false);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get attendance history error: $e');
      return [];
    }
  }

  /// Get today's attendance for all employees (for admin)
  static Future<List<Map<String, dynamic>>> getTodayAttendance() async {
    try {
      final today = DateTime.now().toUtc();
      final startOfDay = DateTime(today.year, today.month, today.day).toUtc();

      final response = await _supabase
          .from('attendance')
          .select('*, employees(id, full_name, branch)')
          .gte('check_in_time', startOfDay.toIso8601String())
          .order('check_in_time', ascending: false);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Get today attendance error: $e');
      return [];
    }
  }

  /// Start break
  static Future<Map<String, dynamic>?> startBreak({
    required String employeeId,
    required String attendanceId,
  }) async {
    try {
      final response = await _supabase
          .from('breaks')
          .insert({
            'employee_id': employeeId,
            'attendance_id': attendanceId,
            'break_start': DateTime.now().toUtc().toIso8601String(),
            'status': 'ACTIVE',
          })
          .select()
          .single();

      return response;
    } catch (e) {
      print('Start break error: $e');
      return null;
    }
  }

  /// End break
  static Future<bool> endBreak(String breakId) async {
    try {
      final breakData = await _supabase
          .from('breaks')
          .select('break_start')
          .eq('id', breakId)
          .single();

      final breakStart = DateTime.parse(breakData['break_start']);
      final breakEnd = DateTime.now().toUtc();
      final durationMinutes = breakEnd.difference(breakStart).inMinutes;

      await _supabase
          .from('breaks')
          .update({
            'break_end': breakEnd.toIso8601String(),
            'duration_minutes': durationMinutes,
            'status': 'COMPLETED',
          })
          .eq('id', breakId);

      return true;
    } catch (e) {
      print('End break error: $e');
      return false;
    }
  }

  /// Get active break for employee
  static Future<Map<String, dynamic>?> getActiveBreak(String employeeId) async {
    try {
      final response = await _supabase
          .from('breaks')
          .select()
          .eq('employee_id', employeeId)
          .eq('status', 'ACTIVE')
          .order('break_start', ascending: false)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Get active break error: $e');
      return null;
    }
  }

  /// Get employee status (check-in status + active attendance + employee data)
  static Future<Map<String, dynamic>> getEmployeeStatus(String employeeId) async {
    try {
      // Get employee data from employees table
      final employeeData = await _supabase
          .from('employees')
          .select('*, branches(id, name)')
          .eq('id', employeeId)
          .maybeSingle();

      print('✅ Employee data from Supabase: $employeeData');
      
      // Get active attendance
      final activeAttendance = await getActiveAttendance(employeeId);
      
      // Get active break
      final activeBreak = await getActiveBreak(employeeId);
      
      return {
        'employee': employeeData,
        'attendance': activeAttendance,
        'break': activeBreak,
        'isCheckedIn': activeAttendance != null,
        'isOnBreak': activeBreak != null,
      };
    } catch (e) {
      print('❌ Get employee status error: $e');
      return {
        'employee': null,
        'attendance': null,
        'break': null,
        'isCheckedIn': false,
        'isOnBreak': false,
      };
    }
  }
}
