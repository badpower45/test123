import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../database/offline_database.dart';

/// Service for managing offline data storage and sync
/// Downloads branch data from Supabase and stores it locally
class OfflineDataService {
  static const String _branchDataBox = 'branch_data';
  static const String _attendanceBox = 'local_attendance';
  static const String _pulsesBox = 'local_pulses';
  
  final _supabase = Supabase.instance.client;
  
  // Helper: Get employee-specific key for branch data
  String _getBranchDataKey(String employeeId) => 'branch_$employeeId';

  // ==========================================
  // 1. Download Branch Data from Supabase
  // ==========================================
  
  /// Download branch data for the employee's assigned branch
  Future<Map<String, dynamic>?> downloadBranchData(String employeeBranch, {String? employeeId}) async {
    try {
      print('📥 Downloading branch data for: $employeeBranch (Employee: $employeeId)');
      
      // Get branch info from Supabase (correct column names)
      final response = await _supabase
          .from('branches')
          .select('id, name, latitude, longitude, wifi_bssid, geofence_radius, created_at')
          .eq('name', employeeBranch)
          .maybeSingle();
      
      if (response == null) {
        print('❌ No branch found with name: $employeeBranch');
        return null;
      }

      print('📦 Raw branch data: $response');

      // Get coordinates directly from response
      final latitude = response['latitude']?.toDouble();
      final longitude = response['longitude']?.toDouble();

      // Get geofence_radius (can be different field names)
      final geofenceRadius = (response['geofence_radius'] ?? 
                             response['geofenceRadius'] ?? 
                             100.0).toDouble();

      Map<String, dynamic>? employeeInfo;
      double? hourlyRate;

      if (employeeId != null) {
        try {
          employeeInfo = await _supabase
              .from('employees')
              .select('shift_start_time, shift_end_time, hourly_rate')
              .eq('id', employeeId)
              .maybeSingle();

          if (employeeInfo != null) {
            final rateValue = employeeInfo['hourly_rate'];
            if (rateValue is num) {
              hourlyRate = rateValue.toDouble();
            }
          }
        } catch (e) {
          print('⚠️ Failed to load employee shift info: $e');
        }
      }

      final dynamic wifiSource =
          response['wifi_bssids'] ?? response['wifi_bssid'];
      final List<String> wifiBssids = [];

      if (wifiSource is List) {
        wifiBssids.addAll(
          wifiSource
              .map((e) => e?.toString().toUpperCase().trim())
              .whereType<String>()
              .where((value) => value.isNotEmpty),
        );
      } else if (wifiSource is String) {
        final trimmed = wifiSource.trim();
        if (trimmed.isNotEmpty) {
          try {
            final decoded = jsonDecode(trimmed);
            if (decoded is List) {
              wifiBssids.addAll(
                decoded
                    .map((e) => e?.toString().toUpperCase().trim())
                    .whereType<String>()
                    .where((value) => value.isNotEmpty),
              );
            } else {
              wifiBssids.addAll(
                trimmed
                    .split(',')
                    .map((e) => e.toUpperCase().trim())
                    .where((value) => value.isNotEmpty),
              );
            }
          } catch (_) {
            wifiBssids.addAll(
              trimmed
                  .split(',')
                  .map((e) => e.toUpperCase().trim())
                  .where((value) => value.isNotEmpty),
            );
          }
        }
      }

      final distinctWifiBssids = wifiBssids.toSet().toList();

      final branchData = {
        'id': response['id'],
        'name': response['name'],
        'latitude': latitude,
        'longitude': longitude,
        'bssid': response['wifi_bssid'], // Map wifi_bssid to bssid for consistency
        'wifi_bssids': distinctWifiBssids,
        'geofence_radius': geofenceRadius,
        'downloaded_at': DateTime.now().toIso8601String(),
        'employee_id': employeeId, // Store which employee this data belongs to
        'shift_start_time': employeeInfo?['shift_start_time'],
        'shift_end_time': employeeInfo?['shift_end_time'],
        'hourly_rate': hourlyRate,
      };

      // ✅ Save to Hive (for Web platform)
      Box? box;
      if (Hive.isBoxOpen(_branchDataBox)) {
        box = Hive.box(_branchDataBox);
      } else {
        box = await Hive.openBox(_branchDataBox);
      }
      
      // Save with employee-specific key
      final storageKey = employeeId != null ? _getBranchDataKey(employeeId) : 'current_branch';
  await box.put(storageKey, branchData);

      // ✅ Also save to SQLite (for Mobile platform)
      if (!kIsWeb && employeeId != null) {
        final db = OfflineDatabase.instance;

        await db.cacheBranchData(
          employeeId: employeeId,
          branchId: response['id'],
          branchName: response['name'],
          wifiBssids: distinctWifiBssids,
          latitude: latitude,
          longitude: longitude,
          geofenceRadius: geofenceRadius?.toInt() ?? 100,
          shiftStartTime: employeeInfo?['shift_start_time'] as String?,
          shiftEndTime: employeeInfo?['shift_end_time'] as String?,
          hourlyRate: hourlyRate,
        );
        
        print('💾 Saved to SQLite database for mobile');
      }

      print('✅ تم تنزيل بيانات الفرع');
      print('📍 Location: ${branchData['latitude']}, ${branchData['longitude']}');
      if (distinctWifiBssids.isNotEmpty) {
        print('� Wi-Fi networks: ${distinctWifiBssids.join(', ')}');
      } else {
        print('📶 Wi-Fi networks: none provided');
      }
  print('🎯 Geofence Radius: ${branchData['geofence_radius']}m');
  print('⏰ Shift: ${branchData['shift_start_time']} → ${branchData['shift_end_time']}');
  print('💵 Hourly Rate: ${branchData['hourly_rate']}');

      return branchData;
    } catch (e) {
      print('❌ Error downloading branch data: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  // ==========================================
  // 2. Get Cached Branch Data (Offline)
  // ==========================================
  
  /// Get cached branch data from local storage for specific employee
  Future<Map<String, dynamic>?> getCachedBranchData({String? employeeId}) async {
    try {
      // Check if box is already open
      Box? box;
      if (Hive.isBoxOpen(_branchDataBox)) {
        box = Hive.box(_branchDataBox);
      } else {
        box = await Hive.openBox(_branchDataBox);
      }
      
      // Try employee-specific key first
      final storageKey = employeeId != null ? _getBranchDataKey(employeeId) : 'current_branch';
      final data = box.get(storageKey);
      
      if (data is Map) {
        print('✅ Found cached branch data for: $employeeId');
        return Map<String, dynamic>.from(data);
      }
      
      // Fallback to old key for backwards compatibility
      if (employeeId != null) {
        final fallbackData = box.get('current_branch');
        if (fallbackData is Map) {
          print('⚠️ Using fallback branch data (migrate to employee-specific)');
          return Map<String, dynamic>.from(fallbackData);
        }
      }
      
      return null;
    } catch (e) {
      print('❌ Error getting cached branch data: $e');
      return null;
    }
  }

  /// Check if branch data is downloaded for specific employee
  Future<bool> isBranchDataDownloaded({String? employeeId}) async {
    final data = await getCachedBranchData(employeeId: employeeId);
    return data != null;
  }
  
  /// Clear branch data for specific employee (on logout)
  Future<void> clearBranchDataForEmployee(String employeeId) async {
    try {
      Box? box;
      if (Hive.isBoxOpen(_branchDataBox)) {
        box = Hive.box(_branchDataBox);
      } else {
        box = await Hive.openBox(_branchDataBox);
      }
      
      await box.delete(_getBranchDataKey(employeeId));
      print('🗑️ Cleared branch data for employee: $employeeId');
    } catch (e) {
      print('❌ Error clearing branch data: $e');
    }
  }

  // ==========================================
  // 3. Local Attendance Storage
  // ==========================================
  
  /// Save check-in locally (offline)
  Future<bool> saveLocalCheckIn({
    required String employeeId,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
    String? bssid,
  }) async {
    try {
      final box = await Hive.openBox(_attendanceBox);
      
      final checkInData = {
        'employee_id': employeeId,
        'type': 'check_in',
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'bssid': bssid,
        'synced': false,
      };

      final key = 'checkin_${timestamp.millisecondsSinceEpoch}';
      await box.put(key, checkInData);
      await box.close();

      print('✅ Check-in saved locally: $key');
      return true;
    } catch (e) {
      print('❌ Error saving local check-in: $e');
      return false;
    }
  }

  /// Save check-out locally (offline)
  Future<bool> saveLocalCheckOut({
    required String employeeId,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
    String? bssid,
  }) async {
    try {
      final box = await Hive.openBox(_attendanceBox);

      final checkOutData = {
        'employee_id': employeeId,
        'type': 'check_out',
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'bssid': bssid,
        'synced': false,
      };

      final key = 'checkout_${timestamp.millisecondsSinceEpoch}';
      await box.put(key, checkOutData);
      await box.close();

      print('✅ Check-out saved locally: $key');
      return true;
    } catch (e) {
      print('❌ Error saving local check-out: $e');
      return false;
    }
  }

  /// Get all unsynced attendance records
  Future<List<Map<String, dynamic>>> getUnsyncedAttendance() async {
    try {
      final box = await Hive.openBox(_attendanceBox);
      final List<Map<String, dynamic>> unsynced = [];
      
      for (var key in box.keys) {
        final record = box.get(key);
        if (record is Map && record['synced'] == false) {
          unsynced.add({
            'key': key,
            ...Map<String, dynamic>.from(record),
          });
        }
      }
      
      await box.close();
      return unsynced;
    } catch (e) {
      print('❌ Error getting unsynced attendance: $e');
      return [];
    }
  }

  /// Mark attendance as synced
  Future<void> markAttendanceSynced(String key) async {
    try {
      final box = await Hive.openBox(_attendanceBox);
      final record = box.get(key);
      if (record is Map) {
        final updated = Map<String, dynamic>.from(record);
        updated['synced'] = true;
        await box.put(key, updated);
      }
      await box.close();
    } catch (e) {
      print('❌ Error marking attendance as synced: $e');
    }
  }

  // ==========================================
  // 4. Local Pulse Storage (Geofence Tracking)
  // ==========================================
  
  /// Save geofence pulse locally AND to Supabase (every 5 minutes)
  Future<bool> saveLocalPulse({
    required String employeeId,
    required DateTime timestamp,
    bool insideGeofence = false,
    double? latitude,
    double? longitude,
    double? distanceFromCenter,
    String? attendanceId,
    String? wifiBssid,
    bool validatedByWifi = false,
    bool validatedByLocation = false,
  }) async {
    try {
      // 1️⃣ Save to Supabase FIRST
      try {
        final payload = <String, dynamic>{
          'employee_id': employeeId,
          'attendance_id': attendanceId,
          'latitude': latitude,
          'longitude': longitude,
          'inside_geofence': insideGeofence,
          'distance_from_center': distanceFromCenter,
          'timestamp': timestamp.toUtc().toIso8601String(),
        };

        payload.removeWhere((key, value) => value == null);

        await _supabase.from('location_pulses').insert(payload);
        final distanceText = distanceFromCenter != null
            ? '${distanceFromCenter.toStringAsFixed(1)}m'
            : 'n/a';
        print('✅ Pulse saved to Supabase: ${insideGeofence ? "INSIDE" : "OUTSIDE"} geofence ($distanceText)');
      } catch (supabaseError) {
        print('⚠️ Could not save to Supabase (offline?): $supabaseError');
        // Continue to save locally for later sync
      }
      
      // 2️⃣ Save to Hive (local backup)
      final box = await Hive.openBox(_pulsesBox);
      
      final pulseData = {
        'employee_id': employeeId,
        'attendance_id': attendanceId,
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'inside_geofence': insideGeofence,
        'distance_from_center': distanceFromCenter,
        'wifi_bssid': wifiBssid,
        'validated_by_wifi': validatedByWifi,
        'validated_by_location': validatedByLocation,
        'synced': false,
      };

      final key = 'pulse_${timestamp.millisecondsSinceEpoch}';
      await box.put(key, pulseData);
      await box.close();

    final distanceText = distanceFromCenter != null
      ? '${distanceFromCenter.toStringAsFixed(1)}m'
      : 'n/a';
    print('📍 Pulse saved locally: ${insideGeofence ? "INSIDE" : "OUTSIDE"} geofence ($distanceText)');
      return true;
    } catch (e) {
      print('❌ Error saving local pulse: $e');
      return false;
    }
  }

  /// Get pulses for a specific date (for calculating work hours)
  Future<List<Map<String, dynamic>>> getPulsesForDate({
    required String employeeId,
    required DateTime date,
  }) async {
    try {
      final box = await Hive.openBox(_pulsesBox);
      final List<Map<String, dynamic>> pulses = [];
      
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      
      for (var key in box.keys) {
        final record = box.get(key);
        if (record is Map && record['employee_id'] == employeeId) {
          final timestamp = DateTime.parse(record['timestamp']);
          if (timestamp.isAfter(startOfDay) && timestamp.isBefore(endOfDay)) {
            pulses.add(Map<String, dynamic>.from(record));
          }
        }
      }
      
      await box.close();
      
      // Sort by timestamp
      pulses.sort((a, b) => 
        DateTime.parse(a['timestamp']).compareTo(DateTime.parse(b['timestamp']))
      );
      
      return pulses;
    } catch (e) {
      print('❌ Error getting pulses for date: $e');
      return [];
    }
  }

  /// Calculate work hours from pulses (time inside geofence)
  Future<double> calculateWorkHoursForDate({
    required String employeeId,
    required DateTime date,
  }) async {
    final pulses = await getPulsesForDate(employeeId: employeeId, date: date);
    
    if (pulses.isEmpty) return 0.0;

    double totalMinutes = 0.0;
    
    // Each pulse represents 5 minutes if inside geofence
    for (var pulse in pulses) {
      if (pulse['inside_geofence'] == true) {
        totalMinutes += 5.0; // 5 minutes per pulse
      }
    }

    return totalMinutes / 60.0; // Convert to hours
  }

  /// Build a quick summary of pulses for payroll/monitoring dashboards
  Future<Map<String, dynamic>> getPulseSummaryForDate({
    required String employeeId,
    required DateTime date,
  }) async {
    final pulses = await getPulsesForDate(employeeId: employeeId, date: date);

    final summary = <String, dynamic>{
      'totalPulses': 0,
      'insidePulses': 0,
      'outsidePulses': 0,
      'validatedByWifi': 0,
      'validatedByLocation': 0,
      'totalInsideMinutes': 0.0,
      'hourlyInsideMinutes': <String, double>{},
    };

    if (pulses.isEmpty) {
      return summary;
    }

    final Map<int, int> insidePulsesByHour = {};

    for (final pulse in pulses) {
      summary['totalPulses'] = (summary['totalPulses'] as int) + 1;

      final timestamp = DateTime.parse(pulse['timestamp'] as String);
      final hour = timestamp.hour;

      final isInside = pulse['inside_geofence'] == true;
      if (isInside) {
        summary['insidePulses'] = (summary['insidePulses'] as int) + 1;
        insidePulsesByHour.update(hour, (value) => value + 1, ifAbsent: () => 1);
      } else {
        summary['outsidePulses'] = (summary['outsidePulses'] as int) + 1;
      }

      if (pulse['validated_by_wifi'] == true) {
        summary['validatedByWifi'] = (summary['validatedByWifi'] as int) + 1;
      }

      if (pulse['validated_by_location'] == true) {
        summary['validatedByLocation'] =
            (summary['validatedByLocation'] as int) + 1;
      }
    }

    summary['totalInsideMinutes'] =
        (summary['insidePulses'] as int) * 5.0;

    final hourlyMinutes = <String, double>{};
    insidePulsesByHour.forEach((hour, pulseCount) {
      final hourKey = hour.toString().padLeft(2, '0');
      hourlyMinutes[hourKey] = pulseCount * 5.0;
    });
    summary['hourlyInsideMinutes'] = hourlyMinutes;

    return summary;
  }

  /// Get all unsynced pulses
  Future<List<Map<String, dynamic>>> getUnsyncedPulses() async {
    try {
      final box = await Hive.openBox(_pulsesBox);
      final List<Map<String, dynamic>> unsynced = [];
      
      for (var key in box.keys) {
        final record = box.get(key);
        if (record is Map && record['synced'] == false) {
          unsynced.add({
            'key': key,
            ...Map<String, dynamic>.from(record),
          });
        }
      }
      
      await box.close();
      return unsynced;
    } catch (e) {
      print('❌ Error getting unsynced pulses: $e');
      return [];
    }
  }

  /// Mark pulse as synced
  Future<void> markPulseSynced(String key) async {
    try {
      final box = await Hive.openBox(_pulsesBox);
      final record = box.get(key);
      if (record is Map) {
        final updated = Map<String, dynamic>.from(record);
        updated['synced'] = true;
        await box.put(key, updated);
      }
      await box.close();
    } catch (e) {
      print('❌ Error marking pulse as synced: $e');
    }
  }

  // ==========================================
  // 5. Sync to Supabase
  // ==========================================
  
  /// Sync all local data to Supabase
  Future<Map<String, int>> syncToSupabase() async {
    int syncedAttendance = 0;
    int syncedPulses = 0;
    
    try {
      // Sync attendance records
      final unsyncedAttendance = await getUnsyncedAttendance();
      for (var record in unsyncedAttendance) {
        try {
          if (record['type'] == 'check_in') {
            await _supabase.from('attendance').insert({
              'employee_id': record['employee_id'],
              'check_in_time': record['timestamp'],
              'check_in_latitude': record['latitude'],
              'check_in_longitude': record['longitude'],
              'check_in_bssid': record['bssid'],
            });
          } else if (record['type'] == 'check_out') {
            // Find matching check-in and update
            // For simplicity, we'll insert as new record
            await _supabase.from('attendance').insert({
              'employee_id': record['employee_id'],
              'check_out_time': record['timestamp'],
              'check_out_latitude': record['latitude'],
              'check_out_longitude': record['longitude'],
              'check_out_bssid': record['bssid'],
            });
          }
          
          await markAttendanceSynced(record['key']);
          syncedAttendance++;
        } catch (e) {
          print('❌ Error syncing attendance record: $e');
        }
      }

      // Sync pulse records
      final unsyncedPulses = await getUnsyncedPulses();
      for (var record in unsyncedPulses) {
        try {
          await _supabase.from('location_pulses').insert({
            'employee_id': record['employee_id'],
            'timestamp': record['timestamp'],
            'latitude': record['latitude'],
            'longitude': record['longitude'],
            'inside_geofence': record['inside_geofence'],
            'distance_from_center': record['distance_from_center'],
          });
          
          await markPulseSynced(record['key']);
          syncedPulses++;
        } catch (e) {
          print('❌ Error syncing pulse record: $e');
        }
      }

      print('✅ تم مزامنة البيانات ورفعها بالكامل');
      
      return {
        'attendance': syncedAttendance,
        'pulses': syncedPulses,
      };
    } catch (e) {
      print('❌ Error during sync: $e');
      return {
        'attendance': syncedAttendance,
        'pulses': syncedPulses,
      };
    }
  }

  // ==========================================
  // 6. Clear Local Data & Statistics
  // ==========================================

  /// Check if branch data needs refresh (Web version)
  Future<bool> needsBranchDataRefresh({String? employeeId}) async {
    try {
      final cachedData = await getCachedBranchData(employeeId: employeeId);
      
      if (cachedData == null) {
        print('📥 No cached data found - needs download');
        return true;
      }
      
      final downloadedAt = DateTime.parse(cachedData['downloaded_at']);
      final now = DateTime.now();
      final difference = now.difference(downloadedAt);
      
      final needsRefresh = difference.inHours >= 24;
      
      if (needsRefresh) {
        print('🔄 Cache is ${difference.inHours} hours old - needs refresh');
      } else {
        print('✅ Cache is fresh (${difference.inHours} hours old)');
      }
      
      return needsRefresh;
    } catch (e) {
      print('⚠️ Error checking cache age: $e');
      return true; // Refresh on error
    }
  }

  /// Get offline data statistics (Web version)
  Future<Map<String, int>> getOfflineDataStats() async {
    try {
      int branchCount = 0;
      int attendanceCount = 0;
      int pulsesCount = 0;

      // Count branch data
      if (Hive.isBoxOpen(_branchDataBox)) {
        final branchBox = Hive.box(_branchDataBox);
        branchCount = branchBox.length;
      }

      // Count attendance records
      if (Hive.isBoxOpen(_attendanceBox)) {
        final attendanceBox = Hive.box(_attendanceBox);
        attendanceCount = attendanceBox.values
            .where((record) => record is Map && record['synced'] == false)
            .length;
      }

      // Count pulses
      if (Hive.isBoxOpen(_pulsesBox)) {
        final pulsesBox = Hive.box(_pulsesBox);
        pulsesCount = pulsesBox.values
            .where((record) => record is Map && record['synced'] == false)
            .length;
      }

      print('📊 Offline Stats: Branches=$branchCount, Attendance=$attendanceCount, Pulses=$pulsesCount');

      return {
        'cached_branches': branchCount,
        'pending_attendance': attendanceCount,
        'pending_pulses': pulsesCount,
      };
    } catch (e) {
      print('⚠️ Error getting offline stats: $e');
      return {
        'cached_branches': 0,
        'pending_attendance': 0,
        'pending_pulses': 0,
      };
    }
  }
  
  /// Clear all local data (logout/reset)
  Future<void> clearAllLocalData() async {
    try {
      final branchBox = await Hive.openBox(_branchDataBox);
      await branchBox.clear();
      await branchBox.close();

      final attendanceBox = await Hive.openBox(_attendanceBox);
      await attendanceBox.clear();
      await attendanceBox.close();

      final pulsesBox = await Hive.openBox(_pulsesBox);
      await pulsesBox.clear();
      await pulsesBox.close();

      print('🗑️ All local data cleared');
    } catch (e) {
      print('❌ Error clearing local data: $e');
    }
  }
}
