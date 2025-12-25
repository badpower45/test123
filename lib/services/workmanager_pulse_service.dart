import '../database/offline_database.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/wifi_service.dart';
import 'notification_service.dart';
import 'supabase_attendance_service.dart';


/// Background Pulse Service using WorkManager
/// Sends location pulses every 5 minutes even when app is closed
/// ✅ V2: Enhanced for old devices (Realme 6, Galaxy A12, etc.)
class WorkManagerPulseService {
  static const String _pulseTaskName = 'pulseTask';
  static const String _uniqueTaskName = 'com.oldies.pulse';
  static const String _oneOffTaskName = 'com.oldies.pulse.oneoff';
  
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
      await prefs.setInt('pulse_start_time', DateTime.now().millisecondsSinceEpoch);
      
      // ✅ V2: Register periodic task (runs every 15 minutes - minimum allowed by Android)
      await Workmanager().registerPeriodicTask(
        _uniqueTaskName,
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
  Future<void> _scheduleImmediatePulse(String employeeId, String attendanceId, String branchId) async {
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
      await Workmanager().cancelByUniqueName(_uniqueTaskName);
      
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
      
      // Initialize Supabase in background isolate
      await Supabase.initialize(
        url: 'https://okwmvkpmvpblnekecwlh.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9rd212a3BtdnBibG5la2Vjd2xoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mjk4NTEyMTQsImV4cCI6MjA0NTQyNzIxNH0.LglZZZGRmP_tg4Y5gHs0VaTc_oKn5-DpTfx3sLZJX7U',
      );
      
      final supabase = Supabase.instance.client;
      
      // Get branch data
      final branchResponse = await supabase
        .from('branches')
        .select('latitude, longitude, geofence_radius, wifi_bssids_array')
        .eq('id', branchId)
        .maybeSingle();
      
      if (branchResponse == null) {
        print('❌ Branch not found');
        return Future.value(false);
      }
      
      final branchLat = branchResponse['latitude'] as double;
      final branchLng = branchResponse['longitude'] as double;
      final radius = (branchResponse['geofence_radius'] as num).toDouble();
      final allowedBssids = (branchResponse['wifi_bssids_array'] as List<dynamic>?)
          ?.map((e) => e.toString().toUpperCase())
          .toList() ?? [];
      
      // Get current location
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          forceAndroidLocationManager: true,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        print('⚠️ Could not get location in background: $e');
        // Try last known position
        position = await Geolocator.getLastKnownPosition();
      }
      
      if (position == null) {
        print('❌ No location available for pulse');
        return Future.value(true); // Success but skip this pulse
      }
      
      // Calculate distance
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        branchLat,
        branchLng,
      );
      
