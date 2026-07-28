import 'dart:async';
import 'dart:convert';
import 'attendance_timer_service.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import '../database/offline_database.dart';
import '../models/employee.dart';
import 'native_location_service.dart'; // 🚀 Native GPS for faster location
import 'offline_data_service.dart';
import 'notification_service.dart';
import 'wifi_service.dart';
import 'app_logger.dart';
import 'pulse_deduplication_service.dart';
import '../utils/time_utils.dart';

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
  DateTime? _checkInTime; // 🚀 Stored check-in time for robust offline count queries
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

  bool _isCurrentlyInside = true;
  bool get isCurrentlyInside => _isCurrentlyInside;

  int _outsidePulsesCount = 0;
  int get outsidePulsesCount => _outsidePulsesCount;

  // Getters
  bool get isTracking => _isTracking;
  DateTime? get lastPulseTime => _lastPulseTime;
  int get pulsesCount => _pulsesCount;

  /// Start pulse tracking
  Future<void> startTracking(String employeeId, {String? attendanceId, DateTime? checkInTime}) async {
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
    _checkInTime = checkInTime;

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
    _recentPulses.clear();
    _outsidePulsesCount = await getSessionOutsidePulsesCount(
      employeeId,
      attendanceId: attendanceId,
      checkInTime: checkInTime,
    );
    await _persistTrackingContext();

    // ✅ نجيب عدد نبضات الجلسة الحالية فقط بدلاً من اليوم كله لتفادي التداخل
    _pulsesCount = await getSessionTotalPulsesCount(
      employeeId,
      attendanceId: attendanceId,
      checkInTime: checkInTime,
    );
    print('📊 استئناف تتبع النبضات: عدد نبضات الجلسة الحالية = $_pulsesCount');

    // Also load the latest pulse info to update the baseline time and inside state
    final latestPulseInfo = await _getLatestLocalPulseInfo(
      employeeId,
      attendanceId: attendanceId,
      checkInTime: checkInTime,
    );
    if (latestPulseInfo != null) {
      _lastPulseTime = latestPulseInfo['timestamp'] as DateTime;
      _isCurrentlyInside = latestPulseInfo['inside'] as bool;
      print('📊 استئناف تتبع النبضات: آخر نبضة كانت في ${_lastPulseTime} وكان الوضع داخل الدائرة = $_isCurrentlyInside');
    } else {
      _lastPulseTime = checkInTime ?? DateTime.now();
      _isCurrentlyInside = true;
    }

    notifyListeners();

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
    _checkInTime = null;
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
      } catch (e) {
        print('⚠️ Failed to check break status: $e');
      }

      // Check if employee is a Super Employee
      bool isSuper = false;
      try {
        if (Hive.isBoxOpen('employees')) {
          final empBox = Hive.box<Employee>('employees');
          final emp = empBox.get(_currentEmployeeId);
          isSuper = emp?.isSuperEmployee ?? false;
        }
      } catch (e) {
        print('⚠️ Error checking isSuper in pulse: $e');
      }

      List<Map<String, dynamic>> superBranches = [];
      if (isSuper) {
        if (kIsWeb) {
          try {
            final box = Hive.isBoxOpen('branch_data') 
                ? Hive.box('branch_data') 
                : await Hive.openBox('branch_data');
            final raw = box.get('super_branches_$_currentEmployeeId');
            if (raw is List) {
              superBranches = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            }
          } catch (e) {
            print('⚠️ Error loading Hive super branches for pulse: $e');
          }
        } else {
          try {
            superBranches = await OfflineDatabase.instance.getCachedSuperBranches(_currentEmployeeId!);
          } catch (e) {
            print('⚠️ Error loading SQLite super branches for pulse: $e');
          }
        }
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

        await PulseDeduplicationService.markPulseRecorded(
          employeeId: _currentEmployeeId!,
          attendanceId: _currentAttendanceId,
          timestamp: timestamp,
          source: 'flutter_active_break',
        );

        // Update pulse data
        final pulseData = {
          'inside_geofence': true,
          'distance': 0.0,
          'timestamp': timestamp,
          'validated_by_break': true,
        };

        _isCurrentlyInside = true;
        _recentPulses.add(pulseData);
        if (_recentPulses.length > 2) {
          _recentPulses.removeAt(0);
        }

        _lastPulseTime = timestamp;

        // ✅ تحديث العداد من قاعدة البيانات لضمان الدقة للجلسة الحالية
        await refreshPulseCounts(checkInTime: _checkInTime);

        return; // Done - break override applied
      }

      if (superBranches.isNotEmpty) {
        print('⭐ Running Super Employee pulse check for $_currentEmployeeId against ${superBranches.length} branches');
        
        // WiFi Check
        String? wifiBssid;
        bool wifiValidated = false;
        Map<String, dynamic>? matchedBranch;

        try {
          wifiBssid = await WiFiService.getCurrentWifiBssidValidated();
          final currentBssid = wifiBssid.toUpperCase();
          
          for (final branch in superBranches) {
            final List<String> allowedBssids = [];
            if (branch['wifi_bssids_array'] != null) {
              final bssidsArray = branch['wifi_bssids_array'] as List<dynamic>;
              allowedBssids.addAll(bssidsArray.map((e) => e?.toString().toUpperCase().trim()).whereType<String>());
            } else {
              final bssidValue = branch['wifi_bssids'] ?? branch['wifi_bssid'];
              if (bssidValue != null && bssidValue.toString().isNotEmpty) {
                allowedBssids.addAll(bssidValue.toString().split(',').map((e) => e.toUpperCase().trim()));
              }
            }
            if (allowedBssids.contains(currentBssid)) {
              wifiValidated = true;
              matchedBranch = branch;
              break;
            }
          }
        } catch (e) {
          print('⚠️ WiFi check error in super employee pulse: $e');
        }

        if (wifiValidated && matchedBranch != null) {
          final timestamp = DateTime.now();
          final branchId = matchedBranch['branch_id']?.toString() ?? matchedBranch['id']?.toString();
          print('✅ Super employee pulse verified by Wi-Fi for branch: ${matchedBranch['name']}');
          
          await _recordWifiValidatedPulse(
            timestamp: timestamp,
            wifiBssid: wifiBssid,
            centerLat: (matchedBranch['latitude'] ?? matchedBranch['branch_latitude'])?.toDouble() ?? centerLat,
            centerLng: (matchedBranch['longitude'] ?? matchedBranch['branch_longitude'])?.toDouble() ?? centerLng,
            branchId: branchId,
            reason: 'Valid branch Wi-Fi (Super Employee: ${matchedBranch['name']})',
          );
          return;
        }

        // GPS Check
        print('📍 Wi-Fi not valid for super employee - checking GPS...');
        Position? position;
        try {
          position = await NativeLocationService.getCurrentLocation();
        } catch (e) {
          print('❌ GPS check error: $e');
        }

        if (position == null) {
          // Fallback WiFi check across all branches
          String? fallbackWifiBssid;
          for (final branch in superBranches) {
            final List<String> allowedBssids = [];
            if (branch['wifi_bssids_array'] != null) {
              final bssidsArray = branch['wifi_bssids_array'] as List<dynamic>;
              allowedBssids.addAll(bssidsArray.map((e) => e?.toString().toUpperCase().trim()).whereType<String>());
            } else {
              final bssidValue = branch['wifi_bssids'] ?? branch['wifi_bssid'];
              if (bssidValue != null && bssidValue.toString().isNotEmpty) {
                allowedBssids.addAll(bssidValue.toString().split(',').map((e) => e.toUpperCase().trim()));
              }
            }
            final fallback = await _validateWithFallbackWifi(allowedBssids);
            if (fallback != null) {
              fallbackWifiBssid = fallback;
              matchedBranch = branch;
              break;
            }
          }

          if (fallbackWifiBssid != null && matchedBranch != null) {
            final timestamp = DateTime.now();
            final branchId = matchedBranch['branch_id']?.toString() ?? matchedBranch['id']?.toString();
            await _recordWifiValidatedPulse(
              timestamp: timestamp,
              wifiBssid: fallbackWifiBssid,
              centerLat: (matchedBranch['latitude'] ?? matchedBranch['branch_latitude'])?.toDouble() ?? centerLat,
              centerLng: (matchedBranch['longitude'] ?? matchedBranch['branch_longitude'])?.toDouble() ?? centerLng,
              branchId: branchId,
              reason: 'Fallback branch Wi-Fi after GPS unavailable (Super Employee: ${matchedBranch['name']})',
            );
            return;
          }

          // If GPS is null and fallback WiFi also failed
          print('❌ Pulse #${_pulsesCount + 1}: FALSE (GPS disabled/no permission for super employee)');
          await AttendanceTimerService.pauseTimerLocally(reason: 'موقع الهاتف مغلق أو غير مصرح');

          final timestamp = DateTime.now();
          final branchId = (_currentBranchData!['id'] ?? _currentBranchData!['branch_id']) as String?;
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

          final pulseData = {
            'inside_geofence': false,
            'distance': 0.0,
            'timestamp': timestamp,
            'validated_by_break': false,
          };
          _isCurrentlyInside = false;
          _recentPulses.add(pulseData);
          if (_recentPulses.length > 2) _recentPulses.removeAt(0);
          _lastPulseTime = timestamp;
          await refreshPulseCounts(checkInTime: _checkInTime);
          return;
        }

        // We have a valid position! Loop through branches to check geofence
        Map<String, dynamic>? closestBranch;
        double minDistance = double.infinity;
        double closestRadius = 100.0;
        bool isInsideAnyGeofence = false;
        Map<String, dynamic>? matchedGPSBranch;

        for (final branch in superBranches) {
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
              isInsideAnyGeofence = true;
              matchedGPSBranch = branch;
              minDistance = distance; // actual distance
              break;
            }
          }
        }

        final timestamp = DateTime.now();
        final effectiveBranch = matchedGPSBranch ?? closestBranch ?? _currentBranchData!;
        final effectiveBranchId = effectiveBranch['branch_id']?.toString() ?? effectiveBranch['id']?.toString();
        final effectiveBranchLat = (effectiveBranch['latitude'] ?? effectiveBranch['branch_latitude'])?.toDouble() ?? centerLat;
        final effectiveBranchLng = (effectiveBranch['longitude'] ?? effectiveBranch['branch_longitude'])?.toDouble() ?? centerLng;

        bool effectiveInsideGeofence = isInsideAnyGeofence;
        double effectiveDistance = minDistance;
        bool effectiveWifiValidated = false;
        String? effectiveWifiBssid = wifiBssid;

        if (!effectiveInsideGeofence) {
          // Try fallback wifi on the closest branch
          final List<String> closestAllowedBssids = [];
          if (closestBranch != null) {
            if (closestBranch['wifi_bssids_array'] != null) {
              final bssidsArray = closestBranch['wifi_bssids_array'] as List<dynamic>;
              closestAllowedBssids.addAll(bssidsArray.map((e) => e?.toString().toUpperCase().trim()).whereType<String>());
            } else {
              final bssidValue = closestBranch['wifi_bssids'] ?? closestBranch['wifi_bssid'];
              if (bssidValue != null && bssidValue.toString().isNotEmpty) {
                closestAllowedBssids.addAll(bssidValue.toString().split(',').map((e) => e.toUpperCase().trim()));
              }
            }
          }
          final fallbackWifiBssid = await _validateWithFallbackWifi(closestAllowedBssids);
          if (fallbackWifiBssid != null) {
            effectiveInsideGeofence = true;
            effectiveDistance = 0.0;
            effectiveWifiBssid = fallbackWifiBssid;
            effectiveWifiValidated = true;
          }
        }

        if (effectiveInsideGeofence) {
          await AttendanceTimerService.resumeTimerLocally();
        } else {
          print('❌ Outside all branch geofences. Closest branch: ${closestBranch?['name']} distance: ${minDistance.round()}m');
          await AttendanceTimerService.pauseTimerLocally(
            reason: 'خارج النطاق الجغرافي لجميع الفروع (${minDistance.round()}م من أقرب فرع)',
          );
        }

        await _offlineService.saveLocalPulse(
          employeeId: _currentEmployeeId!,
          attendanceId: _currentAttendanceId,
          timestamp: timestamp,
          latitude: position.latitude,
          longitude: position.longitude,
          insideGeofence: effectiveInsideGeofence,
          distanceFromCenter: effectiveDistance,
          wifiBssid: effectiveWifiBssid,
          validatedByWifi: effectiveWifiValidated,
          validatedByLocation: !effectiveWifiValidated && effectiveInsideGeofence,
          branchId: effectiveBranchId,
        );

        await PulseDeduplicationService.markPulseRecorded(
          employeeId: _currentEmployeeId!,
          attendanceId: _currentAttendanceId,
          timestamp: timestamp,
          source: 'flutter_pulse_super_employee',
        );

        final pulseData = {
          'inside_geofence': effectiveInsideGeofence,
          'distance': effectiveDistance,
          'timestamp': timestamp,
          'validated_by_break': false,
        };

        _isCurrentlyInside = effectiveInsideGeofence;
        _recentPulses.add(pulseData);
        if (_recentPulses.length > 2) _recentPulses.removeAt(0);
        _lastPulseTime = timestamp;

        await refreshPulseCounts(checkInTime: _checkInTime);
        print('📊 Pulse #$_pulsesCount (Super Employee): ${effectiveInsideGeofence ? "✅ INSIDE" : "❌ OUTSIDE"} geofence (${effectiveDistance.toStringAsFixed(1)}m from ${closestBranch?['name']})');
        return;
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

        await AttendanceTimerService.pauseTimerLocally(reason: 'موقع الهاتف مغلق أو غير مصرح');

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

        _isCurrentlyInside = false;
        _outsidePulsesCount++;
        _recentPulses.add(pulseData);
        if (_recentPulses.length > 2) {
          _recentPulses.removeAt(0);
        }

        _lastPulseTime = timestamp;

        // ✅ تحديث العداد من قاعدة البيانات لضمان الدقة للجلسة الحالية
        await refreshPulseCounts(checkInTime: _checkInTime);

        // Send warning notification
        await NotificationService.instance.showGeofenceViolation(
          employeeName: 'الموظف',
          message: '⚠️ تحذير: GPS مغلق!\nيجب تفعيل الموقع للتحقق من تواجدك',
        );

        // Check for auto-checkout
        await _checkForAutoCheckout();
        return;
      }

      // ✅ STEP 3: GPS is enabled - validate geofence (Native GPS - 1-3s instead of 15-30s!)
      final result = await NativeLocationService.getLocationForGeofence(
        centerLat: centerLat,
        centerLng: centerLng,
        radiusMeters: radius,
      );

      bool isInsideGeofence;
      double distance;
      double? latitude;
      double? longitude;
      double gpsAccuracy;
      DateTime timestamp;

      if (result == null) {
        Position? lastPos;
        try {
          lastPos = await Geolocator.getLastKnownPosition();
        } catch (_) {}

        if (lastPos != null && DateTime.now().difference(lastPos.timestamp).abs() <= const Duration(minutes: 5)) {
          final lastDistance = Geolocator.distanceBetween(
            centerLat,
            centerLng,
            lastPos.latitude,
            lastPos.longitude,
          );
          isInsideGeofence = lastDistance <= radius;
          distance = lastDistance;
          latitude = lastPos.latitude;
          longitude = lastPos.longitude;
          gpsAccuracy = lastPos.accuracy;
          timestamp = lastPos.timestamp;
          print('⚠️ GPS request returned null, using fresh last known location: inside=$isInsideGeofence');
        } else {
          print('⚠️ GPS request returned null and no fresh last known location. Setting to OUTSIDE.');
          isInsideGeofence = false;
          distance = 0.0;
          latitude = null;
          longitude = null;
          gpsAccuracy = 999.0;
          timestamp = DateTime.now();
        }
      } else {
        isInsideGeofence = result['inside_geofence'] as bool;
        distance = result['distance'] as double;
        latitude = result['latitude'] as double;
        longitude = result['longitude'] as double;
        gpsAccuracy = (result['accuracy'] as num?)?.toDouble() ?? 999.0;
        timestamp = result['timestamp'] is DateTime
            ? result['timestamp'] as DateTime
            : TimeUtils.parseTimestamp(result['timestamp']) ?? DateTime.now();

        final bool staleLocation = DateTime.now().difference(timestamp).abs() > _maxLocationSampleAge;
        final bool weakAccuracy = gpsAccuracy > _minReliableGpsAccuracyMeters;

        if (staleLocation) {
          print('⚠️ GPS sample is stale, ignoring.');
          isInsideGeofence = false;
          distance = 0.0;
          latitude = null;
          longitude = null;
        } else if (weakAccuracy) {
          isInsideGeofence = (distance - gpsAccuracy) <= radius;
          print('⚠️ GPS sample has weak accuracy (${gpsAccuracy.toStringAsFixed(1)}m) - applying overlap check: $isInsideGeofence');
        }
      }

      bool effectiveInsideGeofence = isInsideGeofence;
      double effectiveDistance = distance;
      double? effectiveLatitude = latitude;
      double? effectiveLongitude = longitude;
      String? effectiveWifiBssid = wifiBssid;
      bool effectiveWifiValidated = wifiValidated;
      bool effectiveValidatedByLocation = result != null ? isInsideGeofence : false;

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

      if (effectiveInsideGeofence) {
        await AttendanceTimerService.resumeTimerLocally();
      } else {
        await AttendanceTimerService.pauseTimerLocally(reason: 'خارج نطاق الفرع');
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('last_known_distance_$_currentEmployeeId', effectiveDistance);
      } catch (e) {
        print('⚠️ Error saving last known distance in pulse: $e');
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

      await PulseDeduplicationService.markPulseRecorded(
        employeeId: _currentEmployeeId!,
        attendanceId: _currentAttendanceId,
        timestamp: timestamp,
        source: 'flutter_active_location',
      );

      // Save to recent pulses list (keep last 2)
      final pulseData = {
        'inside_geofence': effectiveInsideGeofence,
        'distance': effectiveDistance,
        'timestamp': timestamp,
        'latitude': effectiveLatitude,
        'longitude': effectiveLongitude,
      };

      _isCurrentlyInside = effectiveInsideGeofence;
      if (!effectiveInsideGeofence) {
        _outsidePulsesCount++;
      }
      _recentPulses.add(pulseData);
      if (_recentPulses.length > 2) {
        _recentPulses.removeAt(0); // Keep only last 2 pulses
      }

      _lastPulseTime = timestamp;

      // ✅ تحديث العداد من قاعدة البيانات لضمان الدقة للجلسة الحالية
      await refreshPulseCounts(checkInTime: _checkInTime);

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
                '⚠️ تحذير: أنت خارج منطقة العمل!\nالمسافة: ${effectiveDistance.round()}م\nيرجى العودة إلى النطاق، فلن يتم احتساب وقت عملك طالما كنت بالخارج.',
          );
          print('✅ Notification sent successfully');
        } catch (e) {
          print('❌ Failed to send notification: $e');
        }
      } else {
        print('✅ Pulse inside geofence - no warning needed');
      }

      // Auto-checkout disabled by policy. We only maintain warnings.
      print('[PulseTracking] Geofence auto-checkout trigger skipped by policy.');
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

  /// Check for auto-checkout condition (2 consecutive false pulses) - Disabled by policy
  Future<void> _checkForAutoCheckout() async {
    print('[PulseTracking] _checkForAutoCheckout called: disabled by policy.');
  }

  /// Calculates the number of outside pulses for the active session (Hive + SQLite)
  /// Retrieves all matching pulses for the session from Hive and SQLite
  Future<List<Map<String, dynamic>>> _getSessionPulses(
    String employeeId, {
    String? attendanceId,
    DateTime? checkInTime,
  }) async {
    final List<Map<String, dynamic>> synced = [];
    final now = DateTime.now();
    if (checkInTime != null) {
      // Loop through all dates from checkInTime's date to today's date
      var currentDate = DateTime(checkInTime.year, checkInTime.month, checkInTime.day);
      final endDate = DateTime(now.year, now.month, now.day);
      while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
        try {
          final dayPulses = await _offlineService.getPulsesForDate(
            employeeId: employeeId,
            date: currentDate,
          );
          synced.addAll(dayPulses);
        } catch (e) {
          print('⚠️ Error getting pulses for $currentDate: $e');
        }
        currentDate = currentDate.add(const Duration(days: 1));
      }
    } else {
      final dayPulses = await _offlineService.getPulsesForDate(
        employeeId: employeeId,
        date: now,
      );
      synced.addAll(dayPulses);
    }

    List<Map<String, dynamic>> pending = [];
    if (!kIsWeb) {
      try {
        pending = await OfflineDatabase.instance.getAllPulses();
      } catch (_) {}
    }

    final List<Map<String, dynamic>> sessionPulses = [];

    void processPulse(Map<String, dynamic> pulse) {
      final pAttId = pulse['attendance_id']?.toString() ?? '';
      final pulseTimeStr = pulse['timestamp']?.toString();
      
      bool match = false;
      DateTime? parsedTime;
      if (checkInTime != null && pulseTimeStr != null) {
        try {
          parsedTime = TimeUtils.parseTimestamp(pulseTimeStr);
          if (parsedTime != null && parsedTime.isAfter(checkInTime.subtract(const Duration(minutes: 1)))) {
            match = true;
          }
        } catch (_) {}
      }
      if (!match && attendanceId != null && attendanceId.isNotEmpty && pAttId == attendanceId) {
        match = true;
      }

      if (match && pulseTimeStr != null) {
        final parsed = parsedTime ?? TimeUtils.parseTimestamp(pulseTimeStr);
        if (parsed != null) {
          sessionPulses.add({
            'timestamp': parsed,
            'inside_geofence': pulse['inside_geofence'] == true || pulse['inside_geofence'] == 1,
          });
        }
      }
    }

    for (var pulse in synced) {
      processPulse(pulse);
    }
    for (var pulse in pending) {
      if (pulse['employee_id'] == employeeId) {
        processPulse(pulse);
      }
    }

    return sessionPulses;
  }

  /// Calculates the number of outside pulses for the active session (Hive + SQLite)
  /// Deduplicated by 5-minute slots to avoid duplicate counts.
  Future<int> getSessionOutsidePulsesCount(
    String employeeId, {
    String? attendanceId,
    DateTime? checkInTime,
  }) async {
    try {
      final pulses = await _getSessionPulses(
        employeeId,
        attendanceId: attendanceId,
        checkInTime: checkInTime,
      );
      
      final Map<int, bool> slotInsideStatus = {};
      for (var pulse in pulses) {
        final time = pulse['timestamp'] as DateTime;
        final slot = time.millisecondsSinceEpoch ~/ (5 * 60 * 1000);
        final isInside = pulse['inside_geofence'] as bool;
        
        if (isInside) {
          slotInsideStatus[slot] = true;
        } else {
          slotInsideStatus.putIfAbsent(slot, () => false);
        }
      }
      return slotInsideStatus.values.where((inside) => !inside).length;
    } catch (e) {
      print('⚠️ Error getting session outside pulses: $e');
      return 0;
    }
  }

  /// Calculates the total number of pulses for the active session (Hive + SQLite)
  /// Deduplicated by 5-minute slots to avoid duplicate counts.
  Future<int> getSessionTotalPulsesCount(
    String employeeId, {
    String? attendanceId,
    DateTime? checkInTime,
  }) async {
    try {
      final pulses = await _getSessionPulses(
        employeeId,
        attendanceId: attendanceId,
        checkInTime: checkInTime,
      );
      
      final Set<int> uniqueSlots = {};
      for (var pulse in pulses) {
        final time = pulse['timestamp'] as DateTime;
        final slot = time.millisecondsSinceEpoch ~/ (5 * 60 * 1000);
        uniqueSlots.add(slot);
      }
      return uniqueSlots.length;
    } catch (e) {
      print('⚠️ Error getting session total pulses: $e');
      return 0;
    }
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

    await AttendanceTimerService.resumeTimerLocally();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_known_distance_$_currentEmployeeId', 0.0);
    } catch (_) {}

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

    await PulseDeduplicationService.markPulseRecorded(
      employeeId: _currentEmployeeId!,
      attendanceId: _currentAttendanceId,
      timestamp: timestamp,
      source: 'flutter_active_wifi',
    );

    _isCurrentlyInside = true;
    _recentPulses.add({
      'inside_geofence': true,
      'distance': 0.0,
      'timestamp': timestamp,
      'validated_by_wifi': true,
    });
    if (_recentPulses.length > 2) {
      _recentPulses.removeAt(0);
    }

    _lastPulseTime = timestamp;

    // ✅ تحديث العداد من قاعدة البيانات لضمان الدقة للجلسة الحالية
    await refreshPulseCounts(checkInTime: _checkInTime);
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

  /// Refresh pulse counts from database for active session
  Future<void> refreshPulseCounts({DateTime? checkInTime}) async {
    if (!_isTracking || _currentEmployeeId == null) return;
    
    final effectiveCheckInTime = checkInTime ?? _checkInTime;
    
    _outsidePulsesCount = await getSessionOutsidePulsesCount(
      _currentEmployeeId!,
      attendanceId: _currentAttendanceId,
      checkInTime: effectiveCheckInTime,
    );
    
    _pulsesCount = await getSessionTotalPulsesCount(
      _currentEmployeeId!,
      attendanceId: _currentAttendanceId,
      checkInTime: effectiveCheckInTime,
    );
    
    final latestPulseInfo = await _getLatestLocalPulseInfo(
      _currentEmployeeId!,
      attendanceId: _currentAttendanceId,
      checkInTime: effectiveCheckInTime,
    );
    if (latestPulseInfo != null) {
      _lastPulseTime = latestPulseInfo['timestamp'] as DateTime;
      _isCurrentlyInside = latestPulseInfo['inside'] as bool;
    } else if (effectiveCheckInTime != null) {
      _lastPulseTime = effectiveCheckInTime;
      _isCurrentlyInside = true;
    }
    
    notifyListeners();
    print('📊 [PulseTrackingService] Pulse counts refreshed: pulsesCount=$_pulsesCount, outside=$_outsidePulsesCount');
  }

  Future<Map<String, dynamic>?> _getLatestLocalPulseInfo(
    String employeeId, {
    String? attendanceId,
    DateTime? checkInTime,
  }) async {
    if (kIsWeb) return null;
    try {
      // 1. Get Hive pulses for today
      final today = DateTime.now();
      final hivePulses = await _offlineService.getPulsesForDate(
        employeeId: employeeId,
        date: today,
      );

      // 2. Get SQLite pulses
      final db = await OfflineDatabase.instance.database;
      final sqlitePulses = await db.query(
        'pending_pulses',
        where: 'employee_id = ?',
        whereArgs: [employeeId],
      );

      // 3. Merge and standardize
      final List<Map<String, dynamic>> allPulses = [];
      
      void addNormalized(Map<String, dynamic> p) {
        final timeStr = p['timestamp']?.toString();
        if (timeStr == null) return;
        final time = TimeUtils.parseTimestamp(timeStr);
        if (time == null) return;
        
        final pAttId = p['attendance_id']?.toString() ?? '';
        final isInside = p['inside_geofence'] == true || p['inside_geofence'] == 1;
        
        allPulses.add({
          'timestamp': time,
          'inside': isInside,
          'attendance_id': pAttId,
        });
      }

      for (var p in hivePulses) {
        addNormalized(p);
      }
      for (var p in sqlitePulses) {
        addNormalized(p);
      }

      // 4. Sort by timestamp DESC
      allPulses.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));

      // 5. Find the latest matching pulse
      for (var pulse in allPulses) {
        final time = pulse['timestamp'] as DateTime;
        final pAttId = pulse['attendance_id'] as String;
        
        bool match = false;
        if (checkInTime != null) {
          if (time.isAfter(checkInTime.subtract(const Duration(minutes: 1)))) {
            match = true;
          }
        } else if (attendanceId != null && attendanceId.isNotEmpty) {
          if (pAttId == attendanceId) {
            match = true;
          }
        } else {
          match = true;
        }

        if (match) {
          return {
            'timestamp': time,
            'inside': pulse['inside'],
          };
        }
      }
    } catch (e) {
      print('⚠️ Error getting latest pulse info: $e');
    }
    return null;
  }

  /// Trigger auto checkout for the UI (typically broadcast from native service or shift-end)
  Future<void> triggerAutoCheckout(String reason, {bool savedOffline = false}) async {
    print('🚨 Auto-checkout triggered in service: reason=$reason, savedOffline=$savedOffline. DISABLED BY POLICY.');
    return;
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
