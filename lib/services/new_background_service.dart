import 'dart:convert';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:http/http.dart' as http;
import '../constants/api_endpoints.dart';

class NewBackgroundService {
  static final NewBackgroundService instance = NewBackgroundService._init();
  NewBackgroundService._init();

  String _employeeId = '';

  Future<void> init(String employeeId) async {
    _employeeId = employeeId;

    // 1. إعداد مستمعين الأحداث (Listeners)
    _setupListeners();

    // 2. تهيئة المكتبة
    bg.BackgroundGeolocation.ready(bg.Config(
      desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
      distanceFilter: 10.0, // إرسال تحديث كل 10 أمتار
      stopOnTerminate: false,
      startOnBoot: false,
      enableHeadless: true,
      logLevel: bg.Config.LOG_LEVEL_VERBOSE,
      autoSync: true,

      // إعدادات إرسال البيانات (Pulses)
      url: '$apiBaseUrl/pulses', // <-- Endpoint استقبال الـ Pulses
      httpRootProperty: '.',
      locationTemplate: '''{
          "latitude": <%= latitude %>,
          "longitude": <%= longitude %>,
          "wifi_bssid": "${await _getWifiBSSID()}",
          "employee_id": "$_employeeId",
          "timestamp": "<%= timestamp %>"
      }''',
      headers: {
        'Content-Type': 'application/json'
      },
      params: {
        // أي بيانات ثابتة تريد إرسالها
      },
    )).then((bg.State state) {
      if (!state.enabled) {
        print("[bg_service] BackgroundGeolocation مُهيأ ولكنه متوقف.");
      } else {
        print("[bg_service] BackgroundGeolocation بدأ ويعمل.");
      }
    }).catchError((error) {
      print('[bg_service] خطأ في تهيئة BackgroundGeolocation: $error');
    });
  }

  void _setupListeners() {
    // مستمع إرسال النبضات (Pulses)
    bg.BackgroundGeolocation.onLocation((bg.Location location) {
      print('[onLocation] $location');
      // لا نحتاج لإرسالها يدوياً، المكتبة ترسلها تلقائياً للـ 'url'
    });

    // مستمع الدخول والخروج من النطاق (Geofence)
    bg.BackgroundGeolocation.onGeofence((bg.GeofenceEvent event) {
      print('[onGeofence] $event');
      // هنا نرسل تنبيه الخروج/الدخول للسيرفر
      _reportGeofenceViolation(event);
    });
  }

  // دالة بدء التتبع (تُستدعى عند تسجيل الحضور)
  Future<void> startTracking(Map<String, dynamic> branchData, List<String> allowedBssids) async {
    final branchLat = branchData['latitude'] as double?;
    final branchLng = branchData['longitude'] as double?;
    final branchRadius = (branchData['geofence_radius'] as int?)?.toDouble() ?? 200.0;

    if (branchLat == null || branchLng == null) {
      print('[bg_service] لا يمكن بدء التتبع، إحداثيات الفرع غير موجودة.');
      return;
    }

    // 1. حذف أي Geofence قديم
    await bg.BackgroundGeolocation.removeGeofences();

    // 2. إضافة الـ Geofence الخاص بالفرع
    await bg.BackgroundGeolocation.addGeofence(bg.Geofence(
      identifier: "BRANCH_${branchData['id']}",
      radius: branchRadius,
      latitude: branchLat,
      longitude: branchLng,
      notifyOnEntry: true,
      notifyOnExit: true,
      notifyOnDwell: false,
      loiteringDelay: 30000, // (اختياري)
    ));

    // 3. (اختياري) يمكنك إضافة Geofence للواي فاي إذا أردت
    // (هذا يتطلب إعدادات إضافية)

    // 4. بدء التتبع
    try {
      await bg.BackgroundGeolocation.start();
      print('[bg_service] تم بدء التتبع بنجاح.');
    } catch (e) {
      print('[bg_service] خطأ عند بدء التتبع: $e');
    }
  }

  // دالة إيقاف التتبع (تُستدعى عند تسجيل الانصراف)
  Future<void> stopTracking() async {
    try {
      await bg.BackgroundGeolocation.removeGeofences();
      await bg.BackgroundGeolocation.stop();
      print('[bg_service] تم إيقاف التتبع.');
    } catch (e) {
      print('[bg_service] خطأ عند إيقاف التتبع: $e');
    }
  }

  // دالة إرسال تنبيه الخروج/الدخول (للنقطة رقم 6)
  Future<void> _reportGeofenceViolation(bg.GeofenceEvent event) async {
    try {
      await http.post(
        Uri.parse('$apiBaseUrl/alerts/geofence-violation'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'employeeId': _employeeId,
          'timestamp': DateTime.now().toIso8601String(),
          'latitude': event.location.coords.latitude,
          'longitude': event.location.coords.longitude,
          'action': event.action, // "ENTER" or "EXIT"
          'geofenceId': event.identifier,
        }),
      );
    } catch (e) {
      print('[bg_service] فشل إرسال تنبيه الخروج/الدخول: $e');
      // (هنا يجب تخزينها في OfflineDatabase لإعادة إرسالها لاحقاً)
    }
  }

  // دالة مساعدة لجلب الواي فاي (غير متوفرة مباشرة في المكتبة)
  static Future<String> _getWifiBSSID() async {
    // لا يمكن استدعاء NetworkInfo هنا مباشرة (لأنه في Isolate مختلف)
    // الحل الأفضل هو إرسالها كـ 'params' عند بدء التشغيل
    // ولكن للتبسيط، سنتركها فارغة الآن
    return "";
  }
}