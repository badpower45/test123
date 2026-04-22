import 'package:intl/intl.dart';

/// Centralized time formatting utilities for local-time display.
/// Backend timestamps are stored in UTC (ISO8601, often with a trailing 'Z').
/// We convert to device local time to correctly handle DST and timezone rules.
class TimeUtils {
  static String _normalizeIso(String value) {
    var normalized = value.trim();

    // Support Postgres format like: 2026-04-16 05:47:35.184+00
    if (RegExp(r'^\d{4}-\d{2}-\d{2}\s').hasMatch(normalized)) {
      normalized = normalized.replaceFirst(' ', 'T');
    }

    // Support offsets like +00 or -03 by expanding to +00:00 / -03:00
    normalized = normalized.replaceFirstMapped(
      RegExp(r'([+-]\d{2})$'),
      (m) => '${m[1]}:00',
    );

    // Support offsets like +0200 / -0300 by converting to +02:00 / -03:00
    normalized = normalized.replaceFirstMapped(
      RegExp(r'([+-]\d{2})(\d{2})$'),
      (m) => '${m[1]}:${m[2]}',
    );

    return normalized;
  }

  static DateTime? _parseLocal(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      final dt = DateTime.parse(_normalizeIso(iso));
      return dt.toLocal();
    } catch (_) {
      return null;
    }
  }

  static String formatTimeShort(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '-';

    final raw = iso.trim();
    final timeOnlyMatch = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(raw);
    if (timeOnlyMatch != null) {
      final hour = timeOnlyMatch.group(1)!.padLeft(2, '0');
      final minute = timeOnlyMatch.group(2)!;
      return '$hour:$minute';
    }

    final local = _parseLocal(iso);
    if (local == null) return '-';
    return DateFormat('HH:mm').format(local);
  }

  static String formatDate(String? iso) {
    final local = _parseLocal(iso);
    if (local == null) return '-';
    return DateFormat('dd/MM').format(local);
  }

  static String formatDateTime(String? iso) {
    final local = _parseLocal(iso);
    if (local == null) return iso ?? '-';
    return DateFormat('dd/MM HH:mm').format(local);
  }
}