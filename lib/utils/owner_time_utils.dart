import 'package:intl/intl.dart';

class OwnerTimeUtils {
  static int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  static DateTime _lastWeekdayOfMonth(int year, int month, int weekday) {
    final lastDay = _daysInMonth(year, month);
    var date = DateTime.utc(year, month, lastDay);
    while (date.weekday != weekday) {
      date = date.subtract(const Duration(days: 1));
    }
    return date;
  }

  static int _cairoOffsetMinutesForUtc(DateTime utcDateTime) {
    final year = utcDateTime.year;
    final dstStartLocalDate = _lastWeekdayOfMonth(year, 4, DateTime.friday);
    final dstEndLocalDate = _lastWeekdayOfMonth(year, 10, DateTime.thursday);

    final dstStartUtc = DateTime.utc(
      dstStartLocalDate.year,
      dstStartLocalDate.month,
      dstStartLocalDate.day,
    ).subtract(const Duration(hours: 2));

    final dstEndUtc = DateTime.utc(
      dstEndLocalDate.year,
      dstEndLocalDate.month,
      dstEndLocalDate.day,
    ).subtract(const Duration(hours: 3));

    final inDst = !utcDateTime.isBefore(dstStartUtc) && utcDateTime.isBefore(dstEndUtc);
    return inDst ? 180 : 120;
  }

  static DateTime _toCairoDateTime(DateTime utcDateTime) {
    final utc = utcDateTime.toUtc();
    final offsetMinutes = _cairoOffsetMinutesForUtc(utc);
    return utc.add(Duration(minutes: offsetMinutes));
  }

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
      return _toCairoDateTime(parsed);
    } catch (_) {
      return null;
    }
  }

  static String _formatCairoTime(DateTime cairoDateTime, {bool useAmPm = false}) {
    final hour = cairoDateTime.hour;
    final minute = cairoDateTime.minute.toString().padLeft(2, '0');

    if (!useAmPm) {
      return '${hour.toString().padLeft(2, '0')}:$minute';
    }

    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final period = hour >= 12 ? 'PM' : 'AM';
    return '${displayHour.toString().padLeft(2, '0')}:$minute $period';
  }

  static String formatTimeShort(
    String? value, {
    String fallback = '-',
    bool useAmPm = false,
  }) {
    if (value == null || value.trim().isEmpty) return fallback;

    final raw = value.trim();
    final timeOnlyMatch = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(raw);
    if (timeOnlyMatch != null) {
      final hour = (int.tryParse(timeOnlyMatch.group(1) ?? '') ?? 0)
          .clamp(0, 23)
          .toInt();
      final minute = (int.tryParse(timeOnlyMatch.group(2) ?? '') ?? 0)
          .clamp(0, 59)
          .toInt();

      final cairoTime = DateTime(2000, 1, 1, hour, minute);
      return _formatCairoTime(cairoTime, useAmPm: useAmPm);
    }

    final shifted = _parseShifted(raw);
    if (shifted == null) return fallback;
    return _formatCairoTime(shifted, useAmPm: useAmPm);
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

  static String formatTimeFromDateTime(
    DateTime? value, {
    String fallback = '--:--',
    bool useAmPm = false,
  }) {
    if (value == null) return fallback;
    return _formatCairoTime(_toCairoDateTime(value), useAmPm: useAmPm);
  }

  static String formatDateTimeFromDateTime(
    DateTime? value, {
    String fallback = '-',
  }) {
    if (value == null) return fallback;
    final cairo = _toCairoDateTime(value);
    return DateFormat('dd/MM/yyyy HH:mm').format(cairo);
  }
}