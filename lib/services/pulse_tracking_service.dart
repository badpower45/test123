import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/offline_database.dart';
import 'native_location_service.dart'; // 🚀 Native GPS for faster location
import 'offline_data_service.dart';
import 'notification_service.dart';
import 'foreground_attendance_service.dart';
import 'supabase_attendance_service.dart';
import 'wifi_service.dart';
import 'app_logger.dart';

/// 🚨 Auto-checkout event data for UI updates
class AutoCheckoutEvent {
  final DateTime timestamp;
  final String reason;
  final double? distance;
  final bool savedOffline;

  AutoCheckoutEvent({
    required this.timestamp,
    required this.reason,
    this.distance,
    this.savedOffline = false,
  });
}

/// 🎯 نظام النبضات البسيط والواضح
///
/// الوظيفة:
/// 1. نبضة كل 5 دقائق بالضبط ✅
/// 2. كل نبضة تفحص الموقع: جوا الدائرة = true، برا = false ✅
/// 3. لو 2 نبضة false متتالية → auto check-out تلقائي ✅
/// 4. حفظ البيانات: Flutter (local) + السيرفر (online) ✅
/// 5. التحذيرات: نبضة false أولى = تحذير، نبضة false ثانية = انصراف تلقائي ✅
/// 6. ✅ NEW: أثناء الاستراحة المعتمدة (ACTIVE break) - النبضات تُسجل true دائماً
/// 7. ✅ NEW: Stream event للـ UI عند حدوث auto-checkout
class PulseTrackingService extends ChangeNotifier {
  static final PulseTrackingService _instance =
      PulseTrackingService._internal();
  factory PulseTrackingService() => _instance;
  PulseTrackingService._internal();

  // ⚙️ المتغيرات الأساسية
  Timer? _pulseTimer;
  bool _isTracking = false;
  DateTime? _lastPulseTime;
  int _pulsesCount = 0;
  String? _currentAttendanceId;
  String? _currentEmployeeId;
  Map<String, dynamic>? _currentBranchData;
  bool _isSendingPulse = false;

  // 🎯 تتبع النبضات الـ false
  final List<Map<String, dynamic>> _recentPulses = []; // آخر نبضتين

  final _offlineService = OfflineDataService();

  // نبضة كل 5 دقائق بالضبط
  static const Duration _pulseInterval = Duration(minutes: 5);
  static const Duration _maxLocationSampleAge = Duration(minutes: 5);
  static const double _minReliableGpsAccuracyMeters = 120.0;

  // 🚨 NEW: Auto-checkout event stream for UI updates
  final StreamController<AutoCheckoutEvent> _autoCheckoutController =
      StreamController<AutoCheckoutEvent>.broadcast();
  Stream<AutoCheckoutEvent> get onAutoCheckout =>
      _autoCheckoutController.stream;

  // Flag to track if auto-checkout happened
  bool _autoCheckoutTriggered = false;
  bool get autoCheckoutTriggered => _autoCheckoutTriggered;

  // Getters
  bool get isTracking => _isTracking;
  DateTime? get lastPulseTime => _lastPulseTime;
  int get pulsesCount => _pulsesCount;

  /// Start pulse tracking
  Future<void> startTracking(String employeeId, {String? attendanceId}) async {
    if (_isTracking) {
      print('Pulse tracking already running for employee: $employeeId');
      return;
    }

    print('🎯 Starting pulse tracking for employee: $employeeId');

    // Initialize notification service
    try {
      await NotificationService.instance.initialize();
      print('✅ Notification service initialized');
    } catch (e) {
      print('⚠️ Failed to initialize notifications: $e');
    }

    _currentAttendanceId = attendanceId;
    _currentEmployeeId = employeeId;

    // Load branch data
    final branchData = await _offlineService.getCachedBranchData(
      employeeId: employeeId,
    );
    if (branchData == null) {
      print('Cannot start tracking: Branch data not available');
      return;
    }

    print('Branch data loaded: ${branchData['name']}');
    print('Location: ${branchData['latitude']}, ${branchData['longitude']}');
    print('Radius: ${branchData['geofence_radius']}m');

    _isTracking = true;
    _currentBranchData = branchData;
    _lastPulseTime = DateTime.now();
    _recentPulses.clear();
    await _persistTrackingContext();

    // ✅ بدل ما نبدأ من صفر، نجيب العدد من قاعدة البيانات
    final stats = await getTrackingStats(employeeId);
    _pulsesCount = stats['total_pulses'] ?? 0;
    print('📊 استئناف تتبع النبضات: عدد النبضات الحالي = $_pulsesCount');

    notifyListeners();

    // Send first pulse immediately
    await _sendPulse();

    // Schedule pulses every 5 minutes
    _pulseTimer = Timer.periodic(_pulseInterval, (timer) async {
      await _sendPulse();
    });

    print('Pulse tracking started (every ${_pulseInterval.inMinutes} minutes)');
  }

