import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/attendance_api_service.dart';
import '../../services/blv/blv_manager.dart';
import '../branch_manager_screen.dart';
import '../employee/refreshable_tab.dart';
import '../login_screen.dart';
import 'manager_home_page.dart';
import 'manager_report_page.dart';
import 'manager_profile_page.dart';
import 'blv_flags_page.dart';

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
  int _unresolvedFlagsCount = 0;

  @override
  void initState() {
    super.initState();
    _tabKeys = List.generate(3, (_) => GlobalKey<RefreshableTabState>());
    _pages = [
      RefreshableTab(
        key: _tabKeys[0],
        builder: (context) => ManagerHomePage(managerId: widget.managerId),
      ),
      RefreshableTab(
        key: _tabKeys[1],
        builder: (context) => ManagerReportPage(managerId: widget.managerId, branch: widget.branch),
      ),
      RefreshableTab(
        key: _tabKeys[2],
        builder: (context) => ManagerProfilePage(managerId: widget.managerId),
      ),
    ];
    _loadUnresolvedFlagsCount();
  }

  Future<void> _loadUnresolvedFlagsCount() async {
    try {
      final blvManager = BLVManager();
      final flags = await blvManager.fetchAllFlags();
      if (mounted) {
        setState(() {
          _unresolvedFlagsCount = flags.length;
        });
      }
    } catch (e) {
      // Ignore errors silently
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المدير'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          // BLV Flags - تنبيهات النشاط المشبوه
          IconButton(
            icon: Badge(
              isLabelVisible: _unresolvedFlagsCount > 0,
              label: Text(_unresolvedFlagsCount.toString()),
              backgroundColor: Colors.red,
              child: const Icon(Icons.flag_outlined),
            ),
            tooltip: 'التنبيهات',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BLVFlagsPage(
                    managerId: widget.managerId,
                    branchId: null, // Show all branches for this manager
                  ),
                ),
              );
              // Reload count after returning
              _loadUnresolvedFlagsCount();
            },
          ),
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
              // التحقق من حالة الحضور أولاً
              try {
                final status = await AttendanceApiService.fetchEmployeeStatus(widget.managerId);
                final isCheckedIn = status['attendance']?['status'] == 'active';
                
                if (isCheckedIn) {
                  // منع تسجيل الخروج إذا كان مسجل حضور
                  if (!mounted) return;
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      icon: const Icon(Icons.warning_amber, size: 48, color: AppColors.error),
                      title: const Text('لا يمكن تسجيل الخروج'),
                      content: const Text(
                        'يجب عليك تسجيل الانصراف أولاً قبل تسجيل الخروج من الحساب.\n\n'
                        'الرجاء الضغط على زر "تسجيل الانصراف" من الصفحة الرئيسية.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('حسناً', style: TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                  );
                  return; // إيقاف عملية تسجيل الخروج
                }
              } catch (e) {
                print('⚠️ Failed to check attendance status: $e');
                // في حالة الخطأ، نسمح بالمتابعة
              }

              // إذا لم يكن مسجل حضور، نطلب التأكيد
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
