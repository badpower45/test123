import 'package:network_info_plus/network_info_plus.dart';

class WiFiService {
  static final WiFiService instance = WiFiService._();
  WiFiService._();

  // Cache للـ BSSID الأخير
  static String? _lastKnownBSSID;
  static DateTime? _lastBSSIDTime;
  static const Duration _cacheValidDuration = Duration(seconds: 30);

  final NetworkInfo _networkInfo = NetworkInfo();

  /// Get WiFi BSSID with caching and error handling
  Future<String?> getWifiBSSID() async {
    try {
      // استخدم الـ cache إذا كان حديث (أقل من 30 ثانية)
      if (_lastKnownBSSID != null && _lastBSSIDTime != null) {
        final age = DateTime.now().difference(_lastBSSIDTime!);
        if (age < _cacheValidDuration) {
          print('[WiFiService] 📶 Using cached BSSID (${age.inSeconds}s old)');
          return _lastKnownBSSID;
        }
      }

      // محاولة الحصول على BSSID
      print('[WiFiService] 🔍 Getting WiFi BSSID...');
      
      String? bssid = await _networkInfo.getWifiBSSID()
          .timeout(const Duration(seconds: 5));

      if (bssid != null) {
        // تنظيف وتوحيد الصيغة
        bssid = _normalizeBSSID(bssid);
        
        // حفظ في الـ cache
        _lastKnownBSSID = bssid;
        _lastBSSIDTime = DateTime.now();
        
        print('[WiFiService] ✅ Got BSSID: $bssid');
        return bssid;
      } else {
        print('[WiFiService] ⚠️ BSSID is null (not connected to WiFi?)');
        
        // إذا كان عندنا cache قديم، استخدمه
        if (_lastKnownBSSID != null) {
          print('[WiFiService] 📶 Using old cached BSSID as fallback');
          return _lastKnownBSSID;
        }
        
        return null;
      }
    } catch (e) {
      print('[WiFiService] ❌ Error getting BSSID: $e');
      
      // Fallback: استخدم الـ cache حتى لو قديم
      if (_lastKnownBSSID != null) {
        print('[WiFiService] 📶 Using cached BSSID as fallback');
        return _lastKnownBSSID;
      }
      
      return null;
    }
  }

  /// Get WiFi name/SSID
  Future<String?> getWifiName() async {
    try {
      final ssid = await _networkInfo.getWifiName()
          .timeout(const Duration(seconds: 3));
      
      if (ssid != null) {
        // إزالة علامات الاقتباس إذا وُجدت
        String cleaned = ssid.replaceAll('"', '').trim();
        print('[WiFiService] 📶 WiFi Name: $cleaned');
        return cleaned;
      }
      return null;
    } catch (e) {
      print('[WiFiService] ⚠️ Error getting WiFi name: $e');
      return null;
    }
  }

  /// Check if connected to WiFi
  Future<bool> isConnectedToWifi() async {
    final bssid = await getWifiBSSID();
    return bssid != null && bssid.isNotEmpty && bssid != '<unknown ssid>';
  }

  /// Normalize BSSID format (uppercase, remove special chars if needed)
  String _normalizeBSSID(String bssid) {
    // تحويل لـ uppercase
    String normalized = bssid.toUpperCase().trim();
    
    // إزالة any weird characters
    normalized = normalized.replaceAll(RegExp(r'[^A-F0-9:]'), '');
    
    // التأكد من الصيغة الصحيحة (XX:XX:XX:XX:XX:XX)
    if (!RegExp(r'^[A-F0-9]{2}(:[A-F0-9]{2}){5}$').hasMatch(normalized)) {
      print('[WiFiService] ⚠️ Unusual BSSID format: $normalized');
    }
    
    return normalized;
  }

  /// Compare two BSSIDs (handles format differences)
  bool compareBSSIDs(String? bssid1, String? bssid2) {
    if (bssid1 == null || bssid2 == null) return false;
    
    final normalized1 = _normalizeBSSID(bssid1);
    final normalized2 = _normalizeBSSID(bssid2);
    
    return normalized1 == normalized2;
  }

  /// Clear cache to force fresh BSSID
  static void clearCache() {
    _lastKnownBSSID = null;
    _lastBSSIDTime = null;
    print('[WiFiService] 🗑️ Cache cleared');
  }

  /// Get connection info (for debugging)
  Future<Map<String, String?>> getConnectionInfo() async {
    try {
      final bssid = await getWifiBSSID();
      final ssid = await getWifiName();
      final ip = await _networkInfo.getWifiIP();
      
      return {
        'bssid': bssid,
        'ssid': ssid,
        'ip': ip,
      };
    } catch (e) {
      print('[WiFiService] ❌ Error getting connection info: $e');
      return {};
    }
  }
}
