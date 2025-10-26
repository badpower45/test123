import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_endpoints.dart';
import '../models/pulse.dart';

class PulseBackendClient {
  PulseBackendClient._();

  static Future<void> initialize() async {
    // No initialization required for the REST backend.
  }

  static Future<bool> sendPulse(Pulse pulse) async {
    try {
      final response = await http.post(
        Uri.parse(pulseEndpoint),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(pulse.toApiPayload()),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> sendBulk(List<Pulse> pulses) async {
    if (pulses.isEmpty) {
      return true;
    }
    var allSent = true;
    for (final pulse in pulses) {
      final sent = await sendPulse(pulse);
      if (!sent) {
        allSent = false;
      }
    }
    return allSent;
  }
}
