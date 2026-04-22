/// Compile-safe integration notes for native pulse/location services.
///
/// This file intentionally contains only documentation helpers so it does not
/// break builds. Real implementation lives in:
/// - pulse_tracking_service.dart
/// - native_location_service.dart
/// - native_pulse_service.dart
class NativeIntegrationExample {
  const NativeIntegrationExample._();

  /// High-level sequence to use native tracking safely:
  /// 1) Start native persistent service during check-in.
  /// 2) Use native location for faster geofence reads.
  /// 3) Keep Flutter fallback for non-Android targets.
  /// 4) Stop native service on checkout.
  static List<String> implementationChecklist() {
    return const [
      'Start NativePulseService on check-in when platform is Android',
      'Validate geofence via NativeLocationService before saving pulse',
      'Fallback to Flutter path on iOS/Web or native failures',
      'Stop NativePulseService on checkout and clear tracking state',
    ];
  }
}
