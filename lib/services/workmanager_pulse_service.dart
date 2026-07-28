import '../database/offline_database.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/wifi_service.dart';
import 'notification_service.dart';
import 'pulse_deduplication_service.dart';
import 'supabase_attendance_service.dart';
import 'attendance_timer_service.dart';
import '../config/supabase_config.dart';

/// Background Pulse Service using WorkManager
/// Sends location pulses every 5 minutes even when app is closed
/// ✅ V2: Enhanced for old devices (Realme 6, Galaxy A12, etc.)
class WorkManagerPulseService {
  static const String _pulseTaskName = 'pulseTask';
  static const String _androidUniqueTaskName = 'com.oldies.pulse';
  static const String _iosUniqueTaskName =
      'com.oldies.attendance.full.pulse.periodic';
  static const String _oneOffTaskName = 'com.oldies.pulse.oneoff';

  static String get periodicUniqueTaskName {
    if (kIsWeb) {
      return _androidUniqueTaskName;
    }
    return Platform.isIOS ? _iosUniqueTaskName : _androidUniqueTaskName;
  }

  static final WorkManagerPulseService instance = WorkManagerPulseService._();
  WorkManagerPulseService._();

  /// Initialize WorkManager and register callback
  static Future<void> initialize() async {
    await Workmanager().initialize(
      _callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
    print('✅ WorkManager initialized for background pulses');
  }

  /// Start periodic pulse tracking (every 5 minutes)
  /// ✅ V2: Uses multiple strategies for reliability on old devices
  Future<void> startPeriodicPulses({
    required String employeeId,
    required String attendanceId,
    required String branchId,
  }) async {
    try {
      // Save employee data to SharedPreferences for background access
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_employee_id', employeeId);
      await prefs.setString('active_attendance_id', attendanceId);
      await prefs.setString('active_branch_id', branchId);
      await prefs.setInt(
        'pulse_start_time',
        DateTime.now().millisecondsSinceEpoch,
      );

      // ✅ V2: Register periodic task (runs every 15 minutes - minimum allowed by Android)
      await Workmanager().registerPeriodicTask(
        periodicUniqueTaskName,
        _pulseTaskName,
        frequency: const Duration(minutes: 15), // Minimum allowed
        constraints: Constraints(
          networkType: NetworkType.notRequired, // Work offline too
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 1), // ✅ V2: Faster retry
        inputData: {
          'employeeId': employeeId,
          'attendanceId': attendanceId,
          'branchId': branchId,
        },
      );

      // ✅ V2: Also schedule a one-off task for immediate pulse
      // This helps on devices that delay the first periodic task
      await _scheduleImmediatePulse(employeeId, attendanceId, branchId);

      print('✅ Started background pulse tracking for employee: $employeeId');
    } catch (e) {
      print('❌ Error starting background pulses: $e');
    }
  }

  /// ✅ V2: Schedule an immediate one-off pulse task
  Future<void> _scheduleImmediatePulse(
    String employeeId,
    String attendanceId,
    String branchId,
  ) async {
    try {
      await Workmanager().registerOneOffTask(
        '$_oneOffTaskName.${DateTime.now().millisecondsSinceEpoch}',
        _pulseTaskName,
        initialDelay: const Duration(seconds: 10), // Start in 10 seconds
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        inputData: {
          'employeeId': employeeId,
          'attendanceId': attendanceId,
          'branchId': branchId,
          'isOneOff': true,
        },
      );
      print('✅ Scheduled immediate one-off pulse');
    } catch (e) {
      print('⚠️ Could not schedule immediate pulse: $e');
    }
  }

  /// Stop periodic pulse tracking
  Future<void> stopPeriodicPulses() async {
    try {
      await Workmanager().cancelByUniqueName(periodicUniqueTaskName);

      // ✅ V2: Cancel all one-off tasks too
      await Workmanager().cancelAll();

      // Clear saved data
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_employee_id');
      await prefs.remove('active_attendance_id');
      await prefs.remove('active_branch_id');
      await prefs.remove('pulse_start_time');

      print('✅ Stopped background pulse tracking');
    } catch (e) {
      print('❌ Error stopping background pulses: $e');
    }
  }

  /// ✅ V2: Manually trigger a background pulse (for recovery)
  Future<void> triggerManualPulse() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('active_employee_id');
      final attendanceId = prefs.getString('active_attendance_id');
      final branchId = prefs.getString('active_branch_id');

      if (employeeId != null && attendanceId != null && branchId != null) {
        await _scheduleImmediatePulse(employeeId, attendanceId, branchId);
        print('✅ Manual pulse triggered');
      }
    } catch (e) {
      print('❌ Error triggering manual pulse: $e');
    }
  }
}

