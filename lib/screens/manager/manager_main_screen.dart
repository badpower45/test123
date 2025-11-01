import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/attendance_api_service.dart';
import '../branch_manager_screen.dart';
import '../employee/refreshable_tab.dart';
import '../login_screen.dart';
import 'manager_home_page.dart';
import 'manager_requests_page.dart';
import 'manager_report_page.dart';
import 'manager_profile_page.dart';

class ManagerMainScreen extends StatefulWidget {
  const ManagerMainScreen({
    super.key,
    required this.managerId,
    this.branch = '',
    this.role = 'manager',
  });

  final String managerId;
  final String branch;
  final String role;

  @override
  State<ManagerMainScreen> createState() => _ManagerMainScreenState();
}

class _ManagerMainScreenState extends State<ManagerMainScreen> {
  int _currentIndex = 0;
  late List<Widget> _pages;
  late List<GlobalKey<RefreshableTabState>> _tabKeys;

  @override
  void initState() {
    super.initState();
    _tabKeys = List.generate(4, (_) => GlobalKey<RefreshableTabState>());
    _pages = [
      RefreshableTab(
        key: _tabKeys[0],
        builder: (context) => ManagerHomePage(managerId: widget.managerId),
      ),
      RefreshableTab(
        key: _tabKeys[1],
        builder: (context) => ManagerRequestsPage(managerId: widget.managerId),
      ),
      RefreshableTab(
        key: _tabKeys[2],
        builder: (context) => ManagerReportPage(managerId: widget.managerId, branch: widget.branch),
      ),
      RefreshableTab(
        key: _tabKeys[3],
        builder: (context) => ManagerProfilePage(managerId: widget.managerId),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المدير'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_customize),
            tooltip: 'لوحة تحكم المدير',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BranchManagerScreen(
                    managerId: widget.managerId,
                    branchName: widget.branch,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل الخروج',
            onPressed: () async {
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
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('تسجيل الخروج'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                // Auto check-out if checked in
                try {
                  final status = await AttendanceApiService.fetchEmployeeStatus(widget.managerId);
                  final isCheckedIn = status['attendance']?['status'] == 'active';
                  
                  if (isCheckedIn) {
                    await AttendanceApiService.checkOut(
                      employeeId: widget.managerId,
                      latitude: 0, // dummy values, not validated on logout
                      longitude: 0,
                    );
                    print('✅ Auto check-out successful');
                  }
                } catch (e) {
                  print('⚠️ Failed to auto check-out: $e');
                  // Continue with logout even if check-out fails
                }
                
                await AuthService.logout();
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _tabKeys[_currentIndex].currentState?.refresh();
        },
        child: const Icon(Icons.refresh),
        tooltip: 'تحديث البيانات',
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.primaryOrange,
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: GoogleFonts.ibmPlexSansArabic(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: GoogleFonts.ibmPlexSansArabic(
            fontSize: 12,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(
                Icons.home,
                size: 28,
              ),
              label: 'الرئيسية',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                Icons.assignment,
                size: 28,
              ),
              label: 'الطلبات',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                Icons.description,
                size: 28,
              ),
              label: 'التقارير',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                Icons.person,
                size: 28,
              ),
              label: 'ملفي',
            ),
          ],
        ),
      ),
    );
  }
}
