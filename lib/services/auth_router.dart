import 'package:flutter/material.dart';

import '../screens/admin_dashboard_page.dart';
import '../screens/home_screen.dart';

DashboardMode? _modeForRole(String role) {
  switch (role.toLowerCase()) {
    case 'admin':
      return DashboardMode.admin;
    case 'hr':
      return DashboardMode.hr;
    case 'monitor':
      return DashboardMode.monitor;
    default:
      return null;
  }
}

Future<void> routeAfterLogin(
  BuildContext context, {
  required String role,
  required String employeeId,
}) async {
  final mode = _modeForRole(role);
  if (mode != null) {
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => AdminDashboardPage(
          mode: mode,
          currentUserId: employeeId,
        ),
      ),
      (route) => false,
    );
    return;
  }

  await Navigator.of(context).pushNamedAndRemoveUntil(
    HomeScreen.routeName,
    (route) => false,
    arguments: employeeId,
  );
}
