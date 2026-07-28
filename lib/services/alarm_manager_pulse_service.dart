import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../database/offline_database.dart';
import 'wifi_service.dart';
import 'offline_data_service.dart';
import 'notification_service.dart';
import 'supabase_function_client.dart';
import 'app_logger.dart';
import 'attendance_timer_service.dart';
import '../utils/time_utils.dart';

/// Backup pulse mechanism using Android AlarmManager
/// Guarantees periodic execution even if foreground service fails
/// ⚠️ This is a FALLBACK - the foreground service is primary
/// ✅ Enhanced with: Permission request for Android 12+ (SCHEDULE_EXACT_ALARM)
@pragma('vm:entry-point')
class AlarmManagerPulseService {
  static final AlarmManagerPulseService _instance = AlarmManagerPulseService._internal();
  factory AlarmManagerPulseService() => _instance;
  AlarmManagerPulseService._internal();

  static const int _alarmId = 9876;
  static const Duration _alarmInterval = Duration(minutes: 5);
  bool _isRegistered = false;

  /// Check if platform supports AlarmManager (Android only)
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// ✅ Request SCHEDULE_EXACT_ALARM permission (Android 12+)
  Future<bool> requestExactAlarmPermission() async {
    if (!isSupported) {
      return true; // Not Android, no permission needed
    }

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      
      // Android 12 (API 31) and above require SCHEDULE_EXACT_ALARM permission
      if (sdkInt >= 31) {
        AppLogger.instance.log('Android $sdkInt detected - requesting SCHEDULE_EXACT_ALARM permission', 
          tag: 'AlarmManager');
        
        final status = await Permission.scheduleExactAlarm.status;
        
        if (status.isGranted) {
          AppLogger.instance.log('SCHEDULE_EXACT_ALARM permission already granted', 
            tag: 'AlarmManager');
          return true;
        }
        
        // Request permission
        final result = await Permission.scheduleExactAlarm.request();
        
        if (result.isGranted) {
          AppLogger.instance.log('SCHEDULE_EXACT_ALARM permission granted', 
            tag: 'AlarmManager');
          return true;
        } else if (result.isDenied) {
          AppLogger.instance.log('SCHEDULE_EXACT_ALARM permission denied', 
            level: AppLogger.warning, tag: 'AlarmManager');
          return false;
        } else if (result.isPermanentlyDenied) {
          AppLogger.instance.log('SCHEDULE_EXACT_ALARM permission permanently denied - guiding user to settings', 
            level: AppLogger.warning, tag: 'AlarmManager');
          // Guide user to settings
          await openAppSettings();
          return false;
        }
      } else {
        // Android 11 and below don't need this permission
        AppLogger.instance.log('Android $sdkInt - no SCHEDULE_EXACT_ALARM permission needed', 
          tag: 'AlarmManager');
        return true;
      }
      
      return false;
    } catch (e) {
      AppLogger.instance.log('Error requesting SCHEDULE_EXACT_ALARM permission', 
        level: AppLogger.error, tag: 'AlarmManager', error: e);
      return false;
    }
  }

  /// Check if the app can schedule exact alarms
  Future<bool> canScheduleExactAlarms() async {
    if (!isSupported) return false;
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      if (sdkInt >= 31) {
        return await Permission.scheduleExactAlarm.isGranted;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Initialize the alarm manager service
  Future<bool> initialize() async {
    if (!isSupported) {
      AppLogger.instance.log('AlarmManager not supported on this platform', 
        level: AppLogger.info, tag: 'AlarmManager');
      return false;
    }

    try {
      await AndroidAlarmManager.initialize();
      
      // Restore registration state
      final prefs = await SharedPreferences.getInstance();
      _isRegistered = prefs.getBool('alarm_periodic_registered') ?? false;
      
      AppLogger.instance.log('AlarmManager initialized successfully (registered: $_isRegistered)', 
        tag: 'AlarmManager');
      return true;
    } catch (e) {
      AppLogger.instance.log('Failed to initialize AlarmManager', 
        level: AppLogger.error, tag: 'AlarmManager', error: e);
      return false;
    }
  }

  /// Start periodic alarms for pulse tracking
  /// This runs independently of the foreground service
  Future<bool> startPeriodicAlarms(String employeeId) async {
    if (!isSupported) {
      return false;
    }

    try {
      // Cancel any existing alarms first
      await AndroidAlarmManager.cancel(_alarmId);

      // Store employee ID for background callback
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('alarm_employee_id', employeeId);

      final canExact = await canScheduleExactAlarms();

      // Schedule periodic alarm (every 5 minutes)
      final success = await AndroidAlarmManager.periodic(
        _alarmInterval,
        _alarmId,
        alarmCallback,
        wakeup: true,
        allowWhileIdle: true,
        exact: canExact,
        rescheduleOnReboot: true,
      );

      if (success) {
        await prefs.setBool('alarm_periodic_registered', true);
        _isRegistered = true;
        AppLogger.instance.log('Periodic alarms started for employee $employeeId', 
          tag: 'AlarmManager');
      } else {
        AppLogger.instance.log('Failed to schedule periodic alarms', 
          level: AppLogger.error, tag: 'AlarmManager');
      }

      return success;
    } catch (e) {
      AppLogger.instance.log('Error starting periodic alarms', 
        level: AppLogger.error, tag: 'AlarmManager', error: e);
      return false;
    }
  }

  /// Stop periodic alarms
  Future<bool> stopPeriodicAlarms() async {
    if (!isSupported) {
      return false;
    }

    try {
      await AndroidAlarmManager.cancel(_alarmId);
      
      // Clean up stored employee ID and registration state
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('alarm_employee_id');
      await prefs.setBool('alarm_periodic_registered', false);
      _isRegistered = false;

      AppLogger.instance.log('Periodic alarms stopped', tag: 'AlarmManager');
      return true;
    } catch (e) {
      AppLogger.instance.log('Error stopping periodic alarms', 
        level: AppLogger.error, tag: 'AlarmManager', error: e);
      return false;
    }
  }

  /// Check if alarms are currently registered
  bool get isRegistered => _isRegistered;

  /// Static callback - executed by AlarmManager in background
  /// ⚠️ This runs in an isolate, has limited context
  @pragma('vm:entry-point')
  static Future<void> alarmCallback() async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      AppLogger.instance.log('Alarm fired - executing backup pulse', 
        tag: 'AlarmManager');

      // Get employee ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('alarm_employee_id');
      
      if (employeeId == null) {
        AppLogger.instance.log('No employee ID found in alarm callback', 
          level: AppLogger.warning, tag: 'AlarmManager');
        return;
      }

      // Check if pulse tracking is active
      final trackingActive = prefs.getBool('pulse_tracking_active') ?? false;
      if (!trackingActive) {
        AppLogger.instance.log('Pulse tracking is inactive - skipping backup alarm pulse', 
          tag: 'AlarmManager');
        return;
      }

      // Get branch data (stored by PulseTrackingService)
      final branchDataJson = prefs.getString('current_branch_data');
      if (branchDataJson == null) {
        AppLogger.instance.log('No branch data found in alarm callback', 
          level: AppLogger.warning, tag: 'AlarmManager');
        return;
      }

      final Map<String, dynamic> branchData = jsonDecode(branchDataJson);

      // Check if already sent pulse recently (avoid duplicate with foreground service)
      final lastPulseTimeStr = prefs.getString('last_pulse_time');
      if (lastPulseTimeStr != null) {
        final DateTime? lastPulseTime = TimeUtils.parseTimestamp(lastPulseTimeStr);
        if (lastPulseTime != null) {
          final timeSinceLastPulse = DateTime.now().difference(lastPulseTime);
          
          // If pulse sent less than 4 minutes ago, skip (foreground service is working)
          if (timeSinceLastPulse < const Duration(minutes: 4)) {
            AppLogger.instance.log('Skipping alarm pulse - recent pulse detected (${timeSinceLastPulse.inMinutes}min ago)', 
              tag: 'AlarmManager');
            return;
          }
        }
      }

      AppLogger.instance.log('Triggering background backup pulse for employee $employeeId', 
        tag: 'AlarmManager');
      
      // Store alarm execution time
      await prefs.setString('last_alarm_execution', DateTime.now().toIso8601String());

      // Initialize Supabase in background
      try {
        await SupabaseConfig.initialize();
      } catch (supabaseInitError) {
        AppLogger.instance.log('Supabase init skipped/failed in AlarmManager background', 
          level: AppLogger.warning, tag: 'AlarmManager', error: supabaseInitError);
      }

      // Get branch details
      final centerLat = branchData['latitude'] as double?;
      final centerLng = branchData['longitude'] as double?;
      final baseRadius = (branchData['geofence_radius'] as num?)?.toDouble() ?? 100.0;
      final extraTolerance = ((branchData['distance_from_radius'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 500.0);
      final radius = baseRadius + extraTolerance;
      final branchId = (branchData['id'] ?? branchData['branch_id']) as String?;

      if (centerLat == null || centerLng == null) {
        AppLogger.instance.log('Invalid branch coordinates in alarm callback', 
          level: AppLogger.error, tag: 'AlarmManager');
        return;
      }

      // 0. Check if break is active
      final isBreakActive = prefs.getBool('is_break_active') ?? false;

      bool insideGeofence = false;
      double distance = 0.0;
      double? latResult = centerLat;
      double? lngResult = centerLng;
      bool validatedByLocation = false;
      bool wifiValidated = false;
      String? wifiBssid;

      if (isBreakActive) {
        insideGeofence = true;
        distance = 0.0;
        AppLogger.instance.log('Active Break detected in backup alarm callback - overriding to INSIDE safety zone',
          tag: 'AlarmManager');
      } else {
        // 1. Check Wi-Fi BSSID if configured
        List<String> requiredBssids = [];
        if (branchData['wifi_bssids_array'] is List) {
          requiredBssids = (branchData['wifi_bssids_array'] as List)
              .map((e) => e.toString().toUpperCase())
              .toList();
        }

        if (requiredBssids.isNotEmpty) {
          try {
            wifiBssid = await WiFiService.getCurrentWifiBssidValidated();
            if (wifiBssid.isNotEmpty) {
              wifiValidated = requiredBssids.contains(wifiBssid.toUpperCase());
            }
          } catch (e) {
            AppLogger.instance.log('WiFi check failed in alarm callback', 
              level: AppLogger.warning, tag: 'AlarmManager', error: e);
          }
        }

        insideGeofence = wifiValidated;

        // 2. Check GPS if Wi-Fi did not validate
        if (!wifiValidated) {
          Position? position;
          try {
            late final LocationSettings locationSettings;
            if (Platform.isAndroid) {
              locationSettings = AndroidSettings(
                accuracy: LocationAccuracy.high,
                forceLocationManager: true,
                timeLimit: const Duration(seconds: 10),
              );
            } else if (Platform.isIOS) {
              locationSettings = AppleSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: const Duration(seconds: 10),
                allowBackgroundLocationUpdates: true,
                showBackgroundLocationIndicator: true,
              );
            } else {
              locationSettings = const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 10),
              );
            }

            position = await Geolocator.getCurrentPosition(
              locationSettings: locationSettings,
            );
          } catch (e) {
            AppLogger.instance.log('Could not get GPS in alarm callback, trying last known position', 
              level: AppLogger.warning, tag: 'AlarmManager', error: e);
            try {
              position = await Geolocator.getLastKnownPosition();
            } catch (pe) {
              AppLogger.instance.log('Last known position failed too', 
                level: AppLogger.warning, tag: 'AlarmManager', error: pe);
            }
          }

          if (position != null) {
            latResult = position.latitude;
            lngResult = position.longitude;
            distance = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              centerLat,
              centerLng,
            );

            final bool staleLocation = DateTime.now().difference(position.timestamp).abs() > const Duration(minutes: 5);
            final bool weakAccuracy = position.accuracy > 150.0;
            final bool gpsReliable = !staleLocation && !weakAccuracy;

            if (gpsReliable) {
              insideGeofence = distance <= radius;
              validatedByLocation = insideGeofence;
            } else {
              // Guardrail: if GPS is unreliable, don't penalize. Assume inside.
              insideGeofence = true;
              distance = 0.0;
              latResult = centerLat;
              lngResult = centerLng;
              validatedByLocation = false;
              AppLogger.instance.log('GPS sample unreliable in background alarm - using center safety fallback', 
                level: AppLogger.info, tag: 'AlarmManager');
            }
          } else {
            // GPS failed completely and no wifi validation - Safety Fallback INSIDE
            insideGeofence = true;
            distance = 0.0;
            latResult = centerLat;
            lngResult = centerLng;
            validatedByLocation = false;
            AppLogger.instance.log('GPS and WiFi checks failed in alarm callback - using safety fallback INSIDE', 
              level: AppLogger.info, tag: 'AlarmManager');
          }
        }
      }

      final attendanceId = prefs.getString('active_attendance_id');
      final timestamp = DateTime.now();

      // Record local pulse (it automatically tries syncing to Supabase and falls back to SQLite)
      final offlineService = OfflineDataService();
      await offlineService.saveLocalPulse(
        employeeId: employeeId,
        attendanceId: attendanceId,
        timestamp: timestamp,
        latitude: latResult,
        longitude: lngResult,
        insideGeofence: insideGeofence,
        distanceFromCenter: distance,
        wifiBssid: wifiBssid,
        validatedByWifi: wifiValidated,
        validatedByLocation: validatedByLocation,
        branchId: branchId,
      );

      // Save last pulse time in prefs so the foreground service knows
      await prefs.setString('last_pulse_time', timestamp.toIso8601String());
      await prefs.setDouble('last_known_distance_$employeeId', distance);

      if (insideGeofence) {
        await AttendanceTimerService.resumeTimerLocally();
      } else {
        await AttendanceTimerService.pauseTimerLocally(reason: 'خارج نطاق الفرع');
      }

      AppLogger.instance.log('Backup pulse executed successfully via alarmCallback. Inside: $insideGeofence', 
        tag: 'AlarmManager');

      // Warn if outside geofence, but DO NOT checkout
      if (!insideGeofence) {
        AppLogger.instance.log('Alarm callback: employee is outside geofence. Showing warning notification.', 
          level: AppLogger.warning, tag: 'AlarmManager');

        try {
          await NotificationService.instance.initialize();
          await NotificationService.instance.showGeofenceViolation(
            employeeName: 'الموظف',
            message: '⚠️ تحذير: أنت خارج نطاق الفرع! يرجى العودة، فلن يتم احتساب وقت عملك طالما كنت بالخارج.',
          );
        } catch (e) {
          AppLogger.instance.log('Failed to show warning notification', level: AppLogger.warning, tag: 'AlarmManager', error: e);
        }
      }
      
    } catch (e) {
      AppLogger.instance.log('Error in alarm callback', 
        level: AppLogger.error, tag: 'AlarmManager', error: e);
    }
  }

  /// Get last alarm execution time (for debugging)
  Future<DateTime?> getLastAlarmExecution() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastExecution = prefs.getString('last_alarm_execution');
      return lastExecution != null ? TimeUtils.parseTimestamp(lastExecution) : null;
    } catch (e) {
      return null;
    }
  }
}
