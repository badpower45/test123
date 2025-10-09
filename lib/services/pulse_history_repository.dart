import 'package:hive/hive.dart';

import '../models/pulse.dart';
import '../models/pulse_log_entry.dart';

class PulseHistoryRepository {
  PulseHistoryRepository._();

  static Future<int> recordPulse({
    required Pulse pulse,
    required bool wasOnline,
    required bool sentOnline,
    required bool queuedOffline,
  }) async {
    final box = await _historyBox();
    final status = sentOnline
        ? PulseDeliveryStatus.sentOnline
        : queuedOffline
            ? PulseDeliveryStatus.queuedOffline
            : PulseDeliveryStatus.failed;
    await box.add(
      PulseLogEntry(
        pulse: pulse,
        recordedAt: DateTime.now().toUtc(),
        wasOnline: wasOnline,
        deliveryStatus: status,
      ),
    );
    return box.length;
  }

  static Future<int> totalPulseCount() async {
    final box = await _historyBox();
    return box.length;
  }

  static Future<int> monthlyPulseCount(DateTime reference) async {
    final box = await _historyBox();
  final count = box.values
    .where((entry) {
      final localTimestamp = entry.recordedAt.toLocal();
      return localTimestamp.year == reference.year &&
        localTimestamp.month == reference.month;
    })
    .length;
    return count;
  }

  static Future<void> clearHistory() async {
    final box = await _historyBox();
    await box.clear();
  }

  static Future<Box<PulseLogEntry>> _historyBox() async {
    registerPulseAdapter();
    registerPulseLogEntryAdapter();
    if (Hive.isBoxOpen(pulseHistoryBox)) {
      return Hive.box<PulseLogEntry>(pulseHistoryBox);
    }
    return Hive.openBox<PulseLogEntry>(pulseHistoryBox);
  }
}
