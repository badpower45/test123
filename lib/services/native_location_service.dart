import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// 🚀 Native Location Service
/// 
/// Wrapper around native GPS module for ultra-fast location retrieval
/// Falls back to geolocator plugin on iOS or if native fails
class NativeLocationService {
  static const MethodChannel _gpsChannel = MethodChannel('fast_gps');
  
  /// Get current location using native GPS (Android only)
  /// Falls back to geolocator on iOS or if native fails
  static Future<Position?> getCurrentLocation() async {
    // iOS: Use geolocator (no native implementation)
    if (!Platform.isAndroid) {
      return _getLocationViaPlugin();
    }
    
    try {
      // Android: Try native GPS first (MUCH faster)
      print('🚀 Trying native GPS module...');
      
      final result = await _gpsChannel.invokeMethod('getLocationFast');
      
      if (result == null) {
        print('⚠️ Native GPS returned null, falling back to plugin');
        return _getLocationViaPlugin();
      }
      
      // Parse result from native
      final Map<dynamic, dynamic> locationData = result as Map<dynamic, dynamic>;
      
      final latitude = locationData['latitude'] as double;
      final longitude = locationData['longitude'] as double;
      final accuracy = locationData['accuracy'] as double;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        locationData['timestamp'] as int,
      );
      
      print('✅ Native GPS success: ($latitude, $longitude) ±${accuracy}m');
      
      // Convert to Position object
      return Position(
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        timestamp: timestamp,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );
    } catch (e) {
      print('⚠️ Native GPS failed: $e, falling back to plugin');
      return _getLocationViaPlugin();
    }
  }
  
  /// Fallback: Use geolocator plugin
  static Future<Position?> _getLocationViaPlugin() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        return null;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ Location permissions denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permissions permanently denied');
        return null;
      }

      // Try last known location first (fast)
      try {
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null) {
          final age = DateTime.now().difference(lastPos.timestamp).inSeconds;
          if (age < 60) {
            // Location is fresh (less than 1 minute old)
            print('✅ Using cached location (${age}s old)');
            return lastPos;
          }
        }
      } catch (_) {}

      // Get current position with medium accuracy
      print('📡 Requesting location via plugin...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        forceAndroidLocationManager: false,
        timeLimit: const Duration(seconds: 15),
      ).timeout(
        const Duration(seconds: 17),
        onTimeout: () => throw TimeoutException('Location timeout'),
      );

      print('✅ Plugin location: (${position.latitude}, ${position.longitude})');
      return position;
    } catch (e) {
      print('❌ Error getting location via plugin: $e');
      // Final fallback: last known location
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }
  
  /// Get location with validation data for geofence check
  static Future<Map<String, dynamic>?> getLocationForGeofence({
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
  }) async {
    final position = await getCurrentLocation();
    
    if (position == null) {
      return null;
    }

    // Calculate distance
    final distance = _calculateDistance(
      centerLat,
      centerLng,
      position.latitude,
      position.longitude,
    );

    final isInside = distance <= radiusMeters;
    
    print('📍 Location: (${position.latitude}, ${position.longitude})');
    print('📏 Distance: ${distance.toStringAsFixed(1)}m, Inside: $isInside');

    return {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'timestamp': position.timestamp,
      'distance': distance,
      'inside_geofence': isInside,
    };
  }
  
  /// Calculate distance between two points in meters (Haversine formula)
  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0;
    
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadiusMeters * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  
  @override
  String toString() => message;
}
