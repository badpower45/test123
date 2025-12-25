import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:geolocator/geolocator.dart';
import '../database/offline_database.dart';
import 'notification_service.dart';
import 'wifi_service.dart';
import 'offline_data_service.dart';
import 'supabase_attendance_service.dart';
import '../models/employee.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GeofenceValidationResult {
  final bool isValid;
  final String message;
  final Position? position;
  final String? bssid;
  final double? distance;
  final String? branchId;

  GeofenceValidationResult({
    required this.isValid,
    required this.message,
    this.position,
    this.bssid,
    this.distance,
    this.branchId,
  });
}

class GeofenceService {
  static final GeofenceService instance = GeofenceService._init();
  GeofenceService._init();

  Timer? _locationCheckTimer;
  bool _isMonitoring = false;
  String? _currentEmployeeId;
  String? _currentEmployeeName;
  double? _branchLatitude;
  double? _branchLongitude;
  double? _geofenceRadius;
  List<String> _requiredBssids = [];

  // Start monitoring geofence
  Future<void> startMonitoring({
    required String employeeId,
    required String employeeName,
    required double branchLatitude,
    required double branchLongitude,
    required double geofenceRadius,
    required List<String> requiredBssids,
  }) async {
    if (_isMonitoring) {
      print('[GeofenceService] Already monitoring');
      return;
    }

    _currentEmployeeId = employeeId;
    _currentEmployeeName = employeeName;
    _branchLatitude = branchLatitude;
    _branchLongitude = branchLongitude;
    _geofenceRadius = geofenceRadius;
    _requiredBssids = requiredBssids.map((e) => e.toUpperCase()).toList();

    // Request background location permission
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      print('[GeofenceService] Location permission denied');
      return;
    }

    _isMonitoring = true;

