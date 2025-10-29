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

    // --- بداية التعديلات ---
    Position? position;
    int attempts = 0;
    // قلّلنا عدد المحاولات لـ 2
    const maxAttempts = 2;

    while (attempts < maxAttempts) {
      try {
        position = await Geolocator.getCurrentPosition(
          // قلّلنا الدقة المطلوبة
          desiredAccuracy: LocationAccuracy.high,
          forceAndroidLocationManager: true,
          // قلّلنا مهلة الانتظار لكل محاولة
          timeLimit: const Duration(seconds: 10),
        ).timeout(const Duration(seconds: 12)); // مهلة إجمالية للمحاولة

        print('[LocationService] Attempt ${attempts + 1}: accuracy=${position.accuracy.toStringAsFixed(1)}m');

        // هنقبل أي دقة أقل من 50 متر (بدلاً من 30)
        if (position.accuracy <= 50) {
          print('[LocationService] Good enough accuracy achieved: ${position.accuracy.toStringAsFixed(1)}m');
          return position; // ارجع بالنتيجة فوراً
        }

        // لو الدقة وحشة، حاول مرة كمان لو لسه فيه محاولات
        attempts++;
        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(seconds: 1)); // انتظار ثانية قبل المحاولة التالية
        }

      } catch (e) {
        print('[LocationService] Attempt ${attempts + 1} failed: $e');
        attempts++;

        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    // لو فشلت كل المحاولات أو الدقة لسه وحشة بعد المحاولتين، رجع آخر نتيجة (أو null)
    if (position != null) {
       print('[LocationService] Using best available position after $attempts attempts: accuracy=${position.accuracy.toStringAsFixed(1)}m');
    } else {
       print('[LocationService] Failed to get location after $attempts attempts');
    }
    // --- نهاية التعديلات ---

    return position; // رجع أفضل نتيجة تم الحصول عليها (حتى لو مش مثالية)
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
