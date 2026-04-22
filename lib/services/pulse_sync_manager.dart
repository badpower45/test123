import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../database/offline_database.dart';
import '../models/pulse.dart';
import 'pulse_backend_client.dart';

/// 🔄 Pulse Sync Manager - Unified SQLite Storage
/// 
/// ✅ OPTIMIZED: Uses SQLite (pending_pulses table) instead of Hive
/// ✅ Syncs all offline pulses to Supabase when connection is available
/// ✅ Single source of truth for pulse data
class PulseSyncManager {
  PulseSyncManager._();

  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static bool _isInitialized = false;
  static bool _isSyncing = false;

  static Future<void> initializeForMainIsolate() async {
    if (_isInitialized) {
      return;
    }
    
    print('🔄 Initializing PulseSyncManager with SQLite...');
    
    // Sync pending pulses immediately
    await syncPendingPulses();
    
    // Listen for connectivity changes
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) async {
      final hasConnection =
          results.any((status) => status != ConnectivityResult.none);
      if (hasConnection) {
        print('📡 Connection restored - syncing pending pulses...');
        await syncPendingPulses();
      }
    });
    
    _isInitialized = true;
    print('✅ PulseSyncManager initialized');
  }

  static Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _isInitialized = false;
  }

  /// Store pulse in unified SQLite queue for later sync.
  static Future<void> storePulseOffline(Pulse pulse) async {
    if (kIsWeb) return;

    final hasWifi = (pulse.wifiBssid ?? '').trim().isNotEmpty;
    final validationMethod = hasWifi ? 'WIFI' : 'LOCATION';

    await OfflineDatabase.instance.insertPendingPulse(
      employeeId: pulse.employeeId,
      attendanceId: null,
      branchId: pulse.branchId,
      timestamp: pulse.timestamp,
      latitude: pulse.latitude,
      longitude: pulse.longitude,
      insideGeofence: pulse.isWithinGeofence ?? true,
      distanceFromCenter: pulse.distanceFromCenter,
      wifiBssid: pulse.wifiBssid,
      validationMethod: validationMethod,
      validatedByWifi: hasWifi,
      validatedByLocation: !hasWifi,
      synced: false,
    );
  }

  /// Get count of pending pulses in SQLite
  static Future<int> pendingPulseCount() async {
    if (kIsWeb) return 0;
    
    try {
      final db = OfflineDatabase.instance;
      final pendingPulses = await db.getPendingPulses();
      return pendingPulses.length;
    } catch (e) {
      print('⚠️ Error getting pending pulse count: $e');
      return 0;
    }
  }

  /// Sync all pending pulses from SQLite to Supabase
  static Future<int> syncPendingPulses() async {
    if (kIsWeb) return 0;
    if (_isSyncing) {
      print('⏳ Sync already in progress, skipping...');
      return 0;
    }
    
    _isSyncing = true;
    
    try {
      final db = OfflineDatabase.instance;
      final pendingPulses = await db.getPendingPulses();
      
      if (pendingPulses.isEmpty) {
        print('✅ No pending pulses to sync');
        _isSyncing = false;
        return 0;
      }
      
      print('🔄 Syncing ${pendingPulses.length} pending pulses to Supabase...');

      final pulsesToSend = <Pulse>[];
      final pulseIds = <String>[];

      for (final row in pendingPulses) {
        final pulse = _pulseFromRow(row);
        if (pulse == null) {
          continue;
        }

        pulsesToSend.add(pulse);
        pulseIds.add((row['id'] ?? '').toString());
      }

      if (pulsesToSend.isEmpty) {
        print('⚠️ No valid pending pulses to sync');
        _isSyncing = false;
        return pendingPulses.length;
      }

      final sent = await PulseBackendClient.sendBulk(pulsesToSend);
      if (!sent) {
        print('❌ Backend sync failed, keeping ${pendingPulses.length} pulses offline');
        _isSyncing = false;
        return pendingPulses.length;
      }

      for (final id in pulseIds) {
        if (id.isEmpty) continue;
        await db.markPulseSynced(id);
      }

      print('✅ Synced ${pulseIds.length} pending pulses successfully');

      _isSyncing = false;
      return 0;
    } catch (e) {
      print('❌ Error in syncPendingPulses: $e');
      _isSyncing = false;
      return -1;
    }
  }

  static Pulse? _pulseFromRow(Map<String, dynamic> row) {
    final employeeId = (row['employee_id'] ?? '').toString();
    final timestampText = (row['timestamp'] ?? '').toString();

    if (employeeId.isEmpty || timestampText.isEmpty) {
      return null;
    }

    final timestamp = DateTime.tryParse(timestampText);
    if (timestamp == null) {
      return null;
    }

    final latitude = _toDouble(row['latitude']);
    final longitude = _toDouble(row['longitude']);
    if (latitude == null || longitude == null) {
      return null;
    }

    final isWithinGeofence = _toBool(row['inside_geofence']);
    final distance = _toDouble(row['distance_from_center']);

    return Pulse(
      employeeId: employeeId,
      branchId: row['branch_id']?.toString(),
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
      wifiBssid: row['wifi_bssid']?.toString(),
      isWithinGeofence: isWithinGeofence,
      distanceFromCenter: distance,
      isFake: false,
      isSynced: false,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String && value.isNotEmpty) {
      return double.tryParse(value);
    }
    return null;
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase();
      return normalized == '1' || normalized == 'true' || normalized == 'yes';
    }
    return false;
  }

  /// Clear all offline pulses (use with caution!)
  static Future<void> clearOfflineQueue() async {
    if (kIsWeb) return;
    
    try {
      // This would require a new method in OfflineDatabase
      print('⚠️ clearOfflineQueue not implemented for SQLite');
    } catch (e) {
      print('❌ Error clearing offline queue: $e');
    }
  }
}
