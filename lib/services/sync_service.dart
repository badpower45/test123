import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../database/offline_database.dart';
import '../constants/api_endpoints.dart';
import 'notification_service.dart';
import 'offline_data_service.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  Timer? _syncTimer;
  bool _isSyncing = false;
  final NotificationService _notifications = NotificationService.instance;
  final OfflineDataService _offlineService = OfflineDataService();

  // Start periodic sync (every 60 seconds)
  void startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      syncPendingData();
    });
  }

  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
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
        // Try to connect to a reliable server (Google DNS or Supabase)
        final response = await http
            .head(Uri.parse('https://www.google.com'))
            .timeout(const Duration(seconds: 3));
        
        final hasNet = response.statusCode == 200 || response.statusCode == 301 || response.statusCode == 302;
        print(hasNet ? '✅ Internet available' : '❌ Server unreachable (${response.statusCode})');
        return hasNet;
      } catch (e) {
        print('❌ Network check failed: $e');
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
        final unsyncedAttendance = await _offlineService.getUnsyncedAttendance();
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
              print('[SyncService] Failed to sync check-in ${checkin['id']}: $e');
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
              print('[SyncService] Failed to sync check-out ${checkout['id']}: $e');
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
              print('[SyncService] Failed to sync violation ${violation['id']}: $e');
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
          return {
            'success': false,
            'message': 'Database not ready: $e',
          };
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
    print('📥 Syncing check-in: employee=${checkin['employee_id']}, wifi=${checkin['wifi_bssid']}');
    
    final response = await http.post(
      Uri.parse(checkInEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'employee_id': checkin['employee_id'],
        'timestamp': checkin['timestamp'],
        'latitude': checkin['latitude'],
        'longitude': checkin['longitude'],
        'wifi_bssid': checkin['wifi_bssid'],
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200 && response.statusCode != 201) {
      print('❌ Check-in sync failed: ${response.statusCode} - ${response.body}');
      throw Exception('Check-in failed: ${response.statusCode}');
    }
    
    print('✅ Check-in synced successfully');
  }

  Future<void> _syncCheckout(Map<String, dynamic> checkout) async {
    final response = await http.post(
      Uri.parse(checkOutEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'employee_id': checkout['employee_id'],
        'attendance_id': checkout['attendance_id'],
        'timestamp': checkout['timestamp'],
        'latitude': checkout['latitude'],
        'longitude': checkout['longitude'],
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Check-out failed: ${response.statusCode}');
    }
  }

  Future<void> _syncPulse(Map<String, dynamic> pulse) async {
    print('📍 Syncing pulse: employee=${pulse['employee_id']}, inside=${pulse['inside_geofence']}');
    
    final response = await http.post(
      Uri.parse(pulseEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'employee_id': pulse['employee_id'],
        'timestamp': pulse['timestamp'],
        'latitude': pulse['latitude'],
        'longitude': pulse['longitude'],
        'inside_geofence': pulse['inside_geofence'] ?? true,
        'distance_from_center': pulse['distance_from_center'] ?? 0.0,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200 && response.statusCode != 201) {
      print('❌ Pulse sync failed: ${response.statusCode} - ${response.body}');
      throw Exception('Pulse failed: ${response.statusCode}');
    }
    
    print('✅ Pulse synced successfully');
  }

  Future<void> _syncGeofenceViolation(Map<String, dynamic> violation) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/alerts/geofence-violation'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'employeeId': violation['employee_id'],
        'timestamp': violation['timestamp'],
        'latitude': violation['latitude'],
        'longitude': violation['longitude'],
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Geofence alert failed: ${response.statusCode}');
    }
  }

  // Manual sync trigger
  Future<Map<String, dynamic>> forceSyncNow() async {
    return await syncPendingData();
  }
}
