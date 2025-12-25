import 'dart:io';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_logger.dart';

/// Service to handle device-specific compatibility issues
/// Especially for Chinese ROMs like Realme (ColorOS), Oppo, Xiaomi (MIUI), etc.
class DeviceCompatibilityService {
  static final DeviceCompatibilityService instance = DeviceCompatibilityService._();
  DeviceCompatibilityService._();

  String? _manufacturer;
  String? _model;
  int? _sdkVersion;
  bool _initialized = false;

  /// Initialize device info
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        _manufacturer = androidInfo.manufacturer.toLowerCase();
        _model = androidInfo.model;
        _sdkVersion = androidInfo.version.sdkInt;
        
        AppLogger.instance.log(
          'Device: $_manufacturer $_model, SDK: $_sdkVersion',
          tag: 'DeviceCompatibility',
        );
      }
      _initialized = true;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to get device info: $e',
        level: AppLogger.warning,
        tag: 'DeviceCompatibility',
      );
    }
  }

  /// Check if device is Realme (ColorOS)
  bool get isRealme => _manufacturer?.contains('realme') ?? false;

  /// Check if device is Oppo (ColorOS)
  bool get isOppo => _manufacturer?.contains('oppo') ?? false;

  /// Check if device is Xiaomi (MIUI)
  bool get isXiaomi {
    final m = _manufacturer;
    if (m == null) return false;
    return m.contains('xiaomi') || m.contains('redmi') || m.contains('poco');
  }

  /// Check if device is Huawei (EMUI)
  bool get isHuawei {
    final m = _manufacturer;
    if (m == null) return false;
    return m.contains('huawei') || m.contains('honor');
  }

  /// Check if device has ColorOS (Realme/Oppo)
  bool get hasColorOS => isRealme || isOppo;

  /// Check if device has restrictive battery management
  bool get hasRestrictiveBatteryManagement => 
    hasColorOS || isXiaomi || isHuawei;

  /// Get Android SDK version
  int get sdkVersion => _sdkVersion ?? 33;

  /// Check if POST_NOTIFICATIONS permission is required (Android 13+)
  bool get requiresNotificationPermission => sdkVersion >= 33;

  /// Get device-specific instructions for enabling permissions
  String getPermissionInstructions() {
    if (hasColorOS) {
      return '''
لتشغيل التطبيق بشكل صحيح على جهاز Realme/Oppo:

1️⃣ صلاحية الموقع:
   الإعدادات ← التطبيقات ← AT ← الأذونات ← الموقع ← "مسموح دائماً"

2️⃣ تعطيل تحسين البطارية:
   الإعدادات ← البطارية ← إدارة البطارية ← AT ← اختر "لا تُحسّن"

3️⃣ التشغيل التلقائي:
   الإعدادات ← التطبيقات ← إدارة التطبيقات ← AT ← تفعيل "التشغيل التلقائي"

4️⃣ قفل التطبيق في الخلفية:
   افتح التطبيقات الأخيرة ← اضغط مطولاً على AT ← اختر "قفل"

5️⃣ تأكد من تفعيل GPS:
   اسحب من الأعلى ← تأكد أن "الموقع/GPS" مفعل
''';
    } else if (isXiaomi) {
      return '''
لتشغيل التطبيق بشكل صحيح على جهاز Xiaomi:

1️⃣ صلاحية الموقع:
   الإعدادات ← التطبيقات ← الأذونات ← AT ← الموقع ← "مسموح دائماً"

2️⃣ تعطيل توفير البطارية:
   الإعدادات ← التطبيقات ← AT ← توفير البطارية ← "لا قيود"

3️⃣ التشغيل التلقائي:
   الإعدادات ← التطبيقات ← الأذونات ← التشغيل التلقائي ← تفعيل AT

4️⃣ تفعيل GPS
''';
    } else if (isHuawei) {
      return '''
لتشغيل التطبيق بشكل صحيح على جهاز Huawei:

1️⃣ صلاحية الموقع:
   الإعدادات ← التطبيقات ← AT ← الأذونات ← الموقع ← "مسموح دائماً"

2️⃣ إدارة التطبيقات المحمية:
   الإعدادات ← البطارية ← إطلاق التطبيقات ← AT ← إدارة يدوياً ← تفعيل كل الخيارات

3️⃣ تفعيل GPS
''';
    }

    return '''
لتشغيل التطبيق بشكل صحيح:

1️⃣ منح صلاحية الموقع "دائماً"
2️⃣ تعطيل تحسين البطارية للتطبيق
3️⃣ تفعيل GPS على الجهاز
''';
  }

  /// Show device-specific permission dialog
  Future<void> showPermissionGuideDialog(BuildContext context) async {
    await initialize();
    
    final instructions = getPermissionInstructions();
    final deviceName = hasColorOS 
        ? 'Realme/Oppo (ColorOS)'
        : isXiaomi 
            ? 'Xiaomi (MIUI)'
            : isHuawei 
                ? 'Huawei (EMUI)'
                : 'Android';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.settings, color: Colors.orange),
            const SizedBox(width: 10),
            Text('إعدادات $deviceName', style: const TextStyle(fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'جهازك يحتاج إعدادات خاصة لكي يعمل التطبيق بشكل صحيح:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              Text(instructions, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('فهمت'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('فتح الإعدادات'),
          ),
        ],
      ),
    );
  }

  /// Check and show warning if needed for BSSID issues
  Future<void> checkAndShowBssidWarning(BuildContext context, String errorCode) async {
    await initialize();
    
    String title;
    String message;

    switch (errorCode) {
      case 'LOCATION_SERVICE_DISABLED':
        title = 'GPS غير مفعل';
        message = '''
لقراءة معلومات الواي فاي، يجب تفعيل GPS على جهازك.

على Android 10 وما بعد، لا يمكن قراءة BSSID بدون GPS.

اسحب من أعلى الشاشة وتأكد من تفعيل "الموقع" أو "GPS".
''';
        break;
      
      case 'BSSID_PLACEHOLDER':
        title = 'لم يتمكن الجهاز من قراءة WiFi';
        message = hasColorOS
            ? '''
أجهزة Realme/Oppo تحتاج إعدادات خاصة:

1. تفعيل GPS
2. في الإعدادات ← التطبيقات ← AT ← الأذونات ← الموقع ← اختر "مسموح دائماً" (وليس فقط أثناء الاستخدام)
3. افصل الواي فاي وأعد الاتصال
4. أعد تشغيل التطبيق
'''
            : '''
حاول الخطوات التالية:
1. تأكد من تفعيل GPS
2. اذهب للإعدادات وأعطِ التطبيق صلاحية الموقع "دائماً"
3. افصل الواي فاي وأعد الاتصال
4. أعد تشغيل التطبيق
''';
        break;
      
      default:
        title = 'مشكلة في قراءة WiFi';
        message = 'تأكد من تفعيل GPS ومنح صلاحية الموقع للتطبيق.';
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(message, style: const TextStyle(fontSize: 14)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('فتح الإعدادات'),
          ),
        ],
      ),
    );
  }
}
