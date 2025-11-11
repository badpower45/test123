import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Fraud Alert Model
class FraudAlert {
  FraudAlert({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    this.branchId,
    required this.alertType,
    required this.severity,
    this.totalScore,
    required this.details,
    required this.createdAt,
    this.resolvedAt,
    this.resolvedBy,
    this.resolutionNotes,
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final String? branchId;
  final String alertType; // 'LOW_SCORE', 'REJECTED', 'SUSPICIOUS_PATTERN'
  final double severity; // 0.0 to 1.0
  final int? totalScore;
  final Map<String, dynamic> details;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? resolutionNotes;

  bool get isResolved => resolvedAt != null;

  String get severityText {
    if (severity > 0.8) return 'Critical';
    if (severity > 0.5) return 'Warning';
    return 'Info';
  }

  String get alertTypeDisplay {
    switch (alertType) {
      case 'LOW_SCORE':
        return 'Low BLV Score';
      case 'REJECTED':
        return 'Validation Rejected';
      case 'SUSPICIOUS_PATTERN':
        return 'Suspicious Pattern';
      default:
        return alertType;
    }
  }

  factory FraudAlert.fromJson(Map<String, dynamic> json) {
    return FraudAlert(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      employeeName: json['employee_name'] as String? ?? 'Unknown',
      branchId: json['branch_id'] as String?,
      alertType: json['alert_type'] as String,
      severity: (json['severity'] as num).toDouble(),
      totalScore: json['total_score'] as int?,
      details: json['details'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      resolvedBy: json['resolved_by'] as String?,
      resolutionNotes: json['resolution_notes'] as String?,
    );
  }
}

/// Supabase Fraud Alerts Service
class SupabaseFraudAlertsService {
  static final SupabaseClient _supabase = SupabaseConfig.client;

  /// Get unresolved fraud alerts for a branch
  static Future<List<FraudAlert>> getUnresolvedAlerts({
    required String branchId,
  }) async {
    try {
      final response = await _supabase
          .rpc('get_unresolved_fraud_alerts', params: {'p_branch_id': branchId});

      final List<dynamic> data = response as List;
      return data.map((json) => FraudAlert.fromJson(json)).toList();
    } catch (e) {
      print('Get unresolved fraud alerts error: $e');
      return [];
    }
  }

  /// Get all fraud alerts (resolved and unresolved)
  static Future<List<FraudAlert>> getAllAlerts({
    required String branchId,
    int limit = 100,
  }) async {
    try {
      final response = await _supabase
          .from('fraud_alerts')
          .select('''
            id,
            employee_id,
            branch_id,
            alert_type,
            severity,
            total_score,
            details,
            created_at,
            resolved_at,
            resolved_by,
            resolution_notes,
            employees!inner(full_name)
          ''')
          .eq('branch_id', branchId)
          .order('created_at', ascending: false)
          .limit(limit);

      final List<dynamic> data = response as List;
      return data.map((json) {
        return FraudAlert.fromJson({
          ...json,
          'employee_name': json['employees']['full_name'],
        });
      }).toList();
    } catch (e) {
      print('Get all fraud alerts error: $e');
      return [];
    }
  }

  /// Resolve a fraud alert
  static Future<bool> resolveAlert({
    required String alertId,
    required String resolvedBy,
    String? notes,
  }) async {
    try {
      final response = await _supabase.rpc('resolve_fraud_alert', params: {
        'p_alert_id': alertId,
        'p_resolved_by': resolvedBy,
        'p_notes': notes,
      });

      return response as bool? ?? false;
    } catch (e) {
      print('Resolve fraud alert error: $e');
      return false;
    }
  }

  /// Get fraud statistics
  static Future<Map<String, dynamic>> getFraudStats({
    required String branchId,
    DateTime? startDate,
  }) async {
    try {
      final response = await _supabase.rpc('get_fraud_stats', params: {
        'p_branch_id': branchId,
        if (startDate != null) 'p_start_date': startDate.toIso8601String(),
      });

      if (response is List && response.isNotEmpty) {
        return response.first as Map<String, dynamic>;
      }

      return {
        'total_alerts': 0,
        'critical_alerts': 0,
        'resolved_alerts': 0,
        'pending_alerts': 0,
        'avg_response_time': null,
      };
    } catch (e) {
      print('Get fraud stats error: $e');
      return {
        'total_alerts': 0,
        'critical_alerts': 0,
        'resolved_alerts': 0,
        'pending_alerts': 0,
        'avg_response_time': null,
      };
    }
  }

  /// Subscribe to real-time fraud alerts
  static RealtimeChannel subscribeToFraudAlerts({
    required String branchId,
    required Function(FraudAlert) onAlert,
  }) {
    final channel = _supabase.channel('fraud_alerts_$branchId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'fraud_alerts',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'branch_id',
        value: branchId,
      ),
      callback: (payload) async {
        // Fetch employee name for the alert
        final employeeId = payload.newRecord['employee_id'] as String;
        final employeeResponse = await _supabase
            .from('employees')
            .select('full_name')
            .eq('id', employeeId)
            .single();

        final alert = FraudAlert.fromJson({
          ...payload.newRecord,
          'employee_name': employeeResponse['full_name'],
        });

        onAlert(alert);
      },
    );

    channel.subscribe();
    return channel;
  }

  /// Unsubscribe from fraud alerts
  static Future<void> unsubscribeFromFraudAlerts(RealtimeChannel channel) async {
    await _supabase.removeChannel(channel);
  }
}
