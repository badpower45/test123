import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized logging service for debugging and monitoring
class AppLogger {
  static final AppLogger instance = AppLogger._();
  AppLogger._();

  static const int _maxLogs = 100; // Keep last 100 logs
  final List<LogEntry> _logs = [];

  /// Log levels
  static const String info = 'INFO';
  static const String warning = 'WARNING';
  static const String error = 'ERROR';
  static const String debug = 'DEBUG';

  /// Log a message with context
  void log(String message, {
    String level = info,
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag ?? 'App',
      message: message,
      error: error,
      stackTrace: stackTrace,
    );

    _logs.add(entry);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }

    // Print to console in debug mode
    if (kDebugMode) {
      final emoji = _getEmojiForLevel(level);
      final tagStr = tag != null ? '[$tag] ' : '';
      print('$emoji ${entry.timestamp.toString().substring(11, 19)} $tagStr$message');
      if (error != null) {
        print('   Error: $error');
      }
      if (stackTrace != null && level == AppLogger.error) {
        print('   Stack: ${stackTrace.toString().split('\n').take(3).join('\n   ')}');
      }
    }

    // Save critical errors to persistent storage
    if (level == error) {
      _saveErrorLog(entry);
    }
  }

  String _getEmojiForLevel(String level) {
    switch (level) {
      case info:
        return 'ℹ️';
      case warning:
        return '⚠️';
      case error:
        return '❌';
      case debug:
        return '🔍';
      default:
        return '📝';
    }
  }

  /// Get all logs
  List<LogEntry> getLogs({String? level, String? tag}) {
    var filtered = _logs;
    if (level != null) {
      filtered = filtered.where((log) => log.level == level).toList();
    }
    if (tag != null) {
      filtered = filtered.where((log) => log.tag == tag).toList();
    }
    return filtered;
  }

  /// Get logs as formatted string
  String getLogsAsString({String? level, String? tag}) {
    final logs = getLogs(level: level, tag: tag);
    return logs.map((log) => log.toString()).join('\n');
  }

  /// Clear all logs
  void clearLogs() {
    _logs.clear();
  }

  /// Save error to persistent storage
  Future<void> _saveErrorLog(LogEntry entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final errors = prefs.getStringList('error_logs') ?? [];
      errors.add('${entry.timestamp.toIso8601String()}|${entry.tag}|${entry.message}');
      
      // Keep only last 50 errors
      if (errors.length > 50) {
        errors.removeAt(0);
      }
      
      await prefs.setStringList('error_logs', errors);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to save error log: $e');
      }
    }
  }

  /// Get saved error logs
  Future<List<String>> getSavedErrors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList('error_logs') ?? [];
    } catch (e) {
      return [];
    }
  }

  /// Clear saved errors
  Future<void> clearSavedErrors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('error_logs');
    } catch (e) {
      if (kDebugMode) {
        print('Failed to clear error logs: $e');
      }
    }
  }

  /// Get all logs as a list of maps (for UI display)
  List<Map<String, dynamic>> getLogsAsMap() {
    return _logs.map((entry) => entry.toMap()).toList();
  }
}

/// Log entry data class
class LogEntry {
  final DateTime timestamp;
  final String level;
  final String tag;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  @override
  String toString() {
    final timeStr = timestamp.toString().substring(11, 19);
    final errorStr = error != null ? ' | Error: $error' : '';
    return '[$level] $timeStr [$tag] $message$errorStr';
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp,
      'level': level,
      'tag': tag,
      'message': message,
      'error': error,
    };
  }
}
