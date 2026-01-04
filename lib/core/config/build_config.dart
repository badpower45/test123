/// 🎯 Build Flavor Configuration
/// 
/// This file provides flavor detection and feature flags for the app.
/// It allows different features to be enabled/disabled based on the build flavor.
/// 
/// Flavors:
/// - **lite**: For Employees/Managers - lightweight version without BLV and Google Maps
/// - **full**: For Owners - full version with all features
/// 
/// Usage:
/// ```dart
/// if (BuildConfig.supportsBLV) {
///   await BLVService.initialize();
/// }
/// ```

enum BuildFlavor {
  lite,
  full,
}

class BuildConfig {
  static BuildFlavor _flavor = BuildFlavor.full;
  
  /// Returns the current build flavor
  static BuildFlavor get flavor => _flavor;
  
  /// Sets the build flavor (should be called early in main())
  static void setFlavor(BuildFlavor flavor) {
    _flavor = flavor;
  }
  
  /// Detects the current flavor from the package name
  /// This is called automatically on initialization
  static Future<void> detectFlavor() async {
    // TODO: Implement package name detection
    // For now, we'll use const environment variables
    const String flavorName = String.fromEnvironment('FLAVOR', defaultValue: 'full');
    
    if (flavorName == 'lite') {
      _flavor = BuildFlavor.lite;
    } else {
      _flavor = BuildFlavor.full;
    }
  }
  
  // ============ Flavor Checks ============
  
  /// Returns true if the current flavor is 'lite'
  static bool get isLite => _flavor == BuildFlavor.lite;
  
  /// Returns true if the current flavor is 'full'
  static bool get isFull => _flavor == BuildFlavor.full;
  
  // ============ Feature Flags ============
  
  /// BLV (Background Location Verification) - Only available in Full version
  /// Uses sensors like accelerometer, noise, WiFi to verify employee is working
  static bool get supportsBLV => isFull;
  
  /// Google Maps - Only available in Full version
  /// Shows branch locations and geofencing
  static bool get supportsGoogleMaps => isFull;
  
  /// Advanced Sensors - Only available in Full version
  /// Includes noise meter, accelerometer, gyroscope for BLV
  static bool get supportsAdvancedSensors => isFull;
  
  /// High Resolution Images - Only available in Full version
  /// Lite version uses compressed images to save space
  static bool get supportsHighResImages => isFull;
  
  // ============ Performance Settings ============
  
  /// Pulse interval based on flavor
  /// - Lite: 10 minutes (to save battery)
  /// - Full: 5 minutes (standard)
  static Duration get pulseInterval => isLite 
      ? const Duration(minutes: 10) 
      : const Duration(minutes: 5);
  
  /// Location update interval based on flavor
  /// - Lite: 5 minutes (less frequent)
  /// - Full: 1 minute (more accurate)
  static Duration get locationUpdateInterval => isLite
      ? const Duration(minutes: 5)
      : const Duration(minutes: 1);
  
  /// Maximum cache size based on flavor
  /// - Lite: 50MB
  /// - Full: 200MB
  static int get maxCacheSizeMB => isLite ? 50 : 200;
  
  /// Image quality based on flavor (0-100)
  /// - Lite: 60% quality
  /// - Full: 90% quality
  static int get imageQuality => isLite ? 60 : 90;
  
  // ============ UI Settings ============
  
  /// App name suffix for the flavor
  static String get appNameSuffix => isLite ? ' Lite' : '';
  
  /// Returns the full app name with suffix
  static String get appName => 'Heartbeat$appNameSuffix';
  
  /// Theme color based on flavor
  /// - Lite: Lighter blue (indicating simplified version)
  /// - Full: Standard blue
  static String get primaryColorHex => isLite ? '#64B5F6' : '#2196F3';
  
  // ============ Debug Info ============
  
  /// Returns a map with all configuration info for debugging
  static Map<String, dynamic> get debugInfo => {
    'flavor': _flavor.toString(),
    'isLite': isLite,
    'isFull': isFull,
    'supportsBLV': supportsBLV,
    'supportsGoogleMaps': supportsGoogleMaps,
    'supportsAdvancedSensors': supportsAdvancedSensors,
    'pulseInterval': pulseInterval.inMinutes,
    'locationUpdateInterval': locationUpdateInterval.inMinutes,
    'maxCacheSizeMB': maxCacheSizeMB,
    'imageQuality': imageQuality,
    'appName': appName,
  };
  
  /// Prints configuration info to console
  static void printConfig() {
    print('=== 🎯 Build Configuration ===');
    debugInfo.forEach((key, value) {
      print('$key: $value');
    });
    print('============================');
  }
}
