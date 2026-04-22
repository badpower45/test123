import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../database/offline_database.dart';

class PulseDeduplicationService {
  PulseDeduplicationService._();

  static const Duration duplicateWindow = Duration(seconds: 90);

  static Future<bool> shouldSkipPulse({
    required String employeeId,
    String? attendanceId,
    required DateTime timestamp,
  }) async {
    final utcTimestamp = timestamp.toUtc();

    try {
      final prefs = await SharedPreferences.getInstance();
      if (_hasRecentMarker(prefs, _employeeKey(employeeId), utcTimestamp)) {
        return true;
      }
      if (_hasRecentMarker(
        prefs,
        _attendanceKey(employeeId, attendanceId),
        utcTimestamp,
      )) {
        return true;
      }
    } catch (_) {}

    if (!kIsWeb) {
      try {
        return await OfflineDatabase.instance.hasRecentPulse(
          employeeId: employeeId,
          timestamp: utcTimestamp,
          withinSeconds: duplicateWindow.inSeconds,
        );
      } catch (_) {}
    }

    return false;
  }

  static Future<void> markPulseRecorded({
    required String employeeId,
    String? attendanceId,
    required DateTime timestamp,
    String? source,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final utcTimestamp = timestamp.toUtc();
    final isoTimestamp = utcTimestamp.toIso8601String();

    await prefs.setString('last_pulse_time', isoTimestamp);
    await prefs.setInt(
      'last_pulse_timestamp',
      utcTimestamp.millisecondsSinceEpoch,
    );
    await _writeMarker(prefs, _employeeKey(employeeId), isoTimestamp, source);
    await _writeMarker(
      prefs,
      _attendanceKey(employeeId, attendanceId),
      isoTimestamp,
      source,
    );
  }

  static bool _hasRecentMarker(
    SharedPreferences prefs,
    String key,
    DateTime timestamp,
  ) {
    final rawValue = prefs.getString('${key}_timestamp');
    if (rawValue == null || rawValue.isEmpty) {
      return false;
    }

    final recordedAt = DateTime.tryParse(rawValue)?.toUtc();
    if (recordedAt == null) {
      return false;
    }

    final diff = recordedAt.difference(timestamp).abs();
    return diff <= duplicateWindow;
  }

  static Future<void> _writeMarker(
    SharedPreferences prefs,
    String key,
    String isoTimestamp,
    String? source,
  ) async {
    await prefs.setString('${key}_timestamp', isoTimestamp);
    if (source != null && source.isNotEmpty) {
      await prefs.setString('${key}_source', source);
    }
  }

  static String _employeeKey(String employeeId) =>
      'pulse_dedupe_employee_$employeeId';

  static String _attendanceKey(String employeeId, String? attendanceId) =>
      'pulse_dedupe_attendance_${employeeId}_${attendanceId ?? "none"}';
}
