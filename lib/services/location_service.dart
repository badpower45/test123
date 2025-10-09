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
      return null;
    }
    final hasPermission = await _ensurePermissionGranted();
    if (!hasPermission) {
      return null;
    }
    return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
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
    return distance <= radiusInMeters;
  }

  Future<Position?> tryGetPosition() => _getCurrentPosition();
}
