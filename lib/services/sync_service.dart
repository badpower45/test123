import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../database/offline_database.dart';
import '../constants/api_endpoints.dart';
import 'notification_service.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  Timer? _syncTimer;
  bool _isSyncing = false;
  final NotificationService _notifications = NotificationService.instance;

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
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }

      // Additional check: try to reach the server
      final response = await http
          .get(Uri.parse('$apiBaseUrl/../health'))
          .timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
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
      if (!await hasInternet()) {
        return {'success': false, 'message': 'No internet connection'};
      }

      final db = OfflineDatabase.instance;
      int syncedCount = 0;
      int failedCount = 0;

      // Sync check-ins
      final pendingCheckins = await db.getPendingCheckins();
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

      // Show success notification if data was synced
      if (syncedCount > 0) {
        await _notifications.showSyncSuccessNotification(syncedCount);
      }

      return {
        'success': true,
        'synced': syncedCount,
        'failed': failedCount,
        'message': 'تم رفع $syncedCount سجل بنجاح',
      };
    } catch (e) {
      return {'success': false, 'message': 'خطأ في المزامنة: $e'};
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncCheckin(Map<String, dynamic> checkin) async {
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
      throw Exception('Check-in failed: ${response.statusCode}');
    }
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
    final response = await http.post(
      Uri.parse(pulseEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'employee_id': pulse['employee_id'],
        'timestamp': pulse['timestamp'],
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Pulse failed: ${response.statusCode}');
    }
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
