import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../branch_manager_screen.dart';
import 'attendance_page.dart';
import 'attendance_requests_page.dart';
import 'manager_report_page.dart';
import 'manager_profile_page.dart';

class ManagerMainScreen extends StatelessWidget {
  final String managerId;
  final String branch;
  final String? role;

  const ManagerMainScreen({
    Key? key,
    required this.managerId,
    required this.branch,
    this.role,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('الرئيسية (مدير)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_customize),
            tooltip: 'لوحة تحكم المدير',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BranchManagerScreen(
                    managerId: managerId,
                    branchName: branch,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.event_available, color: AppColors.primaryOrange),
            title: const Text('سجلات الحضور والغياب'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AttendancePage(managerId: managerId, branch: branch),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.event_note, color: AppColors.info),
            title: const Text('طلبات الحضور والانصراف'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AttendanceRequestsPage(managerId: managerId, branch: branch),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart, color: AppColors.success),
            title: const Text('التقرير'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ManagerReportPage(managerId: managerId, branch: branch),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person, color: AppColors.textPrimary),
            title: const Text('الملف الشخصي'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ManagerProfilePage(managerId: managerId),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
