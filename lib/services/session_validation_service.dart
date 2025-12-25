import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/session_validation_request.dart';
import '../database/offline_database.dart';
import 'app_logger.dart';

/// Service for handling session validation requests
/// When employee has a gap in pulse tracking > 5.5 minutes
class SessionValidationService {
  static final SessionValidationService instance = SessionValidationService._();
  SessionValidationService._();

  final _supabase = Supabase.instance.client;

  /// Check for session gaps and create validation request if needed
  /// Returns true if validation request was created
  Future<bool> checkAndCreateSessionValidation({
    required String employeeId,
    required String attendanceId,
    required String branchId,
    required String managerId,
  }) async {
    try {
      AppLogger.instance.log('Checking for session gaps for employee: $employeeId', tag: 'SessionValidation');

      // 1. Get last pulse or check-in time from local/online
      final lastActivity = await _getLastActivityTime(employeeId, attendanceId);
      
      if (lastActivity == null) {
        AppLogger.instance.log('No last activity found - first pulse', tag: 'SessionValidation');
        return false;
      }

      final now = DateTime.now();
      final gapDuration = now.difference(lastActivity);
      final gapMinutes = gapDuration.inMinutes;

      AppLogger.instance.log('Gap duration: $gapMinutes minutes (${gapDuration.inSeconds}s)', tag: 'SessionValidation');

      // 2. Check if gap > 5.5 minutes (330 seconds)
      if (gapDuration.inSeconds <= 330) {
        AppLogger.instance.log('Gap is acceptable (<= 5.5 minutes)', tag: 'SessionValidation');
        return false;
      }

      // 3. Calculate expected pulses (every 5 minutes)
      final expectedPulses = (gapMinutes / 5).floor();

      AppLogger.instance.log('⚠️ Session gap detected! Duration: $gapMinutes min, Expected pulses: $expectedPulses', 
        level: AppLogger.warning, tag: 'SessionValidation');

      // 4. Create validation request
      final request = SessionValidationRequest(
        employeeId: employeeId,
        attendanceId: attendanceId,
        branchId: branchId,
        managerId: managerId,
        gapStartTime: lastActivity,
        gapEndTime: now,
        gapDurationMinutes: gapMinutes,
        expectedPulsesCount: expectedPulses,
        status: 'pending',
      );

      // 5. Save to Supabase
      try {
        final response = await _supabase
            .from('session_validation_requests')
            .insert(request.toJson())
            .select()
            .single();

        AppLogger.instance.log('✅ Session validation request created: ${response['id']}', tag: 'SessionValidation');
        return true;
      } catch (e) {
        AppLogger.instance.log('Failed to create session validation request', 
          level: AppLogger.error, tag: 'SessionValidation', error: e);
        return false;
      }
    } catch (e) {
      AppLogger.instance.log('Error in checkAndCreateSessionValidation', 
        level: AppLogger.error, tag: 'SessionValidation', error: e);
      return false;
    }
  }

  /// Get last activity time (pulse or check-in)
  Future<DateTime?> _getLastActivityTime(String employeeId, String attendanceId) async {
    DateTime? lastTime;

    // Check local pulses first (SQLite/Hive)
    try {
      final db = OfflineDatabase.instance;
      final localPulses = await db.getPendingPulses();
      
      if (localPulses.isNotEmpty) {
        // Filter by attendance_id and get latest
        final relevantPulses = localPulses
            .where((p) => p['attendance_id'] == attendanceId)
            .toList();
        
        if (relevantPulses.isNotEmpty) {
          relevantPulses.sort((a, b) {
            final aTime = _safeParseDateTime(a['timestamp']);
            final bTime = _safeParseDateTime(b['timestamp']);
            return bTime.compareTo(aTime); // Descending
          });
          
          lastTime = _safeParseDateTime(relevantPulses.first['timestamp']);
          AppLogger.instance.log('Found local pulse: $lastTime', tag: 'SessionValidation');
        }
      }
    } catch (e) {
      AppLogger.instance.log('Error checking local pulses', level: AppLogger.warning, tag: 'SessionValidation', error: e);
    }

    // Check online pulses if no local found or to get more recent
    try {
      final onlinePulses = await _supabase
          .from('location_pulses')
          .select('timestamp')
          .eq('attendance_id', attendanceId)
          .order('timestamp', ascending: false)
          .limit(1);

      if (onlinePulses.isNotEmpty) {
        final first = onlinePulses.first;
        DateTime onlineTime;
        if (first is Map) {
          onlineTime = _safeParseDateTime(first['timestamp']);
        } else if (first is String) {
          onlineTime = _safeParseDateTime(first);
        } else {
          // Unknown shape; skip
          throw 'Unexpected pulse row type: ${first.runtimeType}';
        }
        
        if (lastTime == null || onlineTime.isAfter(lastTime)) {
          lastTime = onlineTime;
          AppLogger.instance.log('Found online pulse: $lastTime', tag: 'SessionValidation');
        }
      }
    } catch (e) {
      AppLogger.instance.log('Error checking online pulses', level: AppLogger.warning, tag: 'SessionValidation', error: e);
    }

    // If still no pulse, use check-in time
    if (lastTime == null) {
      try {
        final attendance = await _supabase
            .from('attendance')
            .select('check_in_time')
            .eq('id', attendanceId)
            .single();

        lastTime = _safeParseDateTime(attendance['check_in_time']);
        AppLogger.instance.log('Using check-in time: $lastTime', tag: 'SessionValidation');
      } catch (e) {
        AppLogger.instance.log('Error getting check-in time', level: AppLogger.error, tag: 'SessionValidation', error: e);
      }
    }

    return lastTime;
  }

