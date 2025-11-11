import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'local_geofence_service.dart';
import 'offline_data_service.dart';
import 'notification_service.dart';
import 'wifi_service.dart';

/// Violation severity levels
enum ViolationSeverity {
  warning,    // ⚠️ First time outside - warning only
  penalty,    // ❌ Still outside - time not counted
  resolved,   // ✅ Returned to geofence
}

/// Pulse tracking service - sends location pulse every 5 minutes
/// Validates geofence locally and tracks time inside the area
/// ⚠️ NEW: Violation tracking system with warnings and penalties
class PulseTrackingService extends ChangeNotifier {
  static final PulseTrackingService _instance = PulseTrackingService._internal();
  factory PulseTrackingService() => _instance;
  PulseTrackingService._internal();

  Timer? _pulseTimer;
  bool _isTracking = false;
  DateTime? _lastPulseTime;
  int _pulsesCount = 0;
  String? _currentAttendanceId; // ✅ Store attendance_id for pulse linking
  
  // ⚠️ NEW: Violation tracking
  bool _wasOutsideLastPulse = false;
  int _consecutiveViolations = 0;
  DateTime? _lastViolationTime;
  String? _currentViolationMessage;
  ViolationSeverity? _currentViolationSeverity;
  
  final _offlineService = OfflineDataService();

  // Pulse interval: 5 minutes
  static const Duration _pulseInterval = Duration(minutes: 5);

  bool get isTracking => _isTracking;
  DateTime? get lastPulseTime => _lastPulseTime;
  int get pulsesCount => _pulsesCount;
  bool get hasActiveViolation => _currentViolationMessage != null;
  String? get violationMessage => _currentViolationMessage;
  ViolationSeverity? get violationSeverity => _currentViolationSeverity;

  /// Start pulse tracking
  Future<void> startTracking(String employeeId, {String? attendanceId}) async {
    if (_isTracking) {
      print('⚠️ Pulse tracking already running for employee: $employeeId');
      return;
    }

    print('🎯 Starting pulse tracking for employee: $employeeId (attendance: $attendanceId)');
    
    // ✅ Store attendance_id for linking pulses
    _currentAttendanceId = attendanceId;
    
    // ✅ Check if branch data is downloaded (with employee ID)
    final branchData = await _offlineService.getCachedBranchData(employeeId: employeeId);
    if (branchData == null) {
      print('❌ Cannot start tracking: Branch data not downloaded for employee $employeeId');
      return;
    }

    print('✅ Branch data loaded: ${branchData['name']}');
    print('📍 Location: ${branchData['latitude']}, ${branchData['longitude']}');
    print('🎯 Radius: ${branchData['geofence_radius']}m');

    _isTracking = true;
    _pulsesCount = 0;
    notifyListeners();

    // Send first pulse immediately
    await _sendPulse(employeeId, branchData);

    // Schedule periodic pulses every 5 minutes
    _pulseTimer = Timer.periodic(_pulseInterval, (timer) async {
      await _sendPulse(employeeId, branchData);
    });

    print('✅ Pulse tracking started (every ${_pulseInterval.inMinutes} minutes)');
  }

  /// Stop pulse tracking
  void stopTracking() {
    if (!_isTracking) {
      print('⚠️ Pulse tracking not running');
      return;
    }

    _pulseTimer?.cancel();
    _pulseTimer = null;
    _isTracking = false;
    _lastPulseTime = null;
    _pulsesCount = 0;
    _wasOutsideLastPulse = false;
    _consecutiveViolations = 0;
    _currentViolationMessage = null;
    _currentViolationSeverity = null;
    notifyListeners();

    print('🛑 Pulse tracking stopped');
  }

  /// Acknowledge current violation (user pressed OK)
  void acknowledgeViolation() {
    _currentViolationMessage = null;
    _currentViolationSeverity = null;
    notifyListeners();
    print('✅ Violation acknowledged by user');
  }

