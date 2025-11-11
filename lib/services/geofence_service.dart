import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:geolocator/geolocator.dart';
import '../database/offline_database.dart';
import 'notification_service.dart';
import 'wifi_service.dart';
import 'offline_data_service.dart';
import '../models/employee.dart';

class GeofenceValidationResult {
  final bool isValid;
  final String message;
  final Position? position;
  final String? bssid;

  GeofenceValidationResult({
    required this.isValid,
    required this.message,
    this.position,
    this.bssid,
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

    // Check location every 15 minutes for better battery saving (increased from 10)
    _locationCheckTimer = Timer.periodic(
      const Duration(minutes: 15),
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
            timeLimit: const Duration(seconds: 10), // Reduced from 15
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

      // If outside geofence or wrong WiFi
      if (!isWithinGeofence || !isCorrectWifi) {
        await _handleGeofenceViolation(
          position.latitude,
          position.longitude,
          distance,
        );
      } else {
        print('[GeofenceService] Employee within geofence (${distance.toStringAsFixed(0)}m)');
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
      // Save violation to database
      final db = OfflineDatabase.instance;
      await db.insertGeofenceViolation(
        employeeId: _currentEmployeeId!,
        timestamp: DateTime.now(),
        latitude: latitude,
        longitude: longitude,
      );

      // Show local notification to employee
      await NotificationService.instance.showGeofenceViolation(
        employeeName: _currentEmployeeName ?? 'الموظف',
        message: 'أنت خارج منطقة العمل! المسافة: ${distance.toStringAsFixed(0)} متر.\nيرجى العودة إلى الموقع المحدد.',
      );

      print('[GeofenceService] Violation saved and notification sent');
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
        desiredAccuracy: LocationAccuracy.high,
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
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          forceAndroidLocationManager: true,
          timeLimit: const Duration(seconds: 10),
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
          );
        } else {
          return GeofenceValidationResult(
            isValid: false,
            message: '❌ أنت خارج نطاق الفرع\n'
                'المسافة: ${distance.round()}م (المسموح: ${geofenceRadius.round()}م)\n'
                'يرجى الاقتراب من موقع العمل أو الاتصال بشبكة WiFi الخاصة بالفرع',
          );
        }
      } catch (e) {
        print('❌ GPS error: $e');
        return GeofenceValidationResult(
          isValid: false,
          message: '❌ فشل التحقق\n'
              'لم نتمكن من التحقق من موقعك أو شبكة WiFi\n'
              'تأكد من تفعيل GPS والاتصال بشبكة الفرع',
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
    );
  }

  /// --- Validate for Check-Out (GPS OR WiFi - at least one must be valid) ---
  static Future<GeofenceValidationResult> validateForCheckOut(Employee employee) async {
    print('🔍 [ValidateCheckOut] Starting validation for employee: ${employee.id}');
    
    bool isLocationValid = false;
    bool isWifiValid = false;
    Position? position;
    String? bssid;
    String locationMessage = '';
    String wifiMessage = '';

    // Get cached branch data
    final db = OfflineDatabase.instance;
    final branchData = await db.getCachedBranchData(employee.id);
    
    // Check if we have branch data
    if (branchData == null) {
      return GeofenceValidationResult(
        isValid: false,
        message: '❌ لا توجد بيانات للفرع المحفوظة.\nالرجاء الاتصال بالإنترنت أولاً لتحميل بيانات الفرع.',
      );
    }
    
    final double branchLat = branchData['latitude'] as double;
    final double branchLng = branchData['longitude'] as double;
    final double geofenceRadius = (branchData['geofence_radius'] as int).toDouble();
    
    // Get array of allowed BSSIDs
    final List<String> allowedBssids = [];
    if (branchData['wifi_bssids_array'] != null) {
      final bssidsArray = branchData['wifi_bssids_array'] as List<dynamic>;
      allowedBssids.addAll(bssidsArray.map((e) => e.toString().toUpperCase()));
    }

    print('🔍 Branch data: lat=$branchLat, lng=$branchLng, radius=$geofenceRadius');

    // 1. Try to get and validate current location
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true,
        timeLimit: const Duration(seconds: 15),
      );
      print('📍 [ValidateCheckOut] Location: ${position.latitude}, ${position.longitude}');

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        branchLat,
        branchLng,
      );

      print('📏 Distance: ${distance.round()}m (max: ${geofenceRadius.round()}m)');

      if (distance <= geofenceRadius) {
        isLocationValid = true;
        locationMessage = '✅ الموقع صحيح (${distance.round()}م)';
        print('✅ [ValidateCheckOut] Location VALID: ${distance.round()}m');
      } else {
        locationMessage = '❌ أنت خارج نطاق الفرع (${distance.round()}م من ${geofenceRadius.round()}م)';
        print('❌ [ValidateCheckOut] Location INVALID: ${distance.round()}m > ${geofenceRadius.round()}m');
      }
    } catch (e) {
      locationMessage = '❌ فشل في تحديد الموقع: $e';
      print('⚠️ [ValidateCheckOut] Location error: $e');
    }

    // 2. Try to validate WiFi BSSID
    try {
      bssid = await WiFiService.getCurrentWifiBssidValidated();
      print('📶 [ValidateCheckOut] WiFi BSSID: $bssid');
      
      if (bssid.isNotEmpty) {
        final currentBssid = bssid.toUpperCase();
        
        // Check against array of allowed BSSIDs
        if (allowedBssids.isNotEmpty && allowedBssids.contains(currentBssid)) {
          isWifiValid = true;
          wifiMessage = '✅ شبكة WiFi صحيحة: $bssid';
          print('✅ [ValidateCheckOut] WiFi VALID (matches cached)');
        } else if (allowedBssids.isEmpty) {
          // No cached BSSIDs - accept any WiFi (for backward compatibility)
          isWifiValid = true;
          wifiMessage = '✅ متصل بشبكة WiFi: $bssid';
          print('✅ [ValidateCheckOut] WiFi VALID (no cache)');
        } else {
          wifiMessage = '❌ شبكة WiFi غير صحيحة (متصل بشبكة أخرى)';
          print('❌ [ValidateCheckOut] WiFi INVALID (doesn\'t match any cached BSSID)');
        }
      } else {
        wifiMessage = '❌ غير متصل بشبكة WiFi';
        print('⚠️ [ValidateCheckOut] WiFi not connected');
      }
    } catch (e) {
      wifiMessage = '❌ فشل في التحقق من WiFi: $e';
      print('⚠️ [ValidateCheckOut] WiFi error: $e');
    }

    // 3. Check: At least ONE must be valid (OR logic)
    if (!isLocationValid && !isWifiValid) {
      print('❌ [ValidateCheckOut] Validation FAILED - Neither WiFi nor Location is valid');
      return GeofenceValidationResult(
        isValid: false,
        message: 'يجب أن تكون متصلاً بشبكة الواي فاي الخاصة بالفرع أو متواجداً في الموقع الصحيح لتسجيل الانصراف.\n\n$locationMessage\n$wifiMessage',
        position: position,
        bssid: bssid,
      );
    }

    // Success - at least one is valid
    print('✅ [ValidateCheckOut] Validation PASSED - WiFi: $isWifiValid, Location: $isLocationValid');
    return GeofenceValidationResult(
      isValid: true,
      message: 'تم التحقق بنجاح\n$locationMessage\n$wifiMessage',
      position: position,
      bssid: bssid,
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
