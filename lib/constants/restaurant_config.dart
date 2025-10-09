class RestaurantConfig {
  const RestaurantConfig._();

  static const double latitude = 30.0444; // Example: Cairo Tahrir Square
  static const double longitude = 31.2357;
  static const double allowedRadiusInMeters = 120; // Slightly wider than requested 100m to account for GPS jitter
  static const bool enforceLocation = false;
}
