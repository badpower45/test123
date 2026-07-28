import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import '../database/offline_database.dart';
import 'notification_service.dart';
import 'wifi_service.dart';
import 'offline_data_service.dart';
import '../models/employee.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_location_service.dart';
import 'package:flutter/services.dart';
// Note: Supabase-related helpers removed; geofence is warning-only now.

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

  static List<String> _sanitizeBssidList(Iterable<dynamic> rawValues) {
    final unique = <String>{};
    for (final value in rawValues) {
      final text = value.toString().trim();
      if (text.isEmpty) continue;
      final normalized = WiFiService.normalizeBssid(text);
      if (!WiFiService.isValidBssidFormat(normalized)) continue;
      unique.add(normalized);
    }
    return unique.toList(growable: false);
  }

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
    _requiredBssids = _sanitizeBssidList(requiredBssids);

    // 🚀 PHASE 3: Request ALWAYS location permission for background tracking
    LocationPermission permission = await Geolocator.checkPermission();

    // If denied, request permission
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // After initial permission, check if we need to request "always" (background) permission
    // On Android 10+, this requires a second prompt
    if (permission == LocationPermission.whileInUse) {
      print(
        '[GeofenceService] ⚠️ Got whileInUse permission, requesting always permission for background tracking...',
      );
      // Note: On Android 10+, this will show the "Allow all the time" dialog
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      print(
        '[GeofenceService] ❌ Location permission denied - cannot track in background',
      );
      return;
    }

    if (permission == LocationPermission.whileInUse) {
      print(
        '[GeofenceService] ⚠️ Only whileInUse permission granted - background tracking may not work',
      );
      // Continue anyway - will work when app is in foreground
    } else if (permission == LocationPermission.always) {
      print(
        '[GeofenceService] ✅ Always permission granted - full background tracking enabled!',
      );
    }

    _isMonitoring = true;

    // 🚀 Directive 1: Register OS Hardware Geofence (CLCircularRegion) on iOS to survive Force-Quit
    if (!kIsWeb && Platform.isIOS) {
      try {
        const platform = MethodChannel('persistent_pulse');
        await platform.invokeMethod('startMonitoringRegion', {
          'latitude': branchLatitude,
          'longitude': branchLongitude,
          'radius': geofenceRadius,
          'identifier': 'branch_geofence_$employeeId',
        });
        print('[GeofenceService] ✅ Registered iOS Hardware CLCircularRegion monitoring!');
      } catch (e) {
        print('[GeofenceService] Failed to register iOS hardware geofence: $e');
      }
    }

    // Check location every 5 minutes (as requested)
    _locationCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkGeofence(),
    );

    // Do initial check
    await _checkGeofence();

    print('[GeofenceService] Started monitoring for employee: $employeeId');
  }

  static const MethodChannel _geofenceChannel = MethodChannel('geofence_background_channel');

  /// Initialize background geofence listener for native iOS hardware events
  static void initializeBackgroundGeofenceListener() {
    _geofenceChannel.setMethodCallHandler((call) async {
      if (call.method == 'onGeofenceRegionEvent') {
        final data = Map<String, dynamic>.from(call.arguments as Map);
        final eventType = data['eventType'] as String?;
        final regionId = data['regionId'] as String?;
        print('📍 [Native Hardware Geofence] Triggered $eventType for $regionId');

        await GeofenceService.instance.handleNativeGeofenceTrigger(eventType, regionId);
      }
    });
  }

  Future<void> handleNativeGeofenceTrigger(String? eventType, String? regionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('active_employee_id');
      final attendanceId = prefs.getString('active_attendance_id');
      final branchId = prefs.getString('active_branch_id');

      if (employeeId == null || attendanceId == null) return;

      final isEntered = eventType == 'didEnterRegion';
      String? wifiBssid;
      try {
        wifiBssid = await WiFiService.getCurrentWifiBssidValidated().timeout(const Duration(seconds: 4));
      } catch (e) {
        print('[GeofenceService] BSSID check in hardware trigger failed: $e');
      }

      await OfflineDatabase.instance.insertPendingPulse(
        employeeId: employeeId,
        attendanceId: attendanceId,
        branchId: branchId,
        timestamp: DateTime.now(),
        insideGeofence: isEntered,
        wifiBssid: wifiBssid,
        validationMethod: isEntered ? 'hardware_geofence_entry' : 'hardware_geofence_exit',
        validatedByLocation: isEntered,
        validatedByWifi: wifiBssid != null && wifiBssid.isNotEmpty,
      );

      print('✅ [Native Hardware Geofence] Saved pulse log for region $regionId ($eventType)');
    } catch (e) {
      print('❌ [Native Hardware Geofence] Error saving trigger: $e');
    }
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
          late final LocationSettings locationSettings;
          if (Platform.isAndroid) {
            locationSettings = AndroidSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 20),
            );
          } else if (Platform.isIOS) {
            locationSettings = AppleSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 8),
              allowBackgroundLocationUpdates: true,
              showBackgroundLocationIndicator: true,
              pauseLocationUpdatesAutomatically: false,
            );
          } else {
            locationSettings = const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 8),
            );
          }

          position = await Geolocator.getCurrentPosition(
            locationSettings: locationSettings,
          ).timeout(const Duration(seconds: 8));

          // Verify accuracy is acceptable (less than 100 meters for periodic checks)
          if (position.accuracy > 100) {
            print(
              '[GeofenceService] Poor accuracy (${position.accuracy}m), retrying...',
            );
            position = null;
            attempts++;
            await Future.delayed(
              const Duration(milliseconds: 1500),
            ); // Reduced delay
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
        print(
          '[GeofenceService] Failed to get location after $maxAttempts attempts',
        );
        return;
      }

      // ✅ Check if within geofence (branch coordinates first!)
      final distance = Geolocator.distanceBetween(
        _branchLatitude!,
        _branchLongitude!,
        position.latitude,
        position.longitude,
      );

      print(
        '[GeofenceService] Location check: distance=${distance.toStringAsFixed(1)}m, accuracy=${position.accuracy.toStringAsFixed(1)}m, radius=${_geofenceRadius}m',
      );

      final isWithinGeofence = distance <= _geofenceRadius!;

      // Smart WiFi checking: only check if inside geofence or close to it
      // This saves battery by not checking WiFi when employee is far away
      bool isCorrectWifi = true;
      if (_requiredBssids.isNotEmpty && distance <= (_geofenceRadius! * 1.5)) {
        try {
          final wifiBSSID = await WiFiService.getCurrentWifiBssidValidated()
              .timeout(const Duration(seconds: 4));
          isCorrectWifi = _requiredBssids.contains(wifiBSSID.toUpperCase());
          print(
            '[GeofenceService] WiFi check: BSSID=$wifiBSSID, isCorrect=$isCorrectWifi',
          );
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
        print(
          '[GeofenceService] ☕ Break is active. Skipping violation checks.',
        );
        // Reset violation counter just in case
        await prefs.setInt('consecutive_out_pulses', 0);
        await prefs.setInt(
          'last_pulse_timestamp',
          DateTime.now().millisecondsSinceEpoch,
        );
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
        print(
          '[GeofenceService] Employee within geofence (${distance.toStringAsFixed(0)}m)',
        );
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
    print(
      '[GeofenceService] ⚠️ GEOFENCE VIOLATION! Distance: ${distance.toStringAsFixed(0)}m',
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      int consecutiveOutPulses = prefs.getInt('consecutive_out_pulses') ?? 0;
      consecutiveOutPulses++;

      await prefs.setInt('consecutive_out_pulses', consecutiveOutPulses);
      await prefs.setInt(
        'last_pulse_timestamp',
        DateTime.now().millisecondsSinceEpoch,
      );

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
        // Policy change: Geofence should only warn the user. Do NOT perform
        // an automatic checkout here. The pulse-based flow will handle
        // auto-checkout when configured.
        await NotificationService.instance.showGeofenceViolation(
          employeeName: _currentEmployeeName ?? 'الموظف',
          message:
              '⛔ تم رصد مخالفة متكررة خارج نطاق الفرع. لن يتم تسجيل انصراف تلقائي.',
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

      print(
        '[GeofenceService] Violation handled (Stage $consecutiveOutPulses)',
      );
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
      late final LocationSettings _locationSettings;
      if (Platform.isAndroid) {
        _locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } else if (Platform.isIOS) {
        _locationSettings = AppleSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
          pauseLocationUpdatesAutomatically: false,
        );
      } else {
        _locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: _locationSettings,
      ).timeout(const Duration(seconds: 8));

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
          return isWithinGeofence &&
              requiredBssids.contains(wifiBSSID.toUpperCase());
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

  // _performForegroundAutoCheckout removed: geofence now issues warnings only.

  // Get monitoring status
  bool get isMonitoring => _isMonitoring;

  // Get current employee info
  String? get currentEmployeeId => _currentEmployeeId;

  /// --- New Method: Validate for Check-In (WiFi FIRST, GPS as backup, then SHIFT TIME) ---
  static Future<GeofenceValidationResult> validateForCheckIn(
    Employee employee,
  ) async {
    Position? position;
    String? bssid;

    // ⏰ STEP 0: Check Shift Time FIRST (before expensive WiFi/GPS checks)
    if (employee.shiftStartTime != null && employee.shiftEndTime != null) {
      final now = DateTime.now();
      final currentTime = TimeOfDay(hour: now.hour, minute: now.minute);

      final shiftStart = _parseTimeOfDay(employee.shiftStartTime!);
      final shiftEnd = _parseTimeOfDay(employee.shiftEndTime!);

      if (shiftStart != null && shiftEnd != null) {
        final isWithinShift = _isTimeWithinRange(
          currentTime,
          shiftStart,
          shiftEnd,
        );

        if (!isWithinShift) {
          print(
            '⏰ Outside shift time: Current=${_formatTimeOfDay(currentTime)}, Shift=${employee.shiftStartTime}-${employee.shiftEndTime}',
          );
          return GeofenceValidationResult(
            isValid: false,
            message:
                '⏰ أنت خارج موعد الشيفت\n'
                'وقت الشيفت: ${employee.shiftStartTime} - ${employee.shiftEndTime}\n'
                'الوقت الحالي: ${_formatTimeOfDay(currentTime)}\n'
                'يرجى تسجيل الحضور خلال موعد الشيفت',
          );
        }
        print(
          '✅ Within shift time: ${employee.shiftStartTime}-${employee.shiftEndTime}',
        );
      }
    }

    // Get cached branch data (employee-specific)
    Map<String, dynamic>? branchData;

    if (kIsWeb) {
      // On Web, use OfflineDataService (Hive) with employee ID
      final offlineService = OfflineDataService();
      branchData = await offlineService.getCachedBranchData(
        employeeId: employee.id,
      );
      print(
        '🌐 [Web] Loading branch data from Hive for employee: ${employee.id}',
      );
    } else {
      // On Mobile, use OfflineDatabase (SQLite)
      final db = OfflineDatabase.instance;
      branchData = await db.getCachedBranchData(employee.id);
      print(
        '📱 [Mobile] Loading branch data from SQLite for employee: ${employee.id}',
      );
    }

    // Check if we have branch data
    if (branchData == null) {
      return GeofenceValidationResult(
        isValid: false,
        message:
            '❌ لا توجد بيانات للفرع المحفوظة.\nالرجاء الاتصال بالإنترنت أولاً لتحميل بيانات الفرع.',
      );
    }

    // If employee is Super Employee, validate against all branches!
    if (employee.isSuperEmployee) {
      print('⭐ Employee ${employee.fullName} is Super Employee! Validating against all cached branches...');
      List<Map<String, dynamic>> branches = [];
      if (kIsWeb) {
        try {
          final box = Hive.isBoxOpen('branch_data') 
              ? Hive.box('branch_data') 
              : await Hive.openBox('branch_data');
          final raw = box.get('super_branches_${employee.id}');
          if (raw is List) {
            branches = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
        } catch (e) {
          print('⚠️ Failed to load super branches from Hive: $e');
        }
      } else {
        try {
          final db = OfflineDatabase.instance;
          branches = await db.getCachedSuperBranches(employee.id);
        } catch (e) {
          print('⚠️ Failed to load super branches from SQLite: $e');
        }
      }

      if (branches.isNotEmpty) {
        // ⚡ PRIORITY 1: WiFi check across all branches
        if (!kIsWeb) {
          try {
            bssid = await WiFiService.getCurrentWifiBssidValidated();
            final currentBssid = bssid.toUpperCase();
            print('📶 Super Employee WiFi check: current=$currentBssid');
            
            for (final branch in branches) {
              final List<String> allowedBssids = [];
              if (branch['wifi_bssids_array'] != null) {
                final bssidsArray = branch['wifi_bssids_array'] as List<dynamic>;
                allowedBssids.addAll(bssidsArray.map((e) => e?.toString().toUpperCase().trim()).whereType<String>());
              } else {
                final bssidValue = branch['wifi_bssids'] ?? branch['wifi_bssid'];
                if (bssidValue != null && bssidValue.toString().isNotEmpty) {
                  allowedBssids.addAll(
                    bssidValue.toString().split(',').map((e) => e.toUpperCase().trim()).where((value) => value.isNotEmpty),
                  );
                }
              }
              
              if (allowedBssids.contains(currentBssid)) {
                final matchedBranchId = branch['branch_id']?.toString() ?? branch['id']?.toString();
                final matchedBranchName = branch['branch_name']?.toString() ?? branch['name']?.toString() ?? '';
                print('✅ WiFi MATCH with branch: $matchedBranchName');
                return GeofenceValidationResult(
                  isValid: true,
                  message: '✅ متصل بشبكة الفرع ($matchedBranchName)\nتم التحقق فوراً',
                  position: null,
                  bssid: bssid,
                  branchId: matchedBranchId,
                  distance: 0.0,
                );
              }
            }
          } catch (e) {
            print('⚠️ WiFi check for super employee failed or skipped: $e');
          }
        }

        // ⚡ PRIORITY 2: GPS check across all branches
        try {
          position = await NativeLocationService.getCurrentLocation();
          if (position != null) {
            print('📍 Super Employee GPS: ${position.latitude}, ${position.longitude}');
            
            Map<String, dynamic>? closestBranch;
            double minDistance = double.infinity;
            double closestRadius = 100.0;

            for (final branch in branches) {
              final double? branchLat = (branch['latitude'] ?? branch['branch_latitude'])?.toDouble();
              final double? branchLng = (branch['longitude'] ?? branch['branch_longitude'])?.toDouble();
              final double radius = (branch['geofence_radius'] ?? branch['geofenceRadius'] ?? 100).toDouble();

              if (branchLat != null && branchLng != null) {
                final distance = Geolocator.distanceBetween(
                  branchLat,
                  branchLng,
                  position.latitude,
                  position.longitude,
                );

                if (distance < minDistance) {
                  minDistance = distance;
                  closestBranch = branch;
                  closestRadius = radius;
                }

                if (distance <= radius) {
                  final matchedBranchId = branch['branch_id']?.toString() ?? branch['id']?.toString();
                  final matchedBranchName = branch['branch_name']?.toString() ?? branch['name']?.toString() ?? '';
                  print('✅ GPS MATCH inside geofence of branch: $matchedBranchName');
                  return GeofenceValidationResult(
                    isValid: true,
                    message: '✅ الموقع صحيح\n(${matchedBranchName} - ${distance.round()}م)',
                    position: position,
                    bssid: bssid,
                    branchId: matchedBranchId,
                    distance: distance,
                  );
                }
              }
            }

            // If we checked GPS but none was close enough
            if (closestBranch != null) {
              final closestBranchId = closestBranch['branch_id']?.toString() ?? closestBranch['id']?.toString();
              final closestBranchName = closestBranch['branch_name']?.toString() ?? closestBranch['name']?.toString() ?? '';
              return GeofenceValidationResult(
                isValid: false,
                message: '❌ أنت خارج نطاق جميع الفروع المتاحة\n'
                    'أقرب فرع لك: $closestBranchName\n'
                    'المسافة له: ${minDistance.round()}م (المسموح: ${closestRadius.round()}م)\n'
                    'يرجى الاقتراب من موقع أي فرع أو الاتصال بشبكة WiFi الخاصة به',
                branchId: closestBranchId,
                distance: minDistance,
              );
            }
          }
        } catch (gpsErr) {
          print('❌ GPS check for super employee failed: $gpsErr');
        }

        // If GPS failed and WiFi failed
        return GeofenceValidationResult(
          isValid: false,
          message: '❌ فشل التحقق للموظف السوبر\nلم نتمكن من مطابقة موقعك أو شبكة WiFi مع أي فرع متاح.',
        );
      }
    }

    // ✅ FIX: Check multiple possible keys for branch_id
    final String? branchId =
        branchData['branch_id']?.toString() ??
        branchData['id']?.toString() ??
        branchData['branchId']?.toString();

    print('🏢 Branch ID resolved: $branchId');

    final double? branchLat = branchData['latitude']?.toDouble();
    final double? branchLng = branchData['longitude']?.toDouble();
    final double geofenceRadius = (branchData['geofence_radius'] ?? 100)
        .toDouble();

    // Get array of allowed BSSIDs
    final List<String> allowedBssids = [];

    if (kIsWeb) {
      // On Web, single BSSID
      final bssidValue = branchData['bssid'];
      if (bssidValue != null && bssidValue.toString().isNotEmpty) {
        allowedBssids.addAll(
          _sanitizeBssidList(bssidValue.toString().split(',')),
        );
      }
    } else {
      // On Mobile, array of BSSIDs
      if (branchData['wifi_bssids_array'] != null) {
        final bssidsArray = branchData['wifi_bssids_array'] as List<dynamic>;
        allowedBssids.addAll(_sanitizeBssidList(bssidsArray));
      } else {
        final bssidValue = branchData['wifi_bssid'];
        if (bssidValue != null && bssidValue.toString().isNotEmpty) {
          allowedBssids.addAll(
            _sanitizeBssidList(bssidValue.toString().split(',')),
          );
        }
      }
    }

    print(
      '🔍 Branch: lat=$branchLat, lng=$branchLng, radius=$geofenceRadius, bssids=$allowedBssids',
    );

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
        // Use NativeLocationService for fast retrieval + robust fallbacks
        position = await NativeLocationService.getCurrentLocation();
        if (position == null) {
          throw Exception('Failed to get GPS location');
        }

        print('📍 Current: ${position.latitude}, ${position.longitude}');
        print('📍 Branch: $branchLat, $branchLng');

        final distance = Geolocator.distanceBetween(
          branchLat,
          branchLng,
          position.latitude,
          position.longitude,
        );

        print(
          '📏 Distance: ${distance.toStringAsFixed(1)}m (Radius: ${geofenceRadius.toStringAsFixed(1)}m)',
        );

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
            message:
                '❌ أنت خارج نطاق الفرع\n'
                'المسافة: ${distance.round()}م (المسموح: ${geofenceRadius.round()}م)\n'
                'يرجى الاقتراب من موقع العمل أو الاتصال بشبكة WiFi الخاصة بالفرع',
            branchId: branchId,
            distance: distance,
          );
        }
      } catch (e) {
        print('❌ GPS error: $e');
        return GeofenceValidationResult(
          isValid: false,
          message:
              '❌ فشل التحقق\n'
              'لم نتمكن من التحقق من موقعك أو شبكة WiFi\n'
              'تأكد من تفعيل GPS والاتصال بشبكة الفرع',
          branchId: branchId,
        );
      }
    }

    // Both failed
    return GeofenceValidationResult(
      isValid: false,
      message:
          '❌ فشل التحقق\n'
          'يرجى التأكد من:\n'
          '• الاتصال بشبكة WiFi الخاصة بالفرع\n'
          '• أو التواجد في موقع الفرع مع تفعيل GPS',
      branchId: branchId,
    );
  }

  /// ✅ UNIFIED: Validation for both Check-In and Check-Out
  /// Same logic - WiFi OR GPS (flexible and reliable)
  static Future<GeofenceValidationResult> validateForAttendance(
    Employee employee, {
    required String type, // 'check-in' or 'check-out'
  }) async {
    print(
      '🔍 [Validate${type == 'check-in' ? 'CheckIn' : 'CheckOut'}] Starting validation for employee: ${employee.id}',
    );

    // Shift time validation (check-in only)
    if (type == 'check-in') {
      // Check if shift times are set
      if (employee.shiftStartTime != null && employee.shiftEndTime != null) {
        final now = TimeOfDay.now();
        final nowMinutes = now.hour * 60 + now.minute;

        // Parse shift times from strings
        final shiftStart = _parseTimeOfDay(employee.shiftStartTime!);
        final shiftEnd = _parseTimeOfDay(employee.shiftEndTime!);

        if (shiftStart == null || shiftEnd == null) {
          print('⚠️ Invalid shift time format');
          // Continue with location validation
        } else {
          final shiftStartMinutes = shiftStart.hour * 60 + shiftStart.minute;
          final shiftEndMinutes = shiftEnd.hour * 60 + shiftEnd.minute;

          // Allow check-in from 1 hour before shift start to shift end
          final earlyCheckInMinutes = shiftStartMinutes - 60;

          bool isWithinShiftTime = false;
          if (shiftStartMinutes < shiftEndMinutes) {
            // Same day shift
            isWithinShiftTime =
                nowMinutes >= earlyCheckInMinutes &&
                nowMinutes <= shiftEndMinutes;
          } else {
            // Night shift (crosses midnight)
            isWithinShiftTime =
                nowMinutes >= earlyCheckInMinutes ||
                nowMinutes <= shiftEndMinutes;
          }

          if (!isWithinShiftTime) {
            print(
              '❌ Outside shift time: ${employee.shiftStartTime}-${employee.shiftEndTime}',
            );
            return GeofenceValidationResult(
              isValid: false,
              message:
                  'لا يمكن تسجيل الحضور خارج موعد شيفتك\n'
                  'يرجى تسجيل الحضور خلال موعد الشيفت',
            );
          }
          print(
            '✅ Within shift time: ${employee.shiftStartTime}-${employee.shiftEndTime}',
          );
        }
      }
    }

    Position? position;
    String? bssid;

    // Get cached branch data
    Map<String, dynamic>? branchData;

    if (kIsWeb) {
      final offlineService = OfflineDataService();
      branchData = await offlineService.getCachedBranchData(
        employeeId: employee.id,
      );
      print(
        '🌐 [Web] Loading branch data from Hive for employee: ${employee.id}',
      );
    } else {
      final db = OfflineDatabase.instance;
      branchData = await db.getCachedBranchData(employee.id);
      print(
        '📱 [Mobile] Loading branch data from SQLite for employee: ${employee.id}',
      );
    }

    // Check if we have branch data
    if (branchData == null) {
      return GeofenceValidationResult(
        isValid: false,
        message:
            '❌ لا توجد بيانات للفرع المحفوظة.\nالرجاء الاتصال بالإنترنت أولاً لتحميل بيانات الفرع.',
      );
    }

    // If employee is Super Employee, validate against all branches!
    if (employee.isSuperEmployee) {
      print('⭐ Employee ${employee.fullName} is Super Employee! Validating against all cached branches...');
      List<Map<String, dynamic>> branches = [];
      if (kIsWeb) {
        try {
          final box = Hive.isBoxOpen('branch_data') 
              ? Hive.box('branch_data') 
              : await Hive.openBox('branch_data');
          final raw = box.get('super_branches_${employee.id}');
          if (raw is List) {
            branches = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
        } catch (e) {
          print('⚠️ Failed to load super branches from Hive: $e');
        }
      } else {
        try {
          final db = OfflineDatabase.instance;
          branches = await db.getCachedSuperBranches(employee.id);
        } catch (e) {
          print('⚠️ Failed to load super branches from SQLite: $e');
        }
      }

      if (branches.isNotEmpty) {
        // ⚡ PRIORITY 1: WiFi check across all branches
        if (!kIsWeb) {
          try {
            bssid = await WiFiService.getCurrentWifiBssidValidated();
            final currentBssid = bssid.toUpperCase();
            print('📶 Super Employee WiFi check: current=$currentBssid');
            
            for (final branch in branches) {
              final List<String> allowedBssids = [];
              if (branch['wifi_bssids_array'] != null) {
                final bssidsArray = branch['wifi_bssids_array'] as List<dynamic>;
                allowedBssids.addAll(bssidsArray.map((e) => e?.toString().toUpperCase().trim()).whereType<String>());
              } else {
                final bssidValue = branch['wifi_bssids'] ?? branch['wifi_bssid'];
                if (bssidValue != null && bssidValue.toString().isNotEmpty) {
                  allowedBssids.addAll(
                    bssidValue.toString().split(',').map((e) => e.toUpperCase().trim()).where((value) => value.isNotEmpty),
                  );
                }
              }
              
              if (allowedBssids.contains(currentBssid)) {
                final matchedBranchId = branch['branch_id']?.toString() ?? branch['id']?.toString();
                final matchedBranchName = branch['branch_name']?.toString() ?? branch['name']?.toString() ?? '';
                print('✅ WiFi MATCH with branch: $matchedBranchName');
                return GeofenceValidationResult(
                  isValid: true,
                  message: '✅ متصل بشبكة الفرع ($matchedBranchName)\nتم التحقق فوراً',
                  position: null,
                  bssid: bssid,
                  branchId: matchedBranchId,
                  distance: 0.0,
                );
              }
            }
          } catch (e) {
            print('⚠️ WiFi check for super employee failed or skipped: $e');
          }
        }

        // ⚡ PRIORITY 2: GPS check across all branches
        try {
          position = await NativeLocationService.getCurrentLocation();
          if (position != null) {
            print('📍 Super Employee GPS: ${position.latitude}, ${position.longitude}');
            
            Map<String, dynamic>? closestBranch;
            double minDistance = double.infinity;
            double closestRadius = 100.0;

            for (final branch in branches) {
              final double? branchLat = (branch['latitude'] ?? branch['branch_latitude'])?.toDouble();
              final double? branchLng = (branch['longitude'] ?? branch['branch_longitude'])?.toDouble();
              final double radius = (branch['geofence_radius'] ?? branch['geofenceRadius'] ?? 100).toDouble();

              if (branchLat != null && branchLng != null) {
                final distance = Geolocator.distanceBetween(
                  branchLat,
                  branchLng,
                  position.latitude,
                  position.longitude,
                );

                if (distance < minDistance) {
                  minDistance = distance;
                  closestBranch = branch;
                  closestRadius = radius;
                }

                if (distance <= radius) {
                  final matchedBranchId = branch['branch_id']?.toString() ?? branch['id']?.toString();
                  final matchedBranchName = branch['branch_name']?.toString() ?? branch['name']?.toString() ?? '';
                  print('✅ GPS MATCH inside geofence of branch: $matchedBranchName');
                  return GeofenceValidationResult(
                    isValid: true,
                    message: '✅ الموقع صحيح\n(${matchedBranchName} - ${distance.round()}م)',
                    position: position,
                    bssid: bssid,
                    branchId: matchedBranchId,
                    distance: distance,
                  );
                }
              }
            }

            // If we checked GPS but none was close enough
            if (closestBranch != null) {
              final closestBranchId = closestBranch['branch_id']?.toString() ?? closestBranch['id']?.toString();
              final closestBranchName = closestBranch['branch_name']?.toString() ?? closestBranch['name']?.toString() ?? '';
              return GeofenceValidationResult(
                isValid: false,
                message: '❌ أنت خارج نطاق جميع الفروع المتاحة\n'
                    'أقرب فرع لك: $closestBranchName\n'
                    'المسافة له: ${minDistance.round()}م (المسموح: ${closestRadius.round()}م)\n'
                    'يرجى الاقتراب من موقع أي فرع أو الاتصال بشبكة WiFi الخاصة به',
                branchId: closestBranchId,
                distance: minDistance,
              );
            }
          }
        } catch (gpsErr) {
          print('❌ GPS check for super employee failed: $gpsErr');
        }

        // If GPS failed and WiFi failed
        return GeofenceValidationResult(
          isValid: false,
          message: '❌ فشل التحقق للموظف السوبر\nلم نتمكن من مطابقة موقعك أو شبكة WiFi مع أي فرع متاح.',
        );
      }
    }

    final String? branchId =
        branchData['branch_id']?.toString() ??
        branchData['id']?.toString() ??
        branchData['branchId']?.toString();

    print('🏢 Branch ID resolved: $branchId');

    final double? branchLat = branchData['latitude']?.toDouble();
    final double? branchLng = branchData['longitude']?.toDouble();
    final double geofenceRadius = (branchData['geofence_radius'] ?? 100)
        .toDouble();

    // Get array of allowed BSSIDs
    final List<String> allowedBssids = [];

    if (kIsWeb) {
      final bssidValue = branchData['bssid'];
      if (bssidValue != null && bssidValue.toString().isNotEmpty) {
        allowedBssids.addAll(
          _sanitizeBssidList(bssidValue.toString().split(',')),
        );
      }
    } else {
      if (branchData['wifi_bssids_array'] != null) {
        final bssidsArray = branchData['wifi_bssids_array'] as List<dynamic>;
        allowedBssids.addAll(_sanitizeBssidList(bssidsArray));
      } else {
        final bssidValue = branchData['wifi_bssid'];
        if (bssidValue != null && bssidValue.toString().isNotEmpty) {
          allowedBssids.addAll(
            _sanitizeBssidList(bssidValue.toString().split(',')),
          );
        }
      }
    }

    print(
      '🔍 Branch: lat=$branchLat, lng=$branchLng, radius=$geofenceRadius, bssids=$allowedBssids',
    );

    // ⚡ PRIORITY 1: Check WiFi FIRST (fastest and most reliable)
    if (allowedBssids.isNotEmpty && !kIsWeb) {
      try {
        bssid = await WiFiService.getCurrentWifiBssidValidated();
        final currentBssid = bssid.toUpperCase();

        print('📶 Current WiFi: $currentBssid');
        print('📋 Allowed WiFi: $allowedBssids');

        if (allowedBssids.contains(currentBssid)) {
          print('✅ WiFi MATCH! ${type} approved instantly');
          return GeofenceValidationResult(
            isValid: true,
            message: '✅ متصل بشبكة الفرع\nتم التحقق فوراً',
            position: null,
            bssid: bssid,
            branchId: branchId,
            distance: 0.0,
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
            // Use same radius for both check-in and check-out
            if (lastDistance <= geofenceRadius * 1.2) {
              print(
                '✅ Using last known: ${lastPos.latitude}, ${lastPos.longitude} (distance ${lastDistance.toStringAsFixed(1)}m)',
              );
              return GeofenceValidationResult(
                isValid: true,
                message:
                    '✅ الموقع صحيح (موقع محفوظ)\n(${lastDistance.round()}م)',
                position: lastPos,
                branchId: branchId,
                distance: lastDistance,
              );
            }
          }
        } catch (e) {
          print('⚠️ Last known unavailable: $e');
        }

        // Use NativeLocationService for fast retrieval + robust fallbacks
        position = await NativeLocationService.getCurrentLocation();
        if (position == null) {
          throw Exception('Failed to get GPS location');
        }

        print('📍 Location: ${position.latitude}, ${position.longitude}');
        print('📍 Accuracy: ${position.accuracy.toStringAsFixed(1)}m');

        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          branchLat,
          branchLng,
        );

        print(
          '📏 Distance: ${distance.round()}m (max: ${geofenceRadius.round()}m)',
        );

        // ✅ UNIFIED: Same radius for both check-in and check-out (strict)
        if (distance <= geofenceRadius) {
          print('✅ Location VALID: ${distance.round()}m');
          return GeofenceValidationResult(
            isValid: true,
            message: '✅ الموقع صحيح (${distance.round()}م)',
            position: position,
            branchId: branchId,
            distance: distance,
          );
        } else {
          print(
            '❌ Location INVALID: ${distance.round()}m > ${geofenceRadius.round()}m',
          );
          return GeofenceValidationResult(
            isValid: false,
            message:
                '❌ خارج نطاق الفرع\n'
                'المسافة: ${distance.round()}م\n'
                'المسموح: ${geofenceRadius.round()}م',
            branchId: branchId,
            distance: distance,
          );
        }
      } catch (e) {
        print('❌ GPS error: $e');
        return GeofenceValidationResult(
          isValid: false,
          message:
              '❌ فشل تحديد الموقع\n'
              'يرجى:\n'
              '• تفعيل خدمات الموقع (GPS)\n'
              '• أو الاتصال بشبكة WiFi الخاصة بالفرع',
          branchId: branchId,
        );
      }
    }

    // If no GPS coordinates configured, fail
    return GeofenceValidationResult(
      isValid: false,
      message:
          '❌ لا يمكن التحقق من الموقع\n'
          'يرجى:\n'
          '• الاتصال بشبكة WiFi الخاصة بالفرع\n'
          '• أو التواجد في موقع الفرع مع تفعيل GPS',
      branchId: branchId,
    );
  }

  /// --- Legacy Check-Out wrapper (calls unified validation) ---
  static Future<GeofenceValidationResult> validateForCheckOut(
    Employee employee,
  ) async {
    print(
      '🔍 [ValidateCheckOut] Bypassing geofence check for checkout. Allowed from anywhere.',
    );
    return GeofenceValidationResult(
      isValid: true,
      message: '✅ تسجيل الانصراف مقبول من أي مكان',
      position: null,
      bssid: null,
      distance: 0.0,
      branchId: null,
    );
  }

  /// --- DEPRECATED: Old validateForCheckOut implementation below (kept for reference) ---
  /*
  static Future<GeofenceValidationResult> _oldValidateForCheckOut(Employee employee) async {
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

    if (branchData == null) {
      print('⚠️ [ValidateCheckOut] No branch data - allowing checkout anyway');
      return GeofenceValidationResult(
        isValid: true,
        message: '✅ تسجيل الانصراف (بدون تحقق من الموقع)',
        position: null,
      );
    }
    // ... rest of old implementation
  }
  */

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
  static bool _isTimeWithinRange(
    TimeOfDay current,
    TimeOfDay start,
    TimeOfDay end,
  ) {
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
