import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';

import '../models/pulse.dart';
import 'pulse_backend_client.dart';

class PulseSyncManager {
  PulseSyncManager._();

  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static bool _isInitialized = false;

  static Future<void> initializeForMainIsolate() async {
    if (_isInitialized) {
      return;
    }
    registerPulseAdapter();
    await syncPendingPulses();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) async {
      final hasConnection =
          results.any((status) => status != ConnectivityResult.none);
      if (hasConnection) {
        await syncPendingPulses();
      }
    });
    _isInitialized = true;
  }

  static Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _isInitialized = false;
  }

  static Future<void> storePulseOffline(Pulse pulse) async {
    registerPulseAdapter();
    final box = await Hive.openBox<Pulse>(offlinePulsesBox);
    await box.add(pulse);
    await box.close();
  }

  static Future<int> pendingPulseCount() async {
    registerPulseAdapter();
    final box = await Hive.openBox<Pulse>(offlinePulsesBox);
    final count = box.length;
    await box.close();
    return count;
  }

  static Future<int> syncPendingPulses() async {
    registerPulseAdapter();
    final box = await Hive.openBox<Pulse>(offlinePulsesBox);
    if (box.isEmpty) {
      await box.close();
      return 0;
    }
    final pulses = box.values.toList(growable: false);
    try {
      final success = await PulseBackendClient.sendBulk(pulses);
      if (success) {
        await box.clear();
      }
    } catch (_) {
      // Leave items in the box to retry on the next connectivity update.
    }
    final remaining = box.length;
    await box.close();
    return remaining;
  }

  static Future<void> clearOfflineQueue() async {
    registerPulseAdapter();
    final box = await Hive.openBox<Pulse>(offlinePulsesBox);
    await box.clear();
    await box.close();
  }
}