  /// Safely parse various timestamp shapes into DateTime
  DateTime _safeParseDateTime(dynamic value) {
    if (value is DateTime) return value.toLocal();
    if (value is int) {
      // Heuristic: treat as milliseconds since epoch if > 10^10; otherwise seconds
      final isMillis = value > 10000000000;
      final dt = isMillis
          ? DateTime.fromMillisecondsSinceEpoch(value)
          : DateTime.fromMillisecondsSinceEpoch(value * 1000);
      return dt.toLocal();
    }
    final s = value?.toString() ?? '';
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {
      // Fallback: now
      return DateTime.now();
    }
  }

  /// Approve session validation request
  /// Creates TRUE pulses for the gap period
  Future<bool> approveSessionValidation(String requestId, String managerNotes) async {
    try {
      AppLogger.instance.log('Approving session validation: $requestId', tag: 'SessionValidation');

      // 1. Get request details
      final request = await _supabase
          .from('session_validation_requests')
          .select()
          .eq('id', requestId)
          .single();

      final validationRequest = SessionValidationRequest.fromJson(request);

      // 2. Create TRUE pulses for the gap
      await _createPulsesForGap(
        validationRequest: validationRequest,
        insideGeofence: true,
      );

      // 3. Update request status
      await _supabase
          .from('session_validation_requests')
          .update({
            'status': 'approved',
            'manager_response_time': DateTime.now().toIso8601String(),
            'manager_notes': managerNotes,
          })
          .eq('id', requestId);

      // 4. Update attendance record with approved time
      await _supabase
          .from('attendance')
          .update({
            'check_in_time': validationRequest.gapStartTime.toIso8601String(),
          })
          .eq('id', validationRequest.attendanceId!);

      AppLogger.instance.log('✅ Session validation approved successfully', tag: 'SessionValidation');
      return true;
    } catch (e) {
      AppLogger.instance.log('Error approving session validation', 
        level: AppLogger.error, tag: 'SessionValidation', error: e);
      return false;
    }
  }

  /// Reject session validation request
  /// Creates FALSE pulses for the gap period
  Future<bool> rejectSessionValidation(String requestId, String managerNotes) async {
    try {
      AppLogger.instance.log('Rejecting session validation: $requestId', tag: 'SessionValidation');

      // 1. Get request details
      final request = await _supabase
          .from('session_validation_requests')
          .select()
          .eq('id', requestId)
          .single();

      final validationRequest = SessionValidationRequest.fromJson(request);

      // 2. Create FALSE pulses for the gap
      await _createPulsesForGap(
        validationRequest: validationRequest,
        insideGeofence: false,
      );

      // 3. Update request status
      await _supabase
          .from('session_validation_requests')
          .update({
            'status': 'rejected',
            'manager_response_time': DateTime.now().toIso8601String(),
            'manager_notes': managerNotes,
          })
          .eq('id', requestId);

      AppLogger.instance.log('✅ Session validation rejected successfully', tag: 'SessionValidation');
      return true;
    } catch (e) {
      AppLogger.instance.log('Error rejecting session validation', 
        level: AppLogger.error, tag: 'SessionValidation', error: e);
      return false;
    }
  }

  /// Create pulses for gap period
  Future<void> _createPulsesForGap({
    required SessionValidationRequest validationRequest,
    required bool insideGeofence,
  }) async {
    try {
      final pulses = <Map<String, dynamic>>[];
      final startTime = validationRequest.gapStartTime;
      final endTime = validationRequest.gapEndTime;

      // Create a pulse every 5 minutes
      DateTime currentTime = startTime.add(const Duration(minutes: 5));
      
      while (currentTime.isBefore(endTime)) {
        pulses.add({
          'employee_id': validationRequest.employeeId,
          'attendance_id': validationRequest.attendanceId,
          'branch_id': validationRequest.branchId,
          'timestamp': currentTime.toIso8601String(),
          'inside_geofence': insideGeofence,
          'is_within_geofence': insideGeofence,
          'distance_from_center': 0.0,
          'validated_by_wifi': false,
          'validated_by_location': false,
          'created_by_validation': true, // Mark as validation-generated
          'validation_request_id': validationRequest.id,
        });

        currentTime = currentTime.add(const Duration(minutes: 5));
      }

      if (pulses.isNotEmpty) {
        await _supabase.from('location_pulses').insert(pulses);
        AppLogger.instance.log('Created ${pulses.length} ${insideGeofence ? "TRUE" : "FALSE"} pulses', 
          tag: 'SessionValidation');
      }
    } catch (e) {
      AppLogger.instance.log('Error creating pulses for gap', 
        level: AppLogger.error, tag: 'SessionValidation', error: e);
    }
  }

  /// Get pending session validation requests for a manager
  Future<List<SessionValidationRequest>> getPendingRequestsForManager(String managerId) async {
    try {
      final response = await _supabase
          .from('session_validation_requests')
          .select()
          .eq('manager_id', managerId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      return response
          .map((json) => SessionValidationRequest.fromJson(json))
          .toList();
    } catch (e) {
      AppLogger.instance.log('Error getting pending requests', 
        level: AppLogger.error, tag: 'SessionValidation', error: e);
      return [];
    }
  }
}
