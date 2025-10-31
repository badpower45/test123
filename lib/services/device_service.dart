import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../constants/api_endpoints.dart';

class DeviceService {
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    String deviceId = '';
    String deviceName = '';
    String deviceModel = '';
    String osVersion = '';

    // Skip device info collection for web
    if (kIsWeb) {
      deviceId = 'web_browser_instance';
      deviceName = 'Web Browser';
      deviceModel = 'Browser';
      osVersion = 'Web';
    } else {
      final deviceInfo = DeviceInfoPlugin();

      try {
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          deviceId = androidInfo.id; // Android ID
          deviceName = androidInfo.device;
          deviceModel = androidInfo.model;
          osVersion = 'Android ${androidInfo.version.release}';
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceId = iosInfo.identifierForVendor ?? ''; // iOS UUID
          deviceName = iosInfo.name;
          deviceModel = iosInfo.model;
          osVersion = 'iOS ${iosInfo.systemVersion}';
        }
      } catch (e) {
        print('Error getting device info: $e');
      }
    }

    // Get app version (this should work on web too)
    String appVersion = '';
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = packageInfo.version;
    } catch (e) {
      print('Error getting package info: $e');
    }

    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'deviceModel': deviceModel,
      'osVersion': osVersion,
      'appVersion': appVersion,
    };
  }

  static Future<Map<String, dynamic>> registerDevice(String employeeId) async {
    // Skip device registration for web
    if (kIsWeb) {
      print('Skipping device registration for Web platform.');
      return {'message': 'Device registration skipped for web'};
    }

    final deviceInfo = await getDeviceInfo();

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/device/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'employeeId': employeeId,
          'deviceId': deviceInfo['deviceId'],
          'deviceName': deviceInfo['deviceName'],
          'deviceModel': deviceInfo['deviceModel'],
          'osVersion': deviceInfo['osVersion'],
          'appVersion': deviceInfo['appVersion'],
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to register device: ${response.statusCode}');
      }
    } catch (e) {
      print('Device registration error: $e');
      rethrow;
    }
  }
}
