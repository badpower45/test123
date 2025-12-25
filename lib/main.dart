import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_io/io.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

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
  
  // Global error handler to prevent app crashes
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    print('❌ [FlutterError] ${details.exception}');
    print('   Stack: ${details.stack}');
  };
  
  // Handle errors from async operations
  PlatformDispatcher.instance.onError = (error, stack) {
    print('❌ [PlatformDispatcher Error] $error');
    print('   Stack: $stack');
    return true; // Return true to prevent app from crashing
  };
  
  // Set custom error widget builder
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      child: Container(
        color: Colors.white,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'حدث خطأ في التطبيق',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  details.exception.toString(),
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };
  
  // Initialize Supabase
  await SupabaseConfig.initialize();
  
  // Initialize WorkManager for background pulses (mobile only)
  if (!kIsWeb && Platform.isAndroid) {
    await WorkManagerPulseService.initialize();
    print('✅ WorkManager initialized for background pulse tracking');
    
    // Initialize foreground service for keeping app alive
    await ForegroundAttendanceService.initialize();
    print('✅ Foreground attendance service initialized');
    
    // ✅ V2: Initialize aggressive keep-alive service for old devices
    await AggressiveKeepAliveService().initialize();
    print('✅ Aggressive keep-alive service initialized');
    
    // ✅ V2: Initialize AlarmManager for backup pulses
    final alarmService = AlarmManagerPulseService();
    if (alarmService.isSupported) {
      await alarmService.initialize();
      await alarmService.requestExactAlarmPermission();
      print('✅ AlarmManager initialized for backup pulses');
    }
  }
  
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
  // Open branch data box for offline support
  await Hive.openBox('branch_data');
  await Hive.openBox('local_attendance');
  await Hive.openBox('local_pulses');
  await PulseSyncManager.initializeForMainIsolate();
  await PulseBackendClient.initialize();
  if (!kIsWeb && Platform.isAndroid) {
    final status = await Permission.notification.status;
    if (!status.isGranted && !status.isLimited) {
      await Permission.notification.request();
    }
  }
  // Initialize the new background service when needed
  // Auto-resume tracking if an active attendance exists
  try {
    final login = await AuthService.getLoginData();
    final employeeId = login['employeeId'];
    if (employeeId != null && employeeId.isNotEmpty) {
      final activeAttendance = await SupabaseAttendanceService.getActiveAttendance(employeeId);
      if (activeAttendance != null) {
        final attendanceId = activeAttendance['id'] as String?;
        // Initialize notifications to ensure permission and channels are ready
        await NotificationService.instance.initialize();
        // Start pulse tracking immediately
        await PulseTrackingService().startTracking(employeeId, attendanceId: attendanceId);
        // Ensure foreground service is running (Android)
        if (!kIsWeb && Platform.isAndroid) {
          await ForegroundAttendanceService.instance.ensureServiceRunning(
            employeeId: employeeId,
            employeeName: login['fullName'] ?? 'الموظف',
          );
        }
        print('✅ Auto-resumed tracking for active attendance at app start');
      }
    }
  } catch (e) {
    print('⚠️ Failed to auto-resume tracking on app start: $e');
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
      primaryTextTheme:
          GoogleFonts.ibmPlexSansArabicTextTheme(baseTheme.primaryTextTheme),
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
      supportedLocales: const [
        Locale('ar', 'EG'),
        Locale('ar'),
      ],
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        return const Locale('ar', 'EG');
      },
      localeListResolutionCallback: (deviceLocales, supportedLocales) {
        return const Locale('ar', 'EG');
      },
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
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
          if (employeeId == null) {
            return MaterialPageRoute(
              builder: (_) => const SplashScreen(),
              settings: settings,
            );
          }
          return MaterialPageRoute(
            builder: (_) => HomeScreen(employeeId: employeeId),
            settings: settings,
          );
        }
        if (settings.name == EmployeeMainScreen.routeName) {
          final employeeId = settings.arguments as String?;
          if (employeeId == null) {
            return MaterialPageRoute(
              builder: (_) => const SplashScreen(),
              settings: settings,
            );
          }
          return MaterialPageRoute(
            builder: (_) => EmployeeMainScreen(employeeId: employeeId),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}

