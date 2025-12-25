import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../config/supabase_config.dart';
import '../login_screen.dart';
import 'owner_dashboard_screen.dart';
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

  const OwnerMainScreenNew({
    super.key,
    required this.ownerId,
    this.ownerName,
  });

  @override
  State<OwnerMainScreenNew> createState() => _OwnerMainScreenNewState();
}

class _OwnerMainScreenNewState extends State<OwnerMainScreenNew> {
  int _currentIndex = 0;

  List<_NavItem> get _navItems => [
        _NavItem(
          icon: Icons.dashboard,
          label: 'طلبات المديرين',
          screen: const OwnerManagerRequestsScreen(),
        ),
        _NavItem(
          icon: Icons.store,
          label: 'الفروع',
          screen: const OwnerBranchesScreen(),
        ),
        _NavItem(
          icon: Icons.people,
          label: 'الموظفون',
          screen: const OwnerEmployeesScreen(),
        ),
        _NavItem(
          icon: Icons.attach_money,
          label: 'الرواتب',
          screen: const OwnerSalariesScreen(),
        ),
        _NavItem(
          icon: Icons.table_chart,
          label: 'جدول الحضور',
          screen: const OwnerAttendanceTableScreen(),
        ),
      ];

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
      appBar: AppBar(
        title: Text(widget.ownerName ?? 'لوحة المالك'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'تسجيل الخروج',
          ),
        ],
      ),
      body: _navItems[_currentIndex].screen,
      bottomNavigationBar: _currentIndex < 2
          ? BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() => _currentIndex = index);
              },
              selectedItemColor: AppColors.primaryOrange,
              unselectedItemColor: AppColors.textSecondary,
              type: BottomNavigationBarType.fixed,
              items: _navItems.map((item) {
                return BottomNavigationBarItem(
                  icon: Icon(item.icon),
                  label: item.label,
                );
              }).toList(),
            )
          : null,
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: AppColors.primaryOrange,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.person,
                      size: 40,
                      color: AppColors.primaryOrange,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.ownerName ?? 'المالك',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    widget.ownerId,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            ..._navItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return ListTile(
                leading: Icon(
                  item.icon,
                  color: _currentIndex == index ? AppColors.primaryOrange : AppColors.textSecondary,
                ),
                title: Text(
                  item.label,
                  style: TextStyle(
                    color: _currentIndex == index ? AppColors.primaryOrange : AppColors.textPrimary,
                    fontWeight: _currentIndex == index ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: _currentIndex == index,
                selectedTileColor: AppColors.primaryOrange.withOpacity(0.1),
                onTap: () {
                  setState(() => _currentIndex = index);
                  Navigator.pop(context); // Close drawer
                },
              );
            }),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: const Text(
                'تسجيل الخروج',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () {
                Navigator.pop(context); // Close drawer
                _logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Widget screen;

  _NavItem({
    required this.icon,
    required this.label,
    required this.screen,
  });
}
