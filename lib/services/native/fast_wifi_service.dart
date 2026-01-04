import 'package:flutter/services.dart';
import 'dart:io';

/// 🔍 Fast WiFi Service
/// 
/// Ultra-fast WiFi BSSID and info retrieval using Native Android WifiManager.
/// 
/// Features:
/// - Read current connection BSSID instantly
/// - WiFi scan fallback if needed
/// - Handles Android 10+ location requirement
/// - Avoids "02:00:00:00:00:00" placeholder
/// 
/// Much more reliable than network_info_plus on old devices!
/// 
/// Usage:
/// ```dart
/// final bssid = await FastWiFiService.getBSSID();
/// print('BSSID: $bssid');
/// 
/// final info = await FastWiFiService.getWiFiInfo();
/// print('SSID: ${info?.ssid}, Signal: ${info?.signalStrength}');
/// ```
class FastWiFiService {
  static const MethodChannel _channel = MethodChannel('fast_wifi');
  
  /// Get WiFi BSSID (MAC address of router)
  /// 
  /// Returns BSSID string or null if:
  /// - WiFi is disabled
  /// - Permissions not granted
  /// - Location disabled (Android 10+)
  /// - Not connected to WiFi
  static Future<String?> getBSSID() async {
    // Only works on Android
    if (!Platform.isAndroid) {
      print('⚠️ Fast WiFi only works on Android');
      return null;
    }
    
    try {
      final result = await _channel.invokeMethod('getBSSID');
      
      if (result != null && result is String) {
        print('✅ WiFi BSSID: $result');
        return result;
      }
      
      print('⚠️ No BSSID available');
      return null;
    } on PlatformException catch (e) {
      print('❌ Failed to get BSSID: ${e.message}');
      return null;
    } catch (e) {
      print('❌ Unexpected error: $e');
      return null;
    }
  }
  
  /// Get complete WiFi information
  /// 
  /// Returns WiFiInfo or null if WiFi is not available
  static Future<WiFiInfo?> getWiFiInfo() async {
    // Only works on Android
    if (!Platform.isAndroid) {
      print('⚠️ Fast WiFi only works on Android');
      return null;
    }
    
    try {
      final result = await _channel.invokeMethod('getWiFiInfo');
      
      if (result != null && result is Map) {
        return WiFiInfo.fromMap(Map<String, dynamic>.from(result));
      }
      
      print('⚠️ No WiFi info available');
      return null;
    } on PlatformException catch (e) {
      print('❌ Failed to get WiFi info: ${e.message}');
      return null;
    } catch (e) {
      print('❌ Unexpected error: $e');
      return null;
    }
  }
  
  /// Check if the service is supported on this platform
  static bool get isSupported => Platform.isAndroid;
}

/// WiFi information model
class WiFiInfo {
  final String ssid;
  final String bssid;
  final int signalStrength; // dBm (e.g., -50 is better than -80)
  final int linkSpeed; // Mbps
  final int frequency; // MHz (e.g., 2437 for channel 6)
  final int networkId;
  
  WiFiInfo({
    required this.ssid,
    required this.bssid,
    required this.signalStrength,
    required this.linkSpeed,
    this.frequency = 0,
    this.networkId = -1,
  });
  
  factory WiFiInfo.fromMap(Map<String, dynamic> map) {
    return WiFiInfo(
      ssid: map['ssid'] as String? ?? '',
      bssid: map['bssid'] as String? ?? '',
      signalStrength: (map['signalStrength'] as num?)?.toInt() ?? 0,
      linkSpeed: (map['linkSpeed'] as num?)?.toInt() ?? 0,
      frequency: (map['frequency'] as num?)?.toInt() ?? 0,
      networkId: (map['networkId'] as num?)?.toInt() ?? -1,
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'ssid': ssid,
      'bssid': bssid,
      'signalStrength': signalStrength,
      'linkSpeed': linkSpeed,
      'frequency': frequency,
      'networkId': networkId,
    };
  }
  
  /// Get signal quality percentage (0-100%)
  int get signalQuality {
    // Convert dBm to percentage
    // -30 dBm = 100%, -90 dBm = 0%
    if (signalStrength >= -30) return 100;
    if (signalStrength <= -90) return 0;
    return ((signalStrength + 90) * 100 / 60).round();
  }
  
  /// Get signal quality as text
  String get signalQualityText {
    final quality = signalQuality;
    if (quality >= 80) return 'ممتاز';
    if (quality >= 60) return 'جيد جداً';
    if (quality >= 40) return 'جيد';
    if (quality >= 20) return 'ضعيف';
    return 'ضعيف جداً';
  }
  
  @override
  String toString() {
    return 'WiFiInfo(ssid: $ssid, bssid: $bssid, signal: $signalStrength dBm, speed: $linkSpeed Mbps)';
  }
}
