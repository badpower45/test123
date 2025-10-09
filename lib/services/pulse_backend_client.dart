import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../constants/api_endpoints.dart';
import '../models/pulse.dart';

class PulseBackendClient {
  PulseBackendClient._();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized || !AppConfig.supabaseEnabled) {
      return;
    }
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      debug: false,
    );
    _initialized = true;
  }

  static Future<bool> sendPulse(Pulse pulse) async {
    final map = _mapPulse(pulse);
    if (AppConfig.supabaseEnabled) {
      final success = await _sendViaSupabase(map);
      if (success) {
        return true;
      }
    }
    return _sendViaHttp(ApiEndpoints.primaryHeartbeat, map);
  }

  static Future<bool> sendBulk(List<Pulse> pulses) async {
    final payload = pulses.map(_mapPulse).toList(growable: false);
    if (AppConfig.supabaseEnabled) {
      final success = await _sendBulkViaSupabase(payload);
      if (success) {
        return true;
      }
    }
    return _sendViaHttp(ApiEndpoints.primaryOfflineSync, {
      'pulses': payload,
    });
  }

  static Map<String, dynamic> _mapPulse(Pulse pulse) {
    final payload = pulse.toJson();
    payload['timestamp'] = pulse.timestamp.toUtc().toIso8601String();
    payload['createdAt'] = DateTime.now().toUtc().toIso8601String();
    return payload;
  }

  static Future<bool> _sendViaHttp(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _sendViaSupabase(Map<String, dynamic> map) async {
    try {
      final client = Supabase.instance.client;
      final response =
          await client.from(AppConfig.supabasePulseTable).insert(map);
      return response.error == null;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _sendBulkViaSupabase(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      return true;
    }
    try {
      final client = Supabase.instance.client;
      final response =
          await client.from(AppConfig.supabasePulseTable).insert(rows);
      return response.error == null;
    } catch (_) {
      return false;
    }
  }
}
