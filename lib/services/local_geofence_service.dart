import 'dart:math';
import 'package:geolocator/geolocator.dart';

/// Local geofence validation service
/// Checks if a location is within a circular geofence
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
  static Future<Position?> getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        return null;
      }

      // Check location permissions
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

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return position;
    } catch (e) {
      print('❌ Error getting current location: $e');
      return null;
    }
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
