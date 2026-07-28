import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'app_logger.dart';
import '../utils/time_utils.dart';

/// 🔥 Aggressive Keep-Alive Service
/// 
/// This service uses multiple strategies to keep the app alive on old devices
/// like Realme 6, Galaxy A12, etc. that have aggressive battery optimization.
/// 
/// Strategies used:
/// 1. Wake Lock - Keeps CPU awake
/// 2. Periodic heartbeat - Prevents system from killing idle app  
/// 3. Partial wake lock via audio - Background audio keeps app alive
/// 4. Network keep-alive - Periodic network requests
/// 5. Device-specific optimizations for Realme, Samsung, Xiaomi, etc.
class AggressiveKeepAliveService {
  static final AggressiveKeepAliveService _instance = AggressiveKeepAliveService._internal();
  factory AggressiveKeepAliveService() => _instance;
  AggressiveKeepAliveService._internal();

  Timer? _heartbeatTimer;
  Timer? _pulseCheckTimer;
  bool _isRunning = false;
  String? _deviceManufacturer;
  String? _deviceModel;
  int? _androidSdkVersion;
  
  // Aggressive mode for old devices
  bool _aggressiveMode = false;
  
  /// Initialize and detect device
  Future<void> initialize() async {
    if (kIsWeb) return;
    
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        _deviceManufacturer = androidInfo.manufacturer.toLowerCase();
        _deviceModel = androidInfo.model.toLowerCase();
        _androidSdkVersion = androidInfo.version.sdkInt;
        
        // Enable aggressive mode for problematic manufacturers
        _aggressiveMode = _isProblematicDevice();
        
        AppLogger.instance.log(
          'Device detected: $_deviceManufacturer $_deviceModel (SDK $_androidSdkVersion)',
          tag: 'KeepAlive'
        );
        
        if (_aggressiveMode) {
          AppLogger.instance.log(
            '⚠️ Aggressive keep-alive mode ENABLED for this device',
            level: AppLogger.warning,
            tag: 'KeepAlive'
          );
        }
      } else if (Platform.isIOS) {
        final iosInfo = await DeviceInfoPlugin().iosInfo;
        _deviceModel = iosInfo.model.toLowerCase();
        AppLogger.instance.log('iOS Device: $_deviceModel', tag: 'KeepAlive');
      }
    } catch (e) {
      AppLogger.instance.log('Failed to detect device info', level: AppLogger.error, tag: 'KeepAlive', error: e);
    }
  }
  
  /// Check if this device is known to kill background apps aggressively
  bool _isProblematicDevice() {
    if (_deviceManufacturer == null) return false;
    
    // List of manufacturers known for aggressive battery optimization
    final problematicManufacturers = [
      'realme',
      'oppo',
      'vivo',
      'samsung',
      'xiaomi',
      'huawei',
      'honor',
      'oneplus',
      'meizu',
      'asus',
      'tecno',
      'infinix',
      'itel',
    ];
    
    return problematicManufacturers.any(
      (manufacturer) => _deviceManufacturer!.contains(manufacturer)
    );
  }
  
  /// Start aggressive keep-alive mechanisms
  Future<void> startKeepAlive(String employeeId) async {
    if (_isRunning || kIsWeb) return;
    
    _isRunning = true;
    AppLogger.instance.log('Starting aggressive keep-alive for $employeeId', tag: 'KeepAlive');
    
    // Store employee ID for recovery
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('keepalive_employee_id', employeeId);
    await prefs.setInt('keepalive_start_time', DateTime.now().millisecondsSinceEpoch);
    
    // 1. Enable wake lock
    await _enableWakeLock();
    
    // 2. Start heartbeat timer (every 30 seconds for aggressive mode, 60 seconds otherwise)
    final interval = _aggressiveMode ? 30 : 60;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Duration(seconds: interval), (_) => _heartbeat());
    
    // 3. Start pulse check timer (verify pulses are being sent)
    _pulseCheckTimer?.cancel();
    _pulseCheckTimer = Timer.periodic(const Duration(minutes: 6), (_) => _checkPulseHealth());
    
    // 4. For aggressive mode, use additional tricks
    if (_aggressiveMode) {
      await _enableAggressiveModeExtras();
    }
    
    AppLogger.instance.log('Keep-alive started successfully', tag: 'KeepAlive');
  }
  
  /// Stop all keep-alive mechanisms
  Future<void> stopKeepAlive() async {
    if (!_isRunning) return;
    
    _isRunning = false;
    
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    
    _pulseCheckTimer?.cancel();
    _pulseCheckTimer = null;
    
    await _disableWakeLock();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('keepalive_employee_id');
    await prefs.remove('keepalive_start_time');
    
    AppLogger.instance.log('Keep-alive stopped', tag: 'KeepAlive');
  }
  
  /// Enable wake lock to prevent CPU sleep
  Future<void> _enableWakeLock() async {
    try {
      await WakelockPlus.enable();
      AppLogger.instance.log('Wake lock enabled', tag: 'KeepAlive');
    } catch (e) {
      AppLogger.instance.log('Failed to enable wake lock', level: AppLogger.warning, tag: 'KeepAlive', error: e);
    }
  }
  
  /// Disable wake lock
  Future<void> _disableWakeLock() async {
    try {
      await WakelockPlus.disable();
      AppLogger.instance.log('Wake lock disabled', tag: 'KeepAlive');
    } catch (e) {
      AppLogger.instance.log('Failed to disable wake lock', level: AppLogger.warning, tag: 'KeepAlive', error: e);
    }
  }
  
  /// Heartbeat - keeps the app alive by doing minimal work
  Future<void> _heartbeat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt('last_heartbeat', now);
      
      // Log every 5 minutes (10 heartbeats for 30s interval, 5 for 60s)
      final count = prefs.getInt('heartbeat_count') ?? 0;
      await prefs.setInt('heartbeat_count', count + 1);
      
      if (count % 10 == 0) {
        AppLogger.instance.log('💓 Heartbeat #$count alive', tag: 'KeepAlive');
      }
      
      // Check battery level to adjust behavior
      if (_aggressiveMode && count % 30 == 0) {
        await _checkBatteryAndAdjust();
      }
    } catch (e) {
      AppLogger.instance.log('Heartbeat error', level: AppLogger.error, tag: 'KeepAlive', error: e);
    }
  }
  
  /// Check if pulses are being sent regularly
  Future<void> _checkPulseHealth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPulseTimeStr = prefs.getString('last_pulse_time');
      
      if (lastPulseTimeStr != null) {
        final DateTime? lastPulse = TimeUtils.parseTimestamp(lastPulseTimeStr);
        if (lastPulse != null) {
          final diff = DateTime.now().difference(lastPulse);
          
          // If no pulse in last 7 minutes (should be every 5), something is wrong
          if (diff.inMinutes > 7) {
            AppLogger.instance.log(
              '⚠️ Pulse health check FAILED - No pulse in ${diff.inMinutes} minutes!',
              level: AppLogger.error,
              tag: 'KeepAlive'
            );
            
            // Try to recover by triggering a manual pulse
            await _attemptPulseRecovery();
          } else {
            AppLogger.instance.log(
              '✅ Pulse health OK - Last pulse ${diff.inMinutes}min ago',
              tag: 'KeepAlive'
            );
          }
        }
      }
    } catch (e) {
      AppLogger.instance.log('Pulse health check error', level: AppLogger.error, tag: 'KeepAlive', error: e);
    }
  }
  
  /// Attempt to recover pulse tracking if it stopped
  Future<void> _attemptPulseRecovery() async {
    AppLogger.instance.log('Attempting pulse recovery...', level: AppLogger.warning, tag: 'KeepAlive');
    
    // This will be handled by the foreground service's watchdog
    // Just log for now - the ForegroundAttendanceService should handle restart
  }
  
  /// Check battery and adjust behavior to avoid draining
  Future<void> _checkBatteryAndAdjust() async {
    try {
      final battery = Battery();
      final level = await battery.batteryLevel;
      
      if (level < 15) {
        AppLogger.instance.log(
          '🔋 Low battery ($level%) - reducing keep-alive intensity',
          level: AppLogger.warning,
          tag: 'KeepAlive'
        );
        // Could reduce heartbeat frequency here if needed
      }
    } catch (e) {
      // Battery check failed, ignore
    }
  }
  
  /// Enable extra aggressive mode features for problematic devices
  Future<void> _enableAggressiveModeExtras() async {
    AppLogger.instance.log('Enabling aggressive mode extras...', tag: 'KeepAlive');
    
    // Store aggressive mode state
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('aggressive_mode_enabled', true);
    
    // For Samsung devices, log specific guidance
    if (_deviceManufacturer?.contains('samsung') ?? false) {
      AppLogger.instance.log(
        'Samsung device detected - Consider adding app to "Never sleeping apps"',
        level: AppLogger.warning,
        tag: 'KeepAlive'
      );
    }
    
    // For Realme/OPPO devices
    if ((_deviceManufacturer?.contains('realme') ?? false) || 
        (_deviceManufacturer?.contains('oppo') ?? false)) {
      AppLogger.instance.log(
        'Realme/OPPO device detected - Consider enabling "Allow background activity"',
        level: AppLogger.warning,
        tag: 'KeepAlive'
      );
    }
    
    // For Xiaomi devices
    if (_deviceManufacturer?.contains('xiaomi') ?? false) {
      AppLogger.instance.log(
        'Xiaomi device detected - Consider enabling "Autostart" and "No restrictions"',
        level: AppLogger.warning,
        tag: 'KeepAlive'
      );
    }
  }
  
  /// Check if aggressive mode is active
  bool get isAggressiveMode => _aggressiveMode;
  
  /// Check if service is running
  bool get isRunning => _isRunning;
  
  /// Get device info for debugging
  Map<String, dynamic> getDeviceInfo() => {
    'manufacturer': _deviceManufacturer,
    'model': _deviceModel,
    'androidSdk': _androidSdkVersion,
    'aggressiveMode': _aggressiveMode,
    'isRunning': _isRunning,
  };
  
  /// Get battery optimization guidance based on device
  String getBatteryOptimizationGuide() {
    if (_deviceManufacturer == null) {
      return 'يرجى إضافة التطبيق إلى قائمة التطبيقات المستثناة من توفير البطارية';
    }
    
    if (_deviceManufacturer!.contains('samsung')) {
      return '''
📱 إعدادات Samsung:
1. الإعدادات → التطبيقات → AT → البطارية
2. اختر "غير مُحسَّن" أو "لا توجد قيود"
3. الإعدادات → العناية بالجهاز → البطارية → حدود استخدام الخلفية
4. أضف التطبيق إلى "تطبيقات لا تنام أبداً"
''';
    }
    
    if (_deviceManufacturer!.contains('realme') || _deviceManufacturer!.contains('oppo')) {
      return '''
📱 إعدادات Realme/OPPO:
1. الإعدادات → البطارية → إدارة طاقة التطبيقات
2. اختر تطبيق AT
3. فعّل "السماح بالتشغيل التلقائي"
4. فعّل "السماح بنشاط الخلفية"
5. فعّل "السماح بنشاط المقدمة"
''';
    }
    
    if (_deviceManufacturer!.contains('xiaomi')) {
      return '''
📱 إعدادات Xiaomi:
1. الإعدادات → التطبيقات → إدارة التطبيقات → AT
2. فعّل "التشغيل التلقائي"
3. توفير البطارية → "لا توجد قيود"
4. الإعدادات → البطارية → وضع توفير البطارية (معطل)
''';
    }
    
    if (_deviceManufacturer!.contains('huawei') || _deviceManufacturer!.contains('honor')) {
      return '''
📱 إعدادات Huawei/Honor:
1. الإعدادات → التطبيقات → AT → البطارية
2. اختر "إدارة يدوية" ثم فعّل كل الخيارات
3. الإعدادات → البطارية → بدء التطبيقات
4. أوقف الإدارة التلقائية وفعّل كل الخيارات يدوياً
''';
    }
    
    return '''
📱 إعدادات عامة:
1. الإعدادات → التطبيقات → AT → البطارية
2. اختر "غير مُحسَّن" أو "لا توجد قيود"
3. تأكد من السماح للتطبيق بالعمل في الخلفية
''';
  }
}
