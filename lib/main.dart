import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models/employee.dart';
import 'models/employee_adjustment.dart';
import 'models/pulse.dart';
import 'models/pulse_log_entry.dart';
import 'screens/admin_dashboard_page.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/background_pulse_service.dart';
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
  await Hive.openBox<Pulse>(offlinePulsesBox);
  await Hive.openBox<PulseLogEntry>(pulseHistoryBox);
  await Hive.openBox<Employee>(employeesBox);
  await Hive.openBox<EmployeeAdjustment>(employeeAdjustmentsBox);
  await _seedDemoDataIfNeeded();
  await PulseSyncManager.initializeForMainIsolate();
  await PulseBackendClient.initialize();
  if (!kIsWeb && Platform.isAndroid) {
    final status = await Permission.notification.status;
    if (!status.isGranted && !status.isLimited) {
      await Permission.notification.request();
    }
  }
  await BackgroundPulseService.initialize();
  await BackgroundPulseService.stop();
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
        return null;
      },
    );
  }
}

Future<void> _seedDemoDataIfNeeded() async {
  final employeeBox = Hive.box<Employee>(employeesBox);
  if (employeeBox.isNotEmpty) {
    return;
  }

  final now = DateTime.now().toUtc();
  final employees = [
    Employee(
      id: 'EMP001',
      fullName: 'مريم حسن',
      pin: '1234',
      role: EmployeeRole.admin,
      permissions: const [
        EmployeePermission.manageEmployees,
        EmployeePermission.monitorAccess,
        EmployeePermission.viewPayroll,
      ],
      branch: 'الفرع الرئيسي - الزمالك',
      monthlySalary: 18500,
    ),
    Employee(
      id: 'EMP002',
      fullName: 'عمر سعيد',
      pin: '5678',
      role: EmployeeRole.hr,
      permissions: const [
        EmployeePermission.viewPayroll,
        EmployeePermission.manageScheduling,
      ],
      branch: 'فرع المعادي',
      monthlySalary: 13250,
    ),
    Employee(
      id: 'EMP003',
      fullName: 'نورة عادل',
      pin: '2468',
      role: EmployeeRole.monitor,
      permissions: const [
        EmployeePermission.monitorAccess,
      ],
      branch: 'فرع مدينة نصر',
      monthlySalary: 9800,
    ),
  ];

  await employeeBox.putAll({for (final employee in employees) employee.id: employee});

  final historyBox = Hive.box<PulseLogEntry>(pulseHistoryBox);
  if (historyBox.isEmpty) {
    final pulseEntries = [
      PulseLogEntry(
        pulse: Pulse(
          employeeId: 'EMP003',
          latitude: 30.0444,
          longitude: 31.2357,
          timestamp: now.subtract(const Duration(minutes: 12)),
          isFake: false,
        ),
        recordedAt: now.subtract(const Duration(minutes: 12)),
        wasOnline: true,
        deliveryStatus: PulseDeliveryStatus.sentOnline,
      ),
      PulseLogEntry(
        pulse: Pulse(
          employeeId: 'EMP002',
          latitude: 30.0450,
          longitude: 31.2362,
          timestamp: now.subtract(const Duration(hours: 2, minutes: 20)),
          isFake: false,
        ),
        recordedAt: now.subtract(const Duration(hours: 2, minutes: 20)),
        wasOnline: true,
        deliveryStatus: PulseDeliveryStatus.sentOnline,
      ),
      PulseLogEntry(
        pulse: Pulse(
          employeeId: 'EMP003',
          latitude: 30.0449,
          longitude: 31.2361,
          timestamp: now.subtract(const Duration(hours: 5)),
          isFake: false,
        ),
        recordedAt: now.subtract(const Duration(hours: 5)),
        wasOnline: false,
        deliveryStatus: PulseDeliveryStatus.queuedOffline,
      ),
    ];

    for (final entry in pulseEntries) {
      await historyBox.add(entry);
    }
  }

  final offlineBox = Hive.box<Pulse>(offlinePulsesBox);
  if (offlineBox.isEmpty) {
    await offlineBox.add(
      Pulse(
        employeeId: 'EMP003',
        latitude: 30.0441,
        longitude: 31.2355,
        timestamp: now.subtract(const Duration(hours: 1, minutes: 15)),
        isFake: false,
      ),
    );
  }

  final adjustmentBox = Hive.box<EmployeeAdjustment>(employeeAdjustmentsBox);
  if (adjustmentBox.isEmpty) {
    await adjustmentBox.put(
      'ADJ-001',
      EmployeeAdjustment(
        id: 'ADJ-001',
        employeeId: 'EMP002',
        type: AdjustmentType.bonus,
        reason: 'مكافأة أداء مستهدفة لشهر سبتمبر',
        recordedBy: 'مريم حسن',
        amount: 750,
        createdAt: now.subtract(const Duration(days: 3)),
      ),
    );
  }
}
