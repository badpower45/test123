import 'dart:io';
import 'package:flutter/services.dart';
import '../database/offline_database.dart';
import 'native_location_service.dart';

/// 🎧 Background Pulse Listener
/// 
/// Listens for pulses recorded by Native Service (PersistentPulseService.kt)
/// and saves them to SQLite database
class BackgroundPulseListener {
  static const MethodChannel _channel = MethodChannel('background_pulse_callback');
  static bool _isInitialized = false;
  static Function()? _onPulseRecordedCallback;
  
  /// Initialize the listener
  static Future<void> initialize({Function()? onPulseRecorded}) async {
    if (!Platform.isAndroid) {
      print('⚠️ Background pulse listener only works on Android');
      return;
    }
    
    if (_isInitialized) {
      print('⚠️ Background pulse listener already initialized');
      return;
    }
    
    _onPulseRecordedCallback = onPulseRecorded;
    
    // Set up method call handler
    _channel.setMethodCallHandler(_handleMethodCall);
    
    _isInitialized = true;
    print('✅ Background pulse listener initialized');
  }
  
  /// Handle method calls from Native
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPulseRecorded':
        return await _onPulseRecorded(call.arguments);
      default:
        print('⚠️ Unknown method: ${call.method}');
        return null;
    }
  }
  
  /// Handle pulse recorded event from Native Service
  static Future<void> _onPulseRecorded(dynamic arguments) async {
    try {
      print('💓 Pulse received from native service');
      
      if (arguments == null) {
        print('⚠️ No pulse data provided');
        return;
      }
      
      final Map<dynamic, dynamic> data = arguments as Map<dynamic, dynamic>;
      final employeeId = data['employee_id'] as String?;
      final attendanceId = data['attendance_id'] as String?;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        data['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );
      final pulseCount = data['pulse_count'] as int? ?? 0;
      
      if (employeeId == null || employeeId.isEmpty) {
        print('❌ Invalid employee ID in pulse data');
        return;
      }
      
      print('📋 Pulse details: Employee=$employeeId, Count=$pulseCount, Time=$timestamp');
      
      // Get current location using Native GPS
      final position = await NativeLocationService.getCurrentLocation();
      
      if (position == null) {
        print('⚠️ Could not get location for pulse - saving with null coordinates');
      }
      
      // Save pulse to SQLite
      final db = OfflineDatabase.instance;
      await db.insertPendingPulse(
        employeeId: employeeId,
        attendanceId: attendanceId,
        timestamp: timestamp,
        latitude: position?.latitude,
        longitude: position?.longitude,
        insideGeofence: false, // Will be validated later
        distanceFromCenter: 0.0,
        wifiBssid: null,
        validatedByWifi: false,
        validatedByLocation: position != null,
      );
      
      print('✅ Pulse #$pulseCount saved to SQLite');
      
      // Trigger callback if registered
      _onPulseRecordedCallback?.call();
    } catch (e) {
      print('❌ Error handling pulse from native: $e');
    }
  }
  
  /// Dispose the listener
  static void dispose() {
    _channel.setMethodCallHandler(null);
    _onPulseRecordedCallback = null;
    _isInitialized = false;
    print('🛑 Background pulse listener disposed');
  }
}
