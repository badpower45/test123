import 'package:geolocator/geolocator.dart';

class LocationService {
  // Cache للموقع الأخير لتسريع الاستجابة
  static Position? _lastKnownPosition;
  static DateTime? _lastPositionTime;
  static const Duration _cacheValidDuration = Duration(minutes: 2);

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

  /// Get current position with smart caching and fast response
  Future<Position?> _getCurrentPosition() async {
    final hasService = await _ensureServiceEnabled();
    if (!hasService) {
      print('[LocationService] ❌ Location service not enabled');
      return null;
    }

    final hasPermission = await _ensurePermissionGranted();
    if (!hasPermission) {
      print('[LocationService] ❌ Location permission not granted');
      return null;
    }

    // استخدم الـ cache إذا كان حديث (أقل من دقيقتين)
    if (_lastKnownPosition != null && _lastPositionTime != null) {
      final age = DateTime.now().difference(_lastPositionTime!);
      if (age < _cacheValidDuration) {
        print('[LocationService] 📍 Using cached position (${age.inSeconds}s old)');
        return _lastKnownPosition;
      }
    }

    try {
      // محاولة واحدة سريعة - قبول أي دقة معقولة
      print('[LocationService] 🔍 Getting fresh location...');
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, // متوسط - أسرع من best
        forceAndroidLocationManager: false, // استخدم Google Play Services (أسرع)
        timeLimit: const Duration(seconds: 8),
      ).timeout(const Duration(seconds: 10));

      print('[LocationService] ✅ Got position: accuracy=${position.accuracy.toStringAsFixed(1)}m');
      
      // حفظ في الـ cache
      _lastKnownPosition = position;
      _lastPositionTime = DateTime.now();
      
      return position;
      
    } catch (e) {
      print('[LocationService] ⚠️ Failed to get fresh location: $e');
      
      // Fallback: استخدم آخر موقع معروف من النظام
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          print('[LocationService] 📍 Using last known position from system');
          _lastKnownPosition = lastKnown;
          _lastPositionTime = DateTime.now();
          return lastKnown;
        }
      } catch (e2) {
        print('[LocationService] ❌ Failed to get last known position: $e2');
      }
      
      // Fallback نهائي: استخدم الـ cache حتى لو قديم
      if (_lastKnownPosition != null) {
        print('[LocationService] ⚠️ Using old cached position as last resort');
        return _lastKnownPosition;
      }
      
      return null;
    }
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
    
    print('[LocationService] 📏 Distance: ${distance.toStringAsFixed(1)}m (allowed: ${radiusInMeters}m, accuracy: ${position.accuracy.toStringAsFixed(1)}m)');
    
    // إضافة هامش للدقة - إذا المسافة قريبة من الحد وفي margin للخطأ
    final effectiveRadius = radiusInMeters + (position.accuracy * 0.3);
    
    return distance <= effectiveRadius;
  }

  Future<Position?> tryGetPosition() => _getCurrentPosition();
  
  /// Clear cache to force fresh location
  static void clearCache() {
    _lastKnownPosition = null;
    _lastPositionTime = null;
    print('[LocationService] 🗑️ Cache cleared');
  }
}
