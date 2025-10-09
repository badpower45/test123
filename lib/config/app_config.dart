class AppConfig {
  const AppConfig._();

  /// Supabase project URL, e.g. https://xyzcompany.supabase.co
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://cjojfmnlhkkdqcwkdjea.supabase.co',
  );

  /// Supabase anonymous public key.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNqb2pmbW5saGtrZHFjd2tkamVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk4NDMxMTAsImV4cCI6MjA3NTQxOTExMH0.W7dExxtfxRr56XCr-c0VS1VEidtyyiEJrR97fB4pdsI',
  );

  /// Supabase table that stores pulse rows.
  static const String supabasePulseTable = String.fromEnvironment(
    'SUPABASE_PULSE_TABLE',
    defaultValue: 'pulses',
  );

  /// Optional REST endpoint for the legacy HTTP API (still used as fallback).
  static const String primaryHeartbeatEndpoint = String.fromEnvironment(
    'PRIMARY_HEARTBEAT_ENDPOINT',
    defaultValue: 'https://api.oldies.com/heartbeat',
  );

  static const String primaryOfflineSyncEndpoint = String.fromEnvironment(
    'PRIMARY_OFFLINE_SYNC_ENDPOINT',
    defaultValue: 'https://api.oldies.com/sync-offline-pulses',
  );

  /// Host for the backup monitor (defaults to localhost for dev).
  static const String backupHost = String.fromEnvironment(
    'BACKUP_HOST',
    defaultValue: 'http://localhost:8080',
  );

  static bool get supabaseEnabled =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