    // Check location every 5 minutes (as requested)
    _locationCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkGeofence(),
    );

    // Do initial check
    await _checkGeofence();

    print('[GeofenceService] Started monitoring for employee: $employeeId');
  }

  // Stop monitoring
  void stopMonitoring() {
    _locationCheckTimer?.cancel();
    _locationCheckTimer = null;
    _isMonitoring = false;
    _currentEmployeeId = null;
    _currentEmployeeName = null;
    print('[GeofenceService] Stopped monitoring');
  }

  // Check if employee is within geofence
  Future<void> _checkGeofence() async {
    if (!_isMonitoring || _currentEmployeeId == null) return;

    try {
      // Get current position with BALANCED accuracy for battery efficiency
      Position? position;
      int attempts = 0;
      const maxAttempts = 2; // Reduced from 3 to 2 for better battery

      while (attempts < maxAttempts && position == null) {
        try {
          position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.medium, // Changed from high to medium
            forceAndroidLocationManager: false, // Let system choose best provider
            timeLimit: const Duration(seconds: 20), // Increased timeout
          ).timeout(const Duration(seconds: 12)); // Reduced from 20

          // Verify accuracy is acceptable (less than 100 meters for periodic checks)
          if (position.accuracy > 100) {
            print('[GeofenceService] Poor accuracy (${position.accuracy}m), retrying...');
            position = null;
            attempts++;
            await Future.delayed(const Duration(milliseconds: 1500)); // Reduced delay
          } else {
            break;
          }
        } catch (e) {
          attempts++;
          print('[GeofenceService] Attempt $attempts failed: $e');
          if (attempts < maxAttempts) {
            await Future.delayed(const Duration(milliseconds: 1500));
          }
        }
      }

      if (position == null) {
        print('[GeofenceService] Failed to get location after $maxAttempts attempts');
        return;
      }

      // ✅ Check if within geofence (branch coordinates first!)
      final distance = Geolocator.distanceBetween(
        _branchLatitude!,
        _branchLongitude!,
        position.latitude,
        position.longitude,
      );

      print('[GeofenceService] Location check: distance=${distance.toStringAsFixed(1)}m, accuracy=${position.accuracy.toStringAsFixed(1)}m, radius=${_geofenceRadius}m');

      final isWithinGeofence = distance <= _geofenceRadius!;

      // Smart WiFi checking: only check if inside geofence or close to it
      // This saves battery by not checking WiFi when employee is far away
      bool isCorrectWifi = true;
      if (_requiredBssids.isNotEmpty && distance <= (_geofenceRadius! * 1.5)) {
        try {
          final wifiBSSID = await WiFiService.getCurrentWifiBssidValidated();
          isCorrectWifi = _requiredBssids.contains(wifiBSSID.toUpperCase());
          print('[GeofenceService] WiFi check: BSSID=$wifiBSSID, isCorrect=$isCorrectWifi');
        } catch (e) {
          print('[GeofenceService] Failed to check WiFi: $e');
          // Only consider WiFi invalid if we're inside geofence
          // If outside geofence, WiFi check is not critical
          isCorrectWifi = !isWithinGeofence;
        }
      } else if (_requiredBssids.isNotEmpty) {
        // Employee is far from geofence, skip WiFi check to save battery
        print('[GeofenceService] Skipping WiFi check (too far from geofence)');
      }

      // Check timestamp to avoid double counting with background service
      final prefs = await SharedPreferences.getInstance();
      
      // ✅ CHECK FOR ACTIVE BREAK
      final isBreakActive = prefs.getBool('is_break_active') ?? false;
      if (isBreakActive) {
        print('[GeofenceService] ☕ Break is active. Skipping violation checks.');
        // Reset violation counter just in case
        await prefs.setInt('consecutive_out_pulses', 0);
        await prefs.setInt('last_pulse_timestamp', DateTime.now().millisecondsSinceEpoch);
        return;
      }

      final lastPulseTime = prefs.getInt('last_pulse_timestamp') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      if (now - lastPulseTime < 4 * 60 * 1000) {
        print('[GeofenceService] Skipping check (recent pulse detected)');
        return;
      }

      // If both GPS and Wi-Fi validation fail, treat as violation
      if (!(isWithinGeofence || isCorrectWifi)) {
        await _handleGeofenceViolation(
          position.latitude,
          position.longitude,
          distance,
        );
      } else {
        print('[GeofenceService] Employee within geofence (${distance.toStringAsFixed(0)}m)');
        // Reset violation counter
        await prefs.setInt('consecutive_out_pulses', 0);
        await prefs.setInt('last_pulse_timestamp', now);
      }
    } catch (e) {
      print('[GeofenceService] Error checking geofence: $e');
    }
  }

  // Handle geofence violation
  Future<void> _handleGeofenceViolation(
    double latitude,
    double longitude,
    double distance,
  ) async {
    print('[GeofenceService] ⚠️ GEOFENCE VIOLATION! Distance: ${distance.toStringAsFixed(0)}m');

    try {
      final prefs = await SharedPreferences.getInstance();
      int consecutiveOutPulses = prefs.getInt('consecutive_out_pulses') ?? 0;
      consecutiveOutPulses++;
      
      await prefs.setInt('consecutive_out_pulses', consecutiveOutPulses);
      await prefs.setInt('last_pulse_timestamp', DateTime.now().millisecondsSinceEpoch);

      // 🚨 VIOLATION LOGIC (3 Stages)
      if (consecutiveOutPulses == 1) {
        await NotificationService.instance.showGeofenceViolation(
          employeeName: _currentEmployeeName ?? 'الموظف',
          message: 'تحذير: أنت خارج نطاق الفرع! يرجى العودة فوراً لتجنب الخصم.',
        );
      } else if (consecutiveOutPulses == 2) {
        await NotificationService.instance.showGeofenceViolation(
          employeeName: _currentEmployeeName ?? 'الموظف',
          message: '❌ الـ5 دقائق القادمة لن تُحتسب! أنت خارج نطاق الفرع.',
        );
        print('[GeofenceService] Penalty recorded (violation 2)');
      } else {
        await NotificationService.instance.showGeofenceViolation(
          employeeName: _currentEmployeeName ?? 'الموظف',
          message: 'تم تسجيل انصراف تلقائي بعد خروجين متتاليين عن نطاق الفرع.',
        );

        await _performForegroundAutoCheckout(
          latitude: latitude,
          longitude: longitude,
        );
      }

      // Save violation to database (legacy)
      final db = OfflineDatabase.instance;
      await db.insertGeofenceViolation(
        employeeId: _currentEmployeeId!,
        timestamp: DateTime.now(),
        latitude: latitude,
        longitude: longitude,
      );

      print('[GeofenceService] Violation handled (Stage $consecutiveOutPulses)');
    } catch (e) {
      print('[GeofenceService] Error handling violation: $e');
    }
  }

  // Manual check (can be called when employee checks in)
  Future<bool> isWithinGeofence({
    required double branchLatitude,
    required double branchLongitude,
    required double geofenceRadius,
    List<String>? requiredBssids,
  }) async {
    try {
      // Get current position
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 10));

      // Check distance

      final distance = Geolocator.distanceBetween(
        branchLatitude,
        branchLongitude,
        position.latitude,
        position.longitude,
      );

      final isWithinGeofence = distance <= geofenceRadius;

      // Check WiFi if required
      if (requiredBssids != null && requiredBssids.isNotEmpty) {
        try {
          final wifiBSSID = await WiFiService.getCurrentWifiBssidValidated();
          return isWithinGeofence && requiredBssids.contains(wifiBSSID.toUpperCase());
        } catch (e) {
          print('[GeofenceService] WiFi check failed: $e');
          return false;
        }
      }

      return isWithinGeofence;
    } catch (e) {
      print('[GeofenceService] Error checking location: $e');
      return false;
    }
  }

  Future<void> _performForegroundAutoCheckout({
    required double latitude,
    required double longitude,
  }) async {
    if (_currentEmployeeId == null) {
      print('[GeofenceService] ❌ Cannot auto checkout without employee ID');
      return;
    }

    final supabase = Supabase.instance.client;
    Map<String, dynamic>? attendance;

    try {
      attendance = await supabase
          .from('attendance')
          .select('id')
          .eq('employee_id', _currentEmployeeId!)
          .eq('status', 'active')
          .maybeSingle();
    } catch (e) {
      print('[GeofenceService] ❌ Failed to load active attendance: $e');
    }

    if (attendance == null) {
      print('[GeofenceService] ⚠️ No active attendance found during auto checkout');
      return;
    }

    final attendanceId = attendance['id'] as String;

    try {
      final success = await SupabaseAttendanceService.checkOut(
        attendanceId: attendanceId,
        latitude: latitude,
        longitude: longitude,
      );

      if (success) {
        print('[GeofenceService] ✅ Auto checkout completed after two violations');
        stopMonitoring();
        return;
      }

      throw Exception('Edge function response missing success flag');
    } catch (e) {
      print('[GeofenceService] ❌ Auto checkout failed (likely offline): $e');

      try {
        final db = OfflineDatabase.instance;
        await db.insertPendingCheckout(
          employeeId: _currentEmployeeId!,
          attendanceId: attendanceId,
          timestamp: DateTime.now(),
          latitude: latitude,
          longitude: longitude,
          notes: 'Auto-checkout by system (Foreground Violation)',
        );
        print('[GeofenceService] ✅ Saved pending auto checkout locally');
        stopMonitoring();
      } catch (dbError) {
        print('[GeofenceService] ❌ Failed to store offline auto checkout: $dbError');
      }
    }
  }

  // Get monitoring status
  bool get isMonitoring => _isMonitoring;

  // Get current employee info
  String? get currentEmployeeId => _currentEmployeeId;

  /// --- New Method: Validate for Check-In (WiFi FIRST, GPS as backup, then SHIFT TIME) ---
  static Future<GeofenceValidationResult> validateForCheckIn(Employee employee) async {
    Position? position;
    String? bssid;

    // ⏰ STEP 0: Check Shift Time FIRST (before expensive WiFi/GPS checks)
    if (employee.shiftStartTime != null && employee.shiftEndTime != null) {
      final now = DateTime.now();
      final currentTime = TimeOfDay(hour: now.hour, minute: now.minute);
      
      final shiftStart = _parseTimeOfDay(employee.shiftStartTime!);
      final shiftEnd = _parseTimeOfDay(employee.shiftEndTime!);
      
      if (shiftStart != null && shiftEnd != null) {
        final isWithinShift = _isTimeWithinRange(currentTime, shiftStart, shiftEnd);
        
        if (!isWithinShift) {
          print('⏰ Outside shift time: Current=${_formatTimeOfDay(currentTime)}, Shift=${employee.shiftStartTime}-${employee.shiftEndTime}');
          return GeofenceValidationResult(
            isValid: false,
            message: '⏰ أنت خارج موعد الشيفت\n'
                'وقت الشيفت: ${employee.shiftStartTime} - ${employee.shiftEndTime}\n'
                'الوقت الحالي: ${_formatTimeOfDay(currentTime)}\n'
                'يرجى تسجيل الحضور خلال موعد الشيفت',
          );
        }
        print('✅ Within shift time: ${employee.shiftStartTime}-${employee.shiftEndTime}');
      }
    }

    // Get cached branch data (employee-specific)
    Map<String, dynamic>? branchData;
    
    if (kIsWeb) {
      // On Web, use OfflineDataService (Hive) with employee ID
      final offlineService = OfflineDataService();
      branchData = await offlineService.getCachedBranchData(employeeId: employee.id);
      print('🌐 [Web] Loading branch data from Hive for employee: ${employee.id}');
    } else {
      // On Mobile, use OfflineDatabase (SQLite)
      final db = OfflineDatabase.instance;
      branchData = await db.getCachedBranchData(employee.id);
      print('📱 [Mobile] Loading branch data from SQLite for employee: ${employee.id}');
    }
    
    // Check if we have branch data
    if (branchData == null) {
      return GeofenceValidationResult(
        isValid: false,
        message: '❌ لا توجد بيانات للفرع المحفوظة.\nالرجاء الاتصال بالإنترنت أولاً لتحميل بيانات الفرع.',
      );
    }
    
    // ✅ FIX: Check multiple possible keys for branch_id
    final String? branchId = branchData['branch_id']?.toString() ?? 
                              branchData['id']?.toString() ??
                              branchData['branchId']?.toString();
    
    print('🏢 Branch ID resolved: $branchId');

    final double? branchLat = branchData['latitude']?.toDouble();
    final double? branchLng = branchData['longitude']?.toDouble();
    final double geofenceRadius = (branchData['geofence_radius'] ?? 100).toDouble();
    
    // Get array of allowed BSSIDs
    final List<String> allowedBssids = [];
    
    if (kIsWeb) {
      // On Web, single BSSID
      final bssidValue = branchData['bssid'];
      if (bssidValue != null && bssidValue.toString().isNotEmpty) {
        allowedBssids.addAll(
          bssidValue.toString().split(',').map((e) => e.trim().toUpperCase())
        );
      }
    } else {
      // On Mobile, array of BSSIDs
      if (branchData['wifi_bssids_array'] != null) {
        final bssidsArray = branchData['wifi_bssids_array'] as List<dynamic>;
        allowedBssids.addAll(bssidsArray.map((e) => e.toString().toUpperCase()));
      }
    }

    print('🔍 Branch: lat=$branchLat, lng=$branchLng, radius=$geofenceRadius, bssids=$allowedBssids');

    // ⚡ PRIORITY 1: Check WiFi FIRST (fastest and most reliable)
    if (allowedBssids.isNotEmpty && !kIsWeb) {
      try {
        bssid = await WiFiService.getCurrentWifiBssidValidated();
        final currentBssid = bssid.toUpperCase();
        
        print('📶 Current WiFi: $currentBssid');
        print('📋 Allowed WiFi: $allowedBssids');
        
        if (allowedBssids.contains(currentBssid)) {
          print('✅ WiFi MATCH! Check-in approved instantly');
          return GeofenceValidationResult(
            isValid: true,
            message: '✅ متصل بشبكة الفرع\nتم التحقق فوراً',
            position: null,
            bssid: bssid,
            branchId: branchId,
            distance: 0.0, // WiFi match implies 0 distance effectively
          );
        } else {
          print('⚠️ WiFi mismatch - will check GPS');
        }
      } catch (e) {
        print('⚠️ WiFi check failed: $e - will check GPS');
      }
    }

    // ⚡ PRIORITY 2: Check GPS (if WiFi failed or not available)
    if (branchLat != null && branchLng != null) {
      try {
        // 🚀 Fast path: last known location (often available on older devices)
        try {
          final lastPos = await Geolocator.getLastKnownPosition();
          if (lastPos != null) {
            final lastDistance = Geolocator.distanceBetween(
              branchLat,
              branchLng,
              lastPos.latitude,
              lastPos.longitude,
            );
            if (lastDistance <= geofenceRadius * 1.2) {
              print('✅ Using last known position: ${lastPos.latitude}, ${lastPos.longitude} (distance ${lastDistance.toStringAsFixed(1)}m)');
              return GeofenceValidationResult(
                isValid: true,
                message: '✅ الموقع صحيح (موقع محفوظ)\n(${lastDistance.round()}م من الفرع)',
                position: lastPos,
                bssid: bssid,
                branchId: branchId,
                distance: lastDistance,
              );
            }
          }
        } catch (e) {
          print('⚠️ Last known position unavailable: $e');
        }

        // Live GPS with more lenient settings and longer timeout
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          forceAndroidLocationManager: false,
          timeLimit: const Duration(seconds: 25),
        ).timeout(
          const Duration(seconds: 27),
          onTimeout: () => throw TimeoutException('Location timeout'),
        );

        print('📍 Current: ${position.latitude}, ${position.longitude}');
        print('📍 Branch: $branchLat, $branchLng');

        final distance = Geolocator.distanceBetween(
          branchLat,
          branchLng,
          position.latitude,
          position.longitude,
        );

        print('📏 Distance: ${distance.toStringAsFixed(1)}m (Radius: ${geofenceRadius.toStringAsFixed(1)}m)');

        if (distance <= geofenceRadius) {
          print('✅ GPS MATCH! Inside geofence');
          return GeofenceValidationResult(
            isValid: true,
            message: '✅ الموقع صحيح\n(${distance.round()}م من الفرع)',
            position: position,
            bssid: bssid,
            branchId: branchId,
            distance: distance,
          );
        } else {
          return GeofenceValidationResult(
            isValid: false,
            message: '❌ أنت خارج نطاق الفرع\n'
                'المسافة: ${distance.round()}م (المسموح: ${geofenceRadius.round()}م)\n'
                'يرجى الاقتراب من موقع العمل أو الاتصال بشبكة WiFi الخاصة بالفرع',
            branchId: branchId,
            distance: distance,
          );
        }
      } catch (e) {
        print('❌ GPS error: $e');
        // Fallback: try last known one more time
        try {
          final lastPos = await Geolocator.getLastKnownPosition();
          if (lastPos != null) {
            final lastDistance = Geolocator.distanceBetween(
              branchLat,
              branchLng,
              lastPos.latitude,
              lastPos.longitude,
            );
            if (lastDistance <= geofenceRadius * 1.2) {
              return GeofenceValidationResult(
                isValid: true,
                message: '✅ تم التحقق بموقع محفوظ مؤخراً\n(${lastDistance.round()}م)',
                position: lastPos,
                bssid: bssid,
                branchId: branchId,
                distance: lastDistance,
              );
            }
          }
        } catch (_) {}

        return GeofenceValidationResult(
          isValid: false,
          message: '❌ فشل التحقق\n'
              'لم نتمكن من التحقق من موقعك أو شبكة WiFi\n'
              'تأكد من تفعيل GPS والاتصال بشبكة الفرع',
          branchId: branchId,
        );
      }
    }

    // Both failed
    return GeofenceValidationResult(
      isValid: false,
      message: '❌ فشل التحقق\n'
          'يرجى التأكد من:\n'
          '• الاتصال بشبكة WiFi الخاصة بالفرع\n'
          '• أو التواجد في موقع الفرع مع تفعيل GPS',
      branchId: branchId,
    );
  }

  /// --- Validate for Check-Out (WiFi OR GPS - Same as Check-In for flexibility) ---
  /// ✅ FIXED: Made check-out validation flexible like check-in
  /// Previously required GPS with high accuracy which failed on many devices
  static Future<GeofenceValidationResult> validateForCheckOut(Employee employee) async {
    print('🔍 [ValidateCheckOut] Starting validation for employee: ${employee.id}');

    Position? position;
    String? bssid;

    // Get cached branch data
    Map<String, dynamic>? branchData;
    
    if (kIsWeb) {
      final offlineService = OfflineDataService();
      branchData = await offlineService.getCachedBranchData(employeeId: employee.id);
    } else {
      final db = OfflineDatabase.instance;
      branchData = await db.getCachedBranchData(employee.id);
    }

    // Check if we have branch data
    if (branchData == null) {
      // ✅ NEW: Allow check-out without branch data (offline mode)
      print('⚠️ [ValidateCheckOut] No branch data - allowing checkout anyway');
      return GeofenceValidationResult(
        isValid: true,
        message: '✅ تسجيل الانصراف (بدون تحقق من الموقع)',
        position: null,
      );
    }

    final String? branchId = branchData['branch_id']?.toString() ?? 
                              branchData['id']?.toString();
    final double? branchLat = branchData['latitude']?.toDouble();
    final double? branchLng = branchData['longitude']?.toDouble();
    final double geofenceRadius = (branchData['geofence_radius'] ?? 100).toDouble();
    
    // Get array of allowed BSSIDs
    final List<String> allowedBssids = [];
    if (!kIsWeb) {
      if (branchData['wifi_bssids_array'] != null) {
        final bssidsArray = branchData['wifi_bssids_array'] as List<dynamic>;
        allowedBssids.addAll(bssidsArray.map((e) => e.toString().toUpperCase()));
      }
    } else {
      final bssidValue = branchData['bssid'];
      if (bssidValue != null && bssidValue.toString().isNotEmpty) {
        allowedBssids.addAll(
          bssidValue.toString().split(',').map((e) => e.trim().toUpperCase())
        );
      }
    }

    print('🔍 [ValidateCheckOut] Branch: lat=$branchLat, lng=$branchLng, radius=$geofenceRadius');
    print('🔍 [ValidateCheckOut] Allowed BSSIDs: $allowedBssids');

    // ⚡ PRIORITY 1: Check WiFi FIRST (fastest and most reliable)
    if (allowedBssids.isNotEmpty && !kIsWeb) {
      try {
        bssid = await WiFiService.getCurrentWifiBssidValidated();
        final currentBssid = bssid.toUpperCase();
        
        print('📶 [ValidateCheckOut] Current WiFi: $currentBssid');
        
        if (allowedBssids.contains(currentBssid)) {
          print('✅ [ValidateCheckOut] WiFi MATCH! Check-out approved instantly');
          return GeofenceValidationResult(
            isValid: true,
            message: '✅ متصل بشبكة الفرع',
            position: null,
            bssid: bssid,
            branchId: branchId,
            distance: 0.0,
          );
        } else {
          print('⚠️ [ValidateCheckOut] WiFi mismatch - will check GPS');
        }
      } catch (e) {
        print('⚠️ [ValidateCheckOut] WiFi check failed: $e - will check GPS');
      }
    }

    // ⚡ PRIORITY 2: Check GPS (if WiFi failed or not available)
    if (branchLat != null && branchLng != null) {
      try {
        // 🚀 Fast path: last known location
        try {
          final lastPos = await Geolocator.getLastKnownPosition();
          if (lastPos != null) {
            final lastDistance = Geolocator.distanceBetween(
              branchLat,
              branchLng,
              lastPos.latitude,
              lastPos.longitude,
            );
            if (lastDistance <= geofenceRadius * 1.2) {
              print('✅ [ValidateCheckOut] Using last known: ${lastPos.latitude}, ${lastPos.longitude} (distance ${lastDistance.toStringAsFixed(1)}m)');
              return GeofenceValidationResult(
                isValid: true,
                message: '✅ الموقع صحيح (موقع محفوظ)\n(${lastDistance.round()}م)',
                position: lastPos,
                branchId: branchId,
                distance: lastDistance,
              );
            }
          }
        } catch (e) {
          print('⚠️ [ValidateCheckOut] Last known unavailable: $e');
        }

        // Live GPS with lenient settings
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          forceAndroidLocationManager: false,
          timeLimit: const Duration(seconds: 25),
        ).timeout(
          const Duration(seconds: 27),
          onTimeout: () => throw TimeoutException('Location timeout'),
        );

        print('📍 [ValidateCheckOut] Location: ${position.latitude}, ${position.longitude}');
        print('📍 [ValidateCheckOut] Accuracy: ${position.accuracy.toStringAsFixed(1)}m');

        if (position.accuracy > 150) {
          print('⚠️ [ValidateCheckOut] Low accuracy: ${position.accuracy.toStringAsFixed(1)}m');
        }

        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          branchLat,
          branchLng,
        );

        print('📏 [ValidateCheckOut] Distance: ${distance.round()}m (max: ${geofenceRadius.round()}m)');

        // Lenient radius for checkout (1.5x)
        final checkoutRadius = geofenceRadius * 1.5;

        if (distance <= checkoutRadius) {
          print('✅ [ValidateCheckOut] Location VALID: ${distance.round()}m');
          return GeofenceValidationResult(
            isValid: true,
            message: '✅ الموقع صحيح (${distance.round()}م)',
            position: position,
            branchId: branchId,
            distance: distance,
          );
        } else {
          print('⚠️ [ValidateCheckOut] Location outside radius but allowing checkout');
          return GeofenceValidationResult(
            isValid: true,
            message: '⚠️ أنت خارج نطاق الفرع (${distance.round()}م)\nتم تسجيل الانصراف مع ملاحظة',
            position: position,
            branchId: branchId,
            distance: distance,
          );
        }
      } catch (e) {
        print('⚠️ [ValidateCheckOut] Location error: $e');
        // Fallback: try last known again
        try {
          final lastPos = await Geolocator.getLastKnownPosition();
          if (lastPos != null) {
            final lastDistance = Geolocator.distanceBetween(
              branchLat,
              branchLng,
              lastPos.latitude,
              lastPos.longitude,
            );
            if (lastDistance <= geofenceRadius * 1.5) {
              return GeofenceValidationResult(
                isValid: true,
                message: '✅ تم التحقق بموقع محفوظ مؤخراً\n(${lastDistance.round()}م)',
                position: lastPos,
                branchId: branchId,
                distance: lastDistance,
              );
            }
          }
        } catch (_) {}

        // ✅ Allow checkout even if all GPS attempts failed (failsafe)
        return GeofenceValidationResult(
          isValid: true,
          message: '⚠️ تم تسجيل الانصراف بدون تحديد موقع (تعذر GPS/WiFi)\nستُضاف ملاحظة للمراجعة',
          position: null,
          branchId: branchId,
          distance: null,
        );
      }
    }

    // ✅ NEW: If all checks fail, still allow checkout (better than trapping employee)
    print('⚠️ [ValidateCheckOut] All checks failed - allowing checkout anyway');
    return GeofenceValidationResult(
      isValid: true,
      message: '✅ تسجيل الانصراف (تعذر التحقق من الموقع)',
      position: position,
      branchId: branchId,
    );
  }

  // ⏰ Helper: Parse time string "HH:mm" to TimeOfDay
  static TimeOfDay? _parseTimeOfDay(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length != 2) return null;
      
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      
      if (hour == null || minute == null) return null;
      if (hour < 0 || hour > 23) return null;
      if (minute < 0 || minute > 59) return null;
      
      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      print('❌ Error parsing time: $timeStr - $e');
      return null;
    }
  }

  // ⏰ Helper: Check if current time is within shift range
  static bool _isTimeWithinRange(TimeOfDay current, TimeOfDay start, TimeOfDay end) {
    final currentMinutes = current.hour * 60 + current.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    
    // Handle overnight shifts (e.g., 22:00 - 06:00)
    if (endMinutes < startMinutes) {
      // Shift crosses midnight
      return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
    } else {
      // Normal shift (same day)
      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    }
  }

  // ⏰ Helper: Format TimeOfDay to "HH:mm"
  static String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
