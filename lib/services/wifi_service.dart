import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter/services.dart';

class WifiService {
  static final NetworkInfo _networkInfo = NetworkInfo();

  /// Helper function to validate BSSID format
  /// Returns true if BSSID is in valid format (6 pairs of hex digits separated by : or -)
  static bool _isValidBssidFormat(String? bssid) {
    if (bssid == null || bssid.isEmpty) return false;
    // Regex to match 6 pairs of hex digits separated by colon or dash
    final bssidRegex = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    return bssidRegex.hasMatch(bssid);
  }

  /// Gets the current WiFi BSSID with validation
  /// Returns the validated BSSID or throws an exception if invalid
  static Future<String> getCurrentWifiBssidValidated() async {
    String? bssid;
    try {
      // Request WiFi BSSID (requires location permissions)
      bssid = await _networkInfo.getWifiBSSID();

      if (bssid == null) {
        throw Exception('لم يتم العثور على BSSID. تأكد من اتصالك بشبكة واي فاي.');
      }

      // Validate BSSID format
      if (!_isValidBssidFormat(bssid)) {
        throw FormatException('تم قراءة BSSID بصيغة غير صحيحة: "$bssid". حاول مرة أخرى.');
      }

      // Standardize format to uppercase with colons
      return bssid.toUpperCase().replaceAll('-', ':');

    } on PlatformException catch (e) {
      // Handle platform-specific errors (permissions, etc.)
      throw Exception('خطأ في الوصول لمعلومات الشبكة: ${e.message}');
    } catch (e) {
      // Handle other errors including FormatException
      rethrow;
    }
  }

  /// Checks if a BSSID string is valid format
  static bool isValidBssidFormat(String bssid) {
    return _isValidBssidFormat(bssid);
  }
}
