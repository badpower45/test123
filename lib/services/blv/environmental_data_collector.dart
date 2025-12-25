import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Environmental Data Model
class EnvironmentalData {
  // WiFi signals
  final int wifiCount;
  final double wifiSignalStrength;
  
  // Battery
  final double batteryLevel;
  final bool isCharging;
  
  // Motion
  final double accelVariance;
  
  // Sound
  final double soundLevel;
  
  // Device
  final String deviceOrientation;
  final String deviceModel;
  final String osVersion;
  
  final DateTime timestamp;

  EnvironmentalData({
    required this.wifiCount,
    required this.wifiSignalStrength,
    required this.batteryLevel,
    required this.isCharging,
    required this.accelVariance,
    required this.soundLevel,
    required this.deviceOrientation,
    required this.deviceModel,
    required this.osVersion,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'wifi_count': wifiCount,
      'wifi_signal_strength': wifiSignalStrength,
      'battery_level': batteryLevel,
      'is_charging': isCharging,
      'accel_variance': accelVariance,
      'sound_level': soundLevel,
      'device_orientation': deviceOrientation,
      'device_model': deviceModel,
      'os_version': osVersion,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// BLV Environmental Data Collector
/// جمع البيانات البيئية للتحقق من الوجود
class EnvironmentalDataCollector {
  static final EnvironmentalDataCollector _instance = EnvironmentalDataCollector._internal();
  factory EnvironmentalDataCollector() => _instance;
  EnvironmentalDataCollector._internal();

  final Battery _battery = Battery();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
  NoiseMeter? _noiseMeter;
  StreamSubscription<NoiseReading>? _noiseSubscription;
  
  // Motion tracking
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  final List<double> _accelReadings = [];
  static const int _maxAccelSamples = 50; // 50 samples over ~2 seconds
  
  // Latest environmental data cache
  EnvironmentalData? _latestData;
  DateTime? _lastCollectionTime;
  
  // Collection state
  bool _isCollecting = false;
  double _currentSoundLevel = 0.0;
  
  /// Initialize the collector
  Future<void> initialize() async {
    if (_isCollecting) return;
    
    try {
      _isCollecting = true;
      
      // Start motion tracking
      _startMotionTracking();
      
      // Start sound monitoring (mobile/desktop only; not supported on Web)
      if (!kIsWeb) {
        await _startSoundMonitoring();
      } else {
        debugPrint('[BLV] Sound monitoring disabled on Web');
        _currentSoundLevel = 0.5; // neutral default
      }
      
      debugPrint('[BLV] Environmental data collector initialized');
    } catch (e) {
      debugPrint('[BLV] Error initializing collector: $e');
    }
  }
  
  /// Stop collecting data
  Future<void> dispose() async {
    _isCollecting = false;
    
    await _accelSubscription?.cancel();
    await _noiseSubscription?.cancel();
    
    _accelReadings.clear();
    
    debugPrint('[BLV] Environmental data collector disposed');
  }
  
  /// Start tracking accelerometer for motion detection
  void _startMotionTracking() {
    _accelSubscription = accelerometerEventStream().listen(
      (AccelerometerEvent event) {
        // Calculate magnitude: sqrt(x² + y² + z²)
        final magnitude = (event.x * event.x + event.y * event.y + event.z * event.z);
        
        _accelReadings.add(magnitude);
        
        // Keep only last N samples
        if (_accelReadings.length > _maxAccelSamples) {
          _accelReadings.removeAt(0);
        }
      },
      onError: (error) {
        debugPrint('[BLV] Accelerometer error: $error');
      },
    );
  }
  
  /// Start monitoring ambient sound
  Future<void> _startSoundMonitoring() async {
    try {
      _noiseMeter = NoiseMeter();
      
      _noiseSubscription = _noiseMeter!.noise.listen(
        (NoiseReading reading) {
          // Normalize to 0-1 range (assume 0-100 dB range)
          _currentSoundLevel = (reading.meanDecibel.clamp(0, 100) / 100.0);
        },
        onError: (error) {
          debugPrint('[BLV] Sound monitoring error: $error');
        },
      );
    } catch (e) {
      debugPrint('[BLV] Could not start sound monitoring: $e');
      _currentSoundLevel = 0.5; // Default middle value if unavailable
    }
  }
  
  /// Calculate accelerometer variance (motion indicator)
  double _calculateAccelVariance() {
    if (_accelReadings.length < 2) return 0.0;
    
    // Calculate mean
    final mean = _accelReadings.reduce((a, b) => a + b) / _accelReadings.length;
    
    // Calculate variance
    final variance = _accelReadings
        .map((value) => (value - mean) * (value - mean))
        .reduce((a, b) => a + b) / _accelReadings.length;
    
    // Normalize to 0-1 range (variance typically 0-50)
    return (variance.clamp(0, 50) / 50.0);
  }
  
  /// Get WiFi networks count and signal strength
  Future<Map<String, dynamic>> _getWiFiData() async {
    try {
      // Check if WiFi scan is supported
      final canScan = await WiFiScan.instance.canGetScannedResults();
      
      if (canScan == CanGetScannedResults.yes) {
        final results = await WiFiScan.instance.getScannedResults();
        
        if (results.isNotEmpty) {
          // Calculate average signal strength
          final avgSignal = results
              .map((ap) => ap.level)
              .reduce((a, b) => a + b) / results.length;
          
          return {
            'count': results.length,
            'signal_strength': avgSignal.toDouble(),
          };
        }
      }
      
      // Fallback: use network_info_plus (less accurate)
      return {
        'count': 0,
        'signal_strength': 0.0,
      };
    } catch (e) {
      debugPrint('[BLV] WiFi scan error: $e');
      return {
        'count': 0,
        'signal_strength': 0.0,
      };
    }
  }
  
  /// Get battery information
  Future<Map<String, dynamic>> _getBatteryData() async {
    try {
      final batteryLevel = await _battery.batteryLevel;
      final batteryState = await _battery.batteryState;
      
      return {
        'level': batteryLevel / 100.0, // 0-1 range
        'is_charging': batteryState == BatteryState.charging || 
                       batteryState == BatteryState.full,
      };
    } catch (e) {
      debugPrint('[BLV] Battery data error: $e');
      return {
        'level': 0.5,
        'is_charging': false,
      };
    }
  }
  
  /// Get device info
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return {
          'model': androidInfo.model,
          'os_version': 'Android ${androidInfo.version.release}',
        };
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return {
          'model': iosInfo.model,
          'os_version': 'iOS ${iosInfo.systemVersion}',
        };
      }
      
      return {
        'model': 'Unknown',
        'os_version': 'Unknown',
      };
    } catch (e) {
      debugPrint('[BLV] Device info error: $e');
      return {
        'model': 'Unknown',
        'os_version': 'Unknown',
      };
    }
  }
  
  /// Collect all environmental data
  /// يجمع كل البيانات البيئية من المستشعرات
  Future<EnvironmentalData> collectData() async {
    try {
      // Parallel data collection for speed
      final results = await Future.wait([
        _getWiFiData(),
        _getBatteryData(),
        _getDeviceInfo(),
      ]);
      
      final wifiData = results[0];
      final batteryData = results[1];
      final deviceData = results[2];
      
      final data = EnvironmentalData(
        wifiCount: wifiData['count'] as int,
        wifiSignalStrength: wifiData['signal_strength'] as double,
        batteryLevel: batteryData['level'] as double,
        isCharging: batteryData['is_charging'] as bool,
        accelVariance: _calculateAccelVariance(),
        soundLevel: _currentSoundLevel,
        deviceOrientation: 'portrait', // TODO: Add orientation detection
        deviceModel: deviceData['model'] as String,
        osVersion: deviceData['os_version'] as String,
        timestamp: DateTime.now(),
      );
      
      _latestData = data;
      _lastCollectionTime = DateTime.now();
      
      return data;
    } catch (e) {
      debugPrint('[BLV] Error collecting environmental data: $e');
      rethrow;
    }
  }
  
  /// Get latest collected data (cached)
  EnvironmentalData? getLatestData() {
    // Return cached data if collected within last 10 seconds
    if (_latestData != null && _lastCollectionTime != null) {
      final age = DateTime.now().difference(_lastCollectionTime!);
      if (age.inSeconds < 10) {
        return _latestData;
      }
    }
    return null;
  }
  
  /// Check if collector is ready
  bool isReady() {
    return _isCollecting && _accelReadings.length >= 10;
  }
}
