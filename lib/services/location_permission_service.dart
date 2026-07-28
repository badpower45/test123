import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:universal_io/io.dart';
import 'package:device_info_plus/device_info_plus.dart';

class LocationPermissionService {
  static const Duration _settingsDelay = Duration(seconds: 1);
  static const _pulseChannel = MethodChannel('persistent_pulse');

  /// Directive 3: Check if app is ignoring battery optimizations (whitelisted)
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? isIgnoring = await _pulseChannel.invokeMethod('isIgnoringBatteryOptimizations');
      return isIgnoring ?? await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (_) {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    }
  }

  /// Directive 3: Explicitly prompt user with ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS dialog
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? success = await _pulseChannel.invokeMethod('requestIgnoreBatteryOptimizations');
      if (success == true) return true;
    } catch (_) {}
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  static Future<bool> ensureAllPermissions({
    bool requestAlways = true,
    bool requestNotifications = true,
    bool requestBatteryOptimizations = true,
    bool requestExactAlarms = true,
  }) async {
    final hasLocation = await ensureLocationPermissions(
      requestAlways: requestAlways,
    );
    if (!hasLocation) {
      return false;
    }

    if (!kIsWeb && Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (requestNotifications && sdkInt >= 33) {
        await Permission.notification.request();
      }

      if (requestBatteryOptimizations) {
        await requestIgnoreBatteryOptimizations();
      }

      if (requestExactAlarms && sdkInt >= 31) {
        await Permission.scheduleExactAlarm.request();
      }
    } else if (!kIsWeb && Platform.isIOS) {
      if (requestNotifications) {
        await Permission.notification.request();
      }
    }

    return true;
  }

  static Future<bool> ensureLocationPermissions({
    bool requestAlways = true,
  }) async {
    if (kIsWeb) {
      return true;
    }

    if (!await _ensureLocationServiceEnabled()) {
      return false;
    }

    if (Platform.isAndroid) {
      final whenInUseGranted = await _ensurePermission(
        Permission.locationWhenInUse,
      );
      if (!whenInUseGranted) {
        return false;
      }

      if (requestAlways) {
        final alwaysGranted = await _ensurePermission(
          Permission.locationAlways,
        );
        if (!alwaysGranted) {
          return false;
        }
      }

      return true;
    }

    if (Platform.isIOS) {
      final whenInUseGranted = await _ensurePermission(Permission.locationWhenInUse);
      if (!whenInUseGranted) {
        return false;
      }

      if (requestAlways) {
        final alwaysGranted = await _ensurePermission(Permission.locationAlways);
        if (!alwaysGranted) {
          return false;
        }
      }
      return true;
    }

    return true;
  }

  static Future<bool> _ensureLocationServiceEnabled() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (enabled) {
        return true;
      }

      await Geolocator.openLocationSettings();
      await Future<void>.delayed(_settingsDelay);
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _ensurePermission(Permission permission) async {
    var status = await permission.status;
    if (status.isGranted) {
      return true;
    }

    status = await permission.request();
    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }

    return false;
  }

  static Future<bool> hasAllRequiredPermissions() async {
    if (kIsWeb) return true;
    
    final locationStatus = await Geolocator.checkPermission();
    final locationAlwaysGranted = locationStatus == LocationPermission.always;
    
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      
      bool notifGranted = true;
      if (sdkInt >= 33) {
        notifGranted = await Permission.notification.isGranted;
      }
      
      bool alarmGranted = true;
      if (sdkInt >= 31) {
        alarmGranted = await Permission.scheduleExactAlarm.isGranted;
      }
      
      bool activityGranted = true;
      if (sdkInt >= 29) {
        activityGranted = await Permission.activityRecognition.isGranted;
      }
      
      final batteryGranted = await isIgnoringBatteryOptimizations();
      
      return notifGranted &&
          locationAlwaysGranted &&
          alarmGranted &&
          activityGranted &&
          batteryGranted;
    }
    
    final notifGranted = await Permission.notification.isGranted;
    return notifGranted && locationAlwaysGranted;
  }
}

