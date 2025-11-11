import 'package:flutter/material.dart';
import '../../services/payroll_service.dart';
import '../../theme/app_colors.dart';

class OwnerComprehensivePayrollPage extends StatefulWidget {
  const OwnerComprehensivePayrollPage({super.key});

  @override
  State<OwnerComprehensivePayrollPage> createState() => _OwnerComprehensivePayrollPageState();
}

class _OwnerComprehensivePayrollPageState extends State<OwnerComprehensivePayrollPage> {
  bool _isCurrentPeriod = true;
  bool _isLoading = false;
  List<Map<String, dynamic>> _allEmployeesData = [];
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _calculateCurrentPeriod();
    _loadAllPayrollData();
  }

  void _calculateCurrentPeriod() {
    final now = DateTime.now();
    if (now.day >= 16) {
      // Current period: 16th of this month to 15th of next month
      _startDate = DateTime(now.year, now.month, 16);
      _endDate = DateTime(now.year, now.month + 1, 15);
    } else {
      // Current period: 16th of last month to 15th of this month
      _startDate = DateTime(now.year, now.month - 1, 16);
      _endDate = DateTime(now.year, now.month, 15);
    }
  }

  void _togglePeriod() {
    setState(() {
      _isCurrentPeriod = !_isCurrentPeriod;
      if (_isCurrentPeriod) {
        _calculateCurrentPeriod();
      } else {
        // Previous period
        final prevStart = DateTime(_startDate.year, _startDate.month - 1, 16);
        final prevEnd = DateTime(_startDate.year, _startDate.month, 15);
        _startDate = prevStart;
        _endDate = prevEnd;
      }
      _loadAllPayrollData();
    });
  }

  Future<void> _loadAllPayrollData() async {
    setState(() => _isLoading = true);
    try {
      // Get all employees attendance data (Owner can see all)
      final data = await PayrollService.getAllEmployeesAttendanceReport(
        startDate: _startDate,
        endDate: _endDate,
      );
      
      setState(() {
        _allEmployeesData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('التقرير الشامل للمرتبات'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isCurrentPeriod ? Icons.history : Icons.calendar_today),
            onPressed: _togglePeriod,
            tooltip: _isCurrentPeriod ? 'عرض الفترة السابقة' : 'عرض الفترة الحالية',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllPayrollData,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Period Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primaryOrange, AppColors.primaryOrange.withOpacity(0.8)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        _isCurrentPeriod ? 'الفترة الحالية' : 'الفترة السابقة',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_formatDate(_startDate)} - ${_formatDate(_endDate)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Summary Cards
                _buildSummarySection(),

                // Employees List
                Expanded(
                  child: _allEmployeesData.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد بيانات حضور للموظفين في هذه الفترة',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _allEmployeesData.length,
                          itemBuilder: (context, index) {
                            final employeeData = _allEmployeesData[index];
                            return _buildEmployeeCard(employeeData);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummarySection() {
    // Calculate totals
    double totalHours = 0;
    double totalBaseSalary = 0;
    double totalNetSalary = 0;
    int totalEmployees = _allEmployeesData.length;

    for (var emp in _allEmployeesData) {
      final summary = emp['summary'] as Map<String, dynamic>?;
      if (summary != null) {
        totalHours += (summary['total_hours'] as num?)?.toDouble() ?? 0;
        totalBaseSalary += (summary['base_salary'] as num?)?.toDouble() ?? 0;
        totalNetSalary += (summary['net_salary'] as num?)?.toDouble() ?? 0;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'إجمالي الموظفين',
                  totalEmployees.toString(),
                  Icons.people,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'إجمالي الساعات',
                  totalHours.toStringAsFixed(1),
                  Icons.access_time,
                  Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'إجمالي المرتبات',
                  '${totalBaseSalary.toStringAsFixed(0)} ج',
                  Icons.payments,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'صافي الإجمالي',
                  '${totalNetSalary.toStringAsFixed(0)} ج',
                  Icons.account_balance_wallet,
                  AppColors.primaryOrange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(Map<String, dynamic> employeeData) {
    final employeeName = employeeData['employee_name'] as String? ?? 'موظف';
    final employeeId = employeeData['employee_id'] as String? ?? '';
    final branch = employeeData['branch'] as String? ?? 'غير محدد';
    final summary = employeeData['summary'] as Map<String, dynamic>?;

    if (summary == null) {
      return const SizedBox.shrink();
    }

    final totalHours = (summary['total_hours'] as num?)?.toDouble() ?? 0;
    final baseSalary = (summary['base_salary'] as num?)?.toDouble() ?? 0;
    final leaveAllowance = (summary['leave_allowance'] as num?)?.toDouble() ?? 0;
    final advances = (summary['total_advances'] as num?)?.toDouble() ?? 0;
    final deductions = (summary['total_deductions'] as num?)?.toDouble() ?? 0;
    final netSalary = (summary['net_salary'] as num?)?.toDouble() ?? 0;
    final absenceDays = (summary['absence_days'] as num?)?.toInt() ?? 0;
    final hourlyRate = (summary['hourly_rate'] as num?)?.toDouble() ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryOrange,
          child: Text(
            employeeName.isNotEmpty ? employeeName[0].toUpperCase() : 'M',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          employeeName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text('الفرع: $branch'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${netSalary.toStringAsFixed(0)} ج',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.success,
              ),
            ),
            const Text(
              'صافي المرتب',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Basic Info
                _buildDetailRow('معرف الموظف', employeeId, Icons.badge),
                _buildDetailRow('سعر الساعة', '${hourlyRate.toStringAsFixed(0)} ج', Icons.attach_money),
                const Divider(height: 24),

                // Hours and Days
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoBox(
                        'إجمالي الساعات',
                        totalHours.toStringAsFixed(1),
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoBox(
                        'أيام الغياب',
                        absenceDays.toString(),
                        Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Salary Calculation
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      _buildCalculationRow('المرتب الأساسي', baseSalary, Colors.black87),
                      if (leaveAllowance > 0)
                        _buildCalculationRow('بدل الإجازة', leaveAllowance, Colors.green),
                      if (advances > 0)
                        _buildCalculationRow('السلف', -advances, Colors.orange),
                      if (deductions > 0)
                        _buildCalculationRow('الخصومات', -deductions, Colors.red),
                      const Divider(height: 20),
                      _buildCalculationRow('الصافي', netSalary, AppColors.success, isBold: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculationRow(String label, double amount, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
          Text(
            '${amount >= 0 ? '+' : ''}${amount.toStringAsFixed(0)} ج',
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
