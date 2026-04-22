import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'owner/owner_main_screen_new.dart';
import 'employee/employee_main_screen.dart';
import 'branch_manager_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const routeName = '/';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _contentFade;
  late final Animation<double> _backgroundDrift;
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );

    _logoScale = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _contentFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.22, 1.0, curve: Curves.easeOut),
    );

    _backgroundDrift = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 1200), _navigateNext),
    );
  }

  Future<void> _navigateNext() async {
    if (_didNavigate || !mounted) return;
    _didNavigate = true;

    final loginData = await AuthService.getLoginData();

    Widget targetScreen = const LoginScreen();

    if (loginData.isNotEmpty && loginData['employeeId'] != null) {
      final employeeId = loginData['employeeId']!;
      final role = loginData['role'] ?? 'staff';
      final branch = loginData['branch'] ?? '';
      final fullName = loginData['fullName'] ?? '';

      if (role.toLowerCase() == 'owner') {
        targetScreen = OwnerMainScreenNew(
          ownerId: employeeId,
          ownerName: fullName,
        );
      } else if (role.toLowerCase() == 'admin' || role.toLowerCase() == 'hr') {
        targetScreen = BranchManagerScreen(
          managerId: employeeId,
          branchName: branch,
        );
      } else if (role.toLowerCase() == 'manager') {
        targetScreen = EmployeeMainScreen(
          employeeId: employeeId,
          role: role,
          branch: branch,
        );
      } else {
        targetScreen = EmployeeMainScreen(
          employeeId: employeeId,
          role: role,
          branch: branch,
        );
      }
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: targetScreen,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: _navigateNext,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final drift = _backgroundDrift.value;
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1 + (drift * 0.3), -1),
                  end: Alignment(1, 1 - (drift * 0.2)),
                  colors: const [
                    Color(0xFFF05C2B),
                    Color(0xFFFD964B),
                    Color(0xFFFFC08A),
                  ],
                ),
              ),
              child: child,
            );
          },
          child: Stack(
            children: [
              Positioned(
                top: -90,
                left: -40,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.15),
                  ),
                ),
              ),
              Positioned(
                bottom: -80,
                right: -30,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(46),
                    color: Colors.white.withOpacity(0.12),
                  ),
                ),
              ),
              SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                    child: FadeTransition(
                      opacity: _contentFade,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ScaleTransition(
                            scale: _logoScale,
                            child: Container(
                              width: 132,
                              height: 132,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(34),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.14),
                                    blurRadius: 24,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/images/app_icon.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.storefront_rounded,
                                    size: 62,
                                    color: AppColors.primaryOrange,
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),
                          Text(
                            'أولديزز ووركرز',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.tajawal(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'نظام حضور وانصراف وإدارة يومية للفرق',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.tajawal(
                              color: Colors.white.withOpacity(0.92),
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: 180,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(50),
                              child: LinearProgressIndicator(
                                minHeight: 6,
                                backgroundColor: Colors.white.withOpacity(0.3),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'جاري تحميل النظام...',
                            style: GoogleFonts.tajawal(
                              color: Colors.white.withOpacity(0.86),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'اضغط للتخطي',
                            style: GoogleFonts.tajawal(
                              color: Colors.white.withOpacity(0.68),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
