import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../owner/owner_salaries_screen.dart';
import '../owner/owner_comprehensive_payroll_page.dart';
import '../owner/owner_salary_advance_screen.dart';
import 'hr_payroll_page.dart';

/// Unified Owner & HR Payroll Management Screen
/// Combines salary payouts, comprehensive reports, salary advance approvals, and branch PDF reports.
class HROwnerPayrollScreen extends StatefulWidget {
  final String hrId;

  const HROwnerPayrollScreen({super.key, required this.hrId});

  @override
  State<HROwnerPayrollScreen> createState() => _HROwnerPayrollScreenState();
}

class _HROwnerPayrollScreenState extends State<HROwnerPayrollScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: AppColors.primaryOrange,
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: AppColors.primaryOrange,
            indicatorWeight: 3,
            labelStyle: GoogleFonts.tajawal(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
            unselectedLabelStyle: GoogleFonts.tajawal(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: const [
              Tab(
                icon: Icon(Icons.monetization_on_rounded, size: 20),
                text: 'صرف الرواتب',
              ),
              Tab(
                icon: Icon(Icons.analytics_rounded, size: 20),
                text: 'التقرير الشامل',
              ),
              Tab(
                icon: Icon(Icons.account_balance_wallet_rounded, size: 20),
                text: 'طلبات السلف',
              ),
              Tab(
                icon: Icon(Icons.picture_as_pdf_rounded, size: 20),
                text: 'تقارير الفروع',
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          OwnerSalariesScreen(ownerId: widget.hrId),
          const OwnerComprehensivePayrollPage(),
          OwnerSalaryAdvanceScreen(ownerId: widget.hrId),
          const HRPayrollPage(),
        ],
      ),
    );
  }
}
