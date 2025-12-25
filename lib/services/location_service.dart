import 'package:geolocator/geolocator.dart';

class LocationService {
  // Cache للموقع الأخير لتسريع الاستجابة
  static Position? _lastKnownPosition;
  static DateTime? _lastPositionTime;

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

    // استخدم الـ cache إذا كان حديث (أقل من دقيقة واحدة)
    if (_lastKnownPosition != null && _lastPositionTime != null) {
      final age = DateTime.now().difference(_lastPositionTime!);
      if (age < Duration(seconds: 30)) {
        print('[LocationService] 📍 Using cached position (${age.inSeconds}s old)');
        return _lastKnownPosition;
      }
    }

    try {
      // محاولة الحصول على آخر موقع معروف أولاً (فوري) - أولوية للأجهزة القديمة
      print('[LocationService] 🔍 Trying last known position first...');
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final age = DateTime.now().difference(lastKnown.timestamp);
        // Accept last known position if less than 5 minutes old
        if (age.inMinutes < 5) {
          print('[LocationService] ✅ Using last known position (${age.inMinutes}m old, accuracy: ${lastKnown.accuracy.toStringAsFixed(1)}m)');
          _lastKnownPosition = lastKnown;
          _lastPositionTime = DateTime.now();
          return lastKnown;
        } else {
          print('[LocationService] ⚠️ Last known position too old (${age.inMinutes}m), getting fresh...');
        }
      }
      
      // إذا مفيش last known حديث، جيب موقع جديد بأقصى توافق
      print('[LocationService] 🔍 Getting fresh location...');
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, // Changed from low to medium for better reliability
        forceAndroidLocationManager: true, // Force Android Location Manager for old devices
        timeLimit: const Duration(seconds: 10), // Increased timeout
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () async {
          print('[LocationService] ⏰ Timeout getting position, trying last known...');
          final fallback = await Geolocator.getLastKnownPosition();
          if (fallback != null) {
            print('[LocationService] ✅ Using fallback last known position');
            return fallback;
          }
          throw Exception('Location timeout and no fallback available');
        },
      );

      print('[LocationService] ✅ Got fresh position: accuracy=${position.accuracy.toStringAsFixed(1)}m');
      
      // حفظ في الـ cache
      _lastKnownPosition = position;
      _lastPositionTime = DateTime.now();
      
      return position;
      
    } catch (e) {
      print('[LocationService] ⚠️ Error getting location: $e');
      
      // Fallback نهائي: استخدم الـ cache حتى لو قديم
      if (_lastKnownPosition != null) {
        final age = DateTime.now().difference(_lastPositionTime!);
        print('[LocationService] ⚠️ Using old cached position as last resort (${age.inMinutes}m old)');
        return _lastKnownPosition;
      }
      
      // محاولة أخيرة: getLastKnownPosition
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          print('[LocationService] ✅ Retrieved last known position from system');
          _lastKnownPosition = lastKnown;
          _lastPositionTime = DateTime.now();
          return lastKnown;
        }
      } catch (e2) {
        print('[LocationService] ❌ All fallbacks failed: $e2');
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
