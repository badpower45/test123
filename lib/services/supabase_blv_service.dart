import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/blv_validation_event.dart';

/// Supabase BLV Service
/// Handles fetching BLV validation history and related data
class SupabaseBLVService {
  static final SupabaseClient _supabase = SupabaseConfig.client;

  /// Get validation history for an employee
  /// Combines data from both pulses and blv_validation_logs tables
  static Future<List<BLVValidationEvent>> getValidationHistory({
    required String employeeId,
    int limit = 100,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final List<BLVValidationEvent> events = [];

      // Fetch from pulses table
      final pulses = await _getPulsesHistory(
        employeeId: employeeId,
        limit: limit,
        startDate: startDate,
        endDate: endDate,
      );
      events.addAll(pulses);

      // Fetch from blv_validation_logs table
      final validationLogs = await _getValidationLogs(
        employeeId: employeeId,
        limit: limit,
        startDate: startDate,
        endDate: endDate,
      );
      events.addAll(validationLogs);

      // Sort by timestamp (newest first)
      events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Limit total results
      if (events.length > limit) {
        return events.sublist(0, limit);
      }

      return events;
    } catch (e) {
      print('Get validation history error: $e');
      return [];
    }
  }

  /// Get pulses history
  static Future<List<BLVValidationEvent>> _getPulsesHistory({
    required String employeeId,
    required int limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _supabase
          .from('pulses')
          .select(
            'id, employee_id, timestamp, status, presence_score, trust_score, '
            'verification_method, branch_id',
          )
          .eq('employee_id', employeeId);

      if (startDate != null) {
        query = query.gte('timestamp', startDate.toUtc().toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('timestamp', endDate.toUtc().toIso8601String());
      }

      final response = await query
          .order('timestamp', ascending: false)
          .limit(limit);

      final List<dynamic> data = response as List;
      return data.map((json) => BLVValidationEvent.fromPulse(json)).toList();
    } catch (e) {
      print('Get pulses history error: $e');
      return [];
    }
  }

  /// Get validation logs history
  static Future<List<BLVValidationEvent>> _getValidationLogs({
    required String employeeId,
    required int limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _supabase
          .from('blv_validation_logs')
          .select(
            'id, employee_id, branch_id, validation_type, '
            'wifi_score, gps_score, cell_score, sound_score, motion_score, '
            'bluetooth_score, light_score, battery_score, total_score, '
            'is_approved, created_at',
          )
          .eq('employee_id', employeeId);

      if (startDate != null) {
        query = query.gte('created_at', startDate.toUtc().toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('created_at', endDate.toUtc().toIso8601String());
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(limit);

      final List<dynamic> data = response as List;
      return data.map((json) => BLVValidationEvent.fromValidationLog(json)).toList();
    } catch (e) {
      print('Get validation logs error: $e');
      return [];
    }
  }

  /// Get latest validation event for employee
  static Future<BLVValidationEvent?> getLatestValidation({
    required String employeeId,
  }) async {
    try {
      final history = await getValidationHistory(
        employeeId: employeeId,
        limit: 1,
      );

      return history.isNotEmpty ? history.first : null;
    } catch (e) {
      print('Get latest validation error: $e');
      return null;
    }
  }

  /// Get validation statistics for employee
  static Future<Map<String, dynamic>> getValidationStats({
    required String employeeId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final history = await getValidationHistory(
        employeeId: employeeId,
        limit: 1000,
        startDate: startDate,
        endDate: endDate,
      );

      final total = history.length;
      final approved = history.where((e) =>
        e.isApproved == true || e.status == 'IN'
      ).length;
      final rejected = history.where((e) =>
        e.isApproved == false || e.status == 'REJECTED'
      ).length;
      final suspicious = history.where((e) =>
        e.status == 'SUSPECT' || e.status == 'REVIEW_REQUIRED'
      ).length;

      // Calculate average score
      final scoresWithValues = history
          .where((e) => e.scorePercentage != null)
          .map((e) => e.scorePercentage!)
          .toList();

      final averageScore = scoresWithValues.isNotEmpty
          ? scoresWithValues.reduce((a, b) => a + b) / scoresWithValues.length
          : 0.0;

      return {
        'total': total,
        'approved': approved,
        'rejected': rejected,
        'suspicious': suspicious,
        'average_score': averageScore.round(),
        'approval_rate': total > 0 ? (approved / total * 100).round() : 0,
      };
    } catch (e) {
      print('Get validation stats error: $e');
      return {
        'total': 0,
        'approved': 0,
        'rejected': 0,
        'suspicious': 0,
        'average_score': 0,
        'approval_rate': 0,
      };
    }
  }

  /// Get validation events for today
  static Future<List<BLVValidationEvent>> getTodayValidations({
    required String employeeId,
  }) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return getValidationHistory(
      employeeId: employeeId,
      startDate: startOfDay,
      endDate: endOfDay,
      limit: 200,
    );
  }

  /// Get validation events for current week
  static Future<List<BLVValidationEvent>> getWeekValidations({
    required String employeeId,
  }) async {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfWeekDay = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    return getValidationHistory(
      employeeId: employeeId,
      startDate: startOfWeekDay,
      limit: 500,
    );
  }

  /// Get validation events for current month
  static Future<List<BLVValidationEvent>> getMonthValidations({
    required String employeeId,
  }) async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);

    return getValidationHistory(
      employeeId: employeeId,
      startDate: startOfMonth,
      limit: 1000,
    );
  }

  /// Subscribe to real-time validation updates
  static RealtimeChannel subscribeToValidations({
    required String employeeId,
    required Function(BLVValidationEvent) onValidation,
  }) {
    final channel = _supabase.channel('validation_updates_$employeeId');

    // Subscribe to pulses table
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'pulses',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'employee_id',
        value: employeeId,
      ),
      callback: (payload) {
        final event = BLVValidationEvent.fromPulse(payload.newRecord);
        onValidation(event);
      },
    );

    // Subscribe to blv_validation_logs table
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'blv_validation_logs',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'employee_id',
        value: employeeId,
      ),
      callback: (payload) {
        final event = BLVValidationEvent.fromValidationLog(payload.newRecord);
        onValidation(event);
      },
    );

    channel.subscribe();
    return channel;
  }

  /// Unsubscribe from real-time updates
  static Future<void> unsubscribeFromValidations(RealtimeChannel channel) async {
    await _supabase.removeChannel(channel);
  }
}
