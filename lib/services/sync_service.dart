import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../database/offline_database.dart';
import 'notification_service.dart';
import 'offline_data_service.dart';
import 'supabase_function_client.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  Timer? _syncTimer;
  bool _isSyncing = false;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  final NotificationService _notifications = NotificationService.instance;
  final OfflineDataService _offlineService = OfflineDataService();

  // Start periodic sync (every 60 seconds)
  void startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      syncPendingData();
    });

    // Also listen to connectivity changes to trigger immediate sync when online
    _connSub?.cancel();
    _connSub = Connectivity().onConnectivityChanged.listen((results) async {
      // Treat any non-none connectivity as online
      final hasAny = results.any((r) => r != ConnectivityResult.none);
      if (hasAny) {
        // Small delay to allow network stack to stabilize
        await Future.delayed(const Duration(milliseconds: 300));
        await syncPendingData();
      }
    });
  }

  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _connSub?.cancel();
    _connSub = null;
  }

  // Check if internet is available
  Future<bool> hasInternet() async {
    try {
      // First: Quick connectivity check
      final connectivityResult = await Connectivity().checkConnectivity();

      if (connectivityResult == ConnectivityResult.none) {
        print('❌ No connectivity detected');
        return false;
      }

      // If we have connectivity type, try a simple network request
      try {
        // Use Supabase REST API with anon key (more reliable than auth endpoint)
        final healthUrl = Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/');
        final response = await http
            .get(
              healthUrl,
              headers: {
                'apikey': SupabaseConfig.supabaseAnonKey,
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 4));

        // Any response from Supabase means internet is working
        // (even 404 or 400 means we reached the server)
        final hasNet = response.statusCode < 500;
        print(
          hasNet
              ? '✅ Internet available'
              : '❌ Supabase unreachable (${response.statusCode})',
        );
        return hasNet;
      } catch (e) {
        print('❌ Network check failed (Supabase health): $e');
        // ✅ إذا فشل الطلب، يعني مفيش إنترنت حقيقي
        return false;
      }
    } catch (e) {
      print('❌ Internet check error: $e');
      return false;
    }
  }

  // Sync all pending data
  Future<Map<String, dynamic>> syncPendingData() async {
    if (_isSyncing) {
      return {'success': false, 'message': 'Sync already in progress'};
    }

    _isSyncing = true;

    try {
      // 1. Check internet connection
      if (!await hasInternet()) {
        print('⚠️ No internet - sync postponed');
        return {'success': false, 'message': 'No internet connection'};
      }

      int syncedCount = 0;
      int failedCount = 0;

      // 2. Platform-specific sync
      if (kIsWeb) {
        // === WEB: Use Hive ===
        print('🌐 Syncing Web data (Hive)...');

        // Sync attendance from Hive
        final unsyncedAttendance = await _offlineService
            .getUnsyncedAttendance();
        for (var record in unsyncedAttendance) {
          try {
            if (record['type'] == 'check_in') {
              await _syncCheckin(record);
            } else if (record['type'] == 'check_out') {
              await _syncCheckout(record);
            }
            await _offlineService.markAttendanceSynced(record['key']);
            syncedCount++;
          } catch (e) {
            print('[SyncService] Failed to sync ${record['type']}: $e');
            failedCount++;
          }
        }

        // Sync pulses from Hive
        final unsyncedPulses = await _offlineService.getUnsyncedPulses();
        for (var pulse in unsyncedPulses) {
          try {
            await _syncPulse(pulse);
            await _offlineService.markPulseSynced(pulse['key']);
            syncedCount++;
          } catch (e) {
            print('[SyncService] Failed to sync pulse: $e');
            failedCount++;
          }
        }
      } else {
        // === MOBILE: Use SQLite ===
        print('📱 Syncing Mobile data (SQLite)...');

        // Check if database file exists and is initialized
        try {
          final db = OfflineDatabase.instance;

          // Verify database is accessible
          final pendingCount = await db.getPendingCount();
          print('📊 Total pending records in SQLite: $pendingCount');

          if (pendingCount == 0) {
            print('✅ No pending data to sync');
            return {
              'success': true,
              'synced': 0,
              'failed': 0,
              'message': 'لا توجد بيانات للمزامنة',
            };
          }

          // Sync check-ins
          final pendingCheckins = await db.getPendingCheckins();
          print('📥 Pending check-ins: ${pendingCheckins.length}');
          for (var checkin in pendingCheckins) {
            try {
              await _syncCheckin(checkin);
              await db.markCheckinSynced(checkin['id']);
              syncedCount++;
            } catch (e) {
              print(
                '[SyncService] Failed to sync check-in ${checkin['id']}: $e',
              );
              failedCount++;
            }
          }

          // Sync check-outs
          final pendingCheckouts = await db.getPendingCheckouts();
          print('📤 Pending check-outs: ${pendingCheckouts.length}');
          for (var checkout in pendingCheckouts) {
            try {
              await _syncCheckout(checkout);
              await db.markCheckoutSynced(checkout['id']);
              syncedCount++;
            } catch (e) {
              print(
                '[SyncService] Failed to sync check-out ${checkout['id']}: $e',
              );
              failedCount++;
            }
          }

          // Sync pulses
          final pendingPulses = await db.getPendingPulses();
          print('💓 Pending pulses: ${pendingPulses.length}');
          for (var pulse in pendingPulses) {
            try {
              await _syncPulse(pulse);
              await db.markPulseSynced(pulse['id']);
              syncedCount++;
            } catch (e) {
              print('[SyncService] Failed to sync pulse ${pulse['id']}: $e');
              failedCount++;
            }
          }

          // Sync geofence violations
          final violations = await db.getUnsyncedViolations();
          print('⚠️ Pending violations: ${violations.length}');
          for (var violation in violations) {
            try {
              await _syncGeofenceViolation(violation);
              await db.markViolationSynced(violation['id']);
              syncedCount++;
            } catch (e) {
              print(
                '[SyncService] Failed to sync violation ${violation['id']}: $e',
              );
              failedCount++;
            }
          }

          // Clean up synced data
          await db.deleteSyncedCheckins();
          await db.deleteSyncedCheckouts();
          print('🗑️ Cleaned up synced records');
        } catch (e) {
          print('❌ SQLite database error: $e');
          print('💡 Database may not be initialized yet (first run)');
          return {'success': false, 'message': 'Database not ready: $e'};
        }
      }

      // Show success notification if data was synced
      if (syncedCount > 0) {
        await _notifications.showSyncSuccessNotification(syncedCount);
        print('✅ تم مزامنة البيانات ورفعها بالكامل');
      }

      return {
        'success': true,
        'synced': syncedCount,
        'failed': failedCount,
        'message': syncedCount > 0
            ? 'تم مزامنة البيانات ورفعها بالكامل'
            : 'لا توجد بيانات للمزامنة',
      };
    } catch (e) {
      print('❌ Sync error: $e');
      return {'success': false, 'message': 'خطأ في المزامنة: $e'};
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncCheckin(Map<String, dynamic> checkin) async {
    print(
      '📥 Syncing check-in: employee=${checkin['employee_id']}, wifi=${checkin['wifi_bssid']}',
    );

    final payload = {
      'employee_id': checkin['employee_id'],
      'latitude': checkin['latitude'],
      'longitude': checkin['longitude'],
      if (checkin['wifi_bssid'] != null) 'wifi_bssid': checkin['wifi_bssid'],
      if (checkin['timestamp'] != null) 'timestamp': checkin['timestamp'],
    };
    final result = await SupabaseFunctionClient.post(
      'attendance-check-in',
      payload,
      throwOnError: false,
    );

    String? newAttendanceId;
    if (result != null) {
      // Edge function style
      if (result['attendance'] is Map && result['attendance']['id'] is String) {
        newAttendanceId = result['attendance']['id'] as String;
      } else if (result['id'] is String) {
        // Direct fallback style
        newAttendanceId = result['id'] as String;
      }
    }

    // Backfill pulses with new attendance_id before next pulse sync
    if (newAttendanceId != null && newAttendanceId.isNotEmpty) {
      try {
        final db = OfflineDatabase.instance;
        final affected = await db.backfillAttendanceIdForPulses(
          employeeId: checkin['employee_id'],
          attendanceId: newAttendanceId,
        );
        print(
          '🔄 Backfilled attendance_id for $affected pending pulses (id=$newAttendanceId)',
        );
      } catch (e) {
        print('⚠️ Backfill pulses failed: $e');
      }
    }

    print('✅ Check-in sync attempt completed');
  }

  Future<void> _syncCheckout(Map<String, dynamic> checkout) async {
    print(
      '📤 Syncing check-out: employee=${checkout['employee_id']}, attendance_id=${checkout['attendance_id']}',
    );
    final note = checkout['notes'] as String?;
    final isForced = note?.toLowerCase().contains('auto') ?? false;

    final payload = {
      'employee_id': checkout['employee_id'],
      if (checkout['attendance_id'] != null)
        'attendance_id':
            checkout['attendance_id'], // ✅ Add attendance_id if available
      'latitude': checkout['latitude'],
      'longitude': checkout['longitude'],
      if (checkout['wifi_bssid'] != null) 'wifi_bssid': checkout['wifi_bssid'],
      if (checkout['timestamp'] != null) 'timestamp': checkout['timestamp'],
      if (note != null && note.isNotEmpty) 'notes': note,
      if (isForced) 'force_checkout': true,
    };

    print('📤 Check-out payload: $payload');
    await SupabaseFunctionClient.post('attendance-check-out', payload);
    print('✅ Check-out synced successfully');
  }

  Future<void> _syncPulse(Map<String, dynamic> pulse) async {
    print(
      '📍 Syncing pulse: employee=${pulse['employee_id']}, inside=${pulse['inside_geofence']}',
    );

    bool? insideGeofence;
    final rawInside = pulse['inside_geofence'];
    if (rawInside is bool) {
      insideGeofence = rawInside;
    } else if (rawInside is num) {
      insideGeofence = rawInside != 0;
    } else if (rawInside is String) {
      if (rawInside.toLowerCase() == 'true' || rawInside == '1') {
        insideGeofence = true;
      } else if (rawInside.toLowerCase() == 'false' || rawInside == '0') {
        insideGeofence = false;
      }
    }

    double? distanceFromCenter;
    final rawDistance = pulse['distance_from_center'];
    if (rawDistance is num) {
      distanceFromCenter = rawDistance.toDouble();
    } else if (rawDistance is String) {
      distanceFromCenter = double.tryParse(rawDistance);
    }

    // Validate attendance_id (must be UUID v4) – ignore placeholders or invalid strings
    String? attendanceId = pulse['attendance_id'] as String?;
    if (attendanceId != null) {
      final trimmed = attendanceId.trim();
      final isPlaceholder =
          RegExp(
            r'(pending|local|temp|dummy)',
            caseSensitive: false,
          ).hasMatch(trimmed) ||
          trimmed.length < 8;
      final uuidRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      );
      if (isPlaceholder || !uuidRegex.hasMatch(trimmed)) {
        attendanceId = null; // Strip invalid
      }
    }

    final validationMethod = (pulse['validation_method'] as String?) ??
        ((pulse['validated_by_wifi'] == 1 || pulse['validated_by_wifi'] == true)
            ? 'WIFI'
            : ((pulse['validated_by_location'] == 1 || pulse['validated_by_location'] == true)
                ? 'LOCATION'
                : 'UNKNOWN'));

    final payload = {
      'pulses': [
        {
          'employee_id': pulse['employee_id'],
          if (attendanceId != null) 'attendance_id': attendanceId,
          if (pulse['branch_id'] != null) 'branch_id': pulse['branch_id'],
          'timestamp': pulse['timestamp'],
          'latitude': pulse['latitude'],
          'longitude': pulse['longitude'],
          if (pulse['wifi_bssid'] != null) 'wifi_bssid': pulse['wifi_bssid'],
          'validation_method': validationMethod,
          if (insideGeofence != null) 'inside_geofence': insideGeofence,
          if (insideGeofence != null) 'is_within_geofence': insideGeofence,
          if (distanceFromCenter != null)
            'distance_from_center': distanceFromCenter,
          if (pulse['validated_by_wifi'] != null)
            'validated_by_wifi':
                pulse['validated_by_wifi'] == 1 ||
                pulse['validated_by_wifi'] == true,
          if (pulse['validated_by_location'] != null)
            'validated_by_location':
                pulse['validated_by_location'] == 1 ||
                pulse['validated_by_location'] == true,
        },
      ],
    };

    await SupabaseFunctionClient.post('sync-pulses', payload);

    print(
      '✅ Pulse synced successfully (distance=${distanceFromCenter ?? 'n/a'}m)',
    );
  }

  Future<void> _syncGeofenceViolation(Map<String, dynamic> violation) async {
    // Use Edge Function to bypass RLS
    final payload = {
      'employee_id': violation['employee_id'],
      'timestamp': violation['timestamp'],
      'latitude': violation['latitude'],
      'longitude': violation['longitude'],
      'branch_id': violation['branch_id'],
      'distance': violation['distance'],
      'geofence_radius': violation['geofence_radius'],
    };

    await SupabaseFunctionClient.post('log-violation', payload);
    print('✅ Violation synced successfully');
  }

  // Manual sync trigger
  Future<Map<String, dynamic>> forceSyncNow() async {
    return await syncPendingData();
  }
}
