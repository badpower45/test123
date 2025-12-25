import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/attendance_api_service.dart';
import '../login_screen.dart';
import '../manager/manager_add_employee_page.dart';
import '../manager/manager_dashboard_simple.dart';
import 'employee_home_page.dart';
import 'requests_page.dart';
import 'reports_page.dart';
import 'profile_page.dart';
import 'refreshable_tab.dart';
// import '../../models/employee.dart';

class EmployeeMainScreen extends StatefulWidget {
  const EmployeeMainScreen({super.key, required this.employeeId, this.role = 'staff', this.branch = ''});

  static const routeName = '/employee';

  final String employeeId;
  final String role;
  final String branch;

  @override
  State<EmployeeMainScreen> createState() => _EmployeeMainScreenState();
}

class _EmployeeMainScreenState extends State<EmployeeMainScreen> {
  int _currentIndex = 0;
  late List<Widget> _pages;
  late List<GlobalKey<RefreshableTabState>> _tabKeys;
  bool get isManager => widget.role.toLowerCase() == 'manager';

  @override
  void initState() {
    super.initState();
    _tabKeys = List.generate(4, (_) => GlobalKey<RefreshableTabState>());
    _pages = [
      RefreshableTab(
        key: _tabKeys[0],
        builder: (context) => EmployeeHomePage(employeeId: widget.employeeId),
      ),
      RefreshableTab(
        key: _tabKeys[1],
        builder: (context) => RequestsPage(
          employeeId: widget.employeeId,
          hideBreakTab: false,
        ),
      ),
      RefreshableTab(
        key: _tabKeys[2],
        builder: (context) => ReportsPage(employeeId: widget.employeeId),
      ),
      RefreshableTab(
        key: _tabKeys[3],
        builder: (context) => ProfilePage(employeeId: widget.employeeId),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isManager ? 'مدير الفرع' : 'الموظف'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          // Manager extras: Add Employee + Branch Dashboard
          if (isManager) ...[
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'إضافة موظف',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManagerAddEmployeePage(
                      managerId: widget.employeeId,
                      managerBranch: widget.branch,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.dashboard_customize),
              tooltip: 'لوحة الفرع',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManagerDashboardSimple(
                      managerId: widget.employeeId,
                      branchName: widget.branch,
                    ),
                  ),
                );
              },
            ),
          ],
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل الخروج',
            onPressed: () async {
              // \u2705 PRIORITY 1: Check SharedPreferences for active attendance
              bool hasActiveAttendance = false;
              String? activeAttendanceId;
              
              try {
                final prefs = await SharedPreferences.getInstance();
                activeAttendanceId = prefs.getString('active_attendance_id');
                
                if (activeAttendanceId != null && activeAttendanceId.isNotEmpty) {
                  hasActiveAttendance = true;
                  print('\u2705 Found active attendance in SharedPreferences: $activeAttendanceId');
                }
              } catch (e) {
                print('\u26a0\ufe0f Failed to check SharedPreferences: $e');
              }
              
              // \u2705 PRIORITY 2: If no local data, try online check (requires internet)
              if (!hasActiveAttendance) {
                try {
                  final status = await AttendanceApiService.fetchEmployeeStatus(widget.employeeId);
                  final isCheckedIn = status['attendance']?['status'] == 'active';
                  
                  if (isCheckedIn) {
                    hasActiveAttendance = true;
                    print('\u2705 Found active attendance online');
                  }
                } catch (e) {
                  print('\u26a0\ufe0f Failed to check online attendance status: $e');
                  // Continue - may be offline
                }
              }
              
              // \u2705 Block logout if there's active attendance
              if (hasActiveAttendance) {
                if (!mounted) return;
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    icon: const Icon(Icons.warning_amber, size: 48, color: AppColors.error),
                    title: const Text('\u0644\u0627 \u064a\u0645\u0643\u0646 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062e\u0631\u0648\u062c'),
                    content: const Text(
                      '\u064a\u062c\u0628 \u0639\u0644\u064a\u0643 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u0627\u0646\u0635\u0631\u0627\u0641 \u0623\u0648\u0644\u0627\u064b \u0642\u0628\u0644 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062e\u0631\u0648\u062c \u0645\u0646 \u0627\u0644\u062d\u0633\u0627\u0628.\n\n'
                      '\u0627\u0644\u0631\u062c\u0627\u0621 \u0627\u0644\u0636\u063a\u0637 \u0639\u0644\u0649 \u0632\u0631 "\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u0627\u0646\u0635\u0631\u0627\u0641" \u0645\u0646 \u0627\u0644\u0635\u0641\u062d\u0629 \u0627\u0644\u0631\u0626\u064a\u0633\u064a\u0629.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('\u062d\u0633\u0646\u0627\u064b', style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  ),
                );
                return; // \u2705 Block logout
              }

              // \u2705 No active attendance - proceed with logout
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062e\u0631\u0648\u062c'),
                  content: const Text('\u0647\u0644 \u0623\u0646\u062a \u0645\u062a\u0623\u0643\u062f \u0645\u0646 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062e\u0631\u0648\u062c\u061f'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('\u0625\u0644\u063a\u0627\u0621'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062e\u0631\u0648\u062c'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
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
          items: [
            BottomNavigationBarItem(
              icon: Icon(
                _currentIndex == 0 ? Icons.home : Icons.home_outlined,
                size: 28,
              ),
              label: 'الرئيسية',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                _currentIndex == 1 ? Icons.assignment : Icons.assignment_outlined,
                size: 28,
              ),
              label: 'الطلبات',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                _currentIndex == 2 ? Icons.description : Icons.description_outlined,
                size: 28,
              ),
              label: 'التقارير',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                _currentIndex == 3 ? Icons.person : Icons.person_outlined,
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
