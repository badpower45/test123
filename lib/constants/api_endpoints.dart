import '../config/app_config.dart';

class ApiEndpoints {
  const ApiEndpoints._();

  static String get primaryHeartbeat =>
      AppConfig.primaryHeartbeatEndpoint;

  static String get primaryOfflineSync =>
      AppConfig.primaryOfflineSyncEndpoint;

  /// Backup monitor endpoints. Update [AppConfig.backupHost] to point at the
  /// machine running `tool/pulse_backup_server.dart` (must be reachable from
  /// the device, e.g. http://192.168.1.24:8080).
  static String get backupHeartbeat =>
      '${AppConfig.backupHost}/heartbeat';

  static String get backupOfflineSync =>
      '${AppConfig.backupHost}/sync-offline-pulses';
}
