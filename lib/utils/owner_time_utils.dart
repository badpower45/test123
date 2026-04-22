import 'package:intl/intl.dart';

class OwnerTimeUtils {
  static String _normalizeIso(String value) {
    var normalized = value.trim();

    if (RegExp(r'^\d{4}-\d{2}-\d{2}\s').hasMatch(normalized)) {
      normalized = normalized.replaceFirst(' ', 'T');
    }

    normalized = normalized.replaceFirstMapped(
      RegExp(r'([+-]\d{2})$'),
      (m) => '${m[1]}:00',
    );

    normalized = normalized.replaceFirstMapped(
      RegExp(r'([+-]\d{2})(\d{2})$'),
      (m) => '${m[1]}:${m[2]}',
    );

    return normalized;
  }

  static DateTime? _parseShifted(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final parsed = DateTime.parse(_normalizeIso(value));
      return parsed.toLocal();
    } catch (_) {
      return null;
    }
  }

  static String formatTimeShort(String? value, {String fallback = '-'}) {
    if (value == null || value.trim().isEmpty) return fallback;

    final raw = value.trim();
    final timeOnlyMatch = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(raw);
    if (timeOnlyMatch != null) {
      final hour = (int.tryParse(timeOnlyMatch.group(1) ?? '') ?? 0)
          .clamp(0, 23)
          .toString()
          .padLeft(2, '0');
      final minute = (int.tryParse(timeOnlyMatch.group(2) ?? '') ?? 0)
          .clamp(0, 59)
          .toString()
          .padLeft(2, '0');
      return '$hour:$minute';
    }

    final shifted = _parseShifted(raw);
    if (shifted == null) return fallback;
    return DateFormat('HH:mm').format(shifted);
  }

  static String formatDate(String? value, {String fallback = '-'}) {
    final shifted = _parseShifted(value);
    if (shifted == null) return fallback;
    return DateFormat('dd/MM/yyyy').format(shifted);
  }

  static String formatDateTime(String? value, {String fallback = '-'}) {
    final shifted = _parseShifted(value);
    if (shifted == null) return fallback;
    return DateFormat('dd/MM/yyyy HH:mm').format(shifted);
  }

  static String formatTimeFromDateTime(DateTime? value, {String fallback = '--:--'}) {
    if (value == null) return fallback;
    return DateFormat('HH:mm').format(value.toLocal());
  }

  static String formatDateTimeFromDateTime(DateTime? value, {String fallback = '-'}) {
    if (value == null) return fallback;
    return DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());
  }
}