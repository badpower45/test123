import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../models/pulse.dart';
import '../services/location_service.dart';
import 'pulse_backend_client.dart';
import 'pulse_history_repository.dart';
import 'pulse_sync_manager.dart';

class PulseConfig {
  PulseConfig({
    required this.employeeId,
    required this.restaurantLat,
    required this.restaurantLon,
    required this.radiusInMeters,
    required this.enforceLocation,
    this.allowedWifiBssid,
  });

  final String employeeId;
  final double restaurantLat;
  final double restaurantLon;
  final double radiusInMeters;
  final bool enforceLocation;
  final String? allowedWifiBssid;

  Map<String, dynamic> toMap() => {
        'employeeId': employeeId,
        'restaurantLat': restaurantLat,
        'restaurantLon': restaurantLon,
        'radiusInMeters': radiusInMeters,
        'enforceLocation': enforceLocation,
    'allowedWifiBssid': allowedWifiBssid,
      };

  static PulseConfig fromMap(Map<String, dynamic> map) => PulseConfig(
        employeeId: map['employeeId'] as String,
        restaurantLat: (map['restaurantLat'] as num).toDouble(),
        restaurantLon: (map['restaurantLon'] as num).toDouble(),
        radiusInMeters: (map['radiusInMeters'] as num).toDouble(),
    enforceLocation: (map['enforceLocation'] as bool?) ?? true,
    allowedWifiBssid: (map['allowedWifiBssid'] as String?),
      );
}

class BackgroundPulseService {
  BackgroundPulseService._();

  static Timer? _timer;
  static PulseConfig? _activeConfig;
  static bool _isTicking = false;
  static int _pulseCounter = 0;
  static final StreamController<Map<String, dynamic>?> _statusController =
      StreamController<Map<String, dynamic>?>.broadcast();

  static Future<void> initialize() async {
    // Background isolate setup for pulse service.
  }

  static Future<void> start(PulseConfig config) async {
    await initialize();
    _activeConfig = config;
    _pulseCounter = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    await _tick();
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _activeConfig = null;
    if (!_statusController.isClosed) {
      _statusController.add(null);
    }
  }

  static Stream<Map<String, dynamic>?> statusStream() =>
      _statusController.stream;

  static Future<void> _tick() async {
    if (_isTicking) {
      return;
    }
    final config = _activeConfig;
    if (config == null) {
      return;
    }

    _isTicking = true;
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      final isOnline =
          connectivityResults.any((result) => result != ConnectivityResult.none);

    double latitude;
    double longitude;
    double distance;
    bool isInside;

      if (config.enforceLocation) {
        final position = await LocationService().tryGetPosition();
        if (position == null) {
          final pendingOfflineCount = await PulseSyncManager.pendingPulseCount();
          final totalPulseCount = await PulseHistoryRepository.totalPulseCount();
          final monthlyPulseCount =
              await PulseHistoryRepository.monthlyPulseCount(DateTime.now());
          _statusController.add({
            'isOnline': isOnline,
            'locationEnforced': config.enforceLocation,
            'locationUnavailable': true,
            'pendingOfflineCount': pendingOfflineCount,
            'pulseCounter': _pulseCounter,
            'totalPulseCount': totalPulseCount,
            'monthlyPulseCount': monthlyPulseCount,
          });
          return;
        }
        latitude = position.latitude;
        longitude = position.longitude;
        distance = Geolocator.distanceBetween(
          config.restaurantLat,
          config.restaurantLon,
          latitude,
          longitude,
        );
        isInside = distance <= config.radiusInMeters;
      } else {
        latitude = config.restaurantLat;
        longitude = config.restaurantLon;
        distance = 0;
        isInside = true;
      }

      String? wifiBssid;
      try {
        final networkInfo = NetworkInfo();
        wifiBssid = await networkInfo.getWifiBSSID();
      } catch (_) {
        wifiBssid = null;
      }

      bool wifiValid = true;
      final allowedWifi = config.allowedWifiBssid?.toUpperCase().trim();
      if (allowedWifi != null && allowedWifi.isNotEmpty) {
        final normalizedBssid = wifiBssid?.toUpperCase().trim();
        wifiValid = normalizedBssid != null && normalizedBssid == allowedWifi;
      }

      final geofenceValid = isInside;

      final timestamp = DateTime.now().toUtc();
      final pulse = Pulse(
        employeeId: config.employeeId,
        latitude: latitude,
        longitude: longitude,
        timestamp: timestamp,
        wifiBssid: wifiBssid,
        isWithinGeofence: geofenceValid,
      );

      _pulseCounter++;

      var sentOnline = false;
      var queuedOffline = false;

      if (isOnline) {
        final sent = await _sendPulse(pulse);
        if (sent) {
          sentOnline = true;
        } else {
          await PulseSyncManager.storePulseOffline(pulse);
          queuedOffline = true;
        }
      } else {
        await PulseSyncManager.storePulseOffline(pulse);
        queuedOffline = true;
      }

      final pendingOfflineCount = await PulseSyncManager.pendingPulseCount();
      final totalPulseCount = await PulseHistoryRepository.recordPulse(
        pulse: pulse,
        wasOnline: isOnline,
        sentOnline: sentOnline,
        queuedOffline: queuedOffline,
      );
      final monthlyPulseCount =
          await PulseHistoryRepository.monthlyPulseCount(DateTime.now());

      _statusController.add({
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'distanceInMeters': distance,
        'isInsidePerimeter': geofenceValid,
        'geofenceValid': geofenceValid,
        'wifiValid': wifiValid,
        'requiredWifiBssid': config.allowedWifiBssid,
        'wifiBssid': wifiBssid,
        'isOnline': isOnline,
        'sentOnline': sentOnline,
        'queuedOffline': queuedOffline,
        'pulseCounter': _pulseCounter,
        'pendingOfflineCount': pendingOfflineCount,
        'locationEnforced': config.enforceLocation,
        'totalPulseCount': totalPulseCount,
        'monthlyPulseCount': monthlyPulseCount,
      });
    } finally {
      _isTicking = false;
    }
  }
}

Future<bool> _sendPulse(Pulse pulse) async {
  final sent = await PulseBackendClient.sendPulse(pulse);
  return sent;
}
