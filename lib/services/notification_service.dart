import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../database/offline_database.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._init();
  NotificationService._init();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;

    // Request permissions on Android 13+
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    
    // Request permissions on iOS
    await _notifications
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap
    print('[NotificationService] Notification tapped: ${response.payload}');
  }

  // Show geofence violation notification
  Future<void> showGeofenceViolation({
    required String employeeName,
    required String message,
  }) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      'geofence_channel',
      'تنبيهات الموقع',
      channelDescription: 'تنبيهات عند الخروج من المكان',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      1, // Notification ID
      '⚠️ تحذير: خارج المكان',
      message,
      details,
      payload: 'geofence_violation',
    );
  }

  // Show offline mode notification
  Future<void> showOfflineModeNotification() async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      'offline_channel',
      'وضع عدم الاتصال',
      channelDescription: 'تنبيهات عند حفظ البيانات محلياً',
      importance: Importance.low,
      priority: Priority.low,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      2,
      '📴 وضع عدم الاتصال',
      'تم حفظ البيانات محلياً. سيتم الرفع عند توفر الإنترنت.',
      details,
    );
  }

  // Show sync success notification
  Future<void> showSyncSuccessNotification(int count) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      'sync_channel',
      'المزامنة',
      channelDescription: 'تنبيهات عند رفع البيانات',
      importance: Importance.low,
      priority: Priority.low,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      3,
      '✅ تم الرفع بنجاح',
      'تم رفع $count سجل إلى الخادم',
      details,
    );
  }

  // Show pending data notification
  Future<void> showPendingDataNotification() async {
    await initialize();

    final db = OfflineDatabase.instance;
    final pendingCount = await db.getPendingCount();

    if (pendingCount == 0) return;

    const androidDetails = AndroidNotificationDetails(
      'pending_channel',
      'بيانات معلقة',
      channelDescription: 'تنبيهات للبيانات التي لم يتم رفعها',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true, // Make it persistent
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      4,
      '📤 بيانات في انتظار الرفع',
      'لديك $pendingCount سجل لم يتم رفعه. اتصل بالإنترنت.',
      details,
    );
  }

  // Cancel specific notification
  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  // Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }
}