  /// Send a single pulse
  Future<void> _sendPulse(String employeeId, Map<String, dynamic> branchData) async {
    try {
      final centerLat = branchData['latitude'] as double?;
      final centerLng = branchData['longitude'] as double?;
      final radius = (branchData['geofence_radius'] as num?)?.toDouble() ?? 100.0;

      if (centerLat == null || centerLng == null) {
        print('❌ Invalid branch location data');
        return;
      }

      // Validate geofence with current location
      final result = await LocalGeofenceService.validateGeofence(
        centerLat: centerLat,
        centerLng: centerLng,
        radiusMeters: radius,
      );

      if (result == null) {
        print('❌ Could not get location for pulse');
        return;
      }

      final requiredBssids = _extractRequiredBssids(branchData);
      String? wifiBssid;
      bool wifiValidated = false;

      if (requiredBssids.isNotEmpty) {
        try {
          wifiBssid = await WiFiService.getCurrentWifiBssidValidated();
          wifiValidated = requiredBssids.contains(wifiBssid);
          print('📶 Pulse Wi-Fi check: current=$wifiBssid, required=${requiredBssids.join(', ')}, match=$wifiValidated');
        } catch (wifiError) {
          print('⚠️ Pulse Wi-Fi validation failed: $wifiError');
        }
      }

      final isInside = result['inside_geofence'] as bool;
      final distance = result['distance'] as double;
      final pulseAccepted = isInside || wifiValidated;

      if (!pulseAccepted) {
        // Employee is OUTSIDE geofence and Wi-Fi validation failed
        await _handleOutsideGeofence(
          employeeId,
          distance,
          radius,
          result,
          wifiBssid: wifiBssid,
          wifiValidated: wifiValidated,
          locationValidated: isInside,
        );
      } else {
        // Pulse accepted via GPS, Wi-Fi, or both
        await _handleInsideGeofence(
          employeeId,
          distance,
          result,
          locationValidated: isInside,
          wifiValidated: wifiValidated,
          wifiBssid: wifiBssid,
        );
      }

      _lastPulseTime = result['timestamp'];
      _pulsesCount++;
      notifyListeners();

    } catch (e) {
      print('❌ Error sending pulse: $e');
    }
  }

  /// Handle pulse when employee is OUTSIDE geofence
  Future<void> _handleOutsideGeofence(
    String employeeId,
    double distance,
    double radius,
    Map<String, dynamic> result, {
    String? wifiBssid,
    bool wifiValidated = false,
    bool locationValidated = false,
  }) async {
    if (!_wasOutsideLastPulse) {
      // ⚠️ FIRST violation - Warning only
      _consecutiveViolations = 1;
      _wasOutsideLastPulse = true;
      _lastViolationTime = DateTime.now();
      
      _currentViolationMessage = 
        '⚠️ تحذير!\n'
        'أنت خارج منطقة العمل\n'
        'المسافة: ${distance.round()}م من ${radius.round()}م\n'
        'يرجى العودة إلى موقع العمل فوراً';
      
      _currentViolationSeverity = ViolationSeverity.warning;
      
      print('⚠️ Pulse #$_pulsesCount: FIRST VIOLATION - Warning sent');
      print('📍 Distance: ${distance.toStringAsFixed(1)}m (outside ${radius.toStringAsFixed(1)}m radius)');
      
      // Save pulse (counted but marked as violation)
      await _offlineService.saveLocalPulse(
        employeeId: employeeId,
        attendanceId: _currentAttendanceId,
        timestamp: result['timestamp'],
        latitude: result['latitude'],
        longitude: result['longitude'],
        insideGeofence: false,
        distanceFromCenter: distance,
        wifiBssid: wifiBssid,
        validatedByWifi: wifiValidated,
        validatedByLocation: locationValidated,
      );
      
      // Send notification
      await NotificationService.instance.showGeofenceViolation(
        employeeName: 'الموظف',
        message: 'أنت خارج منطقة العمل! المسافة: ${distance.round()}م',
      );
      
    } else {
      // ❌ SECOND+ violation - Penalty applied
      _consecutiveViolations++;
      
      _currentViolationMessage = 
        '❌ تحذير نهائي!\n'
        'أنت لا زلت خارج منطقة العمل\n'
        'المسافة: ${distance.round()}م من ${radius.round()}م\n'
        'الـ5 دقائق القادمة لن تُحتسب من وقت عملك!\n'
        'يرجى العودة فوراً';
      
      _currentViolationSeverity = ViolationSeverity.penalty;
      
      print('❌ Pulse #$_pulsesCount: PENALTY - Not counted (violation #$_consecutiveViolations)');
      print('📍 Distance: ${distance.toStringAsFixed(1)}m (outside ${radius.toStringAsFixed(1)}m radius)');
      print('⏱️ This 5-minute interval will NOT be counted');
      
      // ❌ Do NOT save pulse - penalty means not counted
      // Only log the violation
      
      // Send critical notification
      await NotificationService.instance.showGeofenceViolation(
        employeeName: 'الموظف',
        message: '❌ الـ5 دقائق القادمة لن تُحتسب! أنت خارج منطقة العمل: ${distance.round()}م',
      );
    }
    
    notifyListeners();
  }

  /// Handle pulse when employee is INSIDE geofence
  Future<void> _handleInsideGeofence(
    String employeeId,
    double distance,
    Map<String, dynamic> result, {
    required bool locationValidated,
    required bool wifiValidated,
    String? wifiBssid,
  }) async {
    // Check if employee just returned
    if (_wasOutsideLastPulse) {
      print('✅ Employee RETURNED to geofence after $_consecutiveViolations violation(s)');
      _currentViolationMessage = 
        '✅ عودة آمنة!\n'
        'لقد عدت إلى منطقة العمل\n'
        'المسافة: ${distance.round()}م من المركز\n'
        'سيتم احتساب وقتك بشكل طبيعي الآن';
      
      _currentViolationSeverity = ViolationSeverity.resolved;
    }
    
    // Reset violation tracking
    _wasOutsideLastPulse = false;
    _consecutiveViolations = 0;
    
    // Save pulse normally (counted)
    await _offlineService.saveLocalPulse(
      employeeId: employeeId,
      attendanceId: _currentAttendanceId,
      timestamp: result['timestamp'],
      latitude: result['latitude'],
      longitude: result['longitude'],
      insideGeofence: true,
      distanceFromCenter: distance,
      wifiBssid: wifiBssid,
      validatedByWifi: wifiValidated,
      validatedByLocation: locationValidated,
    );
    
    final validationSources = <String>[];
    if (locationValidated) validationSources.add('GPS');
    if (wifiValidated) validationSources.add('Wi-Fi');
    final validationLabel = validationSources.isEmpty
        ? 'Manual'
        : validationSources.join(' + ');

    print('✅ Pulse #$_pulsesCount: accepted via $validationLabel (${distance.toStringAsFixed(1)}m from center)');
    notifyListeners();
  }

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

  /// Force send a pulse now (for testing)
  Future<void> sendManualPulse(String employeeId) async {
    final branchData = await _offlineService.getCachedBranchData(employeeId: employeeId);
    if (branchData == null) {
      print('❌ Cannot send pulse: Branch data not downloaded for employee $employeeId');
      return;
    }

    await _sendPulse(employeeId, branchData);
  }

  /// Get tracking statistics
  Future<Map<String, dynamic>> getTrackingStats(String employeeId) async {
    final today = DateTime.now();
    final pulses = await _offlineService.getPulsesForDate(
      employeeId: employeeId,
      date: today,
    );

    int insideCount = 0;
    int outsideCount = 0;
    int wifiValidatedCount = 0;
    int locationValidatedCount = 0;

    for (var pulse in pulses) {
      if (pulse['inside_geofence'] == true) {
        insideCount++;
      } else {
        outsideCount++;
      }

      if (pulse['validated_by_wifi'] == true) {
        wifiValidatedCount++;
      }

      if (pulse['validated_by_location'] == true) {
        locationValidatedCount++;
      }
    }

    final totalMinutes = insideCount * 5;
    final hours = totalMinutes / 60;

    return {
      'total_pulses': pulses.length,
      'inside_geofence': insideCount,
      'outside_geofence': outsideCount,
      'validated_by_wifi': wifiValidatedCount,
      'validated_by_location': locationValidatedCount,
      'total_minutes': totalMinutes,
      'total_hours': hours,
      'is_tracking': _isTracking,
      'last_pulse': _lastPulseTime?.toIso8601String(),
      'last_violation': _lastViolationTime?.toIso8601String(),
    };
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
