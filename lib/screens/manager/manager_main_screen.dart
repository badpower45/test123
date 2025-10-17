import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../employee/requests_page.dart';
import '../branch_manager_screen.dart';

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
      body: RequestsPage(
        employeeId: managerId,
        hideBreakTab: true,
      ),
    );
  }
}
