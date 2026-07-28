import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../database/offline_database.dart';
import 'wifi_service.dart';
import 'app_logger.dart';

/// Debug service for diagnosing auto-checkout issues
/// Helps identify why auto-checkout might not be working on certain devices
class CheckoutDebugService {
  static final CheckoutDebugService instance = CheckoutDebugService._();
  CheckoutDebugService._();

  /// Run full diagnostic and return report
  Future<Map<String, dynamic>> runDiagnostic({
    required String employeeId,
    String? branchId,
  }) async {
    final report = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'employeeId': employeeId,
      'branchId': branchId,
      'issues': <String>[],
      'warnings': <String>[],
      'status': 'unknown',
    };

    try {
      // 1. Check Device Info
      await _checkDeviceInfo(report);

      // 2. Check Location Services
      await _checkLocationServices(report);

      // 3. Check WiFi Status
      await _checkWifiStatus(report);

      // 4. Check Branch Data
      await _checkBranchData(report, employeeId);

      // 5. Check Pulse History
      await _checkPulseHistory(report, employeeId);

      // 6. Check SharedPreferences State
      await _checkPreferencesState(report);

      // 7. Determine overall status
      _determineStatus(report);

    } catch (e) {
      report['error'] = e.toString();
      report['status'] = 'error';
      (report['issues'] as List).add('خطأ في التشخيص: $e');
    }

    AppLogger.instance.log(
      'Checkout Diagnostic Report: $report',
      tag: 'CheckoutDebug',
    );

