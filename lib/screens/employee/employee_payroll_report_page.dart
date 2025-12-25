import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/time_utils.dart';
import '../../services/payroll_service.dart';
import '../../services/supabase_function_client.dart';

class EmployeePayrollReportPage extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const EmployeePayrollReportPage({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<EmployeePayrollReportPage> createState() => _EmployeePayrollReportPageState();
}

class _EmployeePayrollReportPageState extends State<EmployeePayrollReportPage> {
  final PayrollService _payrollService = PayrollService();
  List<Map<String, dynamic>> _attendanceData = [];
  bool _isLoading = true;
  
  late DateTime _startDate;
  late DateTime _endDate;
  bool _isCurrentPeriod = true;

  // Summary totals
  double _totalHours = 0;
  double _totalSalary = 0;
  double _totalAdvances = 0;
  double _totalLeaveAllowance = 0;
  double _totalDeductions = 0;
  int _absenceDays = 0;
  // Approved advances list for display
  List<Map<String, dynamic>> _salaryAdvances = [];
  
  // Period-to-date earnings (current period)
  double _periodEarnings = 0.0;
  Timer? _earningsTimer;
  bool _advanceAppliedChecked = false;

  @override
  void initState() {
    super.initState();
    _calculateCurrentPeriod();
    _loadAttendanceReport();
    _applyAdvancePolicyOnce();
    _loadPeriodEarnings();
    
    // Update earnings every 30 seconds
    _earningsTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _loadPeriodEarnings();
    });
  }

  Future<void> _applyAdvancePolicyOnce() async {
    if (_advanceAppliedChecked) return;
    _advanceAppliedChecked = true;
    try {
      final result = await SupabaseFunctionClient.post('apply-advance-policy', {
        'employee_id': widget.employeeId,
      });
      print('💰 Advance policy result: $result');
    } catch (e) {
      print('⚠️ Advance policy error: $e');
    }
  }
  
  @override
  void dispose() {
    _earningsTimer?.cancel();
    super.dispose();
  }

  void _calculateCurrentPeriod() {
    final now = DateTime.now();
    
    if (now.day >= 16) {
      // من 16 الشهر الحالي إلى 15 الشهر القادم
      _startDate = DateTime(now.year, now.month, 16);
      _endDate = DateTime(now.year, now.month + 1, 15);
    } else {
      // من 16 الشهر الماضي إلى 15 الشهر الحالي
      _startDate = DateTime(now.year, now.month - 1, 16);
      _endDate = DateTime(now.year, now.month, 15);
    }
  }

  // ✅ Load current period-to-date earnings from Edge Function
  Future<void> _loadPeriodEarnings() async {
    try {
      final result = await SupabaseFunctionClient.post('employee-period-earnings', {
        'employee_id': widget.employeeId,
      });
      
      if ((result ?? {})['success'] == true && mounted) {
        final totals = (result ?? {})['totals'] as Map<String, dynamic>?;
        final periodNet = (totals?['net'] as num?)?.toDouble() ?? 0.0;
        final periodGross = (totals?['gross'] as num?)?.toDouble() ?? 0.0;
        
        print('📊 Period earnings loaded: gross=${periodGross.toStringAsFixed(2)}, net=${periodNet.toStringAsFixed(2)}');
        
        setState(() {
          _periodEarnings = periodNet;
        });
      }
    } catch (e) {
      // Silently fail, keep previous value
      print('❌ Failed to load period earnings: $e');
    }
  }

  Future<void> _loadAttendanceReport() async {
    setState(() => _isLoading = true);

    final data = await _payrollService.getEmployeeAttendanceReport(
      employeeId: widget.employeeId,
      startDate: _startDate,
      endDate: _endDate,
    );

    // Calculate totals
    double hours = 0;
    double salary = 0;
    double advances = 0;
    // leave allowance will be computed by rule below
    double deductions = 0;
    int absences = 0;

    for (final day in data) {
      hours += (day['total_hours'] as num?)?.toDouble() ?? 0;
      salary += (day['daily_salary'] as num?)?.toDouble() ?? 0;
      advances += (day['advance_amount'] as num?)?.toDouble() ?? 0;
      // ignore per-day leave_allowance; applied by rule globally
      deductions += (day['deduction_amount'] as num?)?.toDouble() ?? 0;
      if (day['is_absent'] == true) absences++;
    }

    // Fetch approved salary advances for this period
    final advancesList = await _payrollService.getEmployeeApprovedAdvances(
      employeeId: widget.employeeId,
      startDate: _startDate,
      endDate: _endDate,
    );
    double advancesSum = 0.0;
    for (final adv in advancesList) {
      advancesSum += (adv['amount'] as num?)?.toDouble() ?? 0.0;
    }
    
    print('📋 Loaded ${advancesList.length} approved advances totaling ${advancesSum.toStringAsFixed(2)} EGP');

    // Apply fixed 100 EGP allowance; remove if absenceDays > 2
    final fixedAllowance = (absences > 2) ? 0.0 : 100.0;

    setState(() {
      _attendanceData = data;
      _totalHours = hours;
      _totalSalary = salary;
      _salaryAdvances = advancesList;
      _totalAdvances = advances + advancesSum;
      _totalLeaveAllowance = fixedAllowance; // override by rule
      _totalDeductions = deductions;
      _absenceDays = absences;
      _isLoading = false;
    });
  }

  void _togglePeriod() {
    setState(() {
      _isCurrentPeriod = !_isCurrentPeriod;
      
      final now = DateTime.now();
      if (_isCurrentPeriod) {
        _calculateCurrentPeriod();
      } else {
        // الفترة السابقة
        if (now.day >= 16) {
          _startDate = DateTime(now.year, now.month - 1, 16);
          _endDate = DateTime(now.year, now.month, 15);
        } else {
          _startDate = DateTime(now.year, now.month - 2, 16);
          _endDate = DateTime(now.year, now.month - 1, 15);
        }
      }
    });
    _loadAttendanceReport();
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
            const Text(
              'تقرير الحضور والمرتب',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAttendanceReport,
          ),
          IconButton(
            icon: Icon(_isCurrentPeriod ? Icons.history : Icons.update),
            onPressed: _togglePeriod,
            tooltip: _isCurrentPeriod ? 'الفترة السابقة' : 'الفترة الحالية',
          ),
        ],
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'الفترة: ${DateFormat('dd/MM/yyyy').format(_startDate)} - ${DateFormat('dd/MM/yyyy').format(_endDate)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _isCurrentPeriod ? Colors.green : Colors.orange,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Text(
                              _isCurrentPeriod ? 'الفترة الحالية' : 'الفترة السابقة',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
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

                // Period-to-date Earnings Card - Shows current period net
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.blue.shade700, Colors.blue.shade500]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.summarize, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'إجمالي المكتسب حتى الآن',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_periodEarnings.toStringAsFixed(2)} ج.م',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Builder(builder: (_) {
                            return const Text(
                              'صافي بعد خصم النبضات',
                              style: TextStyle(color: Colors.white70, fontSize: 11),
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Attendance Table Header
                Container(
                  color: Colors.grey.shade200,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  child: const Row(
                    children: [
                      Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      Expanded(flex: 2, child: Text('حضور', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      Expanded(flex: 2, child: Text('انصراف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      Expanded(flex: 1, child: Text('ساعات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      Expanded(flex: 2, child: Text('مرتب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    ],
                  ),
                ),

                // Attendance Table Data
                Expanded(
                  child: _attendanceData.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('لا توجد بيانات حضور لهذه الفترة'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _attendanceData.length + (_salaryAdvances.isEmpty ? 0 : (_salaryAdvances.length + 1)),
                          itemBuilder: (context, index) {
                            // If within attendance rows
                            if (index < _attendanceData.length) {
                              final day = _attendanceData[index];
                            final date = DateTime.parse(day['attendance_date'] as String);
                            final rawCheckIn = day['check_in_time'] as String?;
                            final rawCheckOut = day['check_out_time'] as String?;
                            final checkIn = TimeUtils.formatTimeShort(rawCheckIn);
                            final checkOut = TimeUtils.formatTimeShort(rawCheckOut);
                            final hours = (day['total_hours'] as num?)?.toDouble() ?? 0;
                            final dailySalary = (day['daily_salary'] as num?)?.toDouble() ?? 0;
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
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
                                          style: const TextStyle(fontSize: 9, color: Colors.grey),
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
                                ],
                              ),
                            );
                            }

                            // Past attendance rows: first show a header row for deductions/advances
                            final advIndex = index - _attendanceData.length;
                            if (advIndex == 0) {
                              return Container(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                color: Colors.orange.shade50,
                                child: const Row(
                                  children: [
                                    Icon(Icons.money_off, size: 18, color: Colors.orange),
                                    SizedBox(width: 8),
                                    Text('السلف المعتمدة خلال الفترة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  ],
                                ),
                              );
                            }

                            final adv = _salaryAdvances[advIndex - 1];
                            final dateStr = (adv['approved_at'] ?? adv['created_at']) as String?;
                            final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
                            final amount = (adv['amount'] as num?)?.toDouble() ?? 0.0;
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                border: Border(bottom: BorderSide(color: Colors.orange.shade100, width: 0.5)),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              child: Row(
                                children: [
                                  const Expanded(flex: 2, child: Text('—', style: TextStyle(fontSize: 11, color: Colors.orange))),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'سلفة (${date != null ? DateFormat('dd/MM').format(date) : '-'})',
                                      style: const TextStyle(fontSize: 11, color: Colors.orange),
                                    ),
                                  ),
                                  const Expanded(flex: 2, child: Text('-', style: TextStyle(fontSize: 11, color: Colors.orange))),
                                  const Expanded(flex: 1, child: Text('-', style: TextStyle(fontSize: 11, color: Colors.orange))),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '-${amount.toStringAsFixed(0)}',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange),
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
