import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../database/offline_database.dart';
import 'native_location_service.dart';
import 'pulse_deduplication_service.dart';
import 'wifi_service.dart';

/// 🎧 Background Pulse Listener
///
/// Listens for pulses recorded by Native Service (PersistentPulseService.kt)
/// and saves them to SQLite database
class BackgroundPulseListener {
  static const MethodChannel _channel = MethodChannel(
    'background_pulse_callback',
  );
  static bool _isInitialized = false;
  static Function()? _onPulseRecordedCallback;

  /// Initialize the listener
  static Future<void> initialize({Function()? onPulseRecorded}) async {
    if (!Platform.isAndroid) {
      print('⚠️ Background pulse listener only works on Android');
      return;
    }

    if (_isInitialized) {
      print('⚠️ Background pulse listener already initialized');
      return;
    }

    _onPulseRecordedCallback = onPulseRecorded;

    // Set up method call handler
    _channel.setMethodCallHandler(_handleMethodCall);

    _isInitialized = true;
    print('✅ Background pulse listener initialized');
  }

  /// Handle method calls from Native
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPulseRecorded':
        return await _onPulseRecorded(call.arguments);
      default:
        print('⚠️ Unknown method: ${call.method}');
        return null;
    }
  }

  /// Handle pulse recorded event from Native Service
  static Future<void> _onPulseRecorded(dynamic arguments) async {
    try {
      print('💓 Pulse received from native service');

      if (arguments == null) {
        print('⚠️ No pulse data provided');
        return;
      }

      final Map<dynamic, dynamic> data = arguments as Map<dynamic, dynamic>;
      final employeeId = data['employee_id'] as String?;
      final attendanceId = data['attendance_id'] as String?;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        data['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );
      final pulseCount = data['pulse_count'] as int? ?? 0;

      if (employeeId == null || employeeId.isEmpty) {
        print('❌ Invalid employee ID in pulse data');
        return;
      }

      print(
        '📋 Pulse details: Employee=$employeeId, Count=$pulseCount, Time=$timestamp',
      );

      // Get branch data from cache to validate geofence
      Map<String, dynamic>? branchData;
      try {
        final box = await Hive.openBox('branch_data');
        final cachedData = box.get('branch_$employeeId');
        await box.close();

        if (cachedData != null && cachedData is Map) {
          branchData = Map<String, dynamic>.from(cachedData);
          print('📍 Branch loaded: ${branchData['name']}');
        }
      } catch (e) {
        print('⚠️ Could not load branch data: $e');
      }

      // Get current location using Native GPS (ultra fast!)
      final position = await NativeLocationService.getCurrentLocation();

      if (position == null) {
        print(
          '⚠️ Could not get location for pulse - saving with null coordinates',
        );
      }

      // Calculate geofence validation
      bool insideGeofence = false;
      double distance = 0.0;
      String? wifiBssid;
      bool validatedByWifi = false;
      final branchId = branchData?['id'] ?? branchData?['branch_id'];

      if (branchData != null) {
        final centerLat = branchData['latitude'] as double?;
        final centerLng = branchData['longitude'] as double?;
        final radius =
            (branchData['geofence_radius'] as num?)?.toDouble() ?? 100.0;

        // Check WiFi first (faster and more reliable indoors)
        try {
          wifiBssid = await WiFiService.getCurrentWifiBssidValidated();
          final rawBssids = branchData['wifi_bssids'];
          final requiredBssids = rawBssids is List
              ? rawBssids.map((e) => e.toString().trim().toUpperCase()).toList()
              : rawBssids is String
              ? rawBssids
                    .replaceAll('[', '')
                    .replaceAll(']', '')
                    .replaceAll('"', '')
                    .split(',')
                    .map((e) => e.trim().toUpperCase())
                    .where((e) => e.isNotEmpty)
                    .toList()
              : <String>[];

          if (requiredBssids.isNotEmpty &&
              requiredBssids.contains(WiFiService.normalizeBssid(wifiBssid))) {
            insideGeofence = true;
            validatedByWifi = true;
            print('✅ WiFi validated: $wifiBssid');
          }
        } catch (e) {
          print('⚠️ WiFi check error: $e');
        }

        // If WiFi didn't validate, check GPS
        if (!validatedByWifi &&
            position != null &&
            centerLat != null &&
            centerLng != null) {
          distance = _calculateDistance(
            centerLat,
            centerLng,
            position.latitude,
            position.longitude,
          );
          insideGeofence = distance <= radius;
          print(
            '📏 Distance: ${distance.toStringAsFixed(1)}m, Inside: $insideGeofence',
          );
        }
      }

      if (await PulseDeduplicationService.shouldSkipPulse(
        employeeId: employeeId,
        attendanceId: attendanceId,
        timestamp: timestamp,
      )) {
        print('⏭️ Skipping duplicate native pulse: $employeeId @ $timestamp');
        return;
      }

      // Save pulse to SQLite
      final db = OfflineDatabase.instance;
      final validationMethod = validatedByWifi
          ? 'WIFI'
          : (position != null ? 'LOCATION' : 'UNKNOWN');
      await db.insertPendingPulse(
        employeeId: employeeId,
        attendanceId: attendanceId,
        branchId: branchId?.toString(),
        timestamp: timestamp,
        latitude: position?.latitude,
        longitude: position?.longitude,
        insideGeofence: insideGeofence,
        distanceFromCenter: distance,
        wifiBssid: wifiBssid,
        validationMethod: validationMethod,
        validatedByWifi: validatedByWifi,
        validatedByLocation: position != null && !validatedByWifi,
      );
      await PulseDeduplicationService.markPulseRecorded(
        employeeId: employeeId,
        attendanceId: attendanceId,
        timestamp: timestamp,
        source: 'native_listener',
      );

      print(
        '✅ Pulse #$pulseCount saved to SQLite (${insideGeofence ? "INSIDE" : "OUTSIDE"})',
      );

      // Trigger callback if registered
      _onPulseRecordedCallback?.call();
    } catch (e) {
      print('❌ Error handling pulse from native: $e');
    }
  }

  /// Calculate distance between two points in meters (Haversine formula)
  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0;

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  /// Dispose the listener
  static void dispose() {
    _channel.setMethodCallHandler(null);
    _onPulseRecordedCallback = null;
    _isInitialized = false;
    print('🛑 Background pulse listener disposed');
  }
}
