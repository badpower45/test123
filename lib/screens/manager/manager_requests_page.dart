import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../employee/requests/advance_requests_tab.dart';
import '../employee/requests/leave_requests_tab.dart';

class ManagerRequestsPage extends StatefulWidget {
  const ManagerRequestsPage({
    super.key,
    required this.managerId,
  });

  final String managerId;

  @override
  State<ManagerRequestsPage> createState() => _ManagerRequestsPageState();
}

class _ManagerRequestsPageState extends State<ManagerRequestsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Tab>[
      const Tab(icon: Icon(Icons.event_available), text: 'الإجازات'),
      const Tab(icon: Icon(Icons.payments), text: 'السلف'),
    ];

    final views = <Widget>[
      LeaveRequestsTab(employeeId: widget.managerId),
      AdvanceRequestsTab(employeeId: widget.managerId),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('الطلبات'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryOrange,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primaryOrange,
          tabs: tabs,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: views,
      ),
    );
  }
}