import '../models/pulse.dart';
import 'supabase_function_client.dart';

typedef PulseSender = Future<bool> Function(Pulse pulse);
typedef PulseBulkSender = Future<bool> Function(List<Pulse> pulses);

class PulseBackendClient {
  PulseBackendClient._();

  static PulseSender? _singleOverride;
  static PulseBulkSender? _bulkOverride;

  static void setTestingOverrides({
    PulseSender? singleSender,
    PulseBulkSender? bulkSender,
  }) {
    _singleOverride = singleSender;
    _bulkOverride = bulkSender;
  }

  static void resetTestingOverrides() {
    _singleOverride = null;
    _bulkOverride = null;
  }

  static Future<void> initialize() async {
    // No initialization required for the REST backend.
  }

  static Future<bool> sendPulse(Pulse pulse) async {
    if (_singleOverride != null) {
      return _singleOverride!(pulse);
    }
    return sendBulk([pulse]);
  }

  static Future<bool> sendBulk(List<Pulse> pulses) async {
    if (pulses.isEmpty) {
      return true;
    }
    if (_bulkOverride != null) {
      return _bulkOverride!(pulses);
    }
    try {
      final payload = pulses.map((pulse) => pulse.toApiPayload()).toList();
      final response = await SupabaseFunctionClient.post('sync-pulses', {
        'pulses': payload,
      });
      final failedCount = ((response ?? {})['failed'] ?? 0) as int;
      return failedCount == 0;
    } catch (_) {
      return false;
    }
  }
}