const int _silentHeartbeatCooldownMs = 30 * 60 * 1000;
const Duration _maxBackgroundLocationAge = Duration(minutes: 5);
const double _maxBackgroundLocationAccuracyMeters = 150.0;

Future<void> _maybeShowSilentHeartbeatNotification({
  required SharedPreferences prefs,
  required NotificationService notificationService,
  required bool usedWifi,
  required double distanceMeters,
}) async {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final lastShownMs =
      prefs.getInt('last_silent_heartbeat_notification_ms') ?? 0;

  if (nowMs - lastShownMs < _silentHeartbeatCooldownMs) {
    return;
  }

  await notificationService.showSilentBackgroundHeartbeat(
    usedWifi: usedWifi,
    distanceMeters: distanceMeters,
  );
  await prefs.setInt('last_silent_heartbeat_notification_ms', nowMs);
}

/// Background callback dispatcher (runs in isolate)
@pragma('vm:entry-point')
void _callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('🔔 Background pulse task started: $task');

      // Initialize Notifications
      final notificationService = NotificationService.instance;
      await notificationService.initialize();

      // Get saved employee data
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('active_employee_id');
      final attendanceId = prefs.getString('active_attendance_id');
      final branchId = prefs.getString('active_branch_id');

      if (employeeId == null || attendanceId == null || branchId == null) {
        print('⚠️ No active attendance found in background');
        return Future.value(true);
      }

      // Initialize Supabase in background isolate (idempotent-safe).
      try {
        await Supabase.initialize(
          url: SupabaseConfig.supabaseUrl,
          anonKey: SupabaseConfig.supabaseAnonKey,
        );
      } catch (e) {
        print('⚠️ Supabase initialize skipped/reused: $e');
      }

      final supabase = Supabase.instance.client;

      // Get branch data
      final branchResponse = await supabase
          .from('branches')
          .select(
            'latitude, longitude, geofence_radius, distance_from_radius, wifi_bssids_array',
          )
          .eq('id', branchId)
          .maybeSingle();

      if (branchResponse == null) {
        print('❌ Branch not found');
        return Future.value(false);
      }

      final branchLat = branchResponse['latitude'] as double;
      final branchLng = branchResponse['longitude'] as double;
        final baseRadius = (branchResponse['geofence_radius'] as num).toDouble();
        final extraTolerance =
          ((branchResponse['distance_from_radius'] as num?)?.toDouble() ?? 0.0)
            .clamp(0.0, 500.0);
        final radius = baseRadius + extraTolerance;
      final allowedBssids =
          (branchResponse['wifi_bssids_array'] as List<dynamic>?)
              ?.map((e) => e.toString().toUpperCase())
              .toList() ??
          [];

      // Get current location
      Position? position;
      try {
        late final LocationSettings locationSettings;
        if (Platform.isAndroid) {
          locationSettings = AndroidSettings(
            accuracy: LocationAccuracy.high,
            forceLocationManager: true,
            timeLimit: const Duration(seconds: 10),
          );
        } else if (Platform.isIOS) {
          locationSettings = AppleSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 10),
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
          );
        } else {
          locationSettings = const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          );
        }

        position = await Geolocator.getCurrentPosition(
          locationSettings: locationSettings,
        );
      } catch (e) {
        print('⚠️ Could not get location in background: $e');
        // Try last known position
        position = await Geolocator.getLastKnownPosition();
      }

      final double? latResult;
      final double? lngResult;
      final double distance;
      final bool gpsReliable;
      final bool gpsInside;

      if (position != null) {
        latResult = position.latitude;
        lngResult = position.longitude;
        distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          branchLat,
          branchLng,
        );
        final bool staleLocation =
            DateTime.now().difference(position.timestamp).abs() >
            _maxBackgroundLocationAge;
        final bool weakAccuracy =
            position.accuracy > _maxBackgroundLocationAccuracyMeters;
        gpsReliable = !staleLocation && !weakAccuracy;
        gpsInside = distance <= radius;
      } else {
        // Fallback when position is null (deep sleep / GPS lookup timeout)
        latResult = branchLat;
        lngResult = branchLng;
        distance = 0.0;
        gpsReliable = false;
        gpsInside = true;
        print('⚠️ Position is null. Using safety fallback (INSIDE).');
      }

      // Get WiFi BSSID
      String? wifiBssid;
      bool wifiValid = false;
      try {
        wifiBssid = await WiFiService.getCurrentWifiBssidValidated();
        if (wifiBssid.isNotEmpty && allowedBssids.isNotEmpty) {
          wifiValid = allowedBssids.contains(wifiBssid.toUpperCase());
        }
      } catch (e) {
        print('⚠️ Could not get WiFi in background: $e');
      }

      final actualInside = wifiValid || (gpsReliable && gpsInside);
      bool insideGeofence = actualInside;
      bool skipViolationEscalation = false;

      final validationMethod = wifiValid
          ? 'WIFI'
          : (gpsReliable ? 'LOCATION' : 'UNKNOWN');

      if (!wifiValid && !gpsReliable) {
        skipViolationEscalation = true;
        insideGeofence = true;
        final accuracyStr = position != null ? '${position.accuracy.toStringAsFixed(1)}m' : 'null';
        final staleStr = position != null ? (DateTime.now().difference(position.timestamp).abs() > _maxBackgroundLocationAge).toString() : 'true';
        print(
          '⚠️ Unreliable GPS sample - skipping violation escalation '
          '(accuracy: $accuracyStr, stale: $staleStr)',
        );
      }

      // Show a throttled silent heartbeat so the user knows background checks are alive.
      await _maybeShowSilentHeartbeatNotification(
        prefs: prefs,
        notificationService: notificationService,
        usedWifi: wifiValid,
        distanceMeters: distance,
      );

      // ---------------------------------------------------------
      // 🚨 VIOLATION LOGIC (3 Stages)
      // ---------------------------------------------------------
      int consecutiveOutPulses = prefs.getInt('consecutive_out_pulses') ?? 0;
      bool recordAsInside = actualInside; // Default to actual status

      // ✅ CHECK FOR ACTIVE BREAK
      final isBreakActive = prefs.getBool('is_break_active') ?? false;
      final bool breakOverride = isBreakActive && !actualInside;
      if (isBreakActive) {
        print('☕ Break is active. Forcing pulse to be valid.');
        insideGeofence = true; // Treat as inside
        recordAsInside = true; // Record as inside
        consecutiveOutPulses = 0; // Reset violations
        if (breakOverride) {
          print(
            '☕ Break override: actual distance ${distance.toStringAsFixed(1)}m outside geofence.',
          );
        }
      }

      if (skipViolationEscalation) {
        recordAsInside = true;
        consecutiveOutPulses = 0;
        print('✅ Skipped violation escalation for unreliable sample');
      } else if (insideGeofence && !breakOverride) {
        // ✅ User is INSIDE
        consecutiveOutPulses = 0;
        print('✅ User is INSIDE. Resetting violation counter.');
      } else if (breakOverride) {
        consecutiveOutPulses = 0;
        print(
          '☕ Break active - skipping violation escalation for outside pulse.',
        );
      } else {
        // ❌ User is OUTSIDE
        consecutiveOutPulses++;
        print('⚠️ User is OUTSIDE. Violation Counter: $consecutiveOutPulses');

        if (consecutiveOutPulses == 1) {
          // 🟡 STAGE 1: WARNING (5 mins)
          recordAsInside = true;

          await notificationService.showGeofenceViolation(
            employeeName: 'الموظف',
            message:
                'تحذير: أنت خارج نطاق الفرع! يرجى العودة فوراً لتجنب الخصم.',
          );
          print('📢 STAGE 1: Warning Notification Sent');
        } else {
          // 🔴 Stage 2 alert only.
          // Policy: auto checkout is handled by the foreground app pulse flow only.
          recordAsInside = false;

          await notificationService.showGeofenceViolation(
            employeeName: 'الموظف',
            message: '⛔ مخالفة: نبضتين متتاليتين خارج النطاق. افتح التطبيق فوراً.',
          );
          print('📢 STAGE 2: Background violation alert sent (no auto-checkout)');
        }
      }

      // Save updated counter and timestamp
      await prefs.setInt('consecutive_out_pulses', consecutiveOutPulses);
      await prefs.setInt(
        'last_pulse_timestamp',
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setDouble('last_known_distance_$employeeId', distance);

      if (actualInside) {
        await AttendanceTimerService.resumeTimerLocally();
      } else {
        await AttendanceTimerService.pauseTimerLocally(reason: 'خارج نطاق الفرع');
      }

      // ---------------------------------------------------------

      // Save pulse to database
      final now = DateTime.now();
      if (await PulseDeduplicationService.shouldSkipPulse(
        employeeId: employeeId,
        attendanceId: attendanceId,
        timestamp: now,
      )) {
        print('⏭️ Skipping duplicate WorkManager pulse: $employeeId @ $now');
        return Future.value(true);
      }

      try {
        await supabase.from('pulses').insert({
          'employee_id': employeeId,
          'attendance_id': attendanceId,
          'branch_id': branchId,
          'latitude': latResult,
          'longitude': lngResult,
          'inside_geofence': recordAsInside, // Use the modified status
          'is_within_geofence': recordAsInside,
          'distance_from_center': distance, // ✅ FIXED: Always send distance
          'timestamp': now.toUtc().toIso8601String(),
          'wifi_bssid': wifiBssid,
          'validation_method': validationMethod,
          'validated_by_wifi': wifiValid,
          'validated_by_location': gpsReliable && gpsInside,
        });
        await PulseDeduplicationService.markPulseRecorded(
          employeeId: employeeId,
          attendanceId: attendanceId,
          timestamp: now,
          source: 'workmanager_online',
        );

        print(
          '✅ Background pulse saved: ${recordAsInside ? "INSIDE (Recorded)" : "OUTSIDE"} (${distance.round()}m)',
        );
      } catch (e) {
        print('❌ Error saving background pulse: $e');
        // Save to local database for later sync
        final db = OfflineDatabase.instance;
        await db.insertPendingPulse(
          employeeId: employeeId,
          attendanceId: attendanceId,
          branchId: branchId,
          timestamp: now,
          latitude: latResult,
          longitude: lngResult,
          insideGeofence: recordAsInside,
          distanceFromCenter: distance,
          wifiBssid: wifiBssid,
          validationMethod: validationMethod,
          validatedByWifi: wifiValid,
          validatedByLocation: gpsReliable && gpsInside,
        );
        await PulseDeduplicationService.markPulseRecorded(
          employeeId: employeeId,
          attendanceId: attendanceId,
          timestamp: now,
          source: 'workmanager_offline',
        );
        print('📴 Pulse saved offline for later sync');
      }

      // ---------------------------------------------------------
      // 🔔 CHECK FOR SERVER NOTIFICATIONS (Polling)
      // ---------------------------------------------------------
      try {
        // Fetch unread notifications created in the last 20 minutes
        // (Since this task runs every ~15 mins, 20 mins overlap ensures we don't miss any,
        // but might duplicate if task runs fast. We rely on 'is_read' or local cache if possible,
        // but for now, time-based is safest for a simple poll without local state for notifs).

        final twentyMinsAgo = DateTime.now()
            .subtract(const Duration(minutes: 20))
            .toUtc()
            .toIso8601String();

        final notifications =
            (await supabase
                    .from('notifications')
                    .select()
                    .eq('employee_id', employeeId)
                    .eq('is_read', false)
                    .gt('created_at', twentyMinsAgo)
                    .order('created_at', ascending: false))
                as List<dynamic>;

        if (notifications.isNotEmpty) {
          print('🔔 Found ${notifications.length} new server notifications');

          for (final notif in notifications) {
            final title = notif['title'] as String? ?? 'تنبيه جديد';
            final body = notif['body'] as String? ?? '';

            // Show local notification
            await notificationService.showRemoteNotification(
              title: title,
              body: body,
            );

            // Optionally mark as read?
            // No, let the user mark as read when they open the app.
            // But we need to avoid showing it again in the next poll if it's still unread.
            // The 'twentyMinsAgo' filter helps, but if task runs every 15 mins,
            // a notification from 10 mins ago will be shown again.
            // Let's mark it as read? Or maybe just accept the duplicate risk for now
            // (better than missing it).
            // Actually, let's mark it as read to be safe and clean.

            /* 
            // Marking as read might hide it from the in-app inbox if the inbox filters by is_read=false.
            // If the inbox shows all, then marking read is fine.
            // Assuming inbox shows all or we want it to be "new" in inbox.
            // Let's NOT mark as read, but rely on the time window. 
            // If the user doesn't open the app for an hour, they won't get it again 
            // because of the 20 min filter. This is acceptable.
            */
          }
        }
      } catch (e) {
        print('⚠️ Failed to poll server notifications: $e');
      }

      return Future.value(true);
    } catch (e, stackTrace) {
      print('❌ Background pulse task failed: $e');
      print('Stack trace: $stackTrace');
      return Future.value(false);
    }
  });
}
