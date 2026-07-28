import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../config/supabase_config.dart';
import '../login_screen.dart';
import 'owner_employees_screen.dart';
import 'owner_branches_screen.dart';
import 'owner_manager_requests_screen.dart';
import 'owner_attendance_table_screen.dart';
import 'owner_salaries_screen.dart';
import 'owner_main_screen.dart';

/// New Owner Main Screen using Supabase exclusively
/// Responsive Desktop Web Layout + Adaptive Mobile Fallback
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
      subtitle: 'اعتماد ومراجعة طلبات المديرين والفروع',
      screen: OwnerManagerRequestsScreen(ownerId: widget.ownerId),
    ),
    _NavItem(
      icon: Icons.storefront_rounded,
      label: 'الفروع',
      subtitle: 'إدارة وتتبع الفروع ومواقع GPS والواي فاي',
      screen: const OwnerBranchesScreen(),
    ),
    _NavItem(
      icon: Icons.groups_2_rounded,
      label: 'الموظفون',
      subtitle: 'سجل وإعدادات وتعيين الموظفين والرواتب',
      screen: const OwnerEmployeesScreen(),
    ),
    _NavItem(
      icon: Icons.payments_rounded,
      label: 'الرواتب',
      subtitle: 'صرف الرواتب والسلف والتقارير المالية',
      screen: OwnerSalariesScreen(ownerId: widget.ownerId),
    ),
    _NavItem(
      icon: Icons.table_rows_rounded,
      label: 'جدول الحضور',
      subtitle: 'جدول تفصيلي لسجلات الحضور والانصراف الحية',
      screen: const OwnerAttendanceTableScreen(),
    ),
  ];

  _NavItem get _currentItem => _navItems[_currentIndex];

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'تسجيل الخروج',
          style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل أنت متأكد من تسجيل الخروج من حساب المالك؟',
          style: GoogleFonts.tajawal(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء', style: GoogleFonts.tajawal()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('تسجيل الخروج', style: GoogleFonts.tajawal(color: Colors.white)),
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
          content: Text('خطأ في تسجيل الخروج: $e', style: GoogleFonts.tajawal()),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showAttendanceRules() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AttendanceRulesSheet(ownerId: widget.ownerId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        if (isDesktop) {
          return _buildDesktopLayout();
        } else {
          return _buildMobileLayout();
        }
      },
    );
  }

  /// Modern Desktop Layout for Owner
  Widget _buildDesktopLayout() {
    final formattedDate = DateFormat('EEEE - d MMMM yyyy', 'ar').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFAFAFAF).withValues(alpha: 0.15),
      body: Row(
        children: [
          // Sidebar Navigation
          _buildSidebar(),

          // Main Screen Area with Top Header
          Expanded(
            child: Column(
              children: [
                // Top Header Bar
                Container(
                  height: 70,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Active Item Icon & Title
                      Icon(_currentItem.icon, color: AppColors.primaryOrange, size: 28),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _currentItem.label,
                            style: GoogleFonts.tajawal(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            _currentItem.subtitle,
                            style: GoogleFonts.tajawal(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),

                      // Date Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryOrange.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.primaryOrange.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded,
                                size: 16, color: AppColors.primaryOrange),
                            const SizedBox(width: 8),
                            Text(
                              formattedDate,
                              style: GoogleFonts.tajawal(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryOrange,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Attendance Rules Button
                      ElevatedButton.icon(
                        onPressed: _showAttendanceRules,
                        icon: const Icon(Icons.gavel_rounded, size: 18),
                        label: Text(
                          'قواعد الخصم والحضور',
                          style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primaryOrange,
                          elevation: 0,
                          side: const BorderSide(color: AppColors.primaryOrange),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Refresh Button
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: Colors.grey),
                        onPressed: () => setState(() {}),
                        tooltip: 'تحديث البيانات',
                      ),
                    ],
                  ),
                ),

                // Active View Body
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: _navItems.map((item) => item.screen).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sidebar Navigation Widget for Desktop
  Widget _buildSidebar() {
    return Container(
      width: 270,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Sidebar Brand Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryOrange,
                  AppColors.primaryOrange.withRed(220),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'منصة المالك',
                        style: GoogleFonts.tajawal(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'الإدارة العامة والتحكم',
                        style: GoogleFonts.tajawal(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Owner Profile Card
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primaryOrange.withOpacity(0.15),
                  child: Text(
                    (widget.ownerName?.isNotEmpty == true ? widget.ownerName![0] : 'O').toUpperCase(),
                    style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryOrange,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.ownerName ?? 'المالك',
                        style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'مالك النظام (Owner)',
                          style: GoogleFonts.tajawal(
                            fontSize: 10,
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Menu Label
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'لوحة التحكّم الرئيسية',
                style: GoogleFonts.tajawal(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[500],
                ),
              ),
            ),
          ),

          // Navigation List Items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              itemCount: _navItems.length,
              itemBuilder: (context, index) {
                final item = _navItems[index];
                final isSelected = index == _currentIndex;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryOrange.withOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isSelected
                        ? Border.all(color: AppColors.primaryOrange.withOpacity(0.3))
                        : null,
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    leading: Icon(
                      item.icon,
                      color: isSelected ? AppColors.primaryOrange : Colors.grey[600],
                      size: 22,
                    ),
                    title: Text(
                      item.label,
                      style: GoogleFonts.tajawal(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? AppColors.primaryOrange : Colors.grey[800],
                      ),
                    ),
                    trailing: isSelected
                        ? Container(
                            width: 6,
                            height: 20,
                            decoration: BoxDecoration(
                              color: AppColors.primaryOrange,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          )
                        : null,
                    onTap: () => setState(() => _currentIndex = index),
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // Footer Logout Button
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded, color: AppColors.error, size: 18),
                label: Text(
                  'تسجيل الخروج',
                  style: GoogleFonts.tajawal(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.error.withOpacity(0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Mobile Layout Fallback (For narrow mobile screens)
  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _currentItem.label,
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
            icon: const Icon(Icons.gavel_rounded),
            onPressed: _showAttendanceRules,
            tooltip: 'قواعد الحضور والخصم',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => setState(() {}),
            tooltip: 'تحديث البيانات',
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
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: GoogleFonts.tajawal(fontSize: 11),
          items: _navItems.map((item) {
            return BottomNavigationBarItem(
              icon: Icon(item.icon, size: 24),
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
  final String subtitle;
  final Widget screen;

  _NavItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.screen,
  });
}
