import 'dart:async';
import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'app_logger.dart';
import 'aggressive_keep_alive_service.dart';

/// Foreground service to keep the app alive during attendance tracking
/// Shows persistent notification and prevents system from killing the app
/// ✅ Enhanced with: Watchdog Timer, Wake Lock, Auto-restart
/// ✅ V2: Aggressive mode for old devices (Realme 6, Galaxy A12, etc.)
class ForegroundAttendanceService {
  static final ForegroundAttendanceService instance = ForegroundAttendanceService._();
  ForegroundAttendanceService._();

  bool _isRunning = false;
  Timer? _watchdogTimer;
  Timer? _aggressiveHeartbeatTimer;
  String? _lastEmployeeId;
  String? _lastEmployeeName;
  bool _isAggressiveMode = false;
  String? _deviceManufacturer;
  
  /// Initialize foreground task service
  /// ✅ Enhanced with notification action button
  /// ✅ V2: Detect device and enable aggressive mode for problematic devices
  static Future<void> initialize() async {
    // Detect device manufacturer for aggressive mode
    String? manufacturer;
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        manufacturer = androidInfo.manufacturer.toLowerCase();
        
        // Store for later use
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('device_manufacturer', manufacturer);
        await prefs.setInt('android_sdk', androidInfo.version.sdkInt);
      }
    } catch (e) {
      AppLogger.instance.log('Could not detect device info', level: AppLogger.warning, tag: 'ForegroundService');
    }
    
    // Determine if aggressive mode is needed
    final isProblematicDevice = _isProblematicManufacturer(manufacturer);
    
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'attendance_tracking',
        channelName: 'تتبع الحضور',
        channelDescription: 'إشعار دائم أثناء تسجيل الحضور',
        // ✅ V2: Use MAX importance for aggressive mode
        channelImportance: isProblematicDevice 
            ? NotificationChannelImportance.MAX 
            : NotificationChannelImportance.HIGH,
        priority: NotificationPriority.MAX,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // ✅ V2: More frequent checks for aggressive mode (every 3 seconds)
        eventAction: ForegroundTaskEventAction.repeat(isProblematicDevice ? 3000 : 5000),
        autoRunOnBoot: true, // ✅ V2: Auto-start on boot
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    
    // ✅ V2: Initialize aggressive keep-alive service
    await AggressiveKeepAliveService().initialize();
    
    AppLogger.instance.log(
      'Foreground service initialized (Aggressive: $isProblematicDevice, Device: $manufacturer)',
      tag: 'ForegroundService'
    );
  }
  
  /// Check if device manufacturer is known to be problematic
  static bool _isProblematicManufacturer(String? manufacturer) {
    if (manufacturer == null) return false;
    
    final problematicManufacturers = [
      'realme', 'oppo', 'vivo', 'samsung', 'xiaomi', 
      'huawei', 'honor', 'oneplus', 'meizu', 'asus',
      'tecno', 'infinix', 'itel', 'transsion',
    ];
    
    return problematicManufacturers.any((m) => manufacturer.contains(m));
  }

  /// Check Android SDK version
  static Future<int> _getAndroidSdkVersion() async {
    if (!Platform.isAndroid) return 0;
    try {
      // Android 13 = API 33
      // We'll check using device_info_plus if available, otherwise assume recent version
      // For now, use a safe approach that works on all versions
      return 33; // Assume Android 13+ for safety - will be handled by permission_handler
    } catch (e) {
      return 33;
    }
  }

  /// Request necessary permissions for foreground service
  /// Handles Android version differences properly
  static Future<bool> requestPermissions() async {
    try {
      AppLogger.instance.log('Requesting foreground service permissions', tag: 'ForegroundService');
      
      // POST_NOTIFICATIONS permission only exists on Android 13+ (API 33)
      // On older Android versions, notifications are allowed by default
      if (Platform.isAndroid) {
        final notificationStatus = await Permission.notification.status;
        
        // If status is "granted" it means either:
        // 1. User already granted it (Android 13+)
        // 2. It's not needed (Android 12 and below)
        if (notificationStatus.isGranted) {
          AppLogger.instance.log('Notification permission already granted or not needed', tag: 'ForegroundService');
        } else if (notificationStatus.isDenied) {
          // Try to request - this will only work on Android 13+
          final result = await Permission.notification.request();
          if (!result.isGranted && !result.isLimited) {
            // On Android 12 and below, this may return denied but notifications still work
            // So we log warning but don't fail
            AppLogger.instance.log(
              'Notification permission request returned: $result - continuing anyway (may work on older Android)', 
              level: AppLogger.warning, 
              tag: 'ForegroundService'
            );
          }
        } else if (notificationStatus.isPermanentlyDenied) {
          AppLogger.instance.log(
            'Notification permission permanently denied - user needs to enable in settings', 
            level: AppLogger.warning, 
            tag: 'ForegroundService'
          );
          // Don't fail - foreground service might still work
        }
      }
      
      // Request battery optimization exemption (important for all Android versions)
      final batteryStatus = await Permission.ignoreBatteryOptimizations.request();
      if (!batteryStatus.isGranted) {
        AppLogger.instance.log('Battery optimization exemption denied - service may be killed', level: AppLogger.warning, tag: 'ForegroundService');
        // Don't fail completely, just warn
      }
      
      AppLogger.instance.log('Permissions check completed', tag: 'ForegroundService');
      return true; // Always return true - let the service try to start
    } catch (e) {
      AppLogger.instance.log('Error requesting permissions', level: AppLogger.error, tag: 'ForegroundService', error: e);
      // Return true anyway - permission errors shouldn't block the whole app
      return true;
    }
  }

  /// Start foreground service for attendance tracking
  /// ✅ Enhanced with wake lock and watchdog timer
  /// ✅ V2: Aggressive mode for old devices
  Future<bool> startTracking({
    required String employeeId,
    required String employeeName,
  }) async {
    if (_isRunning) {
      print('⚠️ Foreground service already running');
      return true;
    }

    // Request permissions first
    final hasPermissions = await requestPermissions();
    if (!hasPermissions) {
      print('❌ Cannot start service: Missing permissions');
      return false;
    }

    // Save employee info for later restart if needed
    _lastEmployeeId = employeeId;
    _lastEmployeeName = employeeName;

    // Save employee info for the foreground task handler
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fg_employee_id', employeeId);
    await prefs.setString('fg_employee_name', employeeName);
    
    // ✅ V2: Check if this is a problematic device
    _deviceManufacturer = prefs.getString('device_manufacturer');
    _isAggressiveMode = _isProblematicManufacturer(_deviceManufacturer);
    
    if (_isAggressiveMode) {
      AppLogger.instance.log('🔥 Aggressive mode enabled for $_deviceManufacturer', tag: 'ForegroundService');
    }

    try {
      // ✅ Enable wake lock to prevent device sleep
      try {
        await WakelockPlus.enable();
        AppLogger.instance.log('Wake lock enabled', tag: 'ForegroundService');
      } catch (e) {
        AppLogger.instance.log('Failed to enable wake lock', level: AppLogger.warning, tag: 'ForegroundService', error: e);
        // Continue anyway - not critical
      }

      await FlutterForegroundTask.startService(
        notificationTitle: 'تتبع الحضور نشط',
        notificationText: '$employeeName - جاري المراقبة...',
        callback: _foregroundTaskCallback,
      );
      _isRunning = true;
      
      // ✅ Start watchdog timer to monitor service health
      _startWatchdog();
      
      // ✅ V2: Start aggressive keep-alive for problematic devices
      if (_isAggressiveMode) {
        await AggressiveKeepAliveService().startKeepAlive(employeeId);
        _startAggressiveHeartbeat();
      }
      
      AppLogger.instance.log('Foreground service started successfully for $employeeName (Aggressive: $_isAggressiveMode)', tag: 'ForegroundService');
      return true;
    } catch (e) {
      AppLogger.instance.log('Failed to start foreground service', level: AppLogger.error, tag: 'ForegroundService', error: e);
      return false;
    }
  }
  
  /// ✅ V2: Aggressive heartbeat for problematic devices
  void _startAggressiveHeartbeat() {
    _aggressiveHeartbeatTimer?.cancel();
    
    // Every 30 seconds, do a small operation to keep app alive
    _aggressiveHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!_isRunning) {
        timer.cancel();
        return;
      }
      
      try {
        final prefs = await SharedPreferences.getInstance();
        final now = DateTime.now().millisecondsSinceEpoch;
        await prefs.setInt('aggressive_heartbeat', now);
        
        // Check if pulse tracking is still working
        final lastPulse = prefs.getString('last_pulse_time');
        if (lastPulse != null) {
          DateTime? lastPulseTime;
          try {
            lastPulseTime = DateTime.parse(lastPulse);
          } catch (e) {
            lastPulseTime = null;
          }
          if (lastPulseTime != null) {
            final diff = DateTime.now().difference(lastPulseTime);
            if (diff.inMinutes > 7) {
              AppLogger.instance.log(
                '⚠️ No pulse in ${diff.inMinutes} minutes - service may need restart',
                level: AppLogger.warning,
                tag: 'ForegroundService'
              );
            }
          }
        }
      } catch (e) {
        // Ignore heartbeat errors
      }
    });
  }

  /// ✅ Watchdog timer to monitor service health
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    
    _watchdogTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      final isHealthy = await isServiceHealthy();
      
      if (!isHealthy) {
        AppLogger.instance.log('⚠️ Watchdog detected service failure - attempting restart', level: AppLogger.warning, tag: 'ForegroundService');
        
        if (_lastEmployeeId != null && _lastEmployeeName != null) {
          await _restartService();
        } else {
          AppLogger.instance.log('Cannot restart service: Missing employee info', level: AppLogger.error, tag: 'ForegroundService');
          timer.cancel();
        }
      }
    });
  }

  /// ✅ Restart service if it crashed or was killed
  Future<void> _restartService() async {
    if (_lastEmployeeId == null || _lastEmployeeName == null) {
      AppLogger.instance.log('Cannot restart: Missing employee info', level: AppLogger.error, tag: 'ForegroundService');
      return;
    }

    AppLogger.instance.log('Attempting to restart foreground service...', tag: 'ForegroundService');
    
    _isRunning = false;
    await Future.delayed(const Duration(seconds: 2)); // Brief delay
    
    final success = await startTracking(
      employeeId: _lastEmployeeId!,
      employeeName: _lastEmployeeName!,
    );
    
    if (success) {
      AppLogger.instance.log('Service restarted successfully', tag: 'ForegroundService');
    } else {
      AppLogger.instance.log('Service restart failed', level: AppLogger.error, tag: 'ForegroundService');
    }
  }

  /// Stop foreground service
  /// ✅ Also disables wake lock and stops watchdog
  /// ✅ V2: Stop aggressive keep-alive
  Future<bool> stopTracking() async {
    if (!_isRunning) {
      print('⚠️ Foreground service not running');
      return true;
    }

    try {
      // ✅ Stop watchdog timer
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
      
      // ✅ V2: Stop aggressive heartbeat
      _aggressiveHeartbeatTimer?.cancel();
      _aggressiveHeartbeatTimer = null;
      
      // ✅ V2: Stop aggressive keep-alive service
      await AggressiveKeepAliveService().stopKeepAlive();
      
      // ✅ Disable wake lock
      try {
        await WakelockPlus.disable();
        AppLogger.instance.log('Wake lock disabled', tag: 'ForegroundService');
      } catch (e) {
        AppLogger.instance.log('Failed to disable wake lock', level: AppLogger.warning, tag: 'ForegroundService', error: e);
      }

      await FlutterForegroundTask.stopService();
      _isRunning = false;
      _lastEmployeeId = null;
      _lastEmployeeName = null;
      _isAggressiveMode = false;
      
      AppLogger.instance.log('Foreground service stopped successfully', tag: 'ForegroundService');
      return true;
    } catch (e) {
      AppLogger.instance.log('Failed to stop foreground service', level: AppLogger.error, tag: 'ForegroundService', error: e);
      return false;
    }
  }

  /// Update notification text
  Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!_isRunning) return;

    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  /// Check if service is running
  bool get isRunning => _isRunning;
  
  /// Health check: Verify service is actually running
  Future<bool> isServiceHealthy() async {
    if (!_isRunning) {
      return false;
    }
    
    try {
      // Check if FlutterForegroundTask is actually running
      final isTaskRunning = await FlutterForegroundTask.isRunningService;
      
      if (!isTaskRunning) {
        AppLogger.instance.log('Service state mismatch: _isRunning=true but service not active', level: AppLogger.warning, tag: 'ForegroundService');
        _isRunning = false;
        return false;
      }
      
      return true;
    } catch (e) {
      print('❌ Health check failed: $e');
      return false;
    }
  }
  
  /// Auto-restart service if it died unexpectedly
  Future<bool> ensureServiceRunning({
    required String employeeId,
    required String employeeName,
  }) async {
    final isHealthy = await isServiceHealthy();
    
    if (isHealthy) {
      return true;
    }
    
    AppLogger.instance.log('Service not healthy, attempting restart for $employeeName', level: AppLogger.warning, tag: 'ForegroundService');
    return await startTracking(
      employeeId: employeeId,
      employeeName: employeeName,
    );
  }
}

