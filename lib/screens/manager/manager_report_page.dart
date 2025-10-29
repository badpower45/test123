import 'dart:async';

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/requests_api_service.dart';

class ManagerReportPage extends StatefulWidget {
  final String managerId;
  final String branch;

  const ManagerReportPage({Key? key, required this.managerId, required this.branch}) : super(key: key);

  @override
  State<ManagerReportPage> createState() => _ManagerReportPageState();
}

class _ManagerReportPageState extends State<ManagerReportPage> {
  Map<String, dynamic>? _reportData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Load comprehensive report using manager's employeeId
      final reportData = await RequestsApiService.getComprehensiveReport(
        employeeId: widget.managerId,
        startDate: DateTime.now().subtract(const Duration(days: 30)).toIso8601String().split('T')[0],
        endDate: DateTime.now().toIso8601String().split('T')[0],
      );

      setState(() {
        _reportData = reportData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'فشل في تحميل التقرير: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير المدير'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: _loadReport,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('جاري تحميل التقرير...'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadReport,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : _buildReportContent(),
    );
  }

  Widget _buildReportContent() {
    if (_reportData == null) {
      return const Center(child: Text('لا توجد بيانات'));
    }

    final summary = _reportData!['summary'] ?? {};
    final salary = _reportData!['salary'] ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryOrange.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.description,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تقرير المدير الشامل',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'ملخص الأداء والحضور',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Stats Cards
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildStatCard(
                icon: Icons.calendar_month,
                label: 'أيام الحضور',
                value: '${summary['totalWorkDays'] ?? 0}',
                color: AppColors.info,
              ),
              _buildStatCard(
                icon: Icons.schedule,
                label: 'إجمالي الساعات',
                value: '${summary['totalWorkHours'] ?? '0.00'}',
                color: AppColors.success,
              ),
              _buildStatCard(
                icon: Icons.attach_money,
                label: 'إجمالي الراتب',
                value: '${salary['grossSalary']?.toStringAsFixed(2) ?? '0.00'}',
                color: AppColors.primaryOrange,
              ),
              _buildStatCard(
                icon: Icons.money_off,
                label: 'إجمالي الخصومات',
                value: '${salary['totalDeductions']?.toStringAsFixed(2) ?? '0.00'}',
                color: AppColors.error,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Detailed Breakdown
          const Text(
            'تفاصيل الراتب',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          _buildDetailCard(
            icon: Icons.waves,
            title: 'عدد النبضات الصالحة',
            value: '${salary['validPulses'] ?? 0}',
            color: AppColors.info,
          ),

          const SizedBox(height: 8),

          _buildDetailCard(
            icon: Icons.hourglass_bottom,
            title: 'راتب الساعات',
            value: '${salary['total_pay_hours']?.toStringAsFixed(2) ?? '0.00'} جنيه',
            color: AppColors.success,
          ),

          const SizedBox(height: 8),

          _buildDetailCard(
            icon: Icons.timeline,
            title: 'راتب النبضات',
            value: '${salary['total_pay_pulses']?.toStringAsFixed(2) ?? '0.00'} جنيه',
            color: AppColors.primaryOrange,
          ),

          const SizedBox(height: 8),

          _buildDetailCard(
            icon: Icons.account_balance_wallet,
            title: 'السلف المخصومة',
            value: '${salary['totalAdvances']?.toStringAsFixed(2) ?? '0.00'} جنيه',
            color: AppColors.warning,
          ),

          const SizedBox(height: 8),

          _buildDetailCard(
            icon: Icons.local_atm,
            title: 'حافز الغياب',
            value: '${salary['attendanceAllowance']?.toStringAsFixed(2) ?? '0.00'} جنيه',
            color: AppColors.success,
          ),

          const SizedBox(height: 8),

          _buildDetailCard(
            icon: Icons.payments,
            title: 'صافي الراتب',
            value: '${salary['netSalary']?.toStringAsFixed(2) ?? '0.00'} جنيه',
            color: AppColors.primaryOrange,
            isBold: true,
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    bool isBold = false,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: AppColors.textPrimary,
          ),
        ),
        trailing: Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: isBold ? color : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
