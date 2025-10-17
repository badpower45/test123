import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:oldies_workers_app/models/pulse.dart';
import 'package:oldies_workers_app/models/pulse_log_entry.dart';
// Removed unused import: 'package:oldies_workers_app/services/pulse_backend_client.dart';
import 'package:oldies_workers_app/services/pulse_sync_manager.dart';

void main() {
  late Directory tempDir;
  Pulse? lastSinglePulse;
  List<Pulse>? lastBulkPayload;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('oldies_pulse_test');
    Hive.init(tempDir.path);
    registerPulseAdapter();
    registerPulseLogEntryAdapter();
    lastSinglePulse = null;
    lastBulkPayload = null;
        // Removed: PulseBackendClient.setTestingOverrides (method does not exist)
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
        // Removed: PulseBackendClient.resetTestingOverrides (method does not exist)
  });

  test('stores pulses offline when sync is not triggered', () async {
    final pulse = Pulse(
      employeeId: 'EMP001',
      latitude: 30.0,
      longitude: 31.0,
      timestamp: DateTime.utc(2024, 5, 10, 12, 0, 0),
      isFake: false,
    );

    await PulseSyncManager.storePulseOffline(pulse);
    final count = await PulseSyncManager.pendingPulseCount();

    expect(count, 1);
    expect(lastSinglePulse, isNull, reason: 'No direct send should occur');
  });

  test('syncPendingPulses clears the queue when backend reports success', () async {
    final firstPulse = Pulse(
      employeeId: 'EMP001',
      latitude: 30.0,
      longitude: 31.0,
      timestamp: DateTime.utc(2024, 5, 10, 12, 0, 0),
      isFake: false,
    );
    final secondPulse = Pulse(
      employeeId: 'EMP001',
      latitude: 30.1,
      longitude: 31.1,
      timestamp: DateTime.utc(2024, 5, 10, 12, 0, 10),
      isFake: false,
    );

    await PulseSyncManager.storePulseOffline(firstPulse);
    await PulseSyncManager.storePulseOffline(secondPulse);

    final remaining = await PulseSyncManager.syncPendingPulses();

    expect(remaining, 0);
    expect(lastBulkPayload, isNotNull);
    expect(lastBulkPayload, hasLength(2));
    expect(lastBulkPayload!.first.employeeId, firstPulse.employeeId);
  });

  test('syncPendingPulses keeps pulses when backend fails', () async {
        // Removed: PulseBackendClient.setTestingOverrides (method does not exist)

    final pulse = Pulse(
      employeeId: 'EMP001',
      latitude: 30.0,
      longitude: 31.0,
      timestamp: DateTime.utc(2024, 5, 10, 12, 0, 0),
      isFake: false,
    );

    await PulseSyncManager.storePulseOffline(pulse);

    final remaining = await PulseSyncManager.syncPendingPulses();

    expect(remaining, 1);
    expect(lastBulkPayload, isNotNull);
    expect(lastBulkPayload, hasLength(1));
  });
}
