import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../database/offline_database.dart';
import 'notification_service.dart';
import 'wifi_service.dart';
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

      // Check if within geofence
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

  /// --- New Method: Validate for Check-In (GPS OR WiFi - at least one must be valid) ---
  static Future<GeofenceValidationResult> validateForCheckIn(Employee employee) async {
    bool isLocationValid = false;
    bool isWifiValid = false;
    Position? position;
    String? bssid;
    String locationMessage = '';
    String wifiMessage = '';

    // 1. Try to get and validate current location
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true,
        timeLimit: const Duration(seconds: 15),
      );

      // For now, we'll use a simple distance check with hardcoded coordinates
      // TODO: Implement proper branch lookup from API
      const double branchLat = 31.2652; // Default location
      const double branchLng = 29.9863; // Default location
      const double geofenceRadius = 500.0; // Default radius

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        branchLat,
        branchLng,
      );

      if (distance <= geofenceRadius) {
        isLocationValid = true;
        locationMessage = '✅ الموقع صحيح (${distance.round()}م)';
      } else {
        locationMessage = '❌ أنت خارج نطاق الفرع (${distance.round()}م من ${geofenceRadius.round()}م)';
      }
    } catch (e) {
      locationMessage = '❌ فشل في تحديد الموقع: $e';
    }

    // 2. Try to validate WiFi BSSID
    try {
      bssid = await WiFiService.getCurrentWifiBssidValidated();
      if (bssid.isNotEmpty) {
        isWifiValid = true;
        wifiMessage = '✅ شبكة WiFi صحيحة';
      } else {
        wifiMessage = '❌ غير متصل بشبكة WiFi';
      }
    } catch (e) {
      wifiMessage = '❌ فشل في التحقق من WiFi: $e';
    }

    // 3. Check: At least ONE must be valid (OR logic)
    if (!isLocationValid && !isWifiValid) {
      return GeofenceValidationResult(
        isValid: false,
        message: 'يجب أن تكون متصلاً بشبكة الواي فاي الخاصة بالفرع أو متواجداً في الموقع الصحيح.\n\n$locationMessage\n$wifiMessage',
      );
    }

    // Success - at least one is valid
    return GeofenceValidationResult(
      isValid: true,
      message: 'تم التحقق بنجاح\n$locationMessage\n$wifiMessage',
      position: position,
      bssid: bssid,
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

    // 1. Try to get and validate current location
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true,
        timeLimit: const Duration(seconds: 15),
      );
      print('📍 [ValidateCheckOut] Location: ${position.latitude}, ${position.longitude}');

      // TODO: Get branch coordinates from API instead of hardcoded values
      const double branchLat = 31.2652; // Default location
      const double branchLng = 29.9863; // Default location
      const double geofenceRadius = 500.0; // Default radius

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        branchLat,
        branchLng,
      );

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
        // For now, accept any WiFi as valid
        // TODO: Validate against branch's allowed BSSIDs from API
        isWifiValid = true;
        wifiMessage = '✅ متصل بشبكة WiFi: $bssid';
        print('✅ [ValidateCheckOut] WiFi VALID');
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
}