    return report;
  }

  Future<void> _checkDeviceInfo(Map<String, dynamic> report) async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        report['device'] = {
          'manufacturer': androidInfo.manufacturer,
          'model': androidInfo.model,
          'sdkVersion': androidInfo.version.sdkInt,
          'release': androidInfo.version.release,
          'brand': androidInfo.brand,
        };

        // Check for known problematic devices
        final manufacturer = androidInfo.manufacturer.toLowerCase();
        if (manufacturer.contains('realme') || manufacturer.contains('oppo')) {
          (report['warnings'] as List).add(
            'جهاز ${androidInfo.manufacturer} قد يحتاج إعدادات خاصة للعمل في الخلفية'
          );
        }
        if (manufacturer.contains('xiaomi') || manufacturer.contains('redmi')) {
          (report['warnings'] as List).add(
            'جهاز ${androidInfo.manufacturer} يحتاج تعطيل "توفير البطارية" للتطبيق'
          );
        }
        if (manufacturer.contains('samsung')) {
          if (androidInfo.version.sdkInt >= 30) { // Android 11+
            (report['warnings'] as List).add(
              'Samsung Android 11+ قد يوقف الخدمات الخلفية بشكل عدواني'
            );
          }
        }
      }
    } catch (e) {
      report['device'] = {'error': e.toString()};
    }
  }

  Future<void> _checkLocationServices(Map<String, dynamic> report) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      
      report['location'] = {
        'serviceEnabled': serviceEnabled,
        'permission': permission.toString(),
      };

      if (!serviceEnabled) {
        (report['issues'] as List).add('خدمة الموقع (GPS) غير مفعلة');
      }

      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        (report['issues'] as List).add('صلاحية الموقع غير ممنوحة');
      }

      if (permission == LocationPermission.whileInUse) {
        (report['warnings'] as List).add(
          'صلاحية الموقع "أثناء الاستخدام فقط" - قد لا يعمل في الخلفية'
        );
      }

      // Try to get current location
      if (serviceEnabled && permission == LocationPermission.always) {
        try {
          late final LocationSettings locationSettings;
          if (Platform.isAndroid) {
            locationSettings = AndroidSettings(
              accuracy: LocationAccuracy.high,
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

          final position = await Geolocator.getCurrentPosition(
            locationSettings: locationSettings,
          );
          report['location']['currentPosition'] = {
            'lat': position.latitude,
            'lng': position.longitude,
            'accuracy': position.accuracy,
          };
        } catch (e) {
          report['location']['positionError'] = e.toString();
          (report['warnings'] as List).add('فشل في الحصول على الموقع الحالي');
        }
      }
    } catch (e) {
      report['location'] = {'error': e.toString()};
      (report['issues'] as List).add('خطأ في فحص خدمة الموقع');
    }
  }

  Future<void> _checkWifiStatus(Map<String, dynamic> report) async {
    if (kIsWeb) {
      report['wifi'] = {'status': 'not_available_on_web'};
      return;
    }

    try {
      final availability = await WiFiService.checkBssidAvailability();
      report['wifi'] = availability;

      if (availability['available'] != true) {
        final errorCode = availability['errorCode'] as String?;
        if (errorCode == 'LOCATION_SERVICE_DISABLED') {
          (report['issues'] as List).add('يجب تفعيل GPS لقراءة WiFi BSSID');
        } else if (errorCode == 'BSSID_PLACEHOLDER') {
          (report['issues'] as List).add('الجهاز لا يستطيع قراءة BSSID - جرب إعادة تشغيل WiFi');
        } else if (errorCode == 'LOCATION_PERMISSION_DENIED') {
          (report['issues'] as List).add('يجب منح صلاحية الموقع لقراءة WiFi');
        }
      }
    } catch (e) {
      report['wifi'] = {'error': e.toString()};
    }
  }

  Future<void> _checkBranchData(Map<String, dynamic> report, String employeeId) async {
    if (kIsWeb) {
      report['branchData'] = {'status': 'web_mode'};
      return;
    }

    try {
      final db = OfflineDatabase.instance;
      final branchData = await db.getCachedBranchData(employeeId);

      if (branchData == null) {
        report['branchData'] = {'status': 'not_cached'};
        (report['issues'] as List).add('لا توجد بيانات محفوظة للفرع - يجب تحميلها أولاً');
      } else {
        report['branchData'] = {
          'status': 'cached',
          'latitude': branchData['latitude'],
          'longitude': branchData['longitude'],
          'geofenceRadius': branchData['geofence_radius'],
          'hasBssids': branchData['wifi_bssids_array'] != null,
          'bssidsCount': (branchData['wifi_bssids_array'] as List?)?.length ?? 0,
        };
      }
    } catch (e) {
      report['branchData'] = {'error': e.toString()};
    }
  }

  Future<void> _checkPulseHistory(Map<String, dynamic> report, String employeeId) async {
    if (kIsWeb) {
      report['pulses'] = {'status': 'web_mode'};
      return;
    }

    try {
      final db = OfflineDatabase.instance;
      final pendingPulses = await db.getPendingPulses();
      
      report['pulses'] = {
        'pendingCount': pendingPulses.length,
        'recentPulses': pendingPulses.take(5).map((p) => {
          'timestamp': p['timestamp'],
          'inside': p['inside_geofence'],
          'distance': p['distance_from_center'],
          'wifiValidated': p['validated_by_wifi'],
          'locationValidated': p['validated_by_location'],
        }).toList(),
      };

      // Check for consecutive false pulses
      int consecutiveFalse = 0;
      for (final pulse in pendingPulses.reversed.take(3)) {
        if (pulse['inside_geofence'] == 0 || pulse['inside_geofence'] == false) {
          consecutiveFalse++;
        } else {
          break;
        }
      }

      if (consecutiveFalse >= 2) {
        (report['warnings'] as List).add(
          'توجد $consecutiveFalse نبضات متتالية خارج النطاق - يجب تفعيل الخروج التلقائي'
        );
      }
    } catch (e) {
      report['pulses'] = {'error': e.toString()};
    }
  }

  Future<void> _checkPreferencesState(Map<String, dynamic> report) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      report['preferences'] = {
        'activeAttendanceId': prefs.getString('active_attendance_id'),
        'isCheckedIn': prefs.getBool('is_checked_in'),
        'lastPulseTime': prefs.getInt('last_pulse_time'),
        'consecutiveOutPulses': prefs.getInt('consecutive_out_pulses'),
        'forcedAutoCheckoutPending': prefs.getBool('forced_auto_checkout_pending'),
      };

      // Check for stale state
      final lastPulseTime = prefs.getInt('last_pulse_time');
      if (lastPulseTime != null) {
        final lastPulse = DateTime.fromMillisecondsSinceEpoch(lastPulseTime);
        final diff = DateTime.now().difference(lastPulse);
        
        if (diff.inMinutes > 10) {
          (report['warnings'] as List).add(
            'آخر نبضة منذ ${diff.inMinutes} دقيقة - قد تكون الخدمة الخلفية متوقفة'
          );
        }
      }
    } catch (e) {
      report['preferences'] = {'error': e.toString()};
    }
  }

  void _determineStatus(Map<String, dynamic> report) {
    final issues = report['issues'] as List;
    final warnings = report['warnings'] as List;

    if (issues.isEmpty && warnings.isEmpty) {
      report['status'] = 'healthy';
      report['statusMessage'] = '✅ النظام يعمل بشكل طبيعي';
    } else if (issues.isNotEmpty) {
      report['status'] = 'critical';
      report['statusMessage'] = '❌ توجد مشاكل تحتاج إصلاح';
    } else {
      report['status'] = 'warning';
      report['statusMessage'] = '⚠️ توجد تحذيرات يجب مراجعتها';
    }
  }

  /// Get human-readable diagnostic summary
  String getReadableSummary(Map<String, dynamic> report) {
    final buffer = StringBuffer();
    
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📊 تقرير تشخيص الخروج التلقائي');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('');
    
    // Device
    if (report['device'] != null) {
      final device = report['device'] as Map<String, dynamic>;
      buffer.writeln('📱 الجهاز: ${device['manufacturer']} ${device['model']}');
      buffer.writeln('   Android ${device['release']} (SDK ${device['sdkVersion']})');
      buffer.writeln('');
    }

    // Location
    if (report['location'] != null) {
      final location = report['location'] as Map<String, dynamic>;
      buffer.writeln('📍 الموقع:');
      buffer.writeln('   GPS مفعل: ${location['serviceEnabled'] == true ? "✅" : "❌"}');
      buffer.writeln('   الصلاحية: ${_translatePermission(location['permission'])}');
      buffer.writeln('');
    }

    // WiFi
    if (report['wifi'] != null) {
      final wifi = report['wifi'] as Map<String, dynamic>;
      buffer.writeln('📶 WiFi:');
      buffer.writeln('   متاح: ${wifi['available'] == true ? "✅" : "❌"}');
      if (wifi['bssid'] != null) {
        buffer.writeln('   BSSID: ${wifi['bssid']}');
      }
      buffer.writeln('');
    }

    // Issues
    final issues = report['issues'] as List? ?? [];
    if (issues.isNotEmpty) {
      buffer.writeln('❌ المشاكل:');
      for (final issue in issues) {
        buffer.writeln('   • $issue');
      }
      buffer.writeln('');
    }

    // Warnings
    final warnings = report['warnings'] as List? ?? [];
    if (warnings.isNotEmpty) {
      buffer.writeln('⚠️ التحذيرات:');
      for (final warning in warnings) {
        buffer.writeln('   • $warning');
      }
      buffer.writeln('');
    }

    // Status
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln(report['statusMessage'] ?? 'حالة غير معروفة');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    return buffer.toString();
  }

  String _translatePermission(String? permission) {
    switch (permission) {
      case 'LocationPermission.always':
        return '✅ مسموح دائماً';
      case 'LocationPermission.whileInUse':
        return '⚠️ أثناء الاستخدام فقط';
      case 'LocationPermission.denied':
        return '❌ مرفوض';
      case 'LocationPermission.deniedForever':
        return '❌ مرفوض نهائياً';
      default:
        return permission ?? 'غير معروف';
    }
  }
}
