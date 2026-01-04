import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_io/io.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'models/employee.dart';
import 'models/employee_adjustment.dart';
import 'models/pulse.dart';
import 'models/pulse_log_entry.dart';
import 'models/leave_request.dart';
import 'models/advance_request.dart';
import 'models/attendance_request.dart';
import 'screens/admin_dashboard_page.dart';
import 'screens/home_screen.dart';
import 'screens/employee/employee_main_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/pulse_backend_client.dart';
import 'services/pulse_sync_manager.dart';
import 'services/workmanager_pulse_service.dart';
import 'services/foreground_attendance_service.dart';
import 'services/pulse_tracking_service.dart';
import 'services/notification_service.dart';
import 'services/auth_service.dart';
import 'services/supabase_attendance_service.dart';
import 'services/aggressive_keep_alive_service.dart';
import 'services/alarm_manager_pulse_service.dart';
import 'theme/app_colors.dart';
import 'config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Critical Crash Prevention
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };
  
  PlatformDispatcher.instance.onError = (error, stack) {
    return true; 
  };
  
  // 2. Initialize Database (Fastest first for offline support)
  await Hive.initFlutter();
  registerPulseAdapter();
  registerPulseLogEntryAdapter();
  registerEmployeeAdapter();
  registerAdjustmentAdapter();
  registerLeaveRequestAdapter();
  registerAdvanceRequestAdapter();
  registerAttendanceRequestAdapter();
  await Hive.openBox<Pulse>(offlinePulsesBox);
  await Hive.openBox<PulseLogEntry>(pulseHistoryBox);
  await Hive.openBox<Employee>(employeesBox);
  await Hive.openBox<EmployeeAdjustment>(employeeAdjustmentsBox);
  await Hive.openBox('branch_data');
  await Hive.openBox('local_attendance');
  await Hive.openBox('local_pulses');

  // 3. Initialize Core Infrastructure
  await SupabaseConfig.initialize();
  await PulseSyncManager.initializeForMainIsolate();
  await PulseBackendClient.initialize();
  await NotificationService.instance.initialize();

  // 4. ✅ ANDROID 11+ CHINESE DEVICE OPTIMIZATION (THE BEAST MODE)
  if (!kIsWeb && Platform.isAndroid) {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final manufacturer = androidInfo.manufacturer.toLowerCase();
    final sdkInt = androidInfo.version.sdkInt;
    
    print('🚀 System Info: $manufacturer on Android $sdkInt');

    // Request Critical Permissions immediately
    await [
      Permission.notification,
      Permission.locationAlways,
      Permission.ignoreBatteryOptimizations,
      Permission.scheduleExactAlarm,
    ].request();

    // Initialize Persistent Services
    await ForegroundAttendanceService.initialize();
    await AggressiveKeepAliveService().initialize();
    
    // Start Alarm Manager (Resurrector)
    final alarmService = AlarmManagerPulseService();
    if (alarmService.isSupported) {
      await alarmService.initialize();
    }

    // WorkManager as the 3rd layer of defense
    await WorkManagerPulseService.initialize();
  }
  
  // 5. Auto-Resume Logic (Offline-First)
  try {
    final login = await AuthService.getLoginData();
    final employeeId = login['employeeId'];
    if (employeeId != null && employeeId.isNotEmpty) {
      final activeAttendance = await SupabaseAttendanceService.getActiveAttendance(employeeId);
      if (activeAttendance != null) {
        final attendanceId = activeAttendance['id'] as String?;
        await PulseTrackingService().startTracking(employeeId, attendanceId: attendanceId);
        
        if (!kIsWeb && Platform.isAndroid) {
          await ForegroundAttendanceService.instance.startTracking(
            employeeId: employeeId,
            employeeName: login['fullName'] ?? 'الموظف',
          );
        }
      }
    }
  } catch (e) {
    print('⚠️ Resume Error: $e');
  }

  runApp(const OldiesApp());
}

class OldiesApp extends StatelessWidget {
  const OldiesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryOrange),
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
    );

    final theme = baseTheme.copyWith(
      textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(baseTheme.textTheme),
      primaryTextTheme: GoogleFonts.ibmPlexSansArabicTextTheme(baseTheme.primaryTextTheme),
      colorScheme: baseTheme.colorScheme,
      appBarTheme: baseTheme.appBarTheme.copyWith(
        titleTextStyle: GoogleFonts.ibmPlexSansArabic(
          textStyle: baseTheme.textTheme.titleLarge?.copyWith(
            color: baseTheme.colorScheme.onPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    return MaterialApp(
      title: 'أولديزز وركرز',
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG'), Locale('ar')],
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink());
      },
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      initialRoute: SplashScreen.routeName,
      routes: {
        SplashScreen.routeName: (_) => const SplashScreen(),
        LoginScreen.routeName: (_) => LoginScreen(),
        AdminDashboardPage.routeName: (_) => const AdminDashboardPage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == HomeScreen.routeName) {
          final employeeId = settings.arguments as String?;
          return MaterialPageRoute(builder: (_) => HomeScreen(employeeId: employeeId ?? ''));
        }
        if (settings.name == EmployeeMainScreen.routeName) {
          final employeeId = settings.arguments as String?;
          return MaterialPageRoute(builder: (_) => EmployeeMainScreen(employeeId: employeeId ?? ''));
        }
        return null;
      },
    );
  }
}
