import 'package:flutter/services.dart';
import 'dart:io';

/// 🚀 Fast Location Service
/// 
/// Ultra-fast location retrieval using Native Android LocationManager.
/// 
/// Strategy:
/// 1. Cached location (if available and recent)
/// 2. Network Provider (WiFi/Cell towers) - 1-3 seconds
/// 3. Last known location (fallback)
/// 4. GPS Provider (background update for accuracy)
/// 
/// Much faster than geolocator plugin on old devices!
/// 
/// Usage:
/// ```dart
/// final location = await FastLocationService.getCurrentLocationFast();
/// print('Lat: ${location?.latitude}, Lng: ${location?.longitude}');
/// ```
class FastLocationService {
  static const MethodChannel _channel = MethodChannel('fast_gps');
  
  /// Get current location fast (2-5 seconds on most devices)
  /// 
  /// Returns Position or null if:
  /// - Permissions not granted
  /// - GPS/Network disabled
  /// - No location available
  static Future<Position?> getCurrentLocationFast() async {
    // Only works on Android
    if (!Platform.isAndroid) {
      print('⚠️ Fast GPS only works on Android');
      return null;
    }
    
    try {
      final result = await _channel.invokeMethod('getLocationFast');
      
      if (result != null && result is Map) {
        return Position.fromMap(Map<String, dynamic>.from(result));
      }
      
      return null;
    } on PlatformException catch (e) {
      print('❌ Failed to get location: ${e.message}');
      return null;
    } catch (e) {
      print('❌ Unexpected error: $e');
      return null;
    }
  }
  
  /// Check if the service is supported on this platform
  static bool get isSupported => Platform.isAndroid;
}

/// Position model for location data
class Position {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double altitude;
  final double heading;
  final double speed;
  final int timestamp;
  final bool isMocked;
  
  Position({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.altitude = 0.0,
    this.heading = 0.0,
    this.speed = 0.0,
    required this.timestamp,
    this.isMocked = false,
  });
  
  factory Position.fromMap(Map<String, dynamic> map) {
    return Position(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracy: (map['accuracy'] as num).toDouble(),
      altitude: (map['altitude'] as num?)?.toDouble() ?? 0.0,
      heading: (map['heading'] as num?)?.toDouble() ?? 0.0,
      speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
      timestamp: (map['timestamp'] as num).toInt(),
      isMocked: map['isMocked'] as bool? ?? false,
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'heading': heading,
      'speed': speed,
      'timestamp': timestamp,
      'isMocked': isMocked,
    };
  }
  
  @override
  String toString() {
    return 'Position(lat: $latitude, lng: $longitude, accuracy: ${accuracy.toStringAsFixed(1)}m)';
  }
}
