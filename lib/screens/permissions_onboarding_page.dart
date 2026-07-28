import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:universal_io/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../theme/app_colors.dart';

class PermissionsOnboardingPage extends StatefulWidget {
  final Widget nextScreen;

  const PermissionsOnboardingPage({super.key, required this.nextScreen});

  @override
  State<PermissionsOnboardingPage> createState() => _PermissionsOnboardingPageState();
}

class _PermissionsOnboardingPageState extends State<PermissionsOnboardingPage> with WidgetsBindingObserver {
  bool _notificationGranted = false;
  bool _locationInUseGranted = false;
  bool _locationAlwaysGranted = false;
  bool _activityRecognitionGranted = false;
  bool _exactAlarmGranted = false;
  bool _batteryOptExempted = false;
  bool _wifiEnabled = false;
  bool _overlayGranted = false;

  bool _isLoading = true;

  // New Live GPS Verification States
  bool _isCheckingGps = false;
  Position? _currentGpsPosition;
  double? _gpsAccuracy;
  String _gpsError = '';
  StreamSubscription<Position>? _positionStreamSubscription;

  // Chinese ROM states
  String _manufacturer = '';
  bool _isChineseDevice = false;
  bool _autoStartConfirmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detectDevice();
    _checkAllPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopLiveGpsTracking();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllPermissions();
    }
  }

  Future<void> _detectDevice() async {
    if (Platform.isAndroid) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final manufacturer = androidInfo.manufacturer.toLowerCase();
        
        bool isChinese = manufacturer.contains('xiaomi') ||
            manufacturer.contains('redmi') ||
            manufacturer.contains('poco') ||
            manufacturer.contains('oppo') ||
            manufacturer.contains('realme') ||
            manufacturer.contains('vivo') ||
            manufacturer.contains('huawei') ||
            manufacturer.contains('honor') ||
            manufacturer.contains('oneplus') ||
            manufacturer.contains('infinix') ||
            manufacturer.contains('tecno') ||
            manufacturer.contains('meizu');

        setState(() {
          _manufacturer = androidInfo.manufacturer;
          _isChineseDevice = isChinese;
        });
      } catch (e) {
        print('Error detecting device: $e');
      }
    }
  }

  void _startLiveGpsTracking() {
    if (_positionStreamSubscription != null) return;
    if (!_locationInUseGranted) return;

    setState(() {
      _isCheckingGps = true;
      _gpsError = '';
    });

    late final LocationSettings locationSettings;
    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 3),
      );
    } else if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    }

    try {
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          if (!mounted) return;
          setState(() {
            _currentGpsPosition = position;
            _gpsAccuracy = position.accuracy;
            _isCheckingGps = false;
            _gpsError = '';
          });
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _isCheckingGps = false;
            _gpsError = e.toString();
          });
        },
      );
    } catch (e) {
      setState(() {
        _isCheckingGps = false;
        _gpsError = e.toString();
      });
    }
  }

  void _stopLiveGpsTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
  }

  Future<void> _checkAllPermissions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final locationStatus = await Geolocator.checkPermission();
      
      bool inUseOk = locationStatus == LocationPermission.always || locationStatus == LocationPermission.whileInUse;
      bool alwaysOk = locationStatus == LocationPermission.always;
      
      bool notifOk = true;
      bool activityOk = true;
      bool exactAlarmOk = true;
      bool batteryOk = true;
      bool wifiOk = true;
      bool overlayOk = true;

      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        if (sdkInt >= 33) {
          final notifStatus = await Permission.notification.status;
          notifOk = notifStatus.isGranted;
        } else {
          notifOk = true;
        }

        if (sdkInt >= 29) {
          final activityStatus = await Permission.activityRecognition.status;
          activityOk = activityStatus.isGranted;
        } else {
          activityOk = true;
        }

        if (sdkInt >= 31) {
          final exactAlarmStatus = await Permission.scheduleExactAlarm.status;
          exactAlarmOk = exactAlarmStatus.isGranted;
        } else {
          exactAlarmOk = true;
        }

        final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
        batteryOk = batteryStatus.isGranted;

        final overlayStatus = await Permission.systemAlertWindow.status;
        overlayOk = overlayStatus.isGranted;

        try {
          final canStart = await WiFiScan.instance.canStartScan(askPermissions: false);
          wifiOk = canStart != CanStartScan.failed && canStart != CanStartScan.notSupported;
        } catch (e) {
          wifiOk = false;
        }
      } else if (Platform.isIOS) {
        final notifStatus = await Permission.notification.status;
        notifOk = notifStatus.isGranted;
      }

      if (mounted) {
        setState(() {
          _notificationGranted = notifOk;
          _locationInUseGranted = inUseOk;
          _locationAlwaysGranted = alwaysOk;
          _activityRecognitionGranted = activityOk;
          _exactAlarmGranted = exactAlarmOk;
          _batteryOptExempted = batteryOk;
          _wifiEnabled = wifiOk;
          _overlayGranted = overlayOk;
          _isLoading = false;
        });

        if (inUseOk) {
          _startLiveGpsTracking();
        } else {
          _stopLiveGpsTracking();
        }
      }
    } catch (e) {
      print('⚠️ Error checking permissions: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _isAllCriticalGranted {
    bool hasAllPerms = false;
    if (Platform.isAndroid) {
      hasAllPerms = _notificationGranted &&
          _locationInUseGranted &&
          _locationAlwaysGranted &&
          _activityRecognitionGranted &&
          _exactAlarmGranted &&
          _batteryOptExempted &&
          _wifiEnabled &&
          _overlayGranted;
    } else {
      hasAllPerms = _notificationGranted && _locationInUseGranted && _locationAlwaysGranted;
    }

    final hasPreciseLocation = _currentGpsPosition != null &&
        _gpsAccuracy != null &&
        _gpsAccuracy! <= 20.0;

    final autoStartOk = !_isChineseDevice || _autoStartConfirmed;

    return hasAllPerms && hasPreciseLocation && autoStartOk;
  }

  Future<void> _requestNotification() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt < 33) {
        setState(() {
          _notificationGranted = true;
        });
        return;
      }
    }
    final status = await Permission.notification.request();
    setState(() {
      _notificationGranted = status.isGranted;
    });
    if (status.isPermanentlyDenied) {
      _showSettingsDialog('صلاحية الإشعارات مطلوبة لتشغيل الخدمة في الخلفية بشكل صحيح.');
    }
  }

  Future<void> _requestLocationInUse() async {
    // Check service first
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    final status = await Geolocator.requestPermission();
    setState(() {
      _locationInUseGranted = status == LocationPermission.always || status == LocationPermission.whileInUse;
      _locationAlwaysGranted = status == LocationPermission.always;
    });

    if (status == LocationPermission.deniedForever) {
      _showSettingsDialog('صلاحية الموقع الدقيق مطلوبة للتحقق من وجودك بالفرع.');
    }
  }

  Future<void> _requestLocationAlways() async {
    if (!_locationInUseGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تفعيل الموقع الدقيق أولاً قبل تفعيل الموقع طوال الوقت.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final status = await Permission.locationAlways.request();
    setState(() {
      _locationAlwaysGranted = status.isGranted;
    });

    if (status.isPermanentlyDenied) {
      _showSettingsDialog('يرجى اختيار "السماح طوال الوقت" (Allow all the time) من إعدادات موقع التطبيق.');
    }
  }

  Future<void> _requestActivityRecognition() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt < 29) {
        setState(() {
          _activityRecognitionGranted = true;
        });
        return;
      }
    }
    final status = await Permission.activityRecognition.request();
    setState(() {
      _activityRecognitionGranted = status.isGranted;
    });
  }

  Future<void> _requestExactAlarm() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt < 31) {
        setState(() {
          _exactAlarmGranted = true;
        });
        return;
      }
    }
    final status = await Permission.scheduleExactAlarm.request();
    setState(() {
      _exactAlarmGranted = status.isGranted;
    });
    if (status.isPermanentlyDenied) {
      _showSettingsDialog('صلاحية المنبهات الدقيقة مطلوبة لإبقاء النظام حياً بانتظام.');
    }
  }

  Future<void> _requestBatteryOptimizations() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    setState(() {
      _batteryOptExempted = status.isGranted;
    });
    if (!status.isGranted) {
      // Direct intent fallback
      await openAppSettings();
    }
  }

  Future<void> _requestOverlay() async {
    final status = await Permission.systemAlertWindow.request();
    setState(() {
      _overlayGranted = status.isGranted;
    });
    if (!status.isGranted) {
      await openAppSettings();
    }
  }

  void _showSettingsDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('💡 صلاحية مطلوبة', textAlign: TextAlign.right),
        content: Text(message, textAlign: TextAlign.right),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
            child: const Text('فتح الإعدادات'),
          ),
        ],
      ),
    );
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_onboarding_completed', true);
    
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => widget.nextScreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
          : SafeArea(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.primaryOrange.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.security_rounded,
                              color: AppColors.primaryOrange,
                              size: 48,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'صلاحيات تتبع الحضور والموقع',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.tajawal(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'يحتاج التطبيق للصلاحيات التالية للعمل بكفاءة 100% في الخلفية وضمان احتساب وقت عملك بدقة دون توقف.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.tajawal(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildPermissionCard(
                          icon: Icons.notifications_active_rounded,
                          title: 'صلاحية الإشعارات (POST_NOTIFICATIONS)',
                          desc: 'إجبارية لتشغيل خدمة الحضور كخدمة واجهة مستمرة صامتة تمنع النظام من إيقاف التطبيق.',
                          isGranted: _notificationGranted,
                          onRequest: _requestNotification,
                        ),
                        _buildPermissionCard(
                          icon: Icons.my_location_rounded,
                          title: 'الموقع الدقيق (Precise Location)',
                          desc: 'تحديد موقعك الجغرافي بشكل صحيح داخل الفرع. يرجى اختيار "دقيق" (Precise) وليس "تقريبي".',
                          isGranted: _locationInUseGranted,
                          onRequest: _requestLocationInUse,
                        ),
                        _buildPermissionCard(
                          icon: Icons.location_searching_rounded,
                          title: 'الموقع في الخلفية (Background Location)',
                          desc: 'يُرجى تحديد خيار "السماح طوال الوقت" (Allow all the time) لتتبع حضورك عند إغلاق الشاشة.',
                          isGranted: _locationAlwaysGranted,
                          onRequest: _requestLocationAlways,
                        ),
                        if (isAndroid) ...[
                          _buildPermissionCard(
                            icon: Icons.directions_run_rounded,
                            title: 'التعرف على النشاط الحركي (Activity)',
                            desc: 'توفير استهلاك بطارية الهاتف عن طريق تقليل فحص الموقع عندما تكون ثابتاً في مكانك.',
                            isGranted: _activityRecognitionGranted,
                            onRequest: _requestActivityRecognition,
                          ),
                          _buildPermissionCard(
                            icon: Icons.alarm_rounded,
                            title: 'المنبهات الدقيقة (Exact Alarm)',
                            desc: 'ضمان إيقاظ الخدمة كل 5 دقائق بشكل دوري لإرسال النبضات وإثبات وجودك.',
                            isGranted: _exactAlarmGranted,
                            onRequest: _requestExactAlarm,
                          ),
                          _buildPermissionCard(
                            icon: Icons.battery_saver_rounded,
                            title: 'تجاهل تحسين البطارية (Battery Optimization)',
                            desc: 'تجنب قيود توفير الطاقة الشديدة في الهواتف مثل Samsung و Xiaomi لضمان عدم توقف النظام.',
                            isGranted: _batteryOptExempted,
                            onRequest: _requestBatteryOptimizations,
                          ),
                          _buildPermissionCard(
                            icon: Icons.wifi,
                            title: 'تفعيل الواي فاي (Wi-Fi Enabled)',
                            desc: 'يرجى تفعيل الواي فاي لتعزيز قراءة الموقع الجغرافي وتفادي القراءات الخاطئة.',
                            isGranted: _wifiEnabled,
                            onRequest: () async {
                              await openAppSettings();
                            },
                          ),
                          _buildPermissionCard(
                            icon: Icons.layers_rounded,
                            title: 'الظهور فوق التطبيقات (Overlay)',
                            desc: 'تجنب إغلاق نظام الأندرويد للتطبيق تلقائياً، وتأمين تشغيل الخدمات واستعادتها بنجاح.',
                            isGranted: _overlayGranted,
                            onRequest: _requestOverlay,
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (isAndroid) ...[
                          _buildLockAppGuideCard(),
                          const SizedBox(height: 16),
                        ],
                        _buildGpsVerificationCard(),
                        if (_isChineseDevice) ...[
                          const SizedBox(height: 16),
                          _buildChineseDeviceCard(),
                        ],
                      ]),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!_isAllCriticalGranted)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.info_outline, color: AppColors.warning, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'يرجى تفعيل كافة الصلاحيات، والحصول على دقة GPS أقل من 20 متر، وتأكيد التشغيل التلقائي لتفعيل زر المتابعة',
                                      style: GoogleFonts.tajawal(
                                        fontSize: 12,
                                        color: AppColors.warning,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isAllCriticalGranted ? _finishOnboarding : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryOrange,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: AppColors.textTertiary.withOpacity(0.3),
                                disabledForegroundColor: AppColors.textTertiary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                'متابعة ودخول التطبيق',
                                style: GoogleFonts.tajawal(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildGpsVerificationCard() {
    final hasPreciseLocation = _currentGpsPosition != null &&
        _gpsAccuracy != null &&
        _gpsAccuracy! <= 20.0;

    Color cardBorderColor = Colors.transparent;
    Color iconBgColor = AppColors.primaryOrange.withOpacity(0.08);
    Color iconColor = AppColors.primaryOrange;
    IconData icon = Icons.gps_not_fixed_rounded;
    String statusTitle = 'فحص دقة الموقع الجغرافي (GPS Check)';
    String statusBody = 'لم يتم الفحص بعد. يرجى تفعيل صلاحية الموقع الدقيق للبدء.';
    Widget? extraWidget;

    if (!_locationInUseGranted) {
      statusBody = 'يرجى تفعيل صلاحية الموقع الدقيق أولاً للبدء بالفحص الجغرافي.';
    } else if (_isCheckingGps && _currentGpsPosition == null) {
      icon = Icons.gps_fixed_rounded;
      statusBody = 'جاري تحديد موقعك الجغرافي الدقيق... الرجاء الانتظار.';
      extraWidget = const Padding(
        padding: EdgeInsets.only(top: 8.0),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryOrange),
        ),
      );
    } else if (_gpsError.isNotEmpty) {
      cardBorderColor = AppColors.danger.withOpacity(0.3);
      iconBgColor = AppColors.danger.withOpacity(0.1);
      iconColor = AppColors.danger;
      icon = Icons.gps_off_rounded;
      statusBody = 'خطأ في جلب الموقع: $_gpsError. يرجى التأكد من تفعيل خدمة الـ GPS على الهاتف.';
    } else if (_currentGpsPosition != null && _gpsAccuracy != null) {
      if (hasPreciseLocation) {
        cardBorderColor = AppColors.success.withOpacity(0.3);
        iconBgColor = AppColors.success.withOpacity(0.1);
        iconColor = AppColors.success;
        icon = Icons.gps_fixed_rounded;
        statusBody = 'تم تحديد موقعك بدقة عالية!\n'
            'خط العرض: ${_currentGpsPosition!.latitude.toStringAsFixed(6)}\n'
            'خط الطول: ${_currentGpsPosition!.longitude.toStringAsFixed(6)}\n'
            'الدقة: ${_gpsAccuracy!.toStringAsFixed(1)} متر ✅';
      } else {
        cardBorderColor = AppColors.warning.withOpacity(0.3);
        iconBgColor = AppColors.warning.withOpacity(0.1);
        iconColor = AppColors.warning;
        icon = Icons.gps_not_fixed_rounded;
        statusBody = 'موقعك الحالي تقريبي.\n'
            'الدقة الحالية: ${_gpsAccuracy!.toStringAsFixed(1)} متر.\n'
            'يرجى البقاء في مكان مفتوح لتحقيق دقة أفضل من 20 متر (المطلوب للدخول).';
        extraWidget = const Padding(
          padding: EdgeInsets.only(top: 8.0),
          child: SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.warning),
          ),
        );
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: cardBorderColor,
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusTitle,
                  style: GoogleFonts.tajawal(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  statusBody,
                  style: GoogleFonts.tajawal(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                if (extraWidget != null) extraWidget,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChineseDeviceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: _autoStartConfirmed ? AppColors.success.withOpacity(0.3) : AppColors.warning.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.warning,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إعدادات التشغيل التلقائي ($_manufacturer)',
                      style: GoogleFonts.tajawal(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'يتطلب هاتف $_manufacturer تمكين خيار "التشغيل التلقائي" (Auto-Start) وتعطيل قيود البطارية لضمان عمل التطبيق في الخلفية واحتساب ساعات العمل بشكل صحيح دون توقف.',
                      style: GoogleFonts.tajawal(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: openAppSettings,
            icon: const Icon(Icons.settings, size: 18),
            label: Text(
              'فتح إعدادات التطبيق وتفعيل التشغيل التلقائي',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange.withOpacity(0.1),
              foregroundColor: AppColors.primaryOrange,
              elevation: 0,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            title: Text(
              'لقد قمت بتفعيل خيار التشغيل التلقائي في إعدادات الهاتف بشكل صحيح',
              style: GoogleFonts.tajawal(fontSize: 12.5, color: AppColors.textPrimary),
            ),
            value: _autoStartConfirmed,
            onChanged: (val) {
              setState(() {
                _autoStartConfirmed = val ?? false;
              });
            },
            activeColor: AppColors.primaryOrange,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    );
  }

  Widget _buildLockAppGuideCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryOrange.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryOrange.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.lock_person_rounded,
              color: AppColors.primaryOrange,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💡 حماية التطبيق من الإغلاق بالخلفية',
                  style: GoogleFonts.tajawal(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'لمنع نظام الهاتف من إغلاق التطبيق نهائياً عند مسح الرام أو سحبه بالخطأ:\n'
                  '1. افتح شاشة التطبيقات الحديثة (Recent Apps).\n'
                  '2. اضغط مطولاً على أيقونة التطبيق (أو اسحب لأسفل).\n'
                  '3. اضغط على رمز "القفل" (Lock) ليظل نشطاً للأبد.',
                  style: GoogleFonts.tajawal(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String desc,
    required bool isGranted,
    required VoidCallback onRequest,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isGranted ? AppColors.success.withOpacity(0.3) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isGranted ? AppColors.success.withOpacity(0.1) : AppColors.primaryOrange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isGranted ? AppColors.success : AppColors.primaryOrange,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.tajawal(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  desc,
                  style: GoogleFonts.tajawal(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isGranted)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Icon(Icons.check_circle, color: AppColors.success, size: 28),
            )
          else
            ElevatedButton(
              onPressed: onRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange.withOpacity(0.12),
                foregroundColor: AppColors.primaryOrange,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'تفعيل',
                style: GoogleFonts.tajawal(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
