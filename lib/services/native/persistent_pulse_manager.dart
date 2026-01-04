import 'package:flutter/services.dart';
import 'dart:io';

/// 🔥 Persistent Pulse Manager
/// 
/// This service manages the native Android Foreground Service
/// for sending location pulses in the background.
/// 
/// Features:
/// - Native Android Service (doesn't get killed easily)
/// - WakeLock to prevent device sleep
/// - AlarmManager for automatic resurrection
/// - START_STICKY for auto-restart
/// 
/// Usage:
/// ```dart
/// await PersistentPulseManager.startPersistentPulses(
///   employeeId: '123',
///   attendanceId: '456',
///   branchId: '789',
///   interval: 5, // minutes
/// );
/// ```
class PersistentPulseManager {
  static const MethodChannel _channel = MethodChannel('persistent_pulse');
  
  /// Start the persistent pulse service
  /// 
  /// Parameters:
  /// - [employeeId]: The employee ID
  /// - [attendanceId]: The attendance record ID
  /// - [branchId]: The branch ID (optional)
  /// - [interval]: Pulse interval in minutes (default: 5)
  /// 
  /// Returns: true if service started successfully
  static Future<bool> startPersistentPulses({
    required String employeeId,
    required String attendanceId,
    String? branchId,
    int interval = 5,
  }) async {
    // Only works on Android
    if (!Platform.isAndroid) {
      print('⚠️ Persistent Pulse Service only works on Android');
      return false;
    }
    
    try {
      final result = await _channel.invokeMethod('startPersistentService', {
        'employeeId': employeeId,
        'attendanceId': attendanceId,
        'branchId': branchId ?? '',
        'interval': interval,
      });
      
      print('✅ Persistent Pulse Service started successfully');
      return result == true;
    } on PlatformException catch (e) {
      print('❌ Failed to start Persistent Pulse Service: ${e.message}');
      return false;
    } catch (e) {
      print('❌ Unexpected error: $e');
      return false;
    }
  }
  
  /// Stop the persistent pulse service
  /// 
  /// Returns: true if service stopped successfully
  static Future<bool> stopPersistentPulses() async {
    // Only works on Android
    if (!Platform.isAndroid) {
      print('⚠️ Persistent Pulse Service only works on Android');
      return false;
    }
    
    try {
      final result = await _channel.invokeMethod('stopPersistentService');
      
      print('✅ Persistent Pulse Service stopped successfully');
      return result == true;
    } on PlatformException catch (e) {
      print('❌ Failed to stop Persistent Pulse Service: ${e.message}');
      return false;
    } catch (e) {
      print('❌ Unexpected error: $e');
      return false;
    }
  }
  
  /// Check if the service is supported on this platform
  static bool get isSupported => Platform.isAndroid;
}
