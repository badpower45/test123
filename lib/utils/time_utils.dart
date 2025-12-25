import 'package:intl/intl.dart';

/// Centralized time formatting utilities for Cairo timezone display.
/// Backend timestamps are stored in UTC (ISO8601, often with a trailing 'Z').
/// We convert explicitly to Cairo (UTC+2, ignoring DST for now) for consistent UI.
class TimeUtils {
  static DateTime? _parseUtc(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      final dt = DateTime.parse(iso);
      // Ensure we treat timestamp as UTC regardless of parse result
      final utc = dt.isUtc ? dt : dt.toUtc();
      // Cairo is UTC+2 (no automatic DST handling here)
      return utc.add(const Duration(hours: 2));
    } catch (_) {
      return null;
    }
  }

  static String formatTimeShort(String? iso) {
    final cairo = _parseUtc(iso);
    if (cairo == null) return '-';
    return DateFormat('HH:mm').format(cairo);
  }

  static String formatDate(String? iso) {
    final cairo = _parseUtc(iso);
    if (cairo == null) return '-';
    return DateFormat('dd/MM').format(cairo);
  }

  static String formatDateTime(String? iso) {
    final cairo = _parseUtc(iso);
    if (cairo == null) return iso ?? '-';
    return DateFormat('dd/MM HH:mm').format(cairo);
  }
}