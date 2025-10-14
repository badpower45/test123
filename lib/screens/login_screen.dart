import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'admin_dashboard_page.dart';
import 'employee/employee_main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const routeName = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _employeeIdController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _employeeIdController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _employeeIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin(BuildContext context) {
    final employeeId = _employeeIdController.text.trim();
    final password = _passwordController.text.trim();

    if (employeeId.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال معرّف الموظف والرقم السري.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => EmployeeMainScreen(employeeId: employeeId),
      ),
    );
  }

  void _openDashboard(BuildContext context, DashboardMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminDashboardPage(mode: mode),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white70),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white),
      ),
      filled: true,
      fillColor: Colors.white.withAlpha((0.12 * 255).round()),
    );
  }

  Widget _buildDashboardPreviewButton({
    required BuildContext context,
    required DashboardMode mode,
    required String label,
    required IconData icon,
  }) {
    return OutlinedButton.icon(
      onPressed: () => _openDashboard(context, mode),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withAlpha((0.35 * 255).round())),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryOrange,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/app_icon.png',
                height: 160,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Text(
                    'أولديزز وركرز',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                  );
                },
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _employeeIdController,
                style: const TextStyle(color: Colors.white),
                decoration: _buildInputDecoration('معرّف الموظف'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                style: const TextStyle(color: Colors.white),
                decoration: _buildInputDecoration('الرقم السري'),
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleLogin(context),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _handleLogin(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primaryOrange,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'تسجيل الدخول',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'معاينة لوحات التحكم',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white.withAlpha((0.75 * 255).round()),
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _buildDashboardPreviewButton(
                    context: context,
                    mode: DashboardMode.admin,
                    label: 'لوحة الإدارة',
                    icon: Icons.admin_panel_settings_outlined,
                  ),
                  _buildDashboardPreviewButton(
                    context: context,
                    mode: DashboardMode.hr,
                    label: 'شؤون الموظفين',
                    icon: Icons.badge_outlined,
                  ),
                  _buildDashboardPreviewButton(
                    context: context,
                    mode: DashboardMode.monitor,
                    label: 'المراقبة',
                    icon: Icons.monitor_heart_outlined,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
