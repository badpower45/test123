import 'dart:io';
import 'package:flutter/services.dart';

/// 🔥 Native Pulse Service
/// 
/// Wrapper around native persistent pulse service for maximum reliability
/// Uses foreground service + AlarmManager on Android for ultra-reliable pulse tracking
/// Falls back to Flutter implementation on iOS
class NativePulseService {
  static const MethodChannel _channel = MethodChannel('persistent_pulse');
  
  /// Start persistent pulse service (Android native)
  static Future<bool> startPersistentService({
    required String employeeId,
    required String attendanceId,
    String? branchId,
    int intervalMinutes = 5,
  }) async {
    if (!Platform.isAndroid) {
      print('⚠️ Native pulse service only available on Android');
      return false;
    }
    
    try {
      print('🔥 Starting native persistent pulse service...');
      print('   Employee: $employeeId');
      print('   Attendance: $attendanceId');
      print('   Interval: $intervalMinutes min');
      
      final result = await _channel.invokeMethod('startPersistentService', {
        'employeeId': employeeId,
        'attendanceId': attendanceId,
        'branchId': branchId ?? '',
        'interval': intervalMinutes,
      });
      
      if (result == true) {
        print('✅ Native pulse service started successfully');
        return true;
      } else {
        print('❌ Failed to start native pulse service');
        return false;
      }
    } catch (e) {
      print('❌ Error starting native pulse service: $e');
      return false;
    }
  }
  
  /// Stop persistent pulse service
  static Future<bool> stopPersistentService() async {
    if (!Platform.isAndroid) {
      return false;
    }
    
    try {
      print('🛑 Stopping native persistent pulse service...');
      
      final result = await _channel.invokeMethod('stopPersistentService');
      
      if (result == true) {
        print('✅ Native pulse service stopped');
        return true;
      } else {
        print('❌ Failed to stop native pulse service');
        return false;
      }
    } catch (e) {
      print('❌ Error stopping native pulse service: $e');
      return false;
    }
  }
  
  /// Check if persistent service is running
  static Future<bool> isServiceRunning() async {
    if (!Platform.isAndroid) {
      return false;
    }
    
    try {
      final result = await _channel.invokeMethod('isServiceRunning');
      return result == true;
    } catch (e) {
      print('⚠️ Error checking service status: $e');
      return false;
    }
  }
  
  /// Get pulse statistics from native service
  static Future<Map<String, dynamic>?> getPulseStats() async {
    if (!Platform.isAndroid) {
      return null;
    }
    
    try {
      final result = await _channel.invokeMethod('getPulseStats');
      
      if (result != null) {
        final Map<dynamic, dynamic> stats = result as Map<dynamic, dynamic>;
        return {
          'pulse_count': stats['pulse_count'] as int? ?? 0,
          'last_pulse_time': stats['last_pulse_time'] as int? ?? 0,
          'service_uptime': stats['service_uptime'] as int? ?? 0,
        };
      }
      
      return null;
    } catch (e) {
      print('⚠️ Error getting pulse stats: $e');
      return null;
    }
  }
}