  /// Stop pulse tracking
  Future<void> stopTracking({bool fromAutoCheckout = false}) async {
    if (!_isTracking && !fromAutoCheckout) {
      print('Pulse tracking not active');
      return;
    }

    _pulseTimer?.cancel();
    _pulseTimer = null;
    _isTracking = false;
    _lastPulseTime = null;
    _pulsesCount = 0;
    _recentPulses.clear();
    _currentBranchData = null;
    _currentEmployeeId = null;
    await _clearTrackingContext();

    // Reset auto-checkout flag when manually stopped (not from auto-checkout)
    if (!fromAutoCheckout) {
      _autoCheckoutTriggered = false;
    }

    notifyListeners();

    print(
      'Pulse tracking stopped${fromAutoCheckout ? " (auto-checkout)" : ""}',
    );
  }

  /// Send a single pulse
  /// ✅ NEW LOGIC: Wi-Fi Priority + Break Override
  /// 0. ✅ Check if employee is on ACTIVE break - if yes, pulse = TRUE always
  /// 1. Check Wi-Fi FIRST - if valid BSSID = TRUE immediately (no GPS needed)
  /// 2. If Wi-Fi invalid/not connected, check GPS
  /// 3. If GPS disabled = FALSE (distance = 0)
  Future<void> _sendPulse() async {
    if (_isSendingPulse) {
      print('Pulse already in progress - skipping');
      return;
    }

    if (_currentEmployeeId == null || _currentBranchData == null) {
      print('Incomplete data - cannot send pulse');
      return;
    }

    _isSendingPulse = true;

    try {
      // ✅ STEP 0: Check if employee is on ACTIVE break
      bool isOnActiveBreak = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        isOnActiveBreak = prefs.getBool('is_break_active') ?? false;

        // ✅ Double-check with database if cached value says active
        if (isOnActiveBreak) {
          final activeBreak = await SupabaseAttendanceService.getActiveBreak(
            _currentEmployeeId!,
          );
          isOnActiveBreak = activeBreak != null;

          // Update cache if database says different
          if (!isOnActiveBreak) {
            await prefs.setBool('is_break_active', false);
            await prefs.remove('active_break_id');
            print('☕ Break cache corrected: was active, now inactive');
          }
        }
      } catch (e) {
        print('⚠️ Failed to check break status: $e');
      }

      // Get branch center location
      final centerLat = _currentBranchData!['latitude'] as double?;
      final centerLng = _currentBranchData!['longitude'] as double?;

      if (centerLat == null || centerLng == null) {
        print('Invalid branch location data');
        return;
      }

      // ✅ If on active break, always send TRUE pulse
      if (isOnActiveBreak) {
        print(
          '☕ Pulse #${_pulsesCount + 1}: TRUE (Active Break - Skipping all validation)',
        );

        final timestamp = DateTime.now();
        final branchId =
            (_currentBranchData!['id'] ?? _currentBranchData!['branch_id'])
                as String?;

        // Save pulse as TRUE (break override) with branch location
        await _offlineService.saveLocalPulse(
          employeeId: _currentEmployeeId!,
          attendanceId: _currentAttendanceId,
          timestamp: timestamp,
          latitude: centerLat, // ✅ Use branch center
          longitude: centerLng, // ✅ Use branch center
          insideGeofence: true, // ✅ Always true during break
          distanceFromCenter: 0.0,
          wifiBssid: null,
          validatedByWifi: false,
          validatedByLocation: false,
          branchId: branchId,
        );

        // Update pulse data
        final pulseData = {
          'inside_geofence': true,
          'distance': 0.0,
          'timestamp': timestamp,
          'validated_by_break': true,
        };

        _recentPulses.add(pulseData);
        if (_recentPulses.length > 2) {
          _recentPulses.removeAt(0);
        }

        _pulsesCount++;
        _lastPulseTime = timestamp;

        // ✅ تحديث العداد من قاعدة البيانات لضمان الدقة
        final updatedStats = await getTrackingStats(_currentEmployeeId!);
        _pulsesCount = updatedStats['total_pulses'] ?? _pulsesCount;

        notifyListeners();

        return; // Done - break override applied
      }

      // centerLat and centerLng already defined above for break override
      final baseRadius =
          (_currentBranchData!['geofence_radius'] as num?)?.toDouble() ?? 100.0;
      final extraTolerance =
          ((_currentBranchData!['distance_from_radius'] as num?)?.toDouble() ??
                  0.0)
              .clamp(0.0, 500.0);
      final radius = baseRadius + extraTolerance;

      // ✅ STEP 1: Check Wi-Fi FIRST (Priority)
      String? wifiBssid;
      bool wifiValidated = false;
      final requiredBssids = _extractRequiredBssids(_currentBranchData!);

      if (requiredBssids.isNotEmpty) {
        try {
          wifiBssid = await WiFiService.getCurrentWifiBssidValidated();
          wifiValidated =
              wifiBssid.isNotEmpty &&
              requiredBssids.contains(WiFiService.normalizeBssid(wifiBssid));
          print(
            '📶 Wi-Fi: $wifiBssid (${wifiValidated ? "✅ valid" : "❌ invalid"})',
          );

          if (wifiValidated) {
            final timestamp = DateTime.now();
            final branchId =
                (_currentBranchData!['id'] ?? _currentBranchData!['branch_id'])
                    as String?;

            await _recordWifiValidatedPulse(
              timestamp: timestamp,
              wifiBssid: wifiBssid,
              centerLat: centerLat,
              centerLng: centerLng,
              branchId: branchId,
              reason: 'Valid branch Wi-Fi',
            );
            return; // Done - no need for GPS
          }
        } catch (e) {
          print('⚠️ Wi-Fi check error: $e');
        }
      }

      // ✅ STEP 2: Wi-Fi failed or not available - Check GPS
      print('📍 Wi-Fi not valid - checking GPS location (Native)...');

      // Check if location services are enabled (using Native GPS - much faster!)
      final locationEnabled = await NativeLocationService.getCurrentLocation();

      if (locationEnabled == null) {
        final fallbackWifiBssid = await _validateWithFallbackWifi(
          requiredBssids,
        );
        if (fallbackWifiBssid != null) {
          final timestamp = DateTime.now();
          final branchId =
              (_currentBranchData!['id'] ?? _currentBranchData!['branch_id'])
                  as String?;

          await _recordWifiValidatedPulse(
            timestamp: timestamp,
            wifiBssid: fallbackWifiBssid,
            centerLat: centerLat,
            centerLng: centerLng,
            branchId: branchId,
            reason: 'Fallback branch Wi-Fi after GPS unavailable',
          );
          return;
        }

        // GPS disabled or no permission = FALSE pulse
        print(
          '❌ Pulse #${_pulsesCount + 1}: FALSE (GPS disabled or no permission)',
        );

        final timestamp = DateTime.now();
        final branchId =
            (_currentBranchData!['id'] ?? _currentBranchData!['branch_id'])
                as String?;

        await _offlineService.saveLocalPulse(
          employeeId: _currentEmployeeId!,
          attendanceId: _currentAttendanceId,
          timestamp: timestamp,
          latitude: null,
          longitude: null,
          insideGeofence: false,
          distanceFromCenter: 0.0,
          wifiBssid: wifiBssid,
          validatedByWifi: false,
          validatedByLocation: false,
          branchId: branchId,
        );

        // Update pulse data
        final pulseData = {
          'inside_geofence': false,
          'distance': 0.0,
          'timestamp': timestamp,
        };

        _recentPulses.add(pulseData);
        if (_recentPulses.length > 2) {
          _recentPulses.removeAt(0);
        }

        _pulsesCount++;
        _lastPulseTime = timestamp;

        // ✅ تحديث العداد من قاعدة البيانات لضمان الدقة
        final updatedStats = await getTrackingStats(_currentEmployeeId!);
        _pulsesCount = updatedStats['total_pulses'] ?? _pulsesCount;

        // Send warning notification
        await NotificationService.instance.showGeofenceViolation(
          employeeName: 'الموظف',
          message: '⚠️ تحذير: GPS مغلق!\nيجب تفعيل الموقع للتحقق من تواجدك',
        );

        // Check for auto-checkout
        await _checkForAutoCheckout();
        notifyListeners();
        return;
      }

      // ✅ STEP 3: GPS is enabled - validate geofence (Native GPS - 1-3s instead of 15-30s!)
      final result = await NativeLocationService.getLocationForGeofence(
        centerLat: centerLat,
        centerLng: centerLng,
        radiusMeters: radius,
      );

      if (result == null) {
        print('Could not get location');
        return;
      }

      final bool isInsideGeofence = result['inside_geofence'] as bool;
      final double distance = result['distance'] as double;
      final double latitude = result['latitude'] as double;
      final double longitude = result['longitude'] as double;
        final double gpsAccuracy =
          (result['accuracy'] as num?)?.toDouble() ?? 999.0;
      final DateTime timestamp = result['timestamp'] is DateTime
          ? result['timestamp'] as DateTime
          : DateTime.parse(result['timestamp'] as String);
      bool effectiveInsideGeofence = isInsideGeofence;
      double effectiveDistance = distance;
      double effectiveLatitude = latitude;
      double effectiveLongitude = longitude;
      String? effectiveWifiBssid = wifiBssid;
      bool effectiveWifiValidated = wifiValidated;
      bool effectiveValidatedByLocation = isInsideGeofence;
      final bool staleLocation =
          DateTime.now().difference(timestamp).abs() > _maxLocationSampleAge;
      final bool weakAccuracy = gpsAccuracy > _minReliableGpsAccuracyMeters;

      // Guardrail: if Wi-Fi is unavailable and GPS sample is unreliable, do not
      // penalize this pulse to avoid false auto-checkout while user is inside.
      if (!effectiveInsideGeofence && !wifiValidated && (staleLocation || weakAccuracy)) {
        effectiveInsideGeofence = true;
        effectiveDistance = 0.0;
        effectiveLatitude = centerLat;
        effectiveLongitude = centerLng;
        effectiveValidatedByLocation = false;
        print(
          '⚠️ Ignoring unreliable GPS sample (accuracy: ${gpsAccuracy.toStringAsFixed(1)}m, stale: $staleLocation)',
        );
      }

      if (!effectiveInsideGeofence) {
        final fallbackWifiBssid = await _validateWithFallbackWifi(
          requiredBssids,
        );
        if (fallbackWifiBssid != null) {
          effectiveInsideGeofence = true;
          effectiveDistance = 0.0;
          effectiveLatitude = centerLat;
          effectiveLongitude = centerLng;
          effectiveWifiBssid = fallbackWifiBssid;
          effectiveWifiValidated = true;
          effectiveValidatedByLocation = false;
          print('✅ Branch Wi-Fi fallback corrected false GPS pulse');
        }
      }

      // Save pulse
      final branchId =
          (_currentBranchData!['id'] ?? _currentBranchData!['branch_id'])
              as String?;

      await _offlineService.saveLocalPulse(
        employeeId: _currentEmployeeId!,
        attendanceId: _currentAttendanceId,
        timestamp: timestamp,
        latitude: effectiveLatitude,
        longitude: effectiveLongitude,
        insideGeofence: effectiveInsideGeofence,
        distanceFromCenter: effectiveDistance,
        wifiBssid: effectiveWifiBssid,
        validatedByWifi: effectiveWifiValidated,
        validatedByLocation: effectiveValidatedByLocation,
        branchId: branchId,
      );

      // Save to recent pulses list (keep last 2)
      final pulseData = {
        'inside_geofence': effectiveInsideGeofence,
        'distance': effectiveDistance,
        'timestamp': timestamp,
        'latitude': effectiveLatitude,
        'longitude': effectiveLongitude,
      };

      _recentPulses.add(pulseData);
      if (_recentPulses.length > 2) {
        _recentPulses.removeAt(0); // Keep only last 2 pulses
      }

      _pulsesCount++;
      _lastPulseTime = timestamp;

      // ✅ تحديث العداد من قاعدة البيانات لضمان الدقة
      final updatedStats = await getTrackingStats(_currentEmployeeId!);
      _pulsesCount = updatedStats['total_pulses'] ?? _pulsesCount;

      // Print pulse status
      print(
        '📊 Pulse #$_pulsesCount: ${effectiveInsideGeofence ? "✅ INSIDE" : "❌ OUTSIDE"} geofence (${effectiveDistance.toStringAsFixed(1)}m)',
      );
      print('📋 Recent pulses in memory: ${_recentPulses.length}');

      // 1. Send warning for EVERY false pulse
      if (effectiveInsideGeofence == false) {
        print(
          '⚠️ WARNING: Pulse outside geofence - Distance: ${effectiveDistance.toStringAsFixed(1)}m!',
        );
        print('📱 Sending notification to user...');

        try {
          await NotificationService.instance.showGeofenceViolation(
            employeeName: 'الموظف',
            message:
                '⚠️ تحذير: أنت خارج منطقة العمل!\nالمسافة: ${effectiveDistance.round()}م\nعد فوراً أو سيتم تسجيل انصراف تلقائي',
          );
          print('✅ Notification sent successfully');
        } catch (e) {
          print('❌ Failed to send notification: $e');
        }
      } else {
        print('✅ Pulse inside geofence - no warning needed');
      }

      // 2. Check: Are there 2 consecutive false pulses?
      if (_recentPulses.length >= 2) {
        final lastTwo = _recentPulses.sublist(_recentPulses.length - 2);
        final firstPulse = lastTwo[0];
        final secondPulse = lastTwo[1];

        final firstIsOutside = firstPulse['inside_geofence'] == false;
        final secondIsOutside = secondPulse['inside_geofence'] == false;

        if (firstIsOutside && secondIsOutside) {
          print('*** 2 CONSECUTIVE FALSE PULSES DETECTED! ***');
          print(
            '   - First pulse: ${(firstPulse['distance'] as double).toStringAsFixed(1)}m outside',
          );
          print(
            '   - Second pulse: ${(secondPulse['distance'] as double).toStringAsFixed(1)}m outside',
          );
          print('*** TRIGGERING AUTO CHECK-OUT ***');

          // Send final notification
          await NotificationService.instance.showGeofenceViolation(
            employeeName: 'الموظف',
            message:
                '🚨 تم تسجيل انصراف تلقائي!\nنبضتين خارج النطاق (10 دقائق)',
          );

          // Trigger auto check-out
          await _triggerAutoCheckout(
            latitude: effectiveLatitude,
            longitude: effectiveLongitude,
            distance: effectiveDistance,
            wifiBssid: effectiveWifiBssid,
          );

          return; // Stop system after auto check-out
        }
      }

      notifyListeners();
    } catch (e) {
      print('Error sending pulse: $e');
      AppLogger.instance.log(
        'Error sending pulse',
        level: AppLogger.error,
        tag: 'PulseTracking',
        error: e,
      );
    } finally {
      _isSendingPulse = false;
    }
  }

  /// Check for auto-checkout condition (2 consecutive false pulses)
  Future<void> _checkForAutoCheckout() async {
    if (_recentPulses.length >= 2) {
      final lastTwo = _recentPulses.sublist(_recentPulses.length - 2);
      final firstPulse = lastTwo[0];
      final secondPulse = lastTwo[1];

      final firstIsOutside = firstPulse['inside_geofence'] == false;
      final secondIsOutside = secondPulse['inside_geofence'] == false;

      if (firstIsOutside && secondIsOutside) {
        print('*** 2 CONSECUTIVE FALSE PULSES DETECTED! ***');
        print(
          '   - First pulse: ${(firstPulse['distance'] as double).toStringAsFixed(1)}m outside',
        );
        print(
          '   - Second pulse: ${(secondPulse['distance'] as double).toStringAsFixed(1)}m outside',
        );
        print('*** TRIGGERING AUTO CHECK-OUT ***');

        // Send final notification
        await NotificationService.instance.showGeofenceViolation(
          employeeName: 'الموظف',
          message: '🚨 تم تسجيل انصراف تلقائي!\nنبضتين خارج النطاق (10 دقائق)',
        );

        // Trigger auto check-out
        await _triggerAutoCheckout(
          latitude: secondPulse['latitude'] ?? 0.0,
          longitude: secondPulse['longitude'] ?? 0.0,
          distance: secondPulse['distance'] ?? 0.0,
          wifiBssid: null,
        );
      }
    }
  }

  /// Trigger auto check-out
  Future<void> _triggerAutoCheckout({
    required double latitude,
    required double longitude,
    required double distance,
    String? wifiBssid,
  }) async {
    print('*** STARTING AUTO CHECK-OUT PROCESS ***');

    final timestamp = DateTime.now();
    bool savedOffline = false;

    // 🚨 Set flag FIRST to notify UI immediately
    _autoCheckoutTriggered = true;

    try {
      // Get attendance_id
      final attendanceId =
          _currentAttendanceId ?? await _resolveActiveAttendanceId();

      if (attendanceId == null) {
        print('ERROR: No active attendance record found');
        // Still emit event for UI update even without attendance_id
        _emitAutoCheckoutEvent(timestamp, distance, true);
        return;
      }

      print('attendance_id: $attendanceId');

      // Try check-out via server
      bool success = false;

      try {
        success = await SupabaseAttendanceService.checkOut(
          attendanceId: attendanceId,
          latitude: latitude,
          longitude: longitude,
          wifiBssid: wifiBssid,
          forceCheckout: true,
        );
      } catch (e) {
        print('Server check-out failed: $e');
      }

      // If failed, try forceCheckout
      if (!success) {
        try {
          success = await SupabaseAttendanceService.forceCheckout(
            attendanceId: attendanceId,
            latitude: latitude,
            longitude: longitude,
            note:
                'Auto check-out after 2 consecutive pulses outside geofence (${distance.round()}m)',
          );
        } catch (e) {
          print('forceCheckout failed: $e');
        }
      }

      // If all failed, save offline
      if (!success) {
        print('Saving check-out locally (offline)...');
        savedOffline = true;

        await _offlineService.saveLocalCheckOut(
          employeeId: _currentEmployeeId!,
          timestamp: timestamp,
          latitude: latitude,
          longitude: longitude,
          bssid: wifiBssid,
          notes:
              'Auto check-out after 2 consecutive pulses outside geofence - will sync when online',
        );

        // Save to SQLite (mobile)
        if (!kIsWeb) {
          try {
            final db = OfflineDatabase.instance;
            await db.insertPendingCheckout(
              employeeId: _currentEmployeeId!,
              attendanceId: attendanceId,
              timestamp: timestamp,
              latitude: latitude,
              longitude: longitude,
              notes:
                  'Auto check-out after 2 consecutive pulses outside geofence',
            );
          } catch (e) {
            print('SQLite save failed: $e');
          }
        }

        await NotificationService.instance.showOfflineModeNotification();
      }

      // ✅ Clear attendance state from SharedPreferences
      try {
        await SupabaseAttendanceService.clearActiveAttendanceCache();
        print('✅ Cleared attendance state from SharedPreferences');
      } catch (e) {
        print('⚠️ Failed to clear SharedPreferences: $e');
      }

      print('*** AUTO CHECK-OUT COMPLETED SUCCESSFULLY ***');

      // Stop foreground service (Android)
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await ForegroundAttendanceService.instance.stopTracking();
          print('Foreground service stopped');
        } catch (e) {
          print('Foreground service stop error: $e');
        }
      }

      // 🚨 Emit event for UI BEFORE stopping tracking
      _emitAutoCheckoutEvent(timestamp, distance, savedOffline);

      // Stop pulse system
      stopTracking(fromAutoCheckout: true);
    } catch (e) {
      print('Auto check-out error: $e');
      savedOffline = true;

      // Fallback: save offline
      if (_currentEmployeeId != null && _currentAttendanceId != null) {
        await _offlineService.saveLocalCheckOut(
          employeeId: _currentEmployeeId!,
          timestamp: timestamp,
          latitude: latitude,
          longitude: longitude,
          bssid: wifiBssid,
          notes: 'Auto check-out (fallback) - error in main processing',
        );
      }

      // ✅ Clear attendance state even on error
      try {
        await SupabaseAttendanceService.clearActiveAttendanceCache();
      } catch (_) {}

      // 🚨 Emit event for UI
      _emitAutoCheckoutEvent(timestamp, distance, savedOffline);

      await NotificationService.instance.showOfflineModeNotification();
      stopTracking(fromAutoCheckout: true);
    }
  }

  /// 🚨 Helper to emit auto-checkout event
  void _emitAutoCheckoutEvent(
    DateTime timestamp,
    double distance,
    bool savedOffline,
  ) {
    final event = AutoCheckoutEvent(
      timestamp: timestamp,
      reason: 'نبضتين متتاليتين خارج منطقة العمل (${distance.round()}م)',
      distance: distance,
      savedOffline: savedOffline,
    );

    _autoCheckoutController.add(event);
    print('🚨 Auto-checkout event emitted to UI');
  }

  /// Get active attendance_id
  Future<String?> _resolveActiveAttendanceId() async {
    if (_currentAttendanceId != null && _currentAttendanceId!.isNotEmpty) {
      return _currentAttendanceId;
    }

    // Try reading from SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedId = prefs.getString('active_attendance_id');
      if (storedId != null && storedId.isNotEmpty) {
        // Filter out legacy placeholder values (e.g. "pending_local")
        final isPlaceholder =
            RegExp(
              r'(pending|local|temp|dummy)',
              caseSensitive: false,
            ).hasMatch(storedId) ||
            storedId.length < 8;
        if (!isPlaceholder) {
          _currentAttendanceId = storedId;
          return storedId;
        } else {
          // Clean up invalid cached placeholder
          await prefs.remove('active_attendance_id');
        }
      }

      // Fallback to the unified device snapshot if key-value state was partially cleared.
      final snapshot =
          await SupabaseAttendanceService.getCachedActiveAttendanceOnDevice(
            employeeId: _currentEmployeeId,
          );
      final snapshotId = snapshot?['attendance_id']?.toString();
      if (snapshotId != null && snapshotId.isNotEmpty) {
        _currentAttendanceId = snapshotId;
        await prefs.setString('active_attendance_id', snapshotId);
        return snapshotId;
      }
    } catch (e) {
      print('SharedPreferences read error: $e');
    }

    // Try getting from Supabase
    if (_currentEmployeeId != null) {
      try {
        final activeAttendance =
            await SupabaseAttendanceService.getActiveAttendance(
              _currentEmployeeId!,
            );
        final fetchedId = activeAttendance?['id'] as String?;
        if (fetchedId != null && fetchedId.isNotEmpty) {
          _currentAttendanceId = fetchedId;
          return fetchedId;
        }
      } catch (e) {
        print('Supabase attendance_id fetch error: $e');
      }
    }

    return null;
  }

  /// Extract required BSSIDs from branch data
  List<String> _extractRequiredBssids(Map<String, dynamic> branchData) {
    final Set<String> normalized = <String>{};
    final dynamic wifiData =
        branchData['wifi_bssids'] ??
        branchData['wifi_bssid'] ??
        branchData['bssid'];

    void addValue(String value) {
      final formatted = value.trim();
      if (formatted.isEmpty) return;
      normalized.add(formatted.toUpperCase());
    }

    if (wifiData is List) {
      for (final entry in wifiData) {
        final stringValue = entry?.toString();
        if (stringValue != null) {
          addValue(stringValue);
        }
      }
    } else if (wifiData is String) {
      final trimmed = wifiData.trim();
      if (trimmed.isNotEmpty) {
        if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
          try {
            final decoded = jsonDecode(trimmed);
            if (decoded is List) {
              for (final entry in decoded) {
                final stringValue = entry?.toString();
                if (stringValue != null) {
                  addValue(stringValue);
                }
              }
            }
          } catch (_) {
            for (final part in trimmed.split(',')) {
              addValue(part);
            }
          }
        } else {
          for (final part in trimmed.split(',')) {
            addValue(part);
          }
        }
      }
    }

    return normalized.toList();
  }

  Future<String?> _validateWithFallbackWifi(List<String> requiredBssids) async {
    if (requiredBssids.isEmpty) {
      return null;
    }

    final fallbackBssid = await WiFiService.tryGetCurrentWifiBssid();
    if (fallbackBssid == null || fallbackBssid.isEmpty) {
      return null;
    }

    return requiredBssids.contains(fallbackBssid) ? fallbackBssid : null;
  }

  Future<void> _recordWifiValidatedPulse({
    required DateTime timestamp,
    required String? wifiBssid,
    required double centerLat,
    required double centerLng,
    required String? branchId,
    required String reason,
  }) async {
    print('✅ Pulse #${_pulsesCount + 1}: TRUE ($reason)');

    await _offlineService.saveLocalPulse(
      employeeId: _currentEmployeeId!,
      attendanceId: _currentAttendanceId,
      timestamp: timestamp,
      latitude: centerLat,
      longitude: centerLng,
      insideGeofence: true,
      distanceFromCenter: 0.0,
      wifiBssid: wifiBssid,
      validatedByWifi: true,
      validatedByLocation: false,
      branchId: branchId,
    );

    _recentPulses.add({
      'inside_geofence': true,
      'distance': 0.0,
      'timestamp': timestamp,
      'validated_by_wifi': true,
    });
    if (_recentPulses.length > 2) {
      _recentPulses.removeAt(0);
    }

    _pulsesCount++;
    _lastPulseTime = timestamp;

    final updatedStats = await getTrackingStats(_currentEmployeeId!);
    _pulsesCount = updatedStats['total_pulses'] ?? _pulsesCount;

    notifyListeners();
  }

  Future<void> _persistTrackingContext() async {
    if (_currentEmployeeId == null || _currentBranchData == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'current_branch_data',
      jsonEncode(_currentBranchData),
    );
    await prefs.setBool('pulse_tracking_active', true);
  }

  Future<void> _clearTrackingContext() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_branch_data');
    await prefs.setBool('pulse_tracking_active', false);
  }

  /// Send manual pulse (for testing)
  Future<void> sendManualPulse(String employeeId) async {
    final branchData = await _offlineService.getCachedBranchData(
      employeeId: employeeId,
    );
    if (branchData == null) {
      print('Cannot send pulse: Branch data not available');
      return;
    }

    _currentEmployeeId = employeeId;
    _currentBranchData = branchData;
    await _sendPulse();
  }

  /// Get tracking statistics
  /// ✅ يجمع النبضات من Hive (المزامنة) + SQLite (المعلقة)
  Future<Map<String, dynamic>> getTrackingStats(String employeeId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // 1. النبضات المزامنة من Hive
    final syncedPulses = await _offlineService.getPulsesForDate(
      employeeId: employeeId,
      date: today,
    );

    // 2. النبضات المعلقة من SQLite (لو مش Web)
    List<Map<String, dynamic>> pendingPulses = [];
    if (!kIsWeb) {
      try {
        final db = OfflineDatabase.instance;
        final allPending = await db.getPendingPulses();

        // فلترة النبضات الخاصة بالموظف واليوم الحالي
        pendingPulses = allPending.where((p) {
          if (p['employee_id'] != employeeId) return false;

          try {
            final timestamp = DateTime.parse(p['timestamp']?.toString() ?? '');
            return timestamp.isAfter(startOfDay) &&
                timestamp.isBefore(endOfDay);
          } catch (e) {
            return false;
          }
        }).toList();

        print(
          '📊 نبضات مزامنة (Hive): ${syncedPulses.length}, معلقة (SQLite): ${pendingPulses.length}',
        );
      } catch (e) {
        print('⚠️ خطأ في قراءة النبضات المعلقة: $e');
      }
    }

    // 3. حساب الإحصائيات من المصدرين
    int insideCount = 0;
    int outsideCount = 0;

    // من Hive
    for (var pulse in syncedPulses) {
      if (pulse['inside_geofence'] == true) {
        insideCount++;
      } else {
        outsideCount++;
      }
    }

    // من SQLite
    for (var pulse in pendingPulses) {
      if (pulse['inside_geofence'] == 1) {
        // SQLite بيخزن int مش bool
        insideCount++;
      } else {
        outsideCount++;
      }
    }

    final totalPulses = syncedPulses.length + pendingPulses.length;
    final totalMinutes = insideCount * 5;
    final hours = totalMinutes / 60;

    return {
      'total_pulses': totalPulses,
      'inside_geofence': insideCount,
      'outside_geofence': outsideCount,
      'total_minutes': totalMinutes,
      'total_hours': hours,
      'is_tracking': _isTracking,
      'last_pulse': _lastPulseTime?.toIso8601String(),
    };
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
