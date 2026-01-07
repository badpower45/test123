import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/offline_database.dart';
import 'native_location_service.dart'; // 🚀 Native GPS for faster location
import 'native_pulse_service.dart'; // 🔥 Native Persistent Service for old devices
import 'background_pulse_listener.dart'; // 🎧 Listen to native pulses
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
  static final PulseTrackingService _instance = PulseTrackingService._internal();
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
  List<Map<String, dynamic>> _recentPulses = []; // آخر نبضتين
  
  final _offlineService = OfflineDataService();

  // نبضة كل 5 دقائق بالضبط
  static const Duration _pulseInterval = Duration(minutes: 5);

  // 🚨 NEW: Auto-checkout event stream for UI updates
  final StreamController<AutoCheckoutEvent> _autoCheckoutController = 
      StreamController<AutoCheckoutEvent>.broadcast();
  Stream<AutoCheckoutEvent> get onAutoCheckout => _autoCheckoutController.stream;
  
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
    
    // Initialize background pulse listener (for native service)
    await BackgroundPulseListener.initialize(
      onPulseRecorded: () {
        // Update UI when native service records a pulse
        _refreshPulseCount();
      },
    );
    
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
    final branchData = await _offlineService.getCachedBranchData(employeeId: employeeId);
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
    
    // ✅ بدل ما نبدأ من صفر، نجيب العدد من قاعدة البيانات
    final stats = await getTrackingStats(employeeId);
    _pulsesCount = stats['total_pulses'] ?? 0;
    print('📊 استئناف تتبع النبضات: عدد النبضات الحالي = $_pulsesCount');
    
    notifyListeners();

    // 🔥 START NATIVE PERSISTENT SERVICE (for old devices)
    // This ensures pulses continue even if app is killed in background
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final branchId = (_currentBranchData!['id'] ?? _currentBranchData!['branch_id']) as String?;
        final branchLat = _currentBranchData!['latitude'] as double?;
        final branchLng = _currentBranchData!['longitude'] as double?;
        final branchRad = _currentBranchData!['geofence_radius'] as double?;
        
        final success = await NativePulseService.startPersistentService(
          employeeId: employeeId,
          attendanceId: attendanceId ?? 'pending',
          branchId: branchId ?? '',
          branchLatitude: branchLat,
          branchLongitude: branchLng,
          branchRadius: branchRad,
        );
        if (success) {
          print('✅ Native Persistent Service started - will survive app closure');
          print('   📍 Branch geofence configured: ($branchLat, $branchLng), radius: ${branchRad}m');
        } else {
          print('⚠️ Failed to start Native Persistent Service');
        }
      } catch (e) {
        print('⚠️ Error starting Native Service: $e');
      }
    }

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
    
    // 🔥 STOP NATIVE PERSISTENT SERVICE
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await NativePulseService.stopPersistentService();
        print('✅ Native Persistent Service stopped');
      } catch (e) {
        print('⚠️ Error stopping Native Service: $e');
      }
    }
    
    // Reset auto-checkout flag when manually stopped (not from auto-checkout)
    if (!fromAutoCheckout) {
      _autoCheckoutTriggered = false;
    }
    
    notifyListeners();

    print('Pulse tracking stopped${fromAutoCheckout ? " (auto-checkout)" : ""}');
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
          final activeBreak = await SupabaseAttendanceService.getActiveBreak(_currentEmployeeId!);
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

      // ✅ If on active break, always send TRUE pulse
      if (isOnActiveBreak) {
        print('☕ Pulse #${_pulsesCount + 1}: TRUE (Active Break - Skipping all validation)');
        
        final timestamp = DateTime.now();
        final branchId = (_currentBranchData!['id'] ?? _currentBranchData!['branch_id']) as String?;
        
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
      final radius = (_currentBranchData!['geofence_radius'] as num?)?.toDouble() ?? 100.0;

      if (centerLat == null || centerLng == null) {
        print('Invalid branch location data');
        return;
      }

      // ✅ STEP 1: Check Wi-Fi FIRST (Priority)
      String? wifiBssid;
      bool wifiValidated = false;
      final requiredBssids = _extractRequiredBssids(_currentBranchData!);
      
      if (requiredBssids.isNotEmpty) {
        try {
          wifiBssid = await WiFiService.getCurrentWifiBssidValidated();
          wifiValidated = requiredBssids.contains(wifiBssid);
          print('📶 Wi-Fi: $wifiBssid (${wifiValidated ? "✅ valid" : "❌ invalid"})');
          
          if (wifiValidated) {
            // ✅ Wi-Fi is valid = TRUE immediately (no GPS check needed)
            print('✅ Pulse #${_pulsesCount + 1}: TRUE (Valid Wi-Fi) - Skipping GPS check');
            
            final timestamp = DateTime.now();
            final branchId = (_currentBranchData!['id'] ?? _currentBranchData!['branch_id']) as String?;
            
            // ✅ FIXED: Use branch location when WiFi validated (not null)
            // Save pulse as TRUE with branch location
            await _offlineService.saveLocalPulse(
              employeeId: _currentEmployeeId!,
              attendanceId: _currentAttendanceId,
              timestamp: timestamp,
              latitude: centerLat, // ✅ Use branch center location
              longitude: centerLng, // ✅ Use branch center location
              insideGeofence: true,
              distanceFromCenter: 0.0,
              wifiBssid: wifiBssid,
              validatedByWifi: true,
              validatedByLocation: false,
              branchId: branchId,
            );
            
            // Update pulse data
            final pulseData = {
              'inside_geofence': true,
              'distance': 0.0,
              'timestamp': timestamp,
              'validated_by_wifi': true,
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
        // GPS disabled or no permission = FALSE pulse
        print('❌ Pulse #${_pulsesCount + 1}: FALSE (GPS disabled or no permission)');
        
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
      final DateTime timestamp = result['timestamp'] is DateTime 
          ? result['timestamp'] as DateTime 
          : DateTime.parse(result['timestamp'] as String);

      // Save pulse
      final branchId = (_currentBranchData!['id'] ?? _currentBranchData!['branch_id']) as String?;
      
      await _offlineService.saveLocalPulse(
        employeeId: _currentEmployeeId!,
        attendanceId: _currentAttendanceId,
        timestamp: timestamp,
        latitude: latitude,
        longitude: longitude,
        insideGeofence: isInsideGeofence,
        distanceFromCenter: distance,
        wifiBssid: wifiBssid,
        validatedByWifi: wifiValidated,
        validatedByLocation: isInsideGeofence,
        branchId: branchId,
      );

      // Save to recent pulses list (keep last 2)
      final pulseData = {
        'inside_geofence': isInsideGeofence,
        'distance': distance,
        'timestamp': timestamp,
        'latitude': latitude,
        'longitude': longitude,
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
      print('📊 Pulse #$_pulsesCount: ${isInsideGeofence ? "✅ INSIDE" : "❌ OUTSIDE"} geofence (${distance.toStringAsFixed(1)}m)');
      print('📋 Recent pulses in memory: ${_recentPulses.length}');

      // 1. Send warning for EVERY false pulse
      if (isInsideGeofence == false) {
        print('⚠️ WARNING: Pulse outside geofence - Distance: ${distance.toStringAsFixed(1)}m!');
        print('📱 Sending notification to user...');
        
        try {
          await NotificationService.instance.showGeofenceViolation(
            employeeName: 'الموظف',
            message: '⚠️ تحذير: أنت خارج منطقة العمل!\nالمسافة: ${distance.round()}م\nعد فوراً أو سيتم تسجيل انصراف تلقائي',
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
          print('   - First pulse: ${(firstPulse['distance'] as double).toStringAsFixed(1)}m outside');
          print('   - Second pulse: ${(secondPulse['distance'] as double).toStringAsFixed(1)}m outside');
          print('*** TRIGGERING AUTO CHECK-OUT ***');

          // Send final notification
          await NotificationService.instance.showGeofenceViolation(
            employeeName: 'الموظف',
            message: '🚨 تم تسجيل انصراف تلقائي!\nنبضتين خارج النطاق (10 دقائق)',
          );

          // Trigger auto check-out
          await _triggerAutoCheckout(
            latitude: latitude,
            longitude: longitude,
            distance: distance,
            wifiBssid: wifiBssid,
          );
          
          return; // Stop system after auto check-out
        }
      }

      notifyListeners();

    } catch (e) {
      print('Error sending pulse: $e');
      AppLogger.instance.log('Error sending pulse', level: AppLogger.error, tag: 'PulseTracking', error: e);
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
        print('   - First pulse: ${(firstPulse['distance'] as double).toStringAsFixed(1)}m outside');
        print('   - Second pulse: ${(secondPulse['distance'] as double).toStringAsFixed(1)}m outside');
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
      final attendanceId = _currentAttendanceId ?? await _resolveActiveAttendanceId();
      
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
            note: 'Auto check-out after 2 consecutive pulses outside geofence (${distance.round()}m)',
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
          notes: 'Auto check-out after 2 consecutive pulses outside geofence - will sync when online',
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
              notes: 'Auto check-out after 2 consecutive pulses outside geofence',
            );
          } catch (e) {
            print('SQLite save failed: $e');
          }
        }

        await NotificationService.instance.showOfflineModeNotification();
      }

      // ✅ Clear attendance state from SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_attendance_id');
        await prefs.setBool('is_checked_in', false);
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
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_attendance_id');
        await prefs.setBool('is_checked_in', false);
      } catch (_) {}
      
      // 🚨 Emit event for UI
      _emitAutoCheckoutEvent(timestamp, distance, savedOffline);
      
      await NotificationService.instance.showOfflineModeNotification();
      stopTracking(fromAutoCheckout: true);
    }
  }
  
  /// 🚨 Helper to emit auto-checkout event
  void _emitAutoCheckoutEvent(DateTime timestamp, double distance, bool savedOffline) {
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
        final isPlaceholder = RegExp(r'(pending|local|temp|dummy)', caseSensitive: false).hasMatch(storedId) || storedId.length < 8;
        if (!isPlaceholder) {
          _currentAttendanceId = storedId;
          return storedId;
        } else {
          // Clean up invalid cached placeholder
          await prefs.remove('active_attendance_id');
        }
      }
    } catch (e) {
      print('SharedPreferences read error: $e');
    }

    // Try getting from Supabase
    if (_currentEmployeeId != null) {
      try {
        final activeAttendance = await SupabaseAttendanceService.getActiveAttendance(_currentEmployeeId!);
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
    final dynamic wifiData = branchData['wifi_bssids'] ??
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

  /// Send manual pulse (for testing)
  Future<void> sendManualPulse(String employeeId) async {
    final branchData = await _offlineService.getCachedBranchData(employeeId: employeeId);
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
            return timestamp.isAfter(startOfDay) && timestamp.isBefore(endOfDay);
          } catch (e) {
            return false;
          }
        }).toList();
        
        print('📊 نبضات مزامنة (Hive): ${syncedPulses.length}, معلقة (SQLite): ${pendingPulses.length}');
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
      if (pulse['inside_geofence'] == 1) { // SQLite بيخزن int مش bool
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
  
  /// Refresh pulse count from database (called when native service records a pulse)
  Future<void> _refreshPulseCount() async {
    if (_currentEmployeeId == null) return;
    
    try {
      final stats = await getTrackingStats(_currentEmployeeId!);
      _pulsesCount = stats['total_pulses'] ?? 0;
      print('🔄 Pulse count refreshed: $_pulsesCount');
      notifyListeners();
    } catch (e) {
      print('⚠️ Error refreshing pulse count: $e');
    }
  }

  @override
  void dispose() {
    stopTracking();
    BackgroundPulseListener.dispose();
    super.dispose();
  }
}
