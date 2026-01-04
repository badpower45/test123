import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'app_logger.dart';
import 'aggressive_keep_alive_service.dart';

/// ✅ THE ULTIMATE FOREGROUND SERVICE (V4)
/// Designed for maximum persistence on Android 14+ and old Chinese devices.
/// Uses a Hybrid Approach: Foreground Service + Exact Alarms + WakeLock.
class ForegroundAttendanceService {
  static final ForegroundAttendanceService instance = ForegroundAttendanceService._();
  ForegroundAttendanceService._();

  bool _isRunning = false;
  Timer? _watchdogTimer;
  String? _lastEmployeeId;
  String? _lastEmployeeName;
  
  /// Initialize with high-res options
  static Future<void> initialize() async {
    String? manufacturer;
    int sdkInt = 0;
    
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      manufacturer = androidInfo.manufacturer.toLowerCase();
      sdkInt = androidInfo.version.sdkInt;
    }

    // Initialize Alarm Manager for the backup pulse system
    await AndroidAlarmManager.initialize();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'attendance_tracking_v4',
        channelName: 'Oldies Tracking System',
        channelDescription: 'Maintains connection with branch servers',
        channelImportance: NotificationChannelImportance.MAX,
        priority: NotificationPriority.MAX,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000), // Every 5 seconds
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    AppLogger.instance.log('V4 Service Initialized for $manufacturer (API $sdkInt)', tag: 'ServiceV4');
  }

  /// Request all critical permissions for Android 14+
  static Future<bool> requestCriticalPermissions() async {
    if (!Platform.isAndroid) return true;

    Map<Permission, PermissionStatus> statuses = await [
      Permission.notification,
      Permission.locationAlways,
      Permission.ignoreBatteryOptimizations,
      Permission.scheduleExactAlarm,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);
    
    // Special check for Android 14 Foreground Service types
    if (await Permission.sensors.isDenied) await Permission.sensors.request();
    
    return allGranted;
  }

  Future<bool> startTracking({
    required String employeeId,
    required String employeeName,
  }) async {
    if (_isRunning) return true;

    await requestCriticalPermissions();
    
    _lastEmployeeId = employeeId;
    _lastEmployeeName = employeeName;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fg_employee_id', employeeId);
    await prefs.setString('fg_employee_name', employeeName);

    try {
      // 1. Enable WakeLock to keep CPU alive
      await WakelockPlus.enable();

      // 2. Start the primary Foreground Service
      // For Android 14, types are declared in manifest but handled by the library
      await FlutterForegroundTask.startService(
        notificationTitle: 'نظام الحضور نشط',
        notificationText: '$employeeName - جاري تتبع الموقع والنبضات...',
        callback: _foregroundTaskCallback,
      );

      // 3. Start the Backup Alarm (The "Resurrector")
      // This alarm runs every 10 minutes to ensure the service is alive
      await AndroidAlarmManager.periodic(
        const Duration(minutes: 10),
        777, // Unique ID
        _alarmBackupTask,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );

      _isRunning = true;
      _startWatchdog();
      
      AppLogger.instance.log('V4 Tracking Started for $employeeName', tag: 'ServiceV4');
      return true;
    } catch (e) {
      AppLogger.instance.log('Start Error', level: AppLogger.error, tag: 'ServiceV4', error: e);
      return false;
    }
  }

  /// Watchdog monitors internal state every 30 seconds
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      bool healthy = await FlutterForegroundTask.isRunningService;
      if (!healthy && _isRunning) {
        AppLogger.instance.log('Watchdog: Service died! Restarting...', level: AppLogger.warning, tag: 'ServiceV4');
        _restartService();
      }
    });
  }

  Future<void> _restartService() async {
    if (_lastEmployeeId == null) return;
    await FlutterForegroundTask.stopService();
    _isRunning = false;
    await Future.delayed(const Duration(seconds: 2));
    await startTracking(employeeId: _lastEmployeeId!, employeeName: _lastEmployeeName!);
  }

  Future<bool> stopTracking() async {
    _watchdogTimer?.cancel();
    await AndroidAlarmManager.cancel(777);
    await WakelockPlus.disable();
    await FlutterForegroundTask.stopService();
    _isRunning = false;
    return true;
  }

  /// Check if service is actually active
  Future<bool> isServiceActive() async {
    return await FlutterForegroundTask.isRunningService;
  }
}

/// ✅ THE RESURRECTOR: Global top-level function for Alarm Manager
@pragma('vm:entry-point')
void _alarmBackupTask() async {
  // This runs in a separate isolate when the app might be dead
  final prefs = await SharedPreferences.getInstance();
  final employeeId = prefs.getString('fg_employee_id');
  final employeeName = prefs.getString('fg_employee_name');
  
  bool isRunning = await FlutterForegroundTask.isRunningService;
  
  if (!isRunning && employeeId != null) {
    // Attempt to restart the service from the background
    FlutterForegroundTask.startService(
      notificationTitle: 'إعادة تشغيل النظام',
      notificationText: 'جاري استعادة نظام التتبع...',
      callback: _foregroundTaskCallback,
    );
  }
}

@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_V4TaskHandler());
}

class _V4TaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('Service V4 Started successfully');
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // Keep internal logic minimal to save battery
    // Heavy lifting (Location/Sync) is done by PulseTrackingService
    
    // Periodically update notification to show system is alive
    if (timestamp.minute % 2 == 0 && timestamp.second < 5) {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('fg_employee_name') ?? 'الموظف';
      FlutterForegroundTask.updateService(
        notificationTitle: 'تتبع الحضور نشط',
        notificationText: '$name - آخر تحديث: ${timestamp.hour}:${timestamp.minute}',
      );
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isAppKilled) async {
    // If app is killed, the AlarmManager backup will try to restart it
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/employee');
  }
}
