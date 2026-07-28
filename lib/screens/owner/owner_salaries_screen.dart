import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as excel_pkg;
import '../../theme/app_colors.dart';
import '../../services/supabase_function_client.dart';
import '../../services/payroll_service.dart';
import '../../utils/file_saver.dart' as file_saver;
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
  String _selectedBranch = 'الكل';
  List<String> _dbBranches = [];

  late DateTime _periodStart;
  late DateTime _periodEnd;

  List<String> get _branchesList {
    return ['الكل', ..._dbBranches];
  }

  List<Map<String, dynamic>> get _filteredRows {
    if (_selectedBranch == 'الكل') {
      return _rows;
    }
    return _rows.where((row) {
      final branch = (row['branch'] ?? '').toString().trim();
      return branch == _selectedBranch;
    }).toList();
  }

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
    final periodStartStr = _date(_periodStart);
    final periodEndStr = _date(_periodEnd);

    try {
      final payrollDetails = await PayrollService.getAllEmployeesAttendanceReport(
        startDate: _periodStart,
        endDate: _periodEnd,
      );

      final paymentsResp = await client
          .from('salary_payments')
          .select('id, employee_id, net_amount, paid_at')
          .eq('period_start', periodStartStr)
          .eq('period_end', periodEndStr)
          .eq('status', 'paid');

      final branchesQuery = await client
          .from('branches')
          .select('name')
          .order('name');
          
      final dbBranches = (branchesQuery as List)
          .map((b) => (b['name'] ?? '').toString().trim())
          .where((name) => name.isNotEmpty)
          .toList();

      final paymentByEmployee = <String, Map<String, dynamic>>{};
      for (final payment in paymentsResp as List) {
        final employeeId = payment['employee_id']?.toString();
        if (employeeId == null || employeeId.isEmpty) continue;
        paymentByEmployee[employeeId] = Map<String, dynamic>.from(payment);
      }

      final List<Map<String, dynamic>> list = [];

      for (final detail in payrollDetails) {
        final employeeId = detail['employee_id'] as String;
        final summary = detail['summary'] as Map<String, dynamic>;
        
        final payment = paymentByEmployee[employeeId];
        final isPaid = payment != null;
        final paidAmount = (payment?['net_amount'] as num?)?.toDouble() ?? 0.0;
        
        final calculatedNet = summary['net_salary'] as double? ?? 0.0;
        final totalHours = summary['total_hours'] as double? ?? 0.0;
        final hourlyRate = summary['hourly_rate'] as double? ?? 0.0;
        final baseSalary = summary['base_salary'] as double? ?? 0.0;
        final totalAdvances = summary['total_advances'] as double? ?? 0.0;
        final totalDeductions = summary['total_deductions'] as double? ?? 0.0;

        list.add({
          'id': employeeId,
          'full_name': detail['employee_name'] ?? 'غير معروف',
          'branch': detail['branch'] ?? '—',
          'hourly_rate': hourlyRate,
          'total_hours': totalHours,
          'base_salary': baseSalary,
          'total_advances': totalAdvances,
          'total_deductions': totalDeductions,
          'current_salary': isPaid ? paidAmount : calculatedNet,
          'is_paid': isPaid,
          'paid_amount': paidAmount,
          'paid_at': payment?['paid_at'],
          'payment_id': payment?['id'],
          'calculated_salary': calculatedNet,
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
        _dbBranches = dbBranches;
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
    // Keep list view aligned with the detailed report calculation.
    return fallbackMap;
  }

  Future<Map<String, double>> _loadFallbackPeriodNetMap(
    List<String> employeeIds,
    String periodStart,
    String periodEnd,
    SupabaseClient client,
  ) async {
    try {
      // 🔍 First, try loading from daily_attendance_summary
      print('📊 [Salaries] Querying daily_attendance_summary...');
      final attendanceResp = await client
          .from('daily_attendance_summary')
          .select(
            'employee_id, daily_salary, advance_amount, leave_allowance, deduction_amount',
          )
          .inFilter('employee_id', employeeIds)
          .gte('attendance_date', periodStart)
          .lte('attendance_date', periodEnd);

      final netByEmployee = <String, double>{};
      
      // If we got data from daily_attendance_summary, use it
      if ((attendanceResp as List).isNotEmpty) {
        print('✅ [Salaries] Found ${(attendanceResp).length} records in daily_attendance_summary');
        for (final row in attendanceResp) {
          final employeeId = row['employee_id']?.toString() ?? '';
          if (employeeId.isEmpty) continue;

          final daySalary = _asDouble(row['daily_salary']);
          final advances = _asDouble(row['advance_amount']);
          final deductions = _asDouble(row['deduction_amount']);

          // Leave allowance is informational only (not included in net).
          netByEmployee[employeeId] =
            (netByEmployee[employeeId] ?? 0.0) + daySalary - advances - deductions;
        }
        return netByEmployee;
      }
      
      // 🔄 Fallback: If daily_attendance_summary is empty, query attendance table directly
      print('⚠️ [Salaries] No data in daily_attendance_summary, querying attendance table...');
      final attendanceRecords = await client
          .from('attendance')
          .select('employee_id, work_hours')
          .inFilter('employee_id', employeeIds)
          .gte('date', periodStart)
          .lte('date', periodEnd)
          .eq('status', 'completed');

      // Also fetch employees to get hourly rates
      final employeesData = await client
          .from('employees')
          .select('id, hourly_rate')
          .inFilter('id', employeeIds);

      final hourlyRateByEmployee = <String, double>{};
      for (final emp in (employeesData as List)) {
        final empId = emp['id']?.toString() ?? '';
        hourlyRateByEmployee[empId] = _asDouble(emp['hourly_rate']);
      }

      // Get approved advances within period
      final advancesResp = await client
          .from('salary_advances')
          .select('employee_id, amount, approved_at, created_at, status')
          .inFilter('employee_id', employeeIds)
          .eq('status', 'approved');

      final advancesByEmployee = <String, double>{};
      for (final row in (advancesResp as List)) {
        final employeeId = row['employee_id']?.toString() ?? '';
        if (employeeId.isEmpty) continue;
        final approvedAt = row['approved_at']?.toString();
        final createdAt = row['created_at']?.toString();
        final dateValue = (approvedAt != null && approvedAt.isNotEmpty)
            ? approvedAt
            : (createdAt ?? '');
        if (dateValue.isEmpty) continue;
        final dateOnly = dateValue.split('T')[0];
        if (dateOnly.compareTo(periodStart) < 0 || dateOnly.compareTo(periodEnd) > 0) {
          continue;
        }
        final amount = _asDouble(row['amount']);
        advancesByEmployee[employeeId] =
            (advancesByEmployee[employeeId] ?? 0.0) + amount;
      }

      // Get deductions within period
      final deductionsResp = await client
          .from('deductions')
          .select('employee_id, amount, deduction_date')
          .inFilter('employee_id', employeeIds)
          .gte('deduction_date', periodStart)
          .lte('deduction_date', periodEnd);

      final deductionsByEmployee = <String, double>{};
      for (final row in (deductionsResp as List)) {
        final employeeId = row['employee_id']?.toString() ?? '';
        if (employeeId.isEmpty) continue;
        final amount = _asDouble(row['amount']);
        deductionsByEmployee[employeeId] =
            (deductionsByEmployee[employeeId] ?? 0.0) + amount;
      }

      // Calculate totals from attendance table
      for (final record in (attendanceRecords as List)) {
        final employeeId = record['employee_id']?.toString() ?? '';
        if (employeeId.isEmpty) continue;

        final workHours = _asDouble(record['work_hours']);
        final hourlyRate = hourlyRateByEmployee[employeeId] ?? 0.0;
        final dailySalary = workHours * hourlyRate;

        netByEmployee[employeeId] =
            (netByEmployee[employeeId] ?? 0.0) + dailySalary;
      }

      // Apply advances/deductions once per employee
      for (final employeeId in employeeIds) {
        final advances = advancesByEmployee[employeeId] ?? 0.0;
        final deductions = deductionsByEmployee[employeeId] ?? 0.0;
        if (!netByEmployee.containsKey(employeeId)) continue;
        netByEmployee[employeeId] =
            (netByEmployee[employeeId] ?? 0.0) - advances - deductions;
      }

      if (netByEmployee.isNotEmpty) {
        print('✅ [Salaries] Calculated ${netByEmployee.length} employees from attendance table');
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
    final unpaidRows = _filteredRows
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
            onPressed: _loading || _payingAll || _filteredRows.isEmpty ? null : _printBranchPayroll,
            icon: const Icon(Icons.print),
            tooltip: 'طباعة التقرير المالي',
          ),
          IconButton(
            onPressed: _loading || _payingAll || _filteredRows.isEmpty ? null : _exportToExcel,
            icon: const Icon(Icons.description),
            tooltip: 'تصدير إلى Excel',
          ),
          IconButton(
            onPressed: _loading || _payingAll ? null : _pickDateRange,
            icon: const Icon(Icons.date_range),
            tooltip: 'اختيار فترة',
          ),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedBranch,
                isExpanded: true,
                items: _branchesList.map((branch) {
                  return DropdownMenuItem<String>(
                    value: branch,
                    child: Text(
                      branch,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      textDirection: ui.TextDirection.rtl,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedBranch = value ?? 'الكل';
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
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
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'الفرع',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'الساعات',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'سعر الساعة',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'المستحق',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'الخصومات',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'صافي الراتب',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'الحالة',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'الإجراء',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
                rows: _filteredRows.map((row) {
                  final isPaid = row['is_paid'] == true;
                  final employeeId = row['id']?.toString();
                  final isProcessing =
                      _payingEmployeeId != null &&
                      _payingEmployeeId == employeeId;

                  final double baseSalary = _asDouble(row['base_salary']);
                  final double totalAdvances = _asDouble(row['total_advances']);
                  final double totalDeductions = _asDouble(row['total_deductions']);
                  final double totalDeductionsCombined = totalAdvances + totalDeductions;

                  return DataRow(
                    cells: [
                      // 1. Employee
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
                      // 2. Branch
                      DataCell(
                        Text(
                          row['branch']?.toString() ?? '—',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      // 3. Hours
                      DataCell(
                        Text(
                          _asDouble(row['total_hours']).toStringAsFixed(1),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      // 4. Rate/Hour
                      DataCell(
                        Text(
                          _money(_asDouble(row['hourly_rate'])),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      // 5. Earned/Base
                      DataCell(
                        Text(
                          _money(baseSalary),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      // 6. Deductions
                      DataCell(
                        Text(
                          totalDeductionsCombined > 0 
                              ? '-${_money(totalDeductionsCombined)}' 
                              : '0.00 ج.م',
                          style: TextStyle(
                            fontSize: 14, 
                            color: totalDeductionsCombined > 0 ? Colors.red : Colors.black
                          ),
                        ),
                      ),
                      // 7. Net Salary
                      DataCell(
                        Text(
                          _money(_asDouble(row['current_salary'])),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      // 8. Status
                      DataCell(_statusChip(isPaid)),
                      // 9. Action
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
    final filtered = _filteredRows;
    final unpaidCount = filtered.where((row) => row['is_paid'] != true).length;
    
    double filteredTotalDue = 0.0;
    double filteredTotalPaid = 0.0;
    
    for (final row in filtered) {
      final isPaid = row['is_paid'] == true;
      final amount = _asDouble(row['current_salary']);
      if (isPaid) {
        filteredTotalPaid += amount;
      } else {
        filteredTotalDue += amount;
      }
    }

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
            Text('إجمالي المستحق غير المدفوع: ${_money(filteredTotalDue)}'),
            const SizedBox(height: 4),
            Text('إجمالي المدفوع: ${_money(filteredTotalPaid)}'),
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

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initialStart = _periodStart;
    final initialEnd = _periodEnd;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: now,
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      helpText: 'اختر فترة الرواتب',
      cancelText: 'إلغاء',
      confirmText: 'تأكيد',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryOrange,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _periodStart = picked.start;
        _periodEnd = picked.end;
      });
      _load();
    }
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

  Future<void> _printBranchPayroll() async {
    try {
      final font = await PdfGoogleFonts.cairoRegular();
      final boldFont = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document();
      final employees = _filteredRows;

      final totalHours = employees.fold<double>(0, (sum, emp) {
        return sum + _asDouble(emp['total_hours']);
      });
      final totalNet = employees.fold<double>(0, (sum, emp) {
        return sum + _asDouble(emp['current_salary']);
      });

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          theme: pw.ThemeData.withFont(base: font, bold: boldFont),
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => [
            pw.Text(
              'بيانات الرواتب للفرع',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'الفترة: ${DateFormat('dd/MM/yyyy').format(_periodStart)} - ${DateFormat('dd/MM/yyyy').format(_periodEnd)}',
              style: const pw.TextStyle(fontSize: 12),
            ),
            if (_selectedBranch != 'الكل')
              pw.Text(
                'الفرع المفلتر: $_selectedBranch',
                style: const pw.TextStyle(fontSize: 12),
              ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              context: context,
              border: pw.TableBorder.all(color: PdfColors.grey300),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.orange100),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.center,
              data: [
                ['الاسم', 'الفرع', 'الساعات', 'سعر الساعة', 'المستحق', 'الخصومات', 'صافي الراتب', 'الحالة'],
                ...employees.map((employee) {
                  final name = (employee['full_name'] ?? '').toString();
                  final branchName = (employee['branch'] ?? '').toString();
                  final hours = _asDouble(employee['total_hours']).toStringAsFixed(1);
                  final hourlyRate = _money(_asDouble(employee['hourly_rate']));
                  final baseSalary = _money(_asDouble(employee['base_salary']));
                  final totalDeds = _money(_asDouble(employee['total_advances']) + _asDouble(employee['total_deductions']));
                  final net = _money(_asDouble(employee['current_salary']));
                  final status = employee['is_paid'] == true ? 'مدفوع' : 'غير مدفوع';
                  return [name, branchName, hours, hourlyRate, baseSalary, totalDeds, net, status];
                }),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text('إجمالي الساعات: ${totalHours.toStringAsFixed(1)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            pw.Text('إجمالي صافي المرتبات: ${_money(totalNet)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'قائمة_رواتب_الفرع_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الطباعة: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _exportToExcel() async {
    try {
      setState(() => _loading = true);
      
      final excelObj = excel_pkg.Excel.createExcel();
      excelObj.rename('Sheet1', 'التقرير المالي للرواتب');
      final sheet = excelObj['التقرير المالي للرواتب'];
      
      sheet.isRTL = true;
      
      // Add title block
      sheet.appendRow([
        excel_pkg.TextCellValue('التقرير الشامل للرواتب (recap attendee)'),
      ]);
      sheet.appendRow([
        excel_pkg.TextCellValue('الفترة: ${DateFormat('dd/MM/yyyy').format(_periodStart)} - ${DateFormat('dd/MM/yyyy').format(_periodEnd)}'),
      ]);
      if (_selectedBranch != 'الكل') {
        sheet.appendRow([
          excel_pkg.TextCellValue('الفرع المفلتر: $_selectedBranch'),
        ]);
      }
      sheet.appendRow([]); // Empty row
      
      // Add table headers
      sheet.appendRow([
        excel_pkg.TextCellValue('كود الموظف'),
        excel_pkg.TextCellValue('الاسم الكامل'),
        excel_pkg.TextCellValue('الفرع'),
        excel_pkg.TextCellValue('سعر الساعة'),
        excel_pkg.TextCellValue('إجمالي الساعات'),
        excel_pkg.TextCellValue('الراتب الأساسي/المستحق'),
        excel_pkg.TextCellValue('إجمالي السلف والخصومات'),
        excel_pkg.TextCellValue('صافي الراتب'),
        excel_pkg.TextCellValue('حالة الدفع'),
      ]);
      
      // Add data
      final employees = _filteredRows;
      for (final emp in employees) {
        final empId = emp['id']?.toString() ?? '';
        final name = emp['full_name']?.toString() ?? '';
        final branchName = emp['branch']?.toString() ?? '';
        final hourlyRate = _asDouble(emp['hourly_rate']);
        final totalHours = _asDouble(emp['total_hours']);
        final baseSalary = _asDouble(emp['base_salary']);
        final totalDeds = _asDouble(emp['total_advances']) + _asDouble(emp['total_deductions']);
        final netSalary = _asDouble(emp['current_salary']);
        final status = emp['is_paid'] == true ? 'مدفوع' : 'غير مدفوع';
        
        sheet.appendRow([
          excel_pkg.TextCellValue(empId),
          excel_pkg.TextCellValue(name),
          excel_pkg.TextCellValue(branchName),
          excel_pkg.DoubleCellValue(hourlyRate),
          excel_pkg.DoubleCellValue(totalHours),
          excel_pkg.DoubleCellValue(baseSalary),
          excel_pkg.DoubleCellValue(totalDeds),
          excel_pkg.DoubleCellValue(netSalary),
          excel_pkg.TextCellValue(status),
        ]);
      }
      
      // Save
      final bytes = excelObj.encode();
      if (bytes != null) {
        final fileName = 'تقرير_الرواتب_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
        await file_saver.saveFile(bytes, fileName);
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() => _loading = false);
      print('Excel export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تصدير Excel: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }
}
