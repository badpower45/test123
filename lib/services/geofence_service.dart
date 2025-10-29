import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../database/offline_database.dart';
import 'notification_service.dart';

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
    
    // Check location every 5 minutes
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
      // Get current position with BEST accuracy and multiple attempts
      Position? position;
      int attempts = 0;
      const maxAttempts = 3;
      
      while (attempts < maxAttempts && position == null) {
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            forceAndroidLocationManager: true,
            timeLimit: const Duration(seconds: 15),
          ).timeout(const Duration(seconds: 20));
          
          // Verify accuracy is good enough (less than 50 meters)
          if (position.accuracy > 50) {
            print('[GeofenceService] Poor accuracy (${position.accuracy}m), retrying...');
            position = null;
            attempts++;
            await Future.delayed(const Duration(seconds: 2));
          } else {
            break;
          }
        } catch (e) {
          attempts++;
          print('[GeofenceService] Attempt $attempts failed: $e');
          if (attempts < maxAttempts) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }
      
      if (position == null) {
        print('[GeofenceService] Failed to get accurate location after $maxAttempts attempts');
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

      // Check WiFi BSSID if required
      bool isCorrectWifi = true;
      if (_requiredBssids.isNotEmpty) {
        try {
          final info = NetworkInfo();
          final wifiBSSID = (await info.getWifiBSSID())?.toUpperCase();
          isCorrectWifi = wifiBSSID != null && _requiredBssids.contains(wifiBSSID);
        } catch (e) {
          print('[GeofenceService] Failed to check WiFi: $e');
          isCorrectWifi = false;
        }
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
          final info = NetworkInfo();
          final wifiBSSID = (await info.getWifiBSSID())?.toUpperCase();
          return isWithinGeofence && wifiBSSID != null && requiredBssids.contains(wifiBSSID);
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
}
