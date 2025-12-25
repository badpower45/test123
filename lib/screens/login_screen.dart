import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../config/app_config.dart';
import '../models/employee.dart';
import '../screens/branch_manager_screen.dart';
import '../screens/employee/employee_main_screen.dart';
import '../screens/employee/onboarding/employee_onboarding_flow.dart';
import '../screens/owner/owner_main_screen_new.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/blv/blv_manager.dart';
import '../services/supabase_auth_service.dart';
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
      // Check internet connectivity first
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        throw Exception('لا يوجد اتصال بالإنترنت. تأكد من اتصالك بالشبكة');
      }
      
      // Authenticate with Supabase
      final employee = await SupabaseAuthService.login(employeeId, pin);
      
      if (employee == null) {
        throw Exception('معرف الموظف أو الرقم السري غير صحيح');
      }

      // Handle new employees (without branch) - allow login but show warning
      if (employee.branch.isEmpty || employee.branch == 'null' || employee.branch == 'غير محدد') {
        print('⚠️ [Login] Employee ${employee.id} has no branch assigned');
        // Allow login but employee won't be able to check in until branch is assigned
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ تحذير: الموظف غير مرتبط بفرع. يرجى التواصل مع المدير.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }

      // Register device for single device login
      try {
        final deviceResult = await DeviceService.registerDevice(employee.id);
        final wasLoggedOut = deviceResult['wasLoggedOutFromOtherDevice'] as bool? ?? false;
        
        if (wasLoggedOut && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تسجيل خروجك من الجهاز الآخر تلقائياً'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        print('Device registration failed: $e');
        // Continue even if device registration fails
      }

      // Save login data to SharedPreferences for persistent login
      await AuthService.saveLoginData(
        employeeId: employee.id,
        role: employee.role.name,
        branch: employee.branch,
        fullName: employee.fullName,
      );

      // Initialize BLV system for environmental tracking
      if (employee.branch.isNotEmpty) {
        try {
          final blvManager = BLVManager();
          
          // Note: We need to fetch branchId from employee.branch name
          // For now, we'll initialize without baseline (will load later)
          await blvManager.initialize(
            baseUrl: AppConfig.apiBaseUrl, // Uses API_BASE_URL from env or localhost:3000
            authToken: employee.id,
          );
          
          print('✅ [BLV] System initialized for ${employee.branch}');
        } catch (e) {
          print('⚠️ [BLV] Failed to initialize: $e');
          // Continue even if BLV fails - don't block login
        }
      }

      if (!mounted) return;

      // DEBUG: Print navigation decision
      print('🔍 NAVIGATION DEBUG - Employee role: ${employee.role}');
      print('🔍 NAVIGATION DEBUG - Checking conditions:');
      print('   - Is owner? ${employee.role == EmployeeRole.owner}');
      print('   - Is admin/hr? ${employee.role == EmployeeRole.admin || employee.role == EmployeeRole.hr}');
      print('   - Is manager? ${employee.role == EmployeeRole.manager}');
      print('   - Is staff? ${employee.role == EmployeeRole.staff}');

      // Navigate based on role
      if (employee.role == EmployeeRole.owner) {
        print('🔍 NAVIGATION DEBUG - Navigating to OwnerMainScreenNew');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => OwnerMainScreenNew(
              ownerId: employee.id,
              ownerName: employee.fullName,
            ),
          ),
        );
      } else if (employee.role == EmployeeRole.admin || employee.role == EmployeeRole.hr) {
        // Admin/HR goes to branch manager dashboard directly
        print('🔍 NAVIGATION DEBUG - Navigating to BranchManagerScreen (admin/hr)');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BranchManagerScreen(
              managerId: employee.id,
              branchName: employee.branch,
            ),
          ),
        );
      } else if (employee.role == EmployeeRole.manager) {
        // Manager goes to EMPLOYEE screen (same as staff) + admin button
        print('🔍 NAVIGATION DEBUG - Navigating to EmployeeMainScreen (manager with admin privileges)');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => EmployeeMainScreen(
              employeeId: employee.id,
              role: employee.role.name, // Pass 'manager' role
              branch: employee.branch,
            ),
          ),
        );
      } else {
        // Regular employee - check if needs onboarding
        print('🔍 NAVIGATION DEBUG - Navigating to EmployeeMainScreen (staff/default)');
        
        // Check if employee needs onboarding
        final needsOnboarding = await SupabaseAuthService.needsOnboarding(employee.id);
        
        if (needsOnboarding) {
          print('🔍 NAVIGATION DEBUG - Employee needs onboarding, showing onboarding flow');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => EmployeeOnboardingFlow(
                employeeId: employee.id,
                email: employee.email ?? '',
              ),
            ),
          );
        } else {
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
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      // Better error messages for common errors
      String errorMessage = 'حدث خطأ أثناء تسجيل الدخول';
      final errorStr = e.toString().toLowerCase();
      
      if (errorStr.contains('invalid employee') || errorStr.contains('invalid pin')) {
        errorMessage = 'معرف الموظف أو الرقم السري غير صحيح';
      } else if (errorStr.contains('clientconnection') || 
                 errorStr.contains('connection closed') ||
                 errorStr.contains('eof')) {
        errorMessage = 'فشل الاتصال بالخادم. تأكد من اتصالك بالإنترنت وحاول مرة أخرى';
      } else if (errorStr.contains('timeout')) {
        errorMessage = 'انتهت مهلة الاتصال. تأكد من اتصالك بالإنترنت';
      } else if (errorStr.contains('socket') || errorStr.contains('network')) {
        errorMessage = 'مشكلة في الشبكة. تحقق من اتصالك بالإنترنت';
      } else if (errorStr.contains('handshake') || errorStr.contains('certificate')) {
        errorMessage = 'خطأ في الاتصال الآمن. حاول مرة أخرى';
      } else {
        // Keep original message for unknown errors
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(errorMessage)),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'إعادة المحاولة',
            textColor: Colors.white,
            onPressed: () => _handleLogin(context),
          ),
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
