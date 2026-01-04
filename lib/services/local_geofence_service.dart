import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'native_location_service.dart'; // ✅ استخدام Native GPS

/// Local geofence validation service
/// Checks if a location is within a circular geofence
/// ✅ OPTIMIZED: Uses native GPS on Android for faster location
class LocalGeofenceService {
  
  /// Check if a point is inside a circular geofence
  /// Returns true if inside, false if outside
  static bool isInsideGeofence({
    required double userLat,
    required double userLng,
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
  }) {
    // ✅ Calculate distance (center first, then user position)
    final distance = calculateDistance(
      centerLat,
      centerLng,
      userLat,
      userLng,
    );
    
    return distance <= radiusMeters;
  }

  /// Calculate distance between two points in meters
  /// Using Haversine formula
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0; // Earth radius in meters
    
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

  /// Get current location
  /// ✅ OPTIMIZED: Uses native GPS on Android (1-3s instead of 15-30s)
  static Future<Position?> getCurrentLocation() async {
    // Use native GPS service (falls back to plugin on iOS or if native fails)
    return NativeLocationService.getCurrentLocation();
  }

  /// Validate geofence with current location
  static Future<Map<String, dynamic>?> validateGeofence({
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
  }) async {
    final position = await getCurrentLocation();
    
    if (position == null) {
      return null;
    }

    // ✅ Calculate distance (center first, then current position)
    final distance = calculateDistance(
      centerLat,
      centerLng,
      position.latitude,
      position.longitude,
    );

    final isInside = distance <= radiusMeters;
    
    print('📍 Pulse: Current=(${position.latitude}, ${position.longitude}), Center=($centerLat, $centerLng)');
    print('📏 Distance: ${distance.toStringAsFixed(1)}m, Radius: ${radiusMeters.toStringAsFixed(1)}m, Inside: $isInside');

    return {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'distance': distance, // Already in meters
      'inside_geofence': isInside,
      'timestamp': DateTime.now(),
    };
  }
}
