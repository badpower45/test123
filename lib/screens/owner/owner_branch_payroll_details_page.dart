import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/payroll_service.dart';
import 'owner_employee_payroll_report_page.dart';

class OwnerBranchPayrollDetailsPage extends StatefulWidget {
  final String cycleId;
  final String branchName;
  final DateTime startDate;
  final DateTime endDate;

  const OwnerBranchPayrollDetailsPage({
    super.key,
    required this.cycleId,
    required this.branchName,
    required this.startDate,
    required this.endDate,
  });

  @override
  State<OwnerBranchPayrollDetailsPage> createState() => _OwnerBranchPayrollDetailsPageState();
}

class _OwnerBranchPayrollDetailsPageState extends State<OwnerBranchPayrollDetailsPage> {
  final PayrollService _payrollService = PayrollService();
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;
  double _totalAmount = 0;

  @override
  void initState() {
    super.initState();
    _loadEmployeesPayroll();
  }

  Future<void> _loadEmployeesPayroll() async {
    setState(() => _isLoading = true);
    
    final employees = await _payrollService.getBranchEmployeesPayroll(widget.cycleId);
    
    double total = 0;
    for (final emp in employees) {
      if (emp['status'] == 'pending') {
        total += (emp['net_salary'] as num?)?.toDouble() ?? 0;
      }
    }
    
    setState(() {
      _employees = employees;
      _totalAmount = total;
      _isLoading = false;
    });
  }

  Future<void> _markEmployeeAsPaid(String payrollId, String employeeName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الدفع'),
        content: Text('هل أنت متأكد من دفع مرتب $employeeName؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('نعم، تم الدفع'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _payrollService.markEmployeePayrollPaid(
        payrollId: payrollId,
        cycleId: widget.cycleId,
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تسجيل الدفع بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        _loadEmployeesPayroll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ فشل تسجيل الدفع'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.branchName),
            Text(
              'الفترة: ${DateFormat('dd/MM').format(widget.startDate)} - ${DateFormat('dd/MM/yyyy').format(widget.endDate)}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Summary Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.deepPurple, Colors.deepPurple.shade300],
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'إجمالي المرتبات المعلقة',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_totalAmount.toStringAsFixed(2)} ج.م',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_employees.where((e) => e['status'] == 'pending').length} موظف',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                // Employees List
                Expanded(
                  child: _employees.isEmpty
                      ? const Center(
                          child: Text('لا يوجد موظفين في هذا الفرع'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _employees.length,
                          itemBuilder: (context, index) {
                            final employee = _employees[index];
                            final employeeData = employee['employees'] as Map<String, dynamic>;
                            final employeeName = employeeData['name'] as String;
                            final employeeId = employee['employee_id'] as String;
                            final payrollId = employee['id'] as String;
                            final netSalary = (employee['net_salary'] as num?)?.toDouble() ?? 0;
                            final totalHours = (employee['total_hours'] as num?)?.toDouble() ?? 0;
                            final hourlyRate = (employee['hourly_rate'] as num?)?.toDouble() ?? 0;
                            final status = employee['status'] as String;
                            final isPaid = status == 'paid';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isPaid ? Colors.green.shade200 : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => OwnerEmployeePayrollReportPage(
                                        employeeId: employeeId,
                                        employeeName: employeeName,
                                        startDate: widget.startDate,
                                        endDate: widget.endDate,
                                      ),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: isPaid ? Colors.green : Colors.deepPurple,
                                            child: Text(
                                              employeeName[0].toUpperCase(),
                                              style: const TextStyle(color: Colors.white),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  employeeName,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text(
                                                  '${totalHours.toStringAsFixed(1)} ساعة × ${hourlyRate.toStringAsFixed(2)} ج.م',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isPaid ? Colors.green.shade50 : Colors.orange.shade50,
                                              borderRadius: BorderRadius.circular(15),
                                            ),
                                            child: Text(
                                              isPaid ? 'مدفوع' : 'معلق',
                                              style: TextStyle(
                                                color: isPaid ? Colors.green : Colors.orange,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 20),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          _buildInfoChip(
                                            'بدل إجازة',
                                            '${(employee['leave_allowance'] as num?)?.toDouble() ?? 0} ج.م',
                                            Colors.green,
                                          ),
                                          _buildInfoChip(
                                            'السلف',
                                            '${(employee['total_advances'] as num?)?.toDouble() ?? 0} ج.م',
                                            Colors.orange,
                                          ),
                                          _buildInfoChip(
                                            'الخصومات',
                                            '${(employee['total_deductions'] as num?)?.toDouble() ?? 0} ج.م',
                                            Colors.red,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'صافي المرتب:',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            '${netSalary.toStringAsFixed(2)} ج.م',
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.deepPurple,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (!isPaid) ...[
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            onPressed: () => _markEmployeeAsPaid(payrollId, employeeName),
                                            icon: const Icon(Icons.payment, size: 18),
                                            label: const Text('دفع'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (isPaid && employee['paid_at'] != null) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(Icons.check_circle, color: Colors.green, size: 14),
                                            const SizedBox(width: 6),
                                            Builder(builder: (context) {
                                              try {
                                                return Text(
                                                  'تم الدفع في ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(employee['paid_at'] as String))}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.green,
                                                  ),
                                                );
                                              } catch (e) {
                                                return const Text('تم الدفع', style: TextStyle(fontSize: 11, color: Colors.green));
                                              }
                                            }),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
