import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../config/supabase_config.dart';
import '../login_screen.dart';
import 'hr_dashboard_screen.dart';
import 'hr_employees_screen.dart';
import 'hr_attendance_screen.dart';
import 'hr_requests_screen.dart';
import 'hr_rewards_penalties_page.dart';

class HRMainScreen extends StatefulWidget {
  final String hrId;
  final String? hrName;

  const HRMainScreen({super.key, required this.hrId, this.hrName});

  @override
  State<HRMainScreen> createState() => _HRMainScreenState();
}

class _HRMainScreenState extends State<HRMainScreen> {
  int _currentIndex = 0;

  List<_NavItem> get _navItems => [
    _NavItem(
      icon: Icons.dashboard_rounded,
      label: 'لوحة التحكم',
      screen: HRDashboardScreen(hrId: widget.hrId),
    ),
    _NavItem(
      icon: Icons.people_rounded,
      label: 'الموظفون',
      screen: HREmployeesScreen(hrId: widget.hrId),
    ),
    _NavItem(
      icon: Icons.assignment_rounded,
      label: 'الطلبات',
      screen: HRRequestsScreen(hrId: widget.hrId),
    ),
    _NavItem(
      icon: Icons.access_time_rounded,
      label: 'الحضور',
      screen: HRAttendanceScreen(hrId: widget.hrId),
    ),
    _NavItem(
      icon: Icons.card_giftcard_rounded,
      label: 'الحوافز',
      screen: HRRewardsPenaltiesPage(hrId: widget.hrId),
    ),
  ];

  String get _currentTitle => _navItems[_currentIndex].label;

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await SupabaseConfig.client.auth.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تسجيل الخروج: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _currentTitle,
          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: Text(
                widget.hrName ?? 'موارد بشرية',
                style: GoogleFonts.tajawal(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.95),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'تسجيل الخروج',
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _navItems.map((item) => item.screen).toList(),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.primaryOrange,
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: GoogleFonts.tajawal(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: GoogleFonts.tajawal(fontSize: 12),
          items: _navItems.map((item) {
            return BottomNavigationBarItem(
              icon: Icon(item.icon, size: 26),
              label: item.label,
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Widget screen;

  _NavItem({required this.icon, required this.label, required this.screen});
}