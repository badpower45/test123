import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../screens/branch_manager_screen.dart';
import '../screens/employee/employee_main_screen.dart';
import '../screens/manager/manager_main_screen.dart';
import '../screens/owner/owner_main_screen.dart';
import '../services/auth_api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const routeName = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _employeeIdController;
  late final TextEditingController _pinController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _employeeIdController = TextEditingController();
    _pinController = TextEditingController();
  }

  @override
  void dispose() {
    _employeeIdController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin(BuildContext context) async {
    final employeeId = _employeeIdController.text.trim();
    final pin = _pinController.text.trim();

    if (employeeId.isEmpty || pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال معرف الموظف والرقم السري.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    try {
      // Authenticate with server
      final employee = await AuthApiService.login(
        employeeId: employeeId,
        pin: pin,
      );

      // Save login data to SharedPreferences for persistent login
      await AuthService.saveLoginData(
        employeeId: employee.id,
        role: employee.role.name,
        branch: employee.branch,
        fullName: employee.fullName,
      );

      if (!mounted) return;

      // Navigate based on role
      if (employee.role == EmployeeRole.owner) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => OwnerMainScreen(
              ownerId: employee.id,
              ownerName: employee.fullName,
            ),
          ),
        );
      } else if (employee.role == EmployeeRole.admin || employee.role == EmployeeRole.hr) {
        // Admin/HR goes to branch manager dashboard directly
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BranchManagerScreen(
              managerId: employee.id,
              branchName: employee.branch,
            ),
          ),
        );
      } else if (employee.role == EmployeeRole.manager) {
        // Manager goes to manager main screen (employee screens + dashboard button)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ManagerMainScreen(
              managerId: employee.id,
              branch: employee.branch,
              role: employee.role.name,
            ),
          ),
        );
      } else {
        // Regular employee goes to employee main screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => EmployeeMainScreen(
              employeeId: employee.id,
              role: employee.role.name,
              branch: employee.branch,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryOrange,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/app_icon.png',
                  height: 100,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Text(
                      'أولديزز وركرز',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: AppColors.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                    );
                  },
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _employeeIdController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _buildInputDecoration('معرف الموظف'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pinController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _buildInputDecoration('الرقم السري'),
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleLogin(context),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _handleLogin(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primaryOrange,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryOrange),
                            ),
                          )
                        : const Text(
                            'تسجيل الدخول',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
