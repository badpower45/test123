import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import 'employee_home_page.dart';
import 'requests_page.dart';
import 'reports_page.dart';
import 'profile_page.dart';
import 'refreshable_tab.dart';
// import '../../models/employee.dart';
import '../branch_manager_screen.dart';

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
  _tabKeys = List.generate(isManager ? 5 : 4, (_) => GlobalKey<RefreshableTabState>());
    _pages = [
      RefreshableTab(
        key: _tabKeys[0],
        builder: (context) => EmployeeHomePage(employeeId: widget.employeeId),
      ),
      RefreshableTab(
        key: _tabKeys[1],
        builder: (context) => RequestsPage(employeeId: widget.employeeId),
      ),
      RefreshableTab(
        key: _tabKeys[2],
        builder: (context) => ReportsPage(employeeId: widget.employeeId),
      ),
      RefreshableTab(
        key: _tabKeys[3],
        builder: (context) => ProfilePage(employeeId: widget.employeeId),
      ),
      if (isManager)
        RefreshableTab(
          key: _tabKeys[4],
          builder: (context) => BranchManagerScreen(managerId: widget.employeeId, branchName: widget.branch),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            if (isManager)
              BottomNavigationBarItem(
                icon: Icon(
                  _currentIndex == 4 ? Icons.dashboard : Icons.dashboard_outlined,
                  size: 28,
                ),
                label: 'لوحة المدير',
              ),
          ],
        ),
      ),
    );
  }
}
