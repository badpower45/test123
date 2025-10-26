class RestaurantConfig {
  const RestaurantConfig._();

  // Default values for single-branch compatibility
  static const double latitude = 30.0444; // Example: Cairo Tahrir Square
  static const double longitude = 31.2357;
  static const double allowedRadiusInMeters = 120; // Slightly wider than requested 100m to account for GPS jitter
  static const bool enforceLocation = true;

  // For multi-branch, these will be overridden by branch settings
  static const String? allowedWifiBssid = null;

  // Dynamic getters for branch-specific settings (to be set at runtime)
  static double? _branchLatitude;
  static double? _branchLongitude;
  static double? _branchRadius;
  static List<String>? _branchBssids;

  static void setBranchSettings({
    double? latitude,
    double? longitude,
    double? radius,
    List<String>? bssids,
  }) {
    _branchLatitude = latitude;
    _branchLongitude = longitude;
    _branchRadius = radius;
    _branchBssids = bssids;
  }

  static double get branchLatitude => _branchLatitude ?? latitude;
  static double get branchLongitude => _branchLongitude ?? longitude;
  static double get branchRadius => _branchRadius ?? allowedRadiusInMeters;
  static List<String> get branchBssids => _branchBssids ?? (allowedWifiBssid != null ? [allowedWifiBssid!] : []);
}
