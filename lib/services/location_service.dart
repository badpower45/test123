import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<bool> _ensureServiceEnabled() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }
    return true;
  }

  Future<bool> _ensurePermissionGranted() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine ||
        permission == LocationPermission.denied) {
      return false;
    }
    return true;
  }

  /// Get current position with enhanced accuracy and retry mechanism
  Future<Position?> _getCurrentPosition() async {
    final hasService = await _ensureServiceEnabled();
    if (!hasService) {
      print('[LocationService] Location service not enabled');
      return null;
    }
    
    final hasPermission = await _ensurePermissionGranted();
    if (!hasPermission) {
      print('[LocationService] Location permission not granted');
      return null;
    }

    // Try multiple times to get accurate location
    Position? bestPosition;
    int attempts = 0;
    const maxAttempts = 3;
    
    while (attempts < maxAttempts) {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          forceAndroidLocationManager: true,
          timeLimit: const Duration(seconds: 15),
        ).timeout(const Duration(seconds: 20));
        
        print('[LocationService] Attempt ${attempts + 1}: accuracy=${position.accuracy.toStringAsFixed(1)}m');
        
        // If this is the first position or better accuracy than previous
        if (bestPosition == null || position.accuracy < bestPosition.accuracy) {
          bestPosition = position;
        }
        
        // If accuracy is good enough (less than 30 meters), use it
        if (position.accuracy <= 30) {
          print('[LocationService] Good accuracy achieved: ${position.accuracy.toStringAsFixed(1)}m');
          return position;
        }
        
        attempts++;
        
        // Wait a bit before next attempt
        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(seconds: 2));
        }
      } catch (e) {
        print('[LocationService] Attempt ${attempts + 1} failed: $e');
        attempts++;
        
        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }
    
    if (bestPosition != null) {
      print('[LocationService] Using best position with accuracy: ${bestPosition.accuracy.toStringAsFixed(1)}m');
    } else {
      print('[LocationService] Failed to get any position after $maxAttempts attempts');
    }
    
    return bestPosition;
  }

  Future<bool> isWithinRestaurantArea({
    required double restaurantLat,
    required double restaurantLon,
    double radiusInMeters = 100,
  }) async {
    final position = await _getCurrentPosition();
    if (position == null) {
      return false;
    }

    final distance = Geolocator.distanceBetween(
      restaurantLat,
      restaurantLon,
      position.latitude,
      position.longitude,
    );
    
    print('[LocationService] Distance check: ${distance.toStringAsFixed(1)}m (radius: ${radiusInMeters}m)');
    
    return distance <= radiusInMeters;
  }

  Future<Position?> tryGetPosition() => _getCurrentPosition();
}
