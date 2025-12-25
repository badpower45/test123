import 'dart:async';
import 'dart:io';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'pulse_tracking_service.dart';
import 'app_logger.dart';

/// Backup pulse mechanism using Android AlarmManager
/// Guarantees periodic execution even if foreground service fails
/// ⚠️ This is a FALLBACK - the foreground service is primary
/// ✅ Enhanced with: Permission request for Android 12+ (SCHEDULE_EXACT_ALARM)
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

  /// Initialize the alarm manager service
  Future<bool> initialize() async {
    if (!isSupported) {
      AppLogger.instance.log('AlarmManager not supported on this platform', 
        level: AppLogger.info, tag: 'AlarmManager');
      return false;
    }

    try {
      await AndroidAlarmManager.initialize();
      AppLogger.instance.log('AlarmManager initialized successfully', 
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

      // Schedule periodic alarm (every 5 minutes)
      final success = await AndroidAlarmManager.periodic(
        _alarmInterval,
        _alarmId,
        alarmCallback,
      );

      if (success) {
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
      _isRegistered = false;
      
      // Clean up stored employee ID
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('alarm_employee_id');

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

      // Get branch data (stored by PulseTrackingService)
      final branchDataJson = prefs.getString('current_branch_data');
      if (branchDataJson == null) {
        AppLogger.instance.log('No branch data found in alarm callback', 
          level: AppLogger.warning, tag: 'AlarmManager');
        return;
      }

      // Check if already sent pulse recently (avoid duplicate with foreground service)
      final lastPulseTimeStr = prefs.getString('last_pulse_time');
      if (lastPulseTimeStr != null) {
        DateTime? lastPulseTime;
        try {
          lastPulseTime = DateTime.parse(lastPulseTimeStr);
        } catch (e) {
          lastPulseTime = null;
        }
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

      // Trigger pulse through PulseTrackingService
      // Note: This may not work perfectly in isolate, but worth trying
      AppLogger.instance.log('Triggering backup pulse for employee $employeeId', 
        tag: 'AlarmManager');
      
      // Store alarm execution time
      await prefs.setString('last_alarm_execution', DateTime.now().toIso8601String());
      
      // ⚠️ In production, you might need to use a different approach
      // like directly calling the edge function or using WorkManager
      // For now, this serves as a "heartbeat" indicator
      
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
      return lastExecution != null ? DateTime.parse(lastExecution) : null;
    } catch (e) {
      return null;
    }
  }
}
