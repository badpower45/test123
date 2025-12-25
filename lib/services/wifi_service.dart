import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'app_logger.dart';

class WiFiService {
  static final NetworkInfo _networkInfo = NetworkInfo();

  /// Helper function to validate BSSID format
  /// Returns true if BSSID is in valid format (6 pairs of hex digits separated by : or -)
  static bool _isValidBssidFormat(String? bssid) {
    if (bssid == null || bssid.isEmpty) return false;
    // Check for placeholder values that Android returns when location is disabled
    if (bssid == '02:00:00:00:00:00' || bssid == '00:00:00:00:00:00') {
      return false;
    }
    // Regex to match 6 pairs of hex digits separated by colon or dash
    final bssidRegex = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    return bssidRegex.hasMatch(bssid);
  }

  /// Check if Location Services are enabled (required for BSSID on Android 10+)
  static Future<bool> isLocationServiceEnabled() async {
    if (kIsWeb) return true;
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      AppLogger.instance.log('Error checking location service: $e', level: AppLogger.warning, tag: 'WiFiService');
      return false;
    }
  }

  /// Check if we have fine location permission (required for BSSID)
  static Future<bool> hasLocationPermission() async {
    if (kIsWeb) return true;
    final status = await Permission.locationWhenInUse.status;
    return status.isGranted;
  }

  /// Detailed check for BSSID availability with specific error messages
  /// Returns a map with 'available' bool and 'message' string
  static Future<Map<String, dynamic>> checkBssidAvailability() async {
    if (kIsWeb) {
      return {'available': false, 'message': 'قراءة WiFi BSSID غير متاحة على المتصفح'};
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      return {'available': false, 'message': 'قراءة WiFi BSSID متاحة فقط على Android و iOS'};
    }

    // Check 1: Location permission
    final locationStatus = await Permission.locationWhenInUse.status;
    if (!locationStatus.isGranted) {
      return {
        'available': false, 
        'message': 'يجب منح صلاحية الموقع لقراءة معلومات الواي فاي',
        'errorCode': 'LOCATION_PERMISSION_DENIED',
      };
    }

    // Check 2: Location Service enabled (CRITICAL for Android 10+)
    final locationEnabled = await isLocationServiceEnabled();
    if (!locationEnabled) {
      return {
        'available': false,
        'message': 'يجب تفعيل خدمة الموقع (GPS) على الجهاز لقراءة معلومات الواي فاي.\n\nعلى أجهزة Android 10 وما بعد، لا يمكن قراءة BSSID بدون تفعيل GPS.',
        'errorCode': 'LOCATION_SERVICE_DISABLED',
      };
    }

    // Check 3: Try to read BSSID
    try {
      final bssid = await _networkInfo.getWifiBSSID();
      
      if (bssid == null) {
        return {
          'available': false,
          'message': 'غير متصل بشبكة واي فاي. تأكد من الاتصال بشبكة الفرع.',
          'errorCode': 'NOT_CONNECTED',
        };
      }

      // Check for placeholder values
      if (bssid == '02:00:00:00:00:00' || bssid == '00:00:00:00:00:00') {
        return {
          'available': false,
          'message': 'لم يتمكن الجهاز من قراءة BSSID.\n\n'
              'الحلول الممكنة:\n'
              '1. تأكد من تفعيل GPS\n'
              '2. افصل واي فاي وأعد الاتصال\n'
              '3. أعد تشغيل التطبيق\n'
              '4. في الإعدادات: أعطِ التطبيق صلاحية "الموقع" كـ "مسموح دائماً"',
          'errorCode': 'BSSID_PLACEHOLDER',
        };
      }

      if (!_isValidBssidFormat(bssid)) {
        return {
          'available': false,
          'message': 'تم قراءة BSSID بصيغة غير صحيحة. حاول إعادة الاتصال بالشبكة.',
          'errorCode': 'INVALID_FORMAT',
        };
      }

      return {'available': true, 'message': 'BSSID متاح', 'bssid': bssid};
    } catch (e) {
      return {
        'available': false,
        'message': 'خطأ في قراءة معلومات الشبكة: $e',
        'errorCode': 'READ_ERROR',
      };
    }
  }

  /// Gets the current WiFi BSSID with validation
  /// Returns the validated BSSID or throws an exception if invalid
  static Future<String> getCurrentWifiBssidValidated() async {
    // First check availability
    final availability = await checkBssidAvailability();
    if (availability['available'] != true) {
      throw Exception(availability['message'] ?? 'خطأ غير معروف');
    }

    String? bssid;
    try {
      // Request WiFi BSSID (requires location permissions + location service)
      bssid = await _networkInfo.getWifiBSSID();

      if (bssid == null) {
        throw Exception('لم يتم العثور على BSSID. تأكد من اتصالك بشبكة واي فاي.');
      }

      // Check for Android placeholder values (returned when location disabled)
      if (bssid == '02:00:00:00:00:00' || bssid == '00:00:00:00:00:00') {
        throw Exception(
          'الجهاز لا يستطيع قراءة BSSID.\n'
          'تأكد من:\n'
          '1. تفعيل GPS/الموقع\n'
          '2. منح التطبيق صلاحية الموقع "دائماً"\n'
          '3. الاتصال بشبكة الواي فاي'
        );
      }

      // Validate BSSID format
      if (!_isValidBssidFormat(bssid)) {
        throw FormatException('تم قراءة BSSID بصيغة غير صحيحة: "$bssid". حاول مرة أخرى.');
      }

      // Standardize format to uppercase with colons
      return bssid.toUpperCase().replaceAll('-', ':');

    } on PlatformException catch (e) {
      AppLogger.instance.log('PlatformException reading BSSID: ${e.code} - ${e.message}', 
        level: AppLogger.error, tag: 'WiFiService');
      
      // Specific error handling for common platform issues
      if (e.code == 'PERMISSION_DENIED') {
        throw Exception('صلاحية الموقع مطلوبة لقراءة معلومات الواي فاي');
      }
      throw Exception('خطأ في الوصول لمعلومات الشبكة: ${e.message}');
    } catch (e) {
      AppLogger.instance.log('Error reading BSSID: $e', level: AppLogger.error, tag: 'WiFiService');
      rethrow;
    }
  }

  /// Get WiFi SSID (network name)
  static Future<String?> getCurrentWifiSsid() async {
    if (kIsWeb) return null;
    try {
      return await _networkInfo.getWifiName();
    } catch (e) {
      AppLogger.instance.log('Error reading WiFi SSID: $e', level: AppLogger.warning, tag: 'WiFiService');
      return null;
    }
  }

  /// Checks if a BSSID string is valid format
  static bool isValidBssidFormat(String bssid) {
    return _isValidBssidFormat(bssid);
  }

  /// Debug method to get all WiFi info for troubleshooting
  static Future<Map<String, dynamic>> getDebugInfo() async {
    final result = <String, dynamic>{};
    
    try {
      result['locationPermission'] = (await Permission.locationWhenInUse.status).toString();
      result['locationServiceEnabled'] = await isLocationServiceEnabled();
      result['bssid'] = await _networkInfo.getWifiBSSID();
      result['ssid'] = await _networkInfo.getWifiName();
      result['ip'] = await _networkInfo.getWifiIP();
      result['platform'] = Platform.operatingSystem;
      result['platformVersion'] = Platform.operatingSystemVersion;
    } catch (e) {
      result['error'] = e.toString();
    }
    
    return result;
  }
}