      final actualInside = distance <= radius;
      bool insideGeofence = actualInside;
      
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
              '☕ Break override: actual distance ${distance.toStringAsFixed(1)}m outside geofence.');
        }
      }

      if (insideGeofence && !breakOverride) {
        // ✅ User is INSIDE
        consecutiveOutPulses = 0;
        print('✅ User is INSIDE. Resetting violation counter.');
      } else if (breakOverride) {
        consecutiveOutPulses = 0;
        print('☕ Break active - skipping violation escalation for outside pulse.');
      } else {
        // ❌ User is OUTSIDE
        consecutiveOutPulses++;
        print('⚠️ User is OUTSIDE. Violation Counter: $consecutiveOutPulses');

        if (consecutiveOutPulses == 1) {
          // 🟡 STAGE 1: WARNING (5 mins)
          recordAsInside = true;

          await notificationService.showGeofenceViolation(
            employeeName: 'الموظف',
            message: 'تحذير: أنت خارج نطاق الفرع! يرجى العودة فوراً لتجنب الخصم.',
          );
          print('📢 STAGE 1: Warning Notification Sent');

        } else {
          // 🔴 AUTO CHECKOUT at 2nd consecutive outside (10 mins total)
          recordAsInside = false;

          await notificationService.showGeofenceViolation(
            employeeName: 'الموظف',
            message: '⛔ تم تسجيل انصراف تلقائي بعد نبضتين خارج النطاق.',
          );
          print('📢 AUTO CHECKOUT Triggered (2 consecutive outside pulses)');

          try {
            final checkOutTime = DateTime.now().toUtc();

            final attendance = await supabase
                .from('attendance')
                .select('check_in_time')
                .eq('id', attendanceId)
                .single();

            DateTime checkInTime;
            try {
              checkInTime = DateTime.parse(attendance['check_in_time'].toString());
            } catch (e) {
              checkInTime = checkOutTime.subtract(const Duration(hours: 8)); // Fallback
            }
            final totalHours =
                checkOutTime.difference(checkInTime).inMinutes / 60.0;

            await supabase
                .from('attendance')
                .update({
                  'check_out_time': checkOutTime.toIso8601String(),
                  'status': 'completed',
                  'work_hours': totalHours.toStringAsFixed(2),
                  'notes':
                      'Auto-checkout by system (Background Pulse Violation)',
                })
                .eq('id', attendanceId);

            print('✅ Auto-checkout successful');

            await SupabaseAttendanceService.markForcedCheckoutNotice(
              timestamp: checkOutTime,
              distanceMeters: distance,
              pendingSync: false,
              message:
                  'تم تسجيل انصراف تلقائي في الخلفية بسبب الابتعاد عن الفرع.',
            );

            await Workmanager().cancelByUniqueName('com.oldies.pulse');
            await prefs.remove('active_employee_id');
            await prefs.remove('active_attendance_id');
            await prefs.remove('active_branch_id');

            return Future.value(true);
          } catch (e) {
            print('❌ Auto-checkout failed (likely offline): $e');

            try {
              final db = OfflineDatabase.instance;
              final offlineTimestamp = DateTime.now();

              await db.insertPendingCheckout(
                employeeId: employeeId,
                attendanceId: attendanceId,
                timestamp: offlineTimestamp,
                latitude: position.latitude,
                longitude: position.longitude,
                notes:
                    'Auto-checkout by system (Background Pulse Violation - Offline)',
              );
              print('✅ Offline Auto-checkout saved to local DB');

              await SupabaseAttendanceService.markForcedCheckoutNotice(
                timestamp: offlineTimestamp,
                distanceMeters: distance,
                pendingSync: true,
                message:
                    'تم حفظ انصراف تلقائي في الخلفية وسيتم رفعه عند توفر الإنترنت.',
              );

              await Workmanager().cancelByUniqueName('com.oldies.pulse');
              await prefs.remove('active_employee_id');
              await prefs.remove('active_attendance_id');
              await prefs.remove('active_branch_id');

              return Future.value(true);
            } catch (dbError) {
              print('❌ Failed to save offline auto-checkout: $dbError');
            }
          }
        }
      }

      // Save updated counter and timestamp
      await prefs.setInt('consecutive_out_pulses', consecutiveOutPulses);
      await prefs.setInt('last_pulse_timestamp', DateTime.now().millisecondsSinceEpoch);

      // ---------------------------------------------------------
      
      // Save pulse to database
      final now = DateTime.now();
      try {
        await supabase.from('pulses').insert({
          'employee_id': employeeId,
          'attendance_id': attendanceId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'inside_geofence': recordAsInside, // Use the modified status
          'is_within_geofence': recordAsInside,
          'distance_from_center': distance, // ✅ FIXED: Always send distance
          'timestamp': now.toUtc().toIso8601String(),
          'wifi_bssid': wifiBssid,
          'validated_by_wifi': wifiValid,
          'validated_by_location': actualInside, // Preserve actual reading
        });
        
        print('✅ Background pulse saved: ${recordAsInside ? "INSIDE (Recorded)" : "OUTSIDE"} (${distance.round()}m)');
      } catch (e) {
        print('❌ Error saving background pulse: $e');
        // Save to local database for later sync
        final db = OfflineDatabase.instance;
        await db.insertPendingPulse(
          employeeId: employeeId,
          attendanceId: attendanceId,
          timestamp: now,
          latitude: position.latitude,
          longitude: position.longitude,
          insideGeofence: recordAsInside,
          distanceFromCenter: distance,
          wifiBssid: wifiBssid,
          validatedByWifi: wifiValid,
          validatedByLocation: actualInside,
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
        
        final twentyMinsAgo = DateTime.now().subtract(const Duration(minutes: 20)).toUtc().toIso8601String();
        
        final notifications = (await supabase
            .from('notifications')
            .select()
            .eq('employee_id', employeeId)
            .eq('is_read', false)
            .gt('created_at', twentyMinsAgo)
            .order('created_at', ascending: false)) as List<dynamic>;
            
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
