import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/payroll_service.dart';

class OwnerEmployeePayrollReportPage extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final DateTime startDate;
  final DateTime endDate;

  const OwnerEmployeePayrollReportPage({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.startDate,
    required this.endDate,
  });

  @override
  State<OwnerEmployeePayrollReportPage> createState() => _OwnerEmployeePayrollReportPageState();
}

class _OwnerEmployeePayrollReportPageState extends State<OwnerEmployeePayrollReportPage> {
  final PayrollService _payrollService = PayrollService();
  List<Map<String, dynamic>> _attendanceData = [];
  bool _isLoading = true;

  // Summary totals
  double _totalHours = 0;
  double _totalSalary = 0;
  double _totalAdvances = 0;
  double _totalLeaveAllowance = 0;
  double _totalDeductions = 0;
  int _absenceDays = 0;

  @override
  void initState() {
    super.initState();
    _loadAttendanceReport();
  }

  Future<void> _loadAttendanceReport() async {
    setState(() => _isLoading = true);

    final data = await _payrollService.getEmployeeAttendanceReport(
      employeeId: widget.employeeId,
      startDate: widget.startDate,
      endDate: widget.endDate,
    );

    // Calculate totals
    double hours = 0;
    double salary = 0;
    double advances = 0;
    double leaveAllowance = 0;
    double deductions = 0;
    int absences = 0;

    for (final day in data) {
      hours += (day['total_hours'] as num?)?.toDouble() ?? 0;
      salary += (day['daily_salary'] as num?)?.toDouble() ?? 0;
      advances += (day['advance_amount'] as num?)?.toDouble() ?? 0;
      leaveAllowance += (day['leave_allowance'] as num?)?.toDouble() ?? 0;
      deductions += (day['deduction_amount'] as num?)?.toDouble() ?? 0;
      if (day['is_absent'] == true) absences++;
    }

    setState(() {
      _attendanceData = data;
      _totalHours = hours;
      _totalSalary = salary;
      _totalAdvances = advances;
      _totalLeaveAllowance = leaveAllowance;
      _totalDeductions = deductions;
      _absenceDays = absences;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final netSalary = _totalSalary + _totalLeaveAllowance - _totalAdvances - _totalDeductions;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.employeeName),
            Text(
              'تقرير الحضور والمرتب',
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
                // Summary Section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.deepPurple, Colors.deepPurple.shade300],
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'الفترة: ${DateFormat('dd/MM/yyyy').format(widget.startDate)} - ${DateFormat('dd/MM/yyyy').format(widget.endDate)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildSummaryItem('الساعات', '${_totalHours.toStringAsFixed(1)} س', Icons.access_time),
                          _buildSummaryItem('أيام غياب', '$_absenceDays', Icons.event_busy),
                          _buildSummaryItem('المرتب الأساسي', '${_totalSalary.toStringAsFixed(0)} ج.م', Icons.attach_money),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white30),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'صافي المرتب:',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${netSalary.toStringAsFixed(2)} ج.م',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Breakdown Cards
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildBreakdownCard(
                          'بدل إجازة',
                          _totalLeaveAllowance,
                          Colors.green,
                          Icons.card_giftcard,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildBreakdownCard(
                          'السلف',
                          _totalAdvances,
                          Colors.orange,
                          Icons.money_off,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildBreakdownCard(
                          'الخصومات',
                          _totalDeductions,
                          Colors.red,
                          Icons.remove_circle,
                        ),
                      ),
                    ],
                  ),
                ),

                // Attendance Table Header
                Container(
                  color: Colors.grey.shade200,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: const Row(
                    children: [
                      Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(flex: 2, child: Text('الحضور', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(flex: 2, child: Text('الانصراف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(flex: 1, child: Text('ساعات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(flex: 2, child: Text('المرتب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(flex: 1, child: Text('سلف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(flex: 1, child: Text('بدل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(flex: 1, child: Text('خصم', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    ],
                  ),
                ),

                // Attendance Table Data
                Expanded(
                  child: _attendanceData.isEmpty
                      ? const Center(
                          child: Text('لا توجد بيانات حضور'),
                        )
                      : ListView.builder(
                          itemCount: _attendanceData.length,
                          itemBuilder: (context, index) {
                            final day = _attendanceData[index];
                            DateTime date;
                            try {
                              date = DateTime.parse(day['attendance_date']?.toString() ?? '');
                            } catch (e) {
                              date = DateTime.now();
                            }
                            String checkIn = day['check_in_time'] as String? ?? '--';
                            String checkOut = day['check_out_time'] as String? ?? '--';
                            if (checkIn.isEmpty || checkIn == '-' || checkIn == 'null') checkIn = '--';
                            if (checkOut.isEmpty || checkOut == '-' || checkOut == 'null') checkOut = '--';
                            final hours = (day['total_hours'] as num?)?.toDouble() ?? 0;
                            final dailySalary = (day['daily_salary'] as num?)?.toDouble() ?? 0;
                            final advance = (day['advance_amount'] as num?)?.toDouble() ?? 0;
                            final leaveAllowance = (day['leave_allowance'] as num?)?.toDouble() ?? 0;
                            final deduction = (day['deduction_amount'] as num?)?.toDouble() ?? 0;
                            final isAbsent = day['is_absent'] == true;
                            final isOnLeave = day['is_on_leave'] == true;

                            return Container(
                              decoration: BoxDecoration(
                                color: isAbsent || isOnLeave
                                    ? Colors.red.shade50
                                    : index % 2 == 0
                                        ? Colors.white
                                        : Colors.grey.shade50,
                                border: Border(
                                  bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          DateFormat('dd/MM').format(date),
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                        ),
                                        Text(
                                          DateFormat('EEEE', 'ar').format(date),
                                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      isAbsent ? 'غياب' : (isOnLeave ? 'إجازة' : checkIn),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isAbsent ? Colors.red : Colors.black87,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      checkOut,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      hours > 0 ? hours.toStringAsFixed(1) : '-',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      dailySalary > 0 ? '${dailySalary.toStringAsFixed(0)}' : '-',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      advance > 0 ? '${advance.toStringAsFixed(0)}' : '-',
                                      style: const TextStyle(fontSize: 10, color: Colors.orange),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      leaveAllowance > 0 ? '${leaveAllowance.toStringAsFixed(0)}' : '-',
                                      style: const TextStyle(fontSize: 10, color: Colors.green),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      deduction > 0 ? '${deduction.toStringAsFixed(0)}' : '-',
                                      style: const TextStyle(fontSize: 10, color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                // Final Summary Footer
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade400, width: 2),
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildTotalRow('المرتب الأساسي', _totalSalary, Colors.black),
                      _buildTotalRow('+ بدل الإجازة', _totalLeaveAllowance, Colors.green),
                      _buildTotalRow('- السلف', _totalAdvances, Colors.orange),
                      _buildTotalRow('- الخصومات', _totalDeductions, Colors.red),
                      const Divider(thickness: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'صافي المرتب النهائي',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${netSalary.toStringAsFixed(2)} ج.م',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownCard(String title, double amount, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 10, color: Colors.black87),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            '${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: color),
          ),
          Text(
            '${amount.toStringAsFixed(2)} ج.م',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
