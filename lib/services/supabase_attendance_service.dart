import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import 'supabase_function_client.dart';

class SupabaseAttendanceService {
  static final SupabaseClient _supabase = SupabaseConfig.client;
  static const String _activeAttendanceSnapshotKey =
      'device_active_attendance_snapshot_v1';

  static bool _isActiveAttendanceRow(Map<String, dynamic> row) {
    final status = row['status']?.toString().toLowerCase();
    final hasCheckout = row['check_out_time'] != null;

    if (hasCheckout) {
      return false;
    }

    // Handle legacy and mixed status values from older edge functions.
    if (status == null || status.isEmpty) {
      return true;
    }

    const inactiveStates = <String>{
      'completed',
      'checked_out',
      'inactive',
      'out',
    };

    return !inactiveStates.contains(status);
  }

  /// Persist active attendance in one stable device snapshot so UI restore
  /// does not depend on multiple loosely-coupled preference keys.
  static Future<void> cacheActiveAttendanceOnDevice({
    required String employeeId,
    required String attendanceId,
    String? checkInIso,
    bool isOfflineAttendance = false,
  }) async {
    if (attendanceId.isEmpty) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final nowUtcIso = DateTime.now().toUtc().toIso8601String();
      final effectiveCheckInIso =
          (checkInIso != null && checkInIso.isNotEmpty)
          ? checkInIso
          : nowUtcIso;

      await prefs.setString('active_attendance_id', attendanceId);
      await prefs.setString('active_employee_id', employeeId);
      await prefs.setBool('is_checked_in', true);
      await prefs.setBool('is_offline_attendance', isOfflineAttendance);
      await prefs.setString('cached_checkin_time', effectiveCheckInIso);

      if (isOfflineAttendance) {
        await prefs.setString('offline_checkin_time', effectiveCheckInIso);
      } else {
        await prefs.remove('offline_checkin_time');
      }

      final snapshot = <String, dynamic>{
        'employee_id': employeeId,
        'attendance_id': attendanceId,
        'check_in_time': effectiveCheckInIso,
        'is_offline_attendance': isOfflineAttendance,
        'updated_at': nowUtcIso,
      };
      await prefs.setString(_activeAttendanceSnapshotKey, jsonEncode(snapshot));
      print('✅ Cached device active attendance snapshot: $attendanceId');
    } catch (e) {
      print('⚠️ Failed to cache active attendance snapshot: $e');
    }
  }

  /// Read the last active attendance snapshot for this device.
  static Future<Map<String, dynamic>?> getCachedActiveAttendanceOnDevice({
    String? employeeId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_activeAttendanceSnapshotKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await prefs.remove(_activeAttendanceSnapshotKey);
        return null;
      }

      final snapshot = Map<String, dynamic>.from(decoded);
      final snapshotEmployeeId = snapshot['employee_id']?.toString();
      final snapshotAttendanceId = snapshot['attendance_id']?.toString();

      if (snapshotAttendanceId == null || snapshotAttendanceId.isEmpty) {
        await prefs.remove(_activeAttendanceSnapshotKey);
        return null;
      }

      if (employeeId != null &&
          snapshotEmployeeId != null &&
          snapshotEmployeeId.isNotEmpty &&
          snapshotEmployeeId != employeeId) {
        return null;
      }

      return snapshot;
    } catch (e) {
      print('⚠️ Failed to read active attendance snapshot: $e');
      return null;
    }
  }

  /// Remove cached active attendance references from SharedPreferences
  static Future<void> clearActiveAttendanceCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_attendance_id');
      await prefs.remove('active_employee_id');
      await prefs.setBool('is_checked_in', false);
      await prefs.remove('is_offline_attendance');
      await prefs.remove('offline_checkin_time');
      await prefs.remove('cached_checkin_time');
      await prefs.remove(_activeAttendanceSnapshotKey);
      print('🧹 Cleared cached active attendance keys');
    } catch (e) {
      print('⚠️ Failed to clear cached attendance keys: $e');
    }
  }

  static Future<void> clearForcedCheckoutNotice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('forced_auto_checkout_pending');
      await prefs.remove('forced_auto_checkout_message');
      await prefs.remove('forced_auto_checkout_time');
      await prefs.remove('forced_auto_checkout_requires_sync');
    } catch (e) {
      print('⚠️ Failed to clear forced checkout flags: $e');
    }
  }

  static Future<void> resetGeofenceViolationState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('consecutive_out_pulses', 0);
      await prefs.setInt('last_pulse_timestamp', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('⚠️ Failed to reset geofence counters: $e');
    }
  }

  /// Store a local flag so the UI can warn the user about forced auto-checkouts
  static Future<void> markForcedCheckoutNotice({
    required DateTime timestamp,
    double? distanceMeters,
    bool pendingSync = false,
    String? message,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_attendance_id');
      await prefs.remove('active_employee_id');

      final defaultMessage = pendingSync
          ? 'تم حفظ الانصراف تلقائياً وسيتم رفعه عند توفر الإنترنت.'
          : 'تم تسجيل انصراف تلقائي بسبب الابتعاد عن الفرع.';

      final suffix = distanceMeters != null
          ? ' (المسافة ${distanceMeters.round()}م)'
          : '';

      await prefs.setBool('forced_auto_checkout_pending', true);
      await prefs.setBool('forced_auto_checkout_requires_sync', pendingSync);
      await prefs.setString('forced_auto_checkout_time', timestamp.toIso8601String());
      await prefs.setString(
        'forced_auto_checkout_message',
        (message ?? defaultMessage) + suffix,
      );
      print('📌 Stored forced auto-checkout notice locally');

      await resetGeofenceViolationState();
    } catch (e) {
      print('⚠️ Failed to store forced auto-checkout notice: $e');
    }
  }

  /// Check-in employee
  static Future<Map<String, dynamic>?> checkIn({
    required String employeeId,
    double? latitude,
    double? longitude,
    String? wifiBssid,
    String? branchId,
    double? distance,
  }) async {
    // ✅ CRITICAL: Check for active attendance BEFORE attempting check-in
    try {
      final activeAttendance = await getActiveAttendance(employeeId);
      if (activeAttendance != null) {
        print('⚠️ Employee already has active attendance: ${activeAttendance['id']}');
        print('   Check-in time: ${activeAttendance['check_in_time']}');
        
        // Return existing attendance instead of creating duplicate
        return activeAttendance;
      }
    } catch (e) {
      print('⚠️ Could not verify active attendance: $e');
      // Continue with check-in attempt (fail-safe)
    }

    final deviceNow = DateTime.now();
    final deviceNowUtcIso = deviceNow.toUtc().toIso8601String();
    print(
      '🕒 Check-in device timestamp: local=${deviceNow.toIso8601String()} utc=$deviceNowUtcIso',
    );
    
    final payload = {
      'employee_id': employeeId,
      'timestamp': deviceNowUtcIso,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (wifiBssid != null && wifiBssid.isNotEmpty) 'wifi_bssid': wifiBssid,
      if (branchId != null) 'branch_id': branchId,
      if (distance != null) 'distance_from_center': distance,
    };

    try {
      print('📤 Calling attendance-check-in Edge Function: $payload');
      final response = await SupabaseFunctionClient.post('attendance-check-in', payload);
      final attendance = (response ?? {})['attendance'];

      if (attendance is Map<String, dynamic>) {
        print('✅ Edge function check-in success: ${attendance['id']}');
        
        // ✅ Save attendance ID locally for offline check
        try {
          await cacheActiveAttendanceOnDevice(
            employeeId: employeeId,
            attendanceId: attendance['id'].toString(),
            checkInIso: attendance['check_in_time']?.toString(),
            isOfflineAttendance: false,
          );
          print('✅ Saved active attendance ID to SharedPreferences');
        } catch (e) {
          print('⚠️ Failed to save attendance ID: $e');
        }

        await clearForcedCheckoutNotice();
        await resetGeofenceViolationState();
        
        return attendance;
      }

      // Some responses may only include success flag (already checked in)
      if ((response ?? {})['success'] == true && (response ?? {})['alreadyCheckedIn'] == true) {
        final existing = (response ?? {})['attendance'];
        if (existing is Map<String, dynamic>) {
          print('ℹ️ Already checked in earlier today: ${existing['id']}');
          await cacheActiveAttendanceOnDevice(
            employeeId: employeeId,
            attendanceId: existing['id'].toString(),
            checkInIso: existing['check_in_time']?.toString(),
            isOfflineAttendance: false,
          );
          await clearForcedCheckoutNotice();
          await resetGeofenceViolationState();
          return existing;
        }
      }

      return null;
    } catch (edgeError) {
      if (_isAttendanceBusinessConflictError(edgeError)) {
        print('⛔ Check-in business conflict detected, skipping direct fallback: $edgeError');
        rethrow;
      }

      print('⚠️ Edge function check-in failed, falling back: $edgeError');

      try {
        final now = deviceNow;
        final insertPayload = {
          'employee_id': employeeId,
          'check_in_time': now.toUtc().toIso8601String(),
          'status': 'active',
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          if (wifiBssid != null && wifiBssid.isNotEmpty) 'check_in_wifi_bssid': wifiBssid,
          if (branchId != null) 'branch_id': branchId,
        };

        final insertedAttendance = await _supabase
            .from('attendance')
            .insert(insertPayload)
            .select()
            .single();

        print('✅ Direct check-in fallback saved: ${insertedAttendance['id']}');
        
        // ✅ Save attendance ID locally
        try {
          await cacheActiveAttendanceOnDevice(
            employeeId: employeeId,
            attendanceId: insertedAttendance['id'].toString(),
            checkInIso: insertedAttendance['check_in_time']?.toString(),
            isOfflineAttendance: false,
          );
          print('✅ Saved active attendance ID to SharedPreferences (fallback)');
        } catch (e) {
          print('⚠️ Failed to save attendance ID: $e');
        }

        await clearForcedCheckoutNotice();
        await resetGeofenceViolationState();

        // Save initial pulse (best-effort)
        try {
          final validationMethod = wifiBssid != null ? 'WIFI' : 'LOCATION';
          await _supabase.from('pulses').insert({
            'employee_id': employeeId,
            'attendance_id': insertedAttendance['id'],
            'timestamp': now.toUtc().toIso8601String(),
            'latitude': latitude,
            'longitude': longitude,
            'inside_geofence': true,
            'branch_id': branchId,
            'distance_from_center': distance,
            if (wifiBssid != null) 'bssid_address': wifiBssid,
            if (wifiBssid != null) 'wifi_bssid': wifiBssid,
            'validation_method': validationMethod,
            'status': 'active',
          });
        } catch (pulseError) {
          print('⚠️ Failed to insert fallback pulse: $pulseError');
        }

        // ✅ Daily summary will be updated by Edge Function via persist flag
        
        return insertedAttendance as Map<String, dynamic>?;
      } catch (fallbackError) {
        if (_isAttendanceBusinessConflictError(fallbackError)) {
          print('⛔ Check-in fallback blocked by business rule: $fallbackError');
          rethrow;
        }

        print('❌ Fallback check-in error: $fallbackError');
        return null;
      }
    }
  }

  static bool _isAttendanceBusinessConflictError(Object error) {
    final msg = error.toString();

    return msg.contains('alreadyCheckedOut') ||
        msg.contains('alreadyCheckedIn') ||
        msg.contains('تم تسجيل حضور وانصراف اليوم بالفعل') ||
        msg.contains('تم تسجيل الحضور مسبقاً') ||
        msg.contains('attendance_employee_date_unique') ||
        msg.contains('duplicate key value violates unique constraint');
  }

  /// Check-out employee (using Edge Function)
  static Future<bool> checkOut({
    required String attendanceId,
    double? latitude,
    double? longitude,
    String? wifiBssid,
    bool forceCheckout = false,
  }) async {
    try {
      // First, get employee_id from attendance record
      final attendance = await _supabase
          .from('attendance')
          .select('employee_id')
          .eq('id', attendanceId)
          .maybeSingle();
      
      if (attendance == null) {
        print('❌ Attendance record not found: $attendanceId');
        return false;
      }
      
      final employeeId = attendance['employee_id'] as String;
      
      // Use Edge Function for check-out (same as check-in)
      print('📤 Calling attendance-check-out Edge Function');
      print('   Employee ID: $employeeId');
      print('   Attendance ID: $attendanceId');
      print('   Location: $latitude, $longitude');
      print('   WiFi: $wifiBssid');
      
      final response = await SupabaseFunctionClient.post('attendance-check-out', {
        'employee_id': employeeId,
        'attendance_id': attendanceId,
        'latitude': latitude,
        'longitude': longitude,
        if (wifiBssid != null) 'wifi_bssid': wifiBssid,
        if (forceCheckout) 'force_checkout': true,
      });
      
      print('✅ Check-out Edge Function response: $response');
      
      // Check for success in multiple ways
      if ((response ?? {})['success'] == true) {
        print('✅ Check-out successful (success flag)');
        await clearActiveAttendanceCache();
        return true;
      }
      
      // Also check if attendance was returned (indicates success)
      if ((response ?? {})['attendance'] != null) {
        print('✅ Check-out successful (attendance returned)');
        await clearActiveAttendanceCache();
        return true;
      }
      
      // Check for alreadyCheckedOut flag
      if ((response ?? {})['alreadyCheckedOut'] == true) {
        print('ℹ️ Already checked out');
        await clearActiveAttendanceCache();
        return true;
      }
      
      print('❌ Check-out failed - no success indicator in response');
      if (forceCheckout) {
        return await _forceCheckoutDirect(
          attendanceId: attendanceId,
          latitude: latitude,
          longitude: longitude,
          note: 'Auto-checkout by system (Forced outside geofence)',
        );
      }
      return false;
    } catch (e) {
      print('❌ Check-out error: $e');
      print('❌ Error details: ${e.toString()}');
      
      // Fallback to direct update if Edge Function fails
      try {
        print('⚠️ Falling back to direct Supabase update...');
        
        // First verify attendance exists and is active
        return await _forceCheckoutDirect(
          attendanceId: attendanceId,
          latitude: latitude,
          longitude: longitude,
          note: 'Auto-checkout fallback (Edge failure)',
        );
      } catch (e2) {
        print('❌ Direct check-out also failed: $e2');
        print('❌ Direct update error details: ${e2.toString()}');
        return false;
      }
    }
  }

  static Future<bool> forceCheckout({
    required String attendanceId,
    double? latitude,
    double? longitude,
    String note = 'Auto-checkout by system (Forced)',
  }) async {
    return _forceCheckoutDirect(
      attendanceId: attendanceId,
      latitude: latitude,
      longitude: longitude,
      note: note,
    );
  }

  static Future<bool> _forceCheckoutDirect({
    required String attendanceId,
    double? latitude,
    double? longitude,
    required String note,
  }) async {
    final attendance = await _supabase
        .from('attendance')
        .select('check_in_time, employee_id, status')
        .eq('id', attendanceId)
        .maybeSingle();
    
    if (attendance == null) {
      print('❌ Attendance record not found for fallback: $attendanceId');
      return false;
    }
    
    if (attendance['status'] == 'completed') {
      print('ℹ️ Attendance already completed');
      await clearActiveAttendanceCache();
      return true;
    }

    // ✅ FIX: Safe check_in_time parsing
    DateTime checkInTime;
    try {
      final rawCheckIn = attendance['check_in_time'];
      if (rawCheckIn == null || rawCheckIn.toString().isEmpty) {
        print('⚠️ Invalid check_in_time, using current time');
        checkInTime = DateTime.now().toUtc();
      } else {
        checkInTime = DateTime.parse(rawCheckIn.toString());
      }
    } catch (e) {
      print('⚠️ Error parsing check_in_time: $e');
      checkInTime = DateTime.now().toUtc();
    }
    final checkOutTime = DateTime.now().toUtc();
    final totalHours = checkOutTime.difference(checkInTime).inMinutes / 60.0;

    print('🔄 Force-updating attendance: id=$attendanceId, time=${checkOutTime.toIso8601String()}');

    final updateResult = await _supabase
        .from('attendance')
        .update({
          'check_out_time': checkOutTime.toIso8601String(),
          'status': 'completed',
          'work_hours': totalHours.toStringAsFixed(2),
          'notes': note,
          if (latitude != null) 'check_out_latitude': latitude,
          if (longitude != null) 'check_out_longitude': longitude,
        })
        .eq('id', attendanceId)
        .select('id, check_out_time, status')
        .maybeSingle();

    if (updateResult == null) {
      print('❌ Direct force update returned null');
      return false;
    }

      print('✅ Direct force check-out update successful: $updateResult');
      await clearActiveAttendanceCache();
    return true;
  }

  /// Get active attendance for employee
  static Future<Map<String, dynamic>?> getActiveAttendance(String employeeId) async {
    try {
      final response = await _supabase
          .from('attendance')
          .select()
          .eq('employee_id', employeeId)
          .or('status.eq.active,status.eq.ACTIVE')
          .order('check_in_time', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        return Map<String, dynamic>.from(response.first as Map);
      }

      // Fallback 1: accept open attendance rows even if status value is inconsistent.
      final openRows = await _supabase
          .from('attendance')
          .select()
          .eq('employee_id', employeeId)
          .isFilter('check_out_time', null)
          .order('check_in_time', ascending: false)
          .limit(5);

      if (openRows.isNotEmpty) {
        for (final row in openRows) {
          final mapped = Map<String, dynamic>.from(row as Map);
          if (_isActiveAttendanceRow(mapped)) {
            return mapped;
          }
        }
      }

      // Fallback 2: trust cached active attendance ID when it belongs to this employee.
      final prefs = await SharedPreferences.getInstance();
      final cachedEmployeeId = prefs.getString('active_employee_id');
      final cachedAttendanceId = prefs.getString('active_attendance_id');
      if (cachedAttendanceId != null && cachedAttendanceId.isNotEmpty) {
        if (cachedEmployeeId == null || cachedEmployeeId == employeeId) {
          final cached = await _supabase
              .from('attendance')
              .select()
              .eq('id', cachedAttendanceId)
              .maybeSingle();

          if (cached != null) {
            final mapped = Map<String, dynamic>.from(cached as Map);
            if (_isActiveAttendanceRow(mapped)) {
              return mapped;
            }
          }
        }
      }

      return null;
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
          .select('*, employees!attendance_employee_id_fkey(id, full_name, branch)')
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

      // ✅ FIX: Safe break_start parsing
      DateTime breakStart;
      try {
        final rawBreakStart = breakData['break_start'];
        if (rawBreakStart == null || rawBreakStart.toString().isEmpty) {
          throw Exception('break_start is null or empty');
        }
        breakStart = DateTime.parse(rawBreakStart.toString());
      } catch (e) {
        print('⚠️ Error parsing break_start: $e');
        return false;
      }
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

      // Keep the user in an active state on transient network errors if local cache says so.
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedEmployeeId = prefs.getString('active_employee_id');
        final cachedAttendanceId = prefs.getString('active_attendance_id');
        final offlineCheckinTime = prefs.getString('offline_checkin_time');
        final cachedCheckinTime = prefs.getString('cached_checkin_time');
        final isCheckedInFlag = prefs.getBool('is_checked_in') ?? false;

        final cacheBelongsToEmployee =
            cachedEmployeeId == null || cachedEmployeeId == employeeId;
        final hasCachedActiveId =
            cacheBelongsToEmployee &&
            cachedAttendanceId != null &&
            cachedAttendanceId.isNotEmpty;

        if (hasCachedActiveId) {
          try {
            final cachedRow = await _supabase
                .from('attendance')
                .select()
                .eq('id', cachedAttendanceId)
                .maybeSingle();

            if (cachedRow != null) {
              final mapped = Map<String, dynamic>.from(cachedRow as Map);
              if (_isActiveAttendanceRow(mapped)) {
                return {
                  'employee': null,
                  'attendance': mapped,
                  'break': null,
                  'isCheckedIn': true,
                  'isOnBreak': false,
                };
              }
            }
          } catch (_) {}

          // Last resort synthetic active status if local flags still indicate checked-in.
          final preferredCheckinTime = offlineCheckinTime ?? cachedCheckinTime;

          if (isCheckedInFlag || preferredCheckinTime != null) {
            return {
              'employee': null,
              'attendance': {
                'id': cachedAttendanceId,
                'status': 'active',
                if (preferredCheckinTime != null)
                  'check_in_time': preferredCheckinTime,
              },
              'break': null,
              'isCheckedIn': true,
              'isOnBreak': false,
            };
          }
        }
      } catch (cacheError) {
        print('⚠️ Local status fallback failed: $cacheError');
      }

      return {
        'employee': null,
        'attendance': null,
        'break': null,
        'isCheckedIn': false,
        'isOnBreak': false,
      };
    }
  }

  /// Compute today's total earnings with geofence penalties
  /// Rules:
  /// - Work minutes = from today's check_in_time to check_out_time or now
  /// - False pulses today (inside_geofence = false) each deduct 5 minutes
  /// - Deduction minutes capped at worked minutes
  /// Returns: { workedMinutes, penaltyMinutes, hourlyRate, gross, deduction, net, falseCount }
  static Future<Map<String, dynamic>> getTodayEarningsWithPenalties(String employeeId) async {
    try {
      // Load hourly rate
      final employee = await _supabase
          .from('employees')
          .select('hourly_rate')
          .eq('id', employeeId)
          .maybeSingle();

      final hourlyRate = (employee?['hourly_rate'] as num?)?.toDouble() ?? 0.0;

      // Determine today's UTC window
      final nowLocal = DateTime.now();
      final startOfDayLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
      final startUtc = startOfDayLocal.toUtc();
      final endUtc = startOfDayLocal.add(const Duration(days: 1)).toUtc();

      // Get today's attendance
      final List<dynamic> attendanceList = await _supabase
          .from('attendance')
          .select('id, check_in_time, check_out_time')
          .eq('employee_id', employeeId)
          .gte('check_in_time', startUtc.toIso8601String())
          .lt('check_in_time', endUtc.toIso8601String())
          .order('check_in_time', ascending: false);

      if (attendanceList.isEmpty) {
        return {
          'workedMinutes': 0,
          'penaltyMinutes': 0,
          'hourlyRate': hourlyRate,
          'gross': 0.0,
          'deduction': 0.0,
          'net': 0.0,
          'falseCount': 0,
        };
      }

      final attendance = Map<String, dynamic>.from(attendanceList.first as Map);
      
      // ✅ FIX: Safe DateTime parsing for check_in_time and check_out_time
      DateTime inUtc;
      try {
        final rawCheckIn = attendance['check_in_time'];
        if (rawCheckIn == null || rawCheckIn.toString().isEmpty) {
          throw Exception('check_in_time is null');
        }
        inUtc = DateTime.parse(rawCheckIn.toString());
      } catch (e) {
        print('⚠️ Error parsing check_in_time: $e');
        inUtc = DateTime.now().toUtc();
      }
      
      DateTime outUtc;
      try {
        final rawCheckOut = attendance['check_out_time'];
        if (rawCheckOut != null && rawCheckOut.toString().isNotEmpty) {
          outUtc = DateTime.parse(rawCheckOut.toString());
        } else {
          outUtc = DateTime.now().toUtc();
        }
      } catch (e) {
        print('⚠️ Error parsing check_out_time: $e');
        outUtc = DateTime.now().toUtc();
      }

      // Compute worked minutes
      int workedMinutes = outUtc.difference(inUtc).inMinutes;
      if (workedMinutes < 0) workedMinutes = 0;

      // Pulse window within attendance
      final windowStartIso = inUtc.isBefore(startUtc) ? startUtc.toIso8601String() : inUtc.toIso8601String();
      final windowEndIso = outUtc.isAfter(endUtc) ? endUtc.toIso8601String() : outUtc.toIso8601String();

      // Count today's false pulses within attendance window (schema column is is_within_geofence)
      final falsePulses = await _supabase
          .from('pulses')
          .select('id')
          .eq('employee_id', employeeId)
          .eq('is_within_geofence', false)
          .gte('timestamp', windowStartIso)
          .lt('timestamp', windowEndIso);

        final falseCount = (falsePulses as List).length;
      final penaltyMinutesRaw = falseCount * 5; // each false pulse = 5 minutes
      final penaltyMinutes = penaltyMinutesRaw > workedMinutes ? workedMinutes : penaltyMinutesRaw;

      // Monetary computations
      final gross = hourlyRate * (workedMinutes / 60.0);
      final deduction = hourlyRate * (penaltyMinutes / 60.0);
      var net = gross - deduction;
      if (net < 0) net = 0.0;

      return {
        'workedMinutes': workedMinutes,
        'penaltyMinutes': penaltyMinutes,
        'hourlyRate': hourlyRate,
        'gross': gross,
        'deduction': deduction,
        'net': net,
        'falseCount': falseCount,
      };
    } catch (e) {
      print('getTodayEarningsWithPenalties error: $e');
      return {
        'workedMinutes': 0,
        'penaltyMinutes': 0,
        'hourlyRate': 0.0,
        'gross': 0.0,
        'deduction': 0.0,
        'net': 0.0,
        'falseCount': 0,
      };
    }
  }
}
