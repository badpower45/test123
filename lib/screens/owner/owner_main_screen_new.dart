import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../config/supabase_config.dart';
import '../login_screen.dart';
import 'owner_employees_screen.dart';
import 'owner_branches_screen.dart';
import 'owner_manager_requests_screen.dart';
import 'owner_attendance_table_screen.dart';
import 'owner_salaries_screen.dart';

/// New Owner Main Screen using Supabase exclusively
/// Simplified navigation with all screens already created
class OwnerMainScreenNew extends StatefulWidget {
  final String ownerId;
  final String? ownerName;

  const OwnerMainScreenNew({super.key, required this.ownerId, this.ownerName});

  @override
  State<OwnerMainScreenNew> createState() => _OwnerMainScreenNewState();
}

class _OwnerMainScreenNewState extends State<OwnerMainScreenNew> {
  int _currentIndex = 0;

  List<_NavItem> get _navItems => [
    _NavItem(
      icon: Icons.fact_check_rounded,
      label: 'طلبات المديرين',
      screen: const OwnerManagerRequestsScreen(),
    ),
    _NavItem(
      icon: Icons.storefront_rounded,
      label: 'الفروع',
      screen: const OwnerBranchesScreen(),
    ),
    _NavItem(
      icon: Icons.groups_2_rounded,
      label: 'الموظفون',
      screen: const OwnerEmployeesScreen(),
    ),
    _NavItem(
      icon: Icons.payments_rounded,
      label: 'الرواتب',
      screen: OwnerSalariesScreen(ownerId: widget.ownerId),
    ),
    _NavItem(
      icon: Icons.table_rows_rounded,
      label: 'جدول الحضور',
      screen: const OwnerAttendanceTableScreen(),
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
                widget.ownerName ?? 'المالك',
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