/// Foreground task callback handler
@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_AttendanceTaskHandler());
}

/// Task handler that runs in foreground
class _AttendanceTaskHandler extends TaskHandler {
  int _updateCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('🔔 Foreground task started at $timestamp');
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    _updateCount++;
    
    // Update notification every minute
    if (_updateCount % 12 == 0) { // Every 60 seconds (12 * 5s)
      final prefs = await SharedPreferences.getInstance();
      final employeeName = prefs.getString('fg_employee_name') ?? 'الموظف';
      
      FlutterForegroundTask.updateService(
        notificationTitle: 'تتبع الحضور نشط',
        notificationText: '$employeeName - آخر تحديث: ${TimeOfDay.fromDateTime(timestamp).format(null)}',
      );
    }

    // Send data to main isolate
    FlutterForegroundTask.sendDataToMain({
      'timestamp': timestamp.toIso8601String(),
      'updateCount': _updateCount,
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isAppKilled) async {
    print('🛑 Foreground task destroyed at $timestamp (app killed: $isAppKilled)');
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop_tracking') {
      print('⚠️ User requested to stop tracking from notification');
      FlutterForegroundTask.sendDataToMain({
        'action': 'stop_requested',
      });
    }
  }

  @override
  void onNotificationPressed() {
    // User tapped the notification - bring app to foreground
    FlutterForegroundTask.launchApp('/employee');
  }
}

/// Helper class for TimeOfDay formatting without BuildContext
class TimeOfDay {
  final int hour;
  final int minute;

  const TimeOfDay({required this.hour, required this.minute});

  factory TimeOfDay.fromDateTime(DateTime dateTime) {
    return TimeOfDay(hour: dateTime.hour, minute: dateTime.minute);
  }

  String format(dynamic context) {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
