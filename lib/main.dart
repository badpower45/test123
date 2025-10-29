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
import 'theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  await PulseSyncManager.initializeForMainIsolate();
  await PulseBackendClient.initialize();
  if (!kIsWeb && Platform.isAndroid) {
    final status = await Permission.notification.status;
    if (!status.isGranted && !status.isLimited) {
      await Permission.notification.request();
    }
  }
  // Initialize the new background service when needed
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

