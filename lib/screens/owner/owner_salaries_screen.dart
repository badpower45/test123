import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../services/supabase_function_client.dart';
import 'owner_employee_payroll_report_page.dart';

class OwnerSalariesScreen extends StatefulWidget {
  const OwnerSalariesScreen({super.key, required this.ownerId});

  final String ownerId;

  @override
  State<OwnerSalariesScreen> createState() => _OwnerSalariesScreenState();
}

class _OwnerSalariesScreenState extends State<OwnerSalariesScreen> {
  bool _loading = true;
  bool _payingAll = false;
  String? _payingEmployeeId;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  late DateTime _periodStart;
  late DateTime _periodEnd;

  double _totalDue = 0;
  double _totalPaid = 0;

  @override
  void initState() {
    super.initState();
    final period = _currentPeriod();
    _periodStart = period['start']!;
    _periodEnd = period['end']!;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final client = Supabase.instance.client;
    final periodStart = _date(_periodStart);
    final periodEnd = _date(_periodEnd);

    try {
      final results = await Future.wait([
        client
            .from('employees')
            .select('id, full_name, role, branch')
            .eq('is_active', true)
            .neq('role', 'owner')
            .order('full_name'),
        client
            .from('salary_payments')
            .select('id, employee_id, net_amount, paid_at')
            .eq('period_start', periodStart)
            .eq('period_end', periodEnd)
            .eq('status', 'paid'),
      ]);

      final employeesResp = results[0] as List;
      final paymentsResp = results[1] as List;

      final paymentByEmployee = <String, Map<String, dynamic>>{};
      for (final payment in paymentsResp) {
        final employeeId = payment['employee_id']?.toString();
        if (employeeId == null || employeeId.isEmpty) continue;
        paymentByEmployee[employeeId] = Map<String, dynamic>.from(payment);
      }

      final employees = employeesResp.cast<Map<String, dynamic>>();

      final employeeIds = employees
          .map((e) => e['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);

      final employeeIdsNeedingNet = employeeIds
          .where((id) {
            final payment = paymentByEmployee[id];
            final paidAmount =
                (payment?['net_amount'] as num?)?.toDouble() ?? 0.0;
            return payment == null || paidAmount <= 0;
          })
          .toList(growable: false);

      final periodNetByEmployee = await _loadPeriodNetsForEmployees(
        employeeIdsNeedingNet,
        periodStart,
        periodEnd,
        client,
      );

      final List<Map<String, dynamic>> list = [];

      for (final emp in employees) {
        final employeeId = emp['id']?.toString() ?? '';
        if (employeeId.isEmpty) continue;

        final payment = paymentByEmployee[employeeId];
        final paidAmount = (payment?['net_amount'] as num?)?.toDouble() ?? 0.0;
        final periodNet = paidAmount > 0
            ? paidAmount
            : (periodNetByEmployee[employeeId] ?? 0.0);

        list.add({
          'id': employeeId,
          'full_name': emp['full_name'] ?? 'غير معروف',
          'role': emp['role'] ?? '—',
          'branch': emp['branch'] ?? '—',
          'current_salary': periodNet,
          'is_paid': payment != null,
          'paid_amount': paidAmount,
          'paid_at': payment?['paid_at'],
          'payment_id': payment?['id'],
        });
      }

      final totalDue = list
          .where((row) => row['is_paid'] != true)
          .fold<double>(
            0.0,
            (sum, row) => sum + _asDouble(row['current_salary']),
          );

      final totalPaid = list
          .where((row) => row['is_paid'] == true)
          .fold<double>(0.0, (sum, row) {
            final paidAmount = _asDouble(row['paid_amount']);
            final fallbackAmount = _asDouble(row['current_salary']);
            return sum + (paidAmount > 0 ? paidAmount : fallbackAmount);
          });

      if (!mounted) return;
      setState(() {
        _rows = list;
        _totalDue = totalDue;
        _totalPaid = totalPaid;
        _loading = false;
        _error = null;
      });
    } catch (e, stackTrace) {
      print('❌ [Salaries] Error: $e');
      print('❌ [Salaries] StackTrace: $stackTrace');
      if (!mounted) return;
      setState(() {
        _error = 'خطأ في تحميل البيانات: $e';
        _loading = false;
      });
    }
  }

  Future<double> _loadEmployeePeriodNet(
    String employeeId,
    String periodStart,
    String periodEnd,
    double fallbackNet,
  ) async {
    try {
      final periodResult = await SupabaseFunctionClient.post(
        'employee-period-earnings',
        {
          'employee_id': employeeId,
          'start_date': periodStart,
          'end_date': periodEnd,
        },
        timeout: const Duration(seconds: 5),
        throwOnError: false,
        enableLogging: false,
      );

      if ((periodResult ?? const {})['success'] == true) {
        final totals =
            (periodResult ?? const {})['totals'] as Map<String, dynamic>?;
        return _asDouble(totals?['net']);
      }
    } catch (e) {
      print(
        '⚠️ [Salaries] employee-period-earnings failed for $employeeId: $e',
      );
    }

    return fallbackNet;
  }

  Future<Map<String, double>> _loadPeriodNetsForEmployees(
    List<String> employeeIds,
    String periodStart,
    String periodEnd,
    SupabaseClient client,
  ) async {
    if (employeeIds.isEmpty) {
      return const {};
    }

    final fallbackMap = await _loadFallbackPeriodNetMap(
      employeeIds,
      periodStart,
      periodEnd,
      client,
    );

    final result = <String, double>{};
    const chunkSize = 10;

    for (int index = 0; index < employeeIds.length; index += chunkSize) {
      final end = math.min(index + chunkSize, employeeIds.length);
      final chunk = employeeIds.sublist(index, end);

      final chunkEntries = await Future.wait(
        chunk.map((employeeId) async {
          final net = await _loadEmployeePeriodNet(
            employeeId,
            periodStart,
            periodEnd,
            fallbackMap[employeeId] ?? 0.0,
          );
          return MapEntry(employeeId, net);
        }),
      );

      for (final entry in chunkEntries) {
        result[entry.key] = entry.value;
      }
    }

    return result;
  }

  Future<Map<String, double>> _loadFallbackPeriodNetMap(
    List<String> employeeIds,
    String periodStart,
    String periodEnd,
    SupabaseClient client,
  ) async {
    try {
      final attendanceResp = await client
          .from('daily_attendance_summary')
          .select(
            'employee_id, daily_salary, advance_amount, leave_allowance, deduction_amount',
          )
          .inFilter('employee_id', employeeIds)
          .gte('attendance_date', periodStart)
          .lte('attendance_date', periodEnd);

      final netByEmployee = <String, double>{};
      for (final row in (attendanceResp as List)) {
        final employeeId = row['employee_id']?.toString() ?? '';
        if (employeeId.isEmpty) continue;

        final daySalary = _asDouble(row['daily_salary']);
        final advances = _asDouble(row['advance_amount']);
        final leaveAllowance = _asDouble(row['leave_allowance']);
        final deductions = _asDouble(row['deduction_amount']);

        netByEmployee[employeeId] =
            (netByEmployee[employeeId] ?? 0.0) +
            daySalary +
            leaveAllowance -
            advances -
            deductions;
      }
      return netByEmployee;
    } catch (e) {
      print('⚠️ [Salaries] fallback summary failed: $e');
      return const {};
    }
  }

  Future<void> _markSalaryPayment(
    String employeeId,
    double amount,
    String notes,
  ) async {
    try {
      await Supabase.instance.client.rpc(
        'mark_salary_payment',
        params: {
          'p_employee_id': employeeId,
          'p_period_start': _date(_periodStart),
          'p_period_end': _date(_periodEnd),
          'p_net_amount': amount,
          'p_paid_by': widget.ownerId,
          'p_notes': notes,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _payEmployee(Map<String, dynamic> row) async {
    final employeeId = row['id']?.toString();
    final employeeName = row['full_name']?.toString() ?? 'الموظف';
    final amount = _asDouble(row['current_salary']);

    if (employeeId == null || employeeId.isEmpty) {
      return;
    }

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد مبلغ مستحق للدفع لهذا الموظف.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الدفع'),
        content: Text('تأكيد دفع مرتب $employeeName بقيمة ${_money(amount)}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
            ),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _payingEmployeeId = employeeId);

    try {
      await _markSalaryPayment(employeeId, amount, 'دفع فردي من شاشة المالك');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم تسجيل دفع مرتب $employeeName'),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ فشل تسجيل الدفع: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _payingEmployeeId = null);
      }
    }
  }

  Future<void> _payAll() async {
    final unpaidRows = _rows
        .where(
          (row) =>
              row['is_paid'] != true && _asDouble(row['current_salary']) > 0,
        )
        .toList();

    if (unpaidRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('كل الرواتب مدفوعة بالفعل أو لا توجد مبالغ مستحقة.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final total = unpaidRows.fold<double>(
      0.0,
      (sum, row) => sum + _asDouble(row['current_salary']),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد دفع الكل'),
        content: Text(
          'سيتم دفع ${unpaidRows.length} موظف بإجمالي ${_money(total)} لهذه الفترة. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
            ),
            child: const Text('دفع الكل'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _payingAll = true);

    int paidCount = 0;
    int failedCount = 0;

    const chunkSize = 8;
    for (int index = 0; index < unpaidRows.length; index += chunkSize) {
      final end = math.min(index + chunkSize, unpaidRows.length);
      final chunk = unpaidRows.sublist(index, end);

      final chunkResults = await Future.wait(
        chunk.map((row) async {
          try {
            await _markSalaryPayment(
              row['id']?.toString() ?? '',
              _asDouble(row['current_salary']),
              'دفع جماعي من شاشة المالك',
            );
            return true;
          } catch (_) {
            return false;
          }
        }),
      );

      for (final ok in chunkResults) {
        if (ok) {
          paidCount++;
        } else {
          failedCount++;
        }
      }
    }

    if (!mounted) return;

    setState(() => _payingAll = false);
    await _load();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failedCount == 0
              ? '✅ تم دفع $paidCount موظف بنجاح.'
              : '⚠️ تم دفع $paidCount موظف، وتعذر دفع $failedCount موظف.',
        ),
        backgroundColor: failedCount == 0 ? Colors.green : Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('رواتب الموظفين'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loading || _payingAll ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _errorView()
          : _contentView(),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 56, color: AppColors.error),
          const SizedBox(height: 12),
          Text(_error ?? 'حدث خطأ غير متوقع'),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }

  Widget _contentView() {
    if (_rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text('لا يوجد بيانات رواتب', style: TextStyle(fontSize: 16)),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  AppColors.primaryOrange.withOpacity(.1),
                ),
                columns: const [
                  DataColumn(
                    label: Text(
                      'الموظف',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'مرتب الفترة',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'الحالة',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'الإجراء',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
                rows: _rows.map((row) {
                  final isPaid = row['is_paid'] == true;
                  final employeeId = row['id']?.toString();
                  final isProcessing =
                      _payingEmployeeId != null &&
                      _payingEmployeeId == employeeId;

                  return DataRow(
                    cells: [
                      DataCell(
                        InkWell(
                          onTap: () => _openPayrollReport(
                            row['id']?.toString() ?? '',
                            row['full_name']?.toString() ?? 'غير معروف',
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              row['full_name']?.toString() ?? 'غير معروف',
                              style: const TextStyle(
                                color: AppColors.primaryOrange,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          _money(row['current_salary']),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                      DataCell(_statusChip(isPaid)),
                      DataCell(
                        isPaid
                            ? const Text(
                                'تم الدفع',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : ElevatedButton(
                                onPressed: _payingAll || isProcessing
                                    ? null
                                    : () => _payEmployee(row),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryOrange,
                                  foregroundColor: Colors.white,
                                ),
                                child: isProcessing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('دفع'),
                              ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final unpaidCount = _rows.where((row) => row['is_paid'] != true).length;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'فترة الرواتب: ${_periodLabel()}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 10),
            Text('إجمالي المستحق غير المدفوع: ${_money(_totalDue)}'),
            const SizedBox(height: 4),
            Text('إجمالي المدفوع: ${_money(_totalPaid)}'),
            const SizedBox(height: 4),
            Text('عدد الموظفين غير المدفوعين: $unpaidCount'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _payingAll || unpaidCount == 0 ? null : _payAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                  foregroundColor: Colors.white,
                ),
                icon: _payingAll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.payments),
                label: Text(_payingAll ? 'جاري دفع الكل...' : 'دفع الكل'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(bool isPaid) {
    final bgColor = isPaid ? Colors.green.shade50 : Colors.orange.shade50;
    final fgColor = isPaid ? Colors.green : Colors.orange.shade800;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isPaid ? 'مدفوع' : 'غير مدفوع',
        style: TextStyle(
          color: fgColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  void _openPayrollReport(String employeeId, String employeeName) {
    if (employeeId.isEmpty) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerEmployeePayrollReportPage(
          employeeId: employeeId,
          employeeName: employeeName,
          startDate: _periodStart,
          endDate: _periodEnd,
        ),
      ),
    );
  }

  Map<String, DateTime> _currentPeriod() {
    final now = DateTime.now();
    if (now.day <= 15) {
      return {
        'start': DateTime(now.year, now.month, 1),
        'end': DateTime(now.year, now.month, 15),
      };
    }

    return {
      'start': DateTime(now.year, now.month, 16),
      'end': DateTime(now.year, now.month + 1, 0),
    };
  }

  String _periodLabel() {
    final formatter = DateFormat('dd/MM/yyyy');
    return '${formatter.format(_periodStart)} - ${formatter.format(_periodEnd)}';
  }

  String _date(DateTime value) {
    return DateFormat('yyyy-MM-dd').format(value);
  }

  double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _money(dynamic value) {
    final numVal = _asDouble(value);
    return '${numVal.toStringAsFixed(2)} ج.م';
  }
}
