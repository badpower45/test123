import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../services/payroll_service.dart';
import '../../utils/owner_time_utils.dart';

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
  State<OwnerEmployeePayrollReportPage> createState() =>
      _OwnerEmployeePayrollReportPageState();
}

class _OwnerEmployeePayrollReportPageState
    extends State<OwnerEmployeePayrollReportPage> {
  final PayrollService _payrollService = PayrollService();
  List<Map<String, dynamic>> _attendanceData = [];
  bool _isLoading = true;
  bool _isAllTime = false;
  DateTime? _employeeStartDate;

  // Summary totals
  double _totalHours = 0;
  double _totalSalary = 0;
  double _totalAdvances = 0;
  double _totalLeaveAllowance = 0;
  double _totalBonuses = 0;
  double _totalDeductions = 0;
  double _totalPenalties = 0;
  int _absenceDays = 0;
  int _leaveDays = 0;
  double _hourlyRate = 0;

  @override
  void initState() {
    super.initState();
    _loadEmployeeStartDate();
  }

  Future<void> _loadEmployeeStartDate() async {
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('employees')
          .select('created_at')
          .eq('id', widget.employeeId)
          .single();

      if (mounted) {
        setState(() {
          _employeeStartDate = response['created_at'] != null
              ? DateTime.tryParse(response['created_at'].toString())
              : null;
        });
      }
    } catch (e) {
      print('Error loading employee start date: $e');
    }
    _loadAttendanceReport();
  }

  Future<void> _loadAttendanceReport() async {
    setState(() => _isLoading = true);

    DateTime startDate = widget.startDate;
    DateTime endDate = widget.endDate;

    if (_isAllTime && _employeeStartDate != null) {
      startDate = _employeeStartDate!;
      endDate = DateTime.now();
    }

    // Get persisted leave allowance from employee record as fallback
    double persistedLeaveAllowance = 100.0; // Default
    try {
      final client = Supabase.instance.client;
      final empResponse = await client
          .from('employees')
          .select('leave_allowance, hourly_rate')
          .eq('id', widget.employeeId)
          .maybeSingle();

      if (empResponse != null && empResponse['leave_allowance'] != null) {
        persistedLeaveAllowance = (empResponse['leave_allowance'] as num)
            .toDouble();
        print('✓ Fetched persisted leave allowance: $persistedLeaveAllowance');
      } else {
        // Column might not exist yet - use default
        persistedLeaveAllowance = 100.0;
        print('ℹ️ Using default leave allowance: 100.0');
      }

      _hourlyRate = (empResponse?['hourly_rate'] is num)
          ? (empResponse?['hourly_rate'] as num).toDouble()
          : double.tryParse(empResponse?['hourly_rate']?.toString() ?? '') ??
                0.0;
    } catch (e) {
      // Column doesn't exist in database - use default
      print('⚠️ Could not fetch persisted leave allowance: $e');
      persistedLeaveAllowance = 100.0;
    }

    // Calculate leave allowance using edge function
    final now = DateTime.now();
    final currentMonth = now.month;
    final currentYear = now.year;

    print(
      '🔄 Attempting to calculate leave allowance for ${widget.employeeId} (${widget.employeeName})',
    );

    double calculatedLeaveAllowance = await _payrollService
        .calculateLeaveAllowance(
          employeeId: widget.employeeId,
          employeeName: widget.employeeName,
          month: currentMonth,
          year: currentYear,
        );

    print(
      '📊 Calculation result: $calculatedLeaveAllowance (persisted: $persistedLeaveAllowance)',
    );

    // If edge function returned 0, use persisted value as fallback
    // (0 might mean failed calculation, not "no allowance")
    if (calculatedLeaveAllowance == 0.0) {
      print(
        '⚠️ Edge function returned 0, falling back to persisted: $persistedLeaveAllowance',
      );
      calculatedLeaveAllowance = persistedLeaveAllowance;
    } else {
      print('✅ Using calculated leave allowance: $calculatedLeaveAllowance');
    }

    final legacyData = await _payrollService
        .getEmployeeAttendanceReportLegacyFormat(
          employeeId: widget.employeeId,
          startDate: startDate,
          endDate: endDate,
        );

    double _num(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    // PayrollService returns:
    // {
    //   tableRows: [...],
    //   summary: { totalWorkHours, grossSalary, totalAdvances, ... }
    // }
    // Keep fallback to old keys for backward compatibility.
    final summary =
        (legacyData['summary'] as Map<String, dynamic>?) ??
        (legacyData['Summary'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    double hours =
        _num(summary['totalWorkHours']) + _num(legacyData['total_work_hours']);
    double salary =
        _num(summary['grossSalary']) + _num(legacyData['gross_salary']);
    double advances =
        _num(summary['totalAdvances']) + _num(legacyData['total_advances']);
    double deductions =
        _num(summary['totalDeductions']) + _num(legacyData['total_deductions']);
    double penalties =
        _num(summary['totalPenalties']) + _num(legacyData['total_penalties']);
    double bonuses =
        _num(summary['totalBonuses']) + _num(legacyData['total_bonuses']);
    // Override leave allowance with calculated value from edge function
    double leaveAllowance = calculatedLeaveAllowance;

    // Avoid double-counting when only one response shape is present.
    if (summary.isNotEmpty) {
      hours = _num(summary['totalWorkHours']);
      salary = _num(summary['grossSalary']);
      advances = _num(summary['totalAdvances']);
      deductions = _num(summary['totalDeductions']);
      penalties = _num(summary['totalPenalties']);
      bonuses = _num(summary['totalBonuses']);
      // Keep the calculated leave allowance (do not override)
      // leaveAllowance remains as calculatedLeaveAllowance
    }

    int absences = 0;
    int leaveDays = 0;

    List<dynamic> tableRows =
        (legacyData['tableRows'] as List?) ??
        (legacyData['table_rows'] as List?) ??
        [];
    List<Map<String, dynamic>> mappedData = [];

    for (var row in tableRows) {
      double advance = double.tryParse(row['advances'].toString()) ?? 0.0;
      double leave = double.tryParse(row['leaveAllowance'].toString()) ?? 0.0;
      double bonus = double.tryParse(row['bonuses'].toString()) ?? 0.0;
      double deduction = double.tryParse(row['deductions'].toString()) ?? 0.0;
      double penalty = double.tryParse(row['penalties'].toString()) ?? 0.0;
      double wHours = double.tryParse(row['workHours'].toString()) ?? 0.0;

      bool isLeave = row['hasLeave'] == true;
      bool isAbsent = (wHours == 0 && !isLeave);
      if (isAbsent) absences++;
      if (isLeave) leaveDays++;

      mappedData.add({
        'attendance_date': row['date'],
        'check_in_time': row['checkIn'],
        'check_out_time': row['checkOut'],
        'total_hours': wHours,
        'daily_salary':
            double.tryParse(row['dailySalary']?.toString() ?? '') ??
            ((hours > 0 && wHours > 0) ? (salary / hours * wHours) : 0.0),
        'advance_amount': advance,
        'leave_allowance': leave,
        'bonus_amount': bonus,
        'deduction_amount': deduction,
        'penalty_amount': penalty,
        'is_absent': isAbsent,
        'is_on_leave': isLeave,
      });
    }

    // Sort the mapped data by date ascending
    mappedData.sort(
      (a, b) => (a['attendance_date'] ?? '').toString().compareTo(
        (b['attendance_date'] ?? '').toString(),
      ),
    );

    setState(() {
      _attendanceData = mappedData;
      _totalHours = hours;
      _totalSalary = salary;
      _totalAdvances = advances;
      _totalLeaveAllowance = leaveAllowance;
      _totalBonuses = bonuses;
      _totalDeductions = deductions;
      _totalPenalties = penalties;
      _absenceDays = absences;
      _leaveDays = leaveDays;
      _isLoading = false;
    });
  }

  void _toggleAllTimeReport() {
    setState(() {
      _isAllTime = !_isAllTime;
    });
    _loadAttendanceReport();
  }

  @override
  Widget build(BuildContext context) {
    final netSalary =
        _totalSalary +
        _totalLeaveAllowance +
        _totalBonuses -
        _totalAdvances -
        _totalDeductions;

    DateTime displayStartDate = widget.startDate;
    DateTime displayEndDate = widget.endDate;
    if (_isAllTime && _employeeStartDate != null) {
      displayStartDate = _employeeStartDate!;
      displayEndDate = DateTime.now();
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.employeeName),
            Text(
              _isAllTime ? 'تقرير كامل فترة العمل' : 'تقرير الحضور والمرتب',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          if (_employeeStartDate != null)
            TextButton.icon(
              onPressed: _toggleAllTimeReport,
              icon: Icon(
                _isAllTime ? Icons.history : Icons.all_inclusive,
                color: Colors.white,
                size: 20,
              ),
              label: Text(
                _isAllTime ? 'فترة محددة' : 'كل التواريخ',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          IconButton(
            onPressed: _printReport,
            icon: const Icon(Icons.print, color: Colors.white),
            tooltip: 'طباعة',
          ),
          IconButton(
            onPressed: _loadAttendanceReport,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      // Summary Section
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.deepPurple,
                              Colors.deepPurple.shade300,
                            ],
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'الفترة: ${DateFormat('dd/MM/yyyy').format(displayStartDate)} - ${DateFormat('dd/MM/yyyy').format(displayEndDate)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildSummaryItem(
                                  'الساعات',
                                  '${_totalHours.toStringAsFixed(1)} س',
                                  Icons.access_time,
                                ),
                                _buildSummaryItem(
                                  'سعر الساعة',
                                  '${_hourlyRate.toStringAsFixed(2)} ج.م',
                                  Icons.payments,
                                ),
                                _buildSummaryItem(
                                  'أيام الإجازات',
                                  '$_leaveDays',
                                  Icons.event_available,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Additional details row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildSummaryItem(
                                  'المرتب الأساسي',
                                  '${_totalSalary.toStringAsFixed(0)} ج.م',
                                  Icons.attach_money,
                                ),
                                _buildSummaryItem(
                                  'المكافآت',
                                  '${_totalBonuses.toStringAsFixed(2)} ج.م',
                                  Icons.emoji_events,
                                ),
                                _buildSummaryItem(
                                  'السلف',
                                  '${_totalAdvances.toStringAsFixed(2)} ج.م',
                                  Icons.money_off,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildSummaryItem(
                                  'بدل الإجازة',
                                  '${_totalLeaveAllowance.toStringAsFixed(2)} ج.م',
                                  Icons.card_giftcard,
                                ),
                                _buildSummaryItem(
                                  'الخصومات',
                                  '${_totalDeductions.toStringAsFixed(2)} ج.م',
                                  Icons.remove_circle,
                                ),
                                _buildSummaryItem(
                                  'أيام الغياب',
                                  '$_absenceDays',
                                  Icons.event_busy,
                                ),
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
                                'المكافآت',
                                _totalBonuses,
                                Colors.blue,
                                Icons.emoji_events,
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildBreakdownCard(
                                'الجزاءات',
                                _totalPenalties,
                                Colors.deepOrange,
                                Icons.gavel,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Attendance Table Header
                      Container(
                        color: Colors.grey.shade200,
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        child: const Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                'التاريخ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'الحضور',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'الانصراف',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'ساعات',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'المرتب',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'سلف',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'بدل',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'مكافأة',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'خصم',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Attendance Table Data
                _attendanceData.isEmpty
                    ? const SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: Text('لا توجد بيانات حضور'),
                          ),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final day = _attendanceData[index];
                          DateTime date;
                          try {
                            date = DateTime.parse(
                              day['attendance_date']?.toString() ?? '',
                            );
                          } catch (e) {
                            date = DateTime.now();
                          }
                          final checkIn = _formatAttendanceTime(
                            day['check_in_time'],
                          );
                          final checkOut = _formatAttendanceTime(
                            day['check_out_time'],
                          );
                          final hours =
                              (day['total_hours'] as num?)?.toDouble() ?? 0;
                          final dailySalary =
                              (day['daily_salary'] as num?)?.toDouble() ?? 0;
                          final advance =
                              (day['advance_amount'] as num?)?.toDouble() ?? 0;
                          final leaveAllowance =
                              (day['leave_allowance'] as num?)?.toDouble() ?? 0;
                          final bonus =
                              (day['bonus_amount'] as num?)?.toDouble() ?? 0;
                          final deduction =
                              (day['deduction_amount'] as num?)?.toDouble() ??
                              0;
                          final isAbsent = day['is_absent'] == true;
                          final isOnLeave = day['is_on_leave'] == true;
                          final isNonWorkingDay = isAbsent || isOnLeave;
                          final displayedCheckOut = isNonWorkingDay
                              ? '-'
                              : checkOut;

                          return Container(
                            decoration: BoxDecoration(
                              color: isNonWorkingDay
                                  ? Colors.red.shade50
                                  : index % 2 == 0
                                  ? Colors.white
                                  : Colors.grey.shade50,
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.grey.shade300,
                                  width: 0.5,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        DateFormat('dd/MM').format(date),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        DateFormat('EEEE', 'ar').format(date),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    isAbsent
                                        ? 'غياب'
                                        : (isOnLeave ? 'إجازة' : checkIn),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isNonWorkingDay
                                          ? Colors.red
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    displayedCheckOut,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Text(
                                    hours > 0 ? hours.toStringAsFixed(1) : '-',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    dailySalary > 0
                                        ? '${dailySalary.toStringAsFixed(0)}'
                                        : '-',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Text(
                                    advance > 0
                                        ? '${advance.toStringAsFixed(0)}'
                                        : '-',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Text(
                                    leaveAllowance > 0
                                        ? '${leaveAllowance.toStringAsFixed(0)}'
                                        : '-',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.green,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Text(
                                    bonus > 0
                                        ? '${bonus.toStringAsFixed(0)}'
                                        : '-',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Text(
                                    deduction > 0
                                        ? '${deduction.toStringAsFixed(0)}'
                                        : '-',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }, childCount: _attendanceData.length),
                      ),

                // Final Summary Footer
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade400, width: 2),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildTotalRow(
                          'المرتب الأساسي',
                          _totalSalary,
                          Colors.black,
                        ),
                        _buildTotalRow(
                          'بدل الإجازة (عرض فقط)',
                          _totalLeaveAllowance,
                          Colors.green,
                        ),
                        _buildTotalRow(
                          '+ المكافآت',
                          _totalBonuses,
                          Colors.blue,
                        ),
                        _buildTotalRow(
                          '- السلف',
                          _totalAdvances,
                          Colors.orange,
                        ),
                        _buildTotalRow(
                          '- الخصومات',
                          _totalDeductions,
                          Colors.red,
                        ),
                        _buildTotalRow(
                          '- الجزاءات (ضمن الخصومات)',
                          _totalPenalties,
                          Colors.deepOrange,
                        ),
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
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildBreakdownCard(
    String title,
    double amount,
    Color color,
    IconData icon,
  ) {
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
          Text(label, style: TextStyle(fontSize: 14, color: color)),
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

  String _formatAttendanceTime(dynamic value) {
    if (value == null) return '--';
    final raw = value.toString().trim();
    if (raw.isEmpty || raw == '-' || raw == '--' || raw == 'null') {
      return '--';
    }

    final formatted = OwnerTimeUtils.formatTimeShort(raw);
    if (formatted == '-') return raw;
    return formatted;
  }

  Future<void> _printReport() async {
    final netSalary =
        _totalSalary +
        _totalLeaveAllowance +
        _totalBonuses -
        _totalAdvances -
        _totalDeductions;

    DateTime displayStartDate = widget.startDate;
    DateTime displayEndDate = widget.endDate;
    if (_isAllTime && _employeeStartDate != null) {
      displayStartDate = _employeeStartDate!;
      displayEndDate = DateTime.now();
    }

    final font = await PdfGoogleFonts.cairoRegular();
    final boldFont = await PdfGoogleFonts.cairoBold();
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        margin: const pw.EdgeInsets.all(30),
        textDirection: pw.TextDirection.rtl,
        header: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 15),
            margin: const pw.EdgeInsets.only(bottom: 20),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 2),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'تقرير المرتبات المفصل',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.deepPurple700,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'الشركة: EVo HR System',
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'تاريخ الإصدار: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                    pw.Text(
                      'رقم التقرير: #${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
        footer: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 10),
            margin: const pw.EdgeInsets.only(top: 20),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColors.grey300, width: 1),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'تم إنشاء هذا التقرير تلقائياً من نظام الإدارة',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  'صفحة ${context.pageNumber} من ${context.pagesCount}',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          );
        },
        build: (context) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.all(15),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'معلومات الموظف',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.deepPurple,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'الاسم: ${widget.employeeName}',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'كود الموظف: ${widget.employeeId}',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'فترة التقرير',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.deepPurple,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'من: ${DateFormat('dd/MM/yyyy').format(displayStartDate)}',
                        style: const pw.TextStyle(fontSize: 14),
                      ),
                      pw.Text(
                        'إلى: ${DateFormat('dd/MM/yyyy').format(displayEndDate)}',
                        style: const pw.TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 25),

            pw.Text(
              'ملخص المرتب',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              context: context,
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.deepPurple100,
              ),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.deepPurple900,
              ),
              cellAlignment: pw.Alignment.centerRight,
              cellPadding: const pw.EdgeInsets.all(8),
              data: [
                ['البيان', 'القيمة'],
                ['إجمالي الساعات', '${_totalHours.toStringAsFixed(1)} ساعة'],
                ['سعر الساعة', '${_hourlyRate.toStringAsFixed(2)} ج.م'],
                ['أيام الإجازات', '$_leaveDays يوم'],
                ['أيام الغياب', '$_absenceDays يوم'],
                ['المرتب الأساسي', '${_totalSalary.toStringAsFixed(2)} ج.م'],
                [
                  'بدل الإجازات (عرض فقط)',
                  '${_totalLeaveAllowance.toStringAsFixed(2)} ج.م',
                ],
                ['المكافآت (+)', '${_totalBonuses.toStringAsFixed(2)} ج.م'],
                ['السلف (-)', '${_totalAdvances.toStringAsFixed(2)} ج.م'],
                ['الخصومات (-)', '${_totalDeductions.toStringAsFixed(2)} ج.م'],
                [
                  'الجزاءات (-) (ضمن الخصومات)',
                  '${_totalPenalties.toStringAsFixed(2)} ج.م',
                ],
                ['صافي المرتب النهائي', '${netSalary.toStringAsFixed(2)} ج.م'],
              ],
            ),

            // Signatures
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(
                  children: [
                    pw.Text(
                      'توقيع الموظف',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    pw.SizedBox(height: 40),
                    pw.Container(width: 150, height: 1, color: PdfColors.black),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      'توقيع المدير / الإدارة',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    pw.SizedBox(height: 40),
                    pw.Container(width: 150, height: 1, color: PdfColors.black),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name:
          'تقرير_مرتب_${widget.employeeName}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }
}
