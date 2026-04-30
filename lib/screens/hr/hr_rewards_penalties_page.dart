import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';

class HRRewardsPenaltiesPage extends StatefulWidget {
  final String hrId;

  const HRRewardsPenaltiesPage({super.key, required this.hrId});

  @override
  State<HRRewardsPenaltiesPage> createState() => _HRRewardsPenaltiesPageState();
}

class _HRRewardsPenaltiesPageState extends State<HRRewardsPenaltiesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _deductions = [];
  List<Map<String, dynamic>> _bonuses = [];

  DateTime _selectedMonth = DateTime.now();

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _bootstrap();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _monthLabel(DateTime month) {
    return DateFormat('MMMM yyyy', 'ar').format(month);
  }

  String _dateForApi(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final employees = await _supabase
          .from('employees')
          .select('id, full_name, role, branch')
          .neq('role', 'owner')
          .eq('is_active', true)
          .order('full_name')
          ;

      setState(() {
        _employees = List<Map<String, dynamic>>.from(employees);
      });

      await _loadRecords();

      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadRecords() async {
    try {
      final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
      final startStr = _dateForApi(monthStart);
      final endStr = _dateForApi(monthEnd);

      final deductionsResp = await _supabase
          .from('deductions')
          .select('id, employee_id, amount, reason, deduction_date, created_by')
          .gte('deduction_date', startStr)
          .lte('deduction_date', endStr)
          .order('deduction_date', ascending: false);

      final bonusesResp = await _supabase
          .from('bonuses')
          .select('id, employee_id, amount, reason, bonus_date, created_by')
          .gte('bonus_date', startStr)
          .lte('bonus_date', endStr)
          .order('bonus_date', ascending: false);

      // Enrich with employee data
      final deductionsWithEmployees = await _enrichWithEmployeeData(deductionsResp);
      final bonusesWithEmployees = await _enrichWithEmployeeData(bonusesResp);

      setState(() {
        _deductions = deductionsWithEmployees;
        _bonuses = bonusesWithEmployees;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _enrichWithEmployeeData(List<dynamic> records) async {
    if (records.isEmpty) return [];

    // Get all employees - simpler approach
    final employeesResp = await _supabase
        .from('employees')
        .select('id, full_name');

    final employeeMap = <String, Map<String, dynamic>>{};
    for (final emp in employeesResp) {
      final id = emp['id']?.toString();
      if (id != null) {
        employeeMap[id] = Map<String, dynamic>.from(emp);
      }
    }

    return records.map((r) {
      final empId = r['employee_id']?.toString();
      final enriched = Map<String, dynamic>.from(r);
      if (empId != null && employeeMap.containsKey(empId)) {
        enriched['employees'] = employeeMap[empId];
      }
      return enriched;
    }).toList();
  }

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
    await _loadRecords();
  }

  Future<void> _addPenalty() async {
    final employeeController = TextEditingController();
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String? selectedEmployeeId;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إضافة خصم',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedEmployeeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'اختر الموظف',
                    border: OutlineInputBorder(),
                  ),
                  items: _employees
                      .map((e) => DropdownMenuItem(
                            value: e['id']?.toString(),
                            child: Text(e['full_name']?.toString() ?? ''),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setSheetState(() {
                      selectedEmployeeId = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    suffixText: 'ج.م',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'السبب',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (selectedEmployeeId == null || amountController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('يرجى إكمال جميع الحقول')),
                        );
                        return;
                      }
                      Navigator.pop(context, {
                        'employee_id': selectedEmployeeId,
                        'amount': double.tryParse(amountController.text) ?? 0,
                        'reason': reasonController.text,
                        'date': selectedDate,
                      });
                    },
                    child: const Text('إضافة الخصم'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == null) return;

    try {
      setState(() => _loading = true);

      await _supabase.from('deductions').insert({
        'employee_id': result['employee_id'],
        'amount': (result['amount'] as double).abs() * -1,
        'reason': result['reason'] ?? 'خصم من الموارد البشرية',
        'deduction_date': _dateForApi(result['date'] as DateTime),
        'created_by': widget.hrId,
      });

      await _loadRecords();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم إضافة الخصم بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _addBonus() async {
    final employeeController = TextEditingController();
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String? selectedEmployeeId;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إضافة مكافأة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedEmployeeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'اختر الموظف',
                    border: OutlineInputBorder(),
                  ),
                  items: _employees
                      .map((e) => DropdownMenuItem(
                            value: e['id']?.toString(),
                            child: Text(e['full_name']?.toString() ?? ''),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setSheetState(() {
                      selectedEmployeeId = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    suffixText: 'ج.م',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'السبب',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (selectedEmployeeId == null || amountController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('يرجى إكمال جميع الحقول')),
                        );
                        return;
                      }
                      Navigator.pop(context, {
                        'employee_id': selectedEmployeeId,
                        'amount': double.tryParse(amountController.text) ?? 0,
                        'reason': reasonController.text,
                        'date': selectedDate,
                      });
                    },
                    child: const Text('إضافة المكافأة'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == null) return;

    try {
      setState(() => _loading = true);

      await _supabase.from('bonuses').insert({
        'employee_id': result['employee_id'],
        'amount': (result['amount'] as double).abs(),
        'reason': result['reason'] ?? 'مكافأة من الموارد البشرية',
        'bonus_date': _dateForApi(result['date'] as DateTime),
        'created_by': widget.hrId,
      });

      await _loadRecords();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم إضافة المكافأة بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildMonthSelector(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : _buildTabContent(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (context) => Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.remove_circle, color: Colors.red),
                    title: const Text('إضافة خصم'),
                    onTap: () {
                      Navigator.pop(context);
                      _addPenalty();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_circle, color: Colors.green),
                    title: const Text('إضافة مكافأة'),
                    onTap: () {
                      Navigator.pop(context);
                      _addBonus();
                    },
                  ),
                ],
              ),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('إضافة'),
        backgroundColor: AppColors.primaryOrange,
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_right),
          ),
          Expanded(
            child: Text(
              _monthLabel(_selectedMonth),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          IconButton(
            onPressed: () => _changeMonth(1),
            icon: const Icon(Icons.chevron_left),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildDeductionsList(),
        _buildBonusesList(),
        _buildSummary(),
      ],
    );
  }

  Widget _buildDeductionsList() {
    if (_deductions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.remove_circle_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('لا توجد خصومات', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRecords,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _deductions.length,
        itemBuilder: (context, index) {
          final deduction = _deductions[index];
          return _buildRecordCard(deduction, 'deduction');
        },
      ),
    );
  }

  Widget _buildBonusesList() {
    if (_bonuses.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.card_giftcard, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('لا توجد مكافآت', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRecords,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _bonuses.length,
        itemBuilder: (context, index) {
          final bonus = _bonuses[index];
          return _buildRecordCard(bonus, 'bonus');
        },
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record, String type) {
    final employee = record['employees'] as Map<String, dynamic>?;
    final employeeName = employee?['full_name']?.toString() ?? 'غير معروف';
    final amount = (record['amount'] as num?)?.toDouble() ?? 0;
    final date = record['deduction_date']?.toString() ?? record['bonus_date']?.toString() ?? '';
    final reason = record['reason']?.toString() ?? '';
    final isDeduction = type == 'deduction';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (isDeduction ? Colors.red : Colors.green).withValues(alpha: 0.2),
          child: Icon(
            isDeduction ? Icons.remove_circle : Icons.add_circle,
            color: isDeduction ? Colors.red : Colors.green,
          ),
        ),
        title: Text(
          employeeName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reason,
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              date,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        trailing: Text(
          '${isDeduction ? '-' : '+'}${amount.abs().toStringAsFixed(2)} ج.م',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDeduction ? Colors.red : Colors.green,
          ),
        ),
      ),
    );
  }

  Widget _buildSummary() {
    double totalDeductions = 0;
    double totalBonuses = 0;

    for (final d in _deductions) {
      totalDeductions += (d['amount'] as num?)?.abs() ?? 0;
    }
    for (final b in _bonuses) {
      totalBonuses += (b['amount'] as num?)?.abs() ?? 0;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ملخص الشهر',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  _summaryRow('إجمالي الخصومات', totalDeductions, Colors.red),
                  _summaryRow('إجمالي المكافآت', totalBonuses, Colors.green),
                  const Divider(),
                  _summaryRow(
                    'الصافي',
                    totalBonuses - totalDeductions,
                    totalBonuses >= totalDeductions ? Colors.green : Colors.red,
                    isBold: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double amount, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '${amount.abs().toStringAsFixed(2)} ج.م',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
              fontSize: isBold ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _bootstrap,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}