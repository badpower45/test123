import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/manager_attendance_admin_service.dart';
import '../../theme/app_colors.dart';

class ManagerPenaltiesPage extends StatefulWidget {
  const ManagerPenaltiesPage({
    super.key,
    required this.managerId,
    required this.branchName,
  });

  final String managerId;
  final String branchName;

  @override
  State<ManagerPenaltiesPage> createState() => _ManagerPenaltiesPageState();
}

class _ManagerPenaltiesPageState extends State<ManagerPenaltiesPage> {
  bool _loading = true;
  bool _processing = false;
  String? _error;

  List<Map<String, dynamic>> _employees = [];
  String? _selectedEmployeeId;

  DateTime _selectedDate = DateTime.now();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  ManagerPenaltyType _selectedPenaltyType = ManagerPenaltyType.day;
  double _dayPenaltyValue = 100;

  final TextEditingController _customAmountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  List<Map<String, dynamic>> _penalties = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _customAmountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final employees = await ManagerAttendanceAdminService.getBranchEmployees(
        managerId: widget.managerId,
        branchName: widget.branchName,
      );

      if (!mounted) return;

      setState(() {
        _employees = employees;
        if (_selectedEmployeeId == null && _employees.isNotEmpty) {
          _selectedEmployeeId = _employees.first['id']?.toString();
        }
      });

      await _loadPenalties();

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

  Future<void> _loadPenalties() async {
    try {
      final response = await ManagerAttendanceAdminService.listPenalties(
        managerId: widget.managerId,
        branchName: widget.branchName,
        month: _selectedMonth,
        employeeId: _selectedEmployeeId,
      );

      if (!mounted) return;

      setState(() {
        _penalties = _asMapList(response['penalties']);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    }
  }

  String _monthLabel(DateTime month) {
    return DateFormat('MMMM yyyy', 'ar').format(month);
  }

  String _dateForApi(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _dateLabel(DateTime date) {
    return DateFormat('EEEE - dd/MM/yyyy', 'ar').format(date);
  }

  double _amountPreview() {
    switch (_selectedPenaltyType) {
      case ManagerPenaltyType.halfDay:
        return _dayPenaltyValue / 2;
      case ManagerPenaltyType.day:
        return _dayPenaltyValue;
      case ManagerPenaltyType.twoDays:
        return _dayPenaltyValue * 2;
      case ManagerPenaltyType.custom:
        return double.tryParse(_customAmountController.text) ?? 0;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _selectedDate,
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
    await _loadPenalties();
  }

  Future<void> _applyPenalty() async {
    final employeeId = _selectedEmployeeId;
    if (employeeId == null || employeeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر الموظف أولاً'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final amount = _amountPreview();
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('قيمة الجزاء لازم تكون أكبر من صفر'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _processing = true);

    try {
      await ManagerAttendanceAdminService.applyPenalty(
        managerId: widget.managerId,
        branchName: widget.branchName,
        employeeId: employeeId,
        date: _dateForApi(_selectedDate),
        penaltyType: _selectedPenaltyType,
        customAmount: _selectedPenaltyType == ManagerPenaltyType.custom
            ? double.tryParse(_customAmountController.text)
            : null,
        reason: _reasonController.text,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم إضافة الجزاء بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );

      _reasonController.clear();
      if (_selectedPenaltyType == ManagerPenaltyType.custom) {
        _customAmountController.clear();
      }

      await _loadPenalties();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Widget _buildPenaltyTypeChips() {
    final types = [
      ManagerPenaltyType.halfDay,
      ManagerPenaltyType.day,
      ManagerPenaltyType.twoDays,
      ManagerPenaltyType.custom,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: types
          .map(
            (type) => ChoiceChip(
              label: Text(type.label),
              selected: _selectedPenaltyType == type,
              onSelected: (selected) {
                if (!selected) return;
                setState(() {
                  _selectedPenaltyType = type;
                });
              },
            ),
          )
          .toList(),
    );
  }

  Widget _buildCreatePenaltyCard() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'إضافة جزاء جديد',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedEmployeeId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'الموظف',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              items: _employees
                  .map(
                    (employee) => DropdownMenuItem(
                      value: employee['id']?.toString(),
                      child: Text(
                        employee['full_name']?.toString() ?? 'غير معروف',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedEmployeeId = value;
                });
              },
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_month,
                      color: AppColors.primaryOrange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_dateLabel(_selectedDate))),
                    const Icon(Icons.edit_calendar),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildPenaltyTypeChips(),
            const SizedBox(height: 12),
            if (_selectedPenaltyType == ManagerPenaltyType.custom)
              TextField(
                controller: _customAmountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'المبلغ المخصص',
                  suffixText: 'ج.م',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            if (_selectedPenaltyType == ManagerPenaltyType.custom)
              const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'سبب الجزاء (اختياري)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'قيمة الجزاء الحالية: ${_amountPreview().toStringAsFixed(2)} ج.م',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _processing ? null : _applyPenalty,
              icon: _processing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.gavel),
              label: Text(_processing ? 'جاري الإضافة...' : 'إضافة الجزاء'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryHeader() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_right),
            ),
            Expanded(
              child: Text(
                'سجل الجزاءات - ${_monthLabel(_selectedMonth)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              onPressed: _loadPenalties,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPenaltyCard(Map<String, dynamic> penalty) {
    final employeeName = penalty['employee_name']?.toString() ?? 'غير معروف';
    final reason = penalty['reason']?.toString() ?? '';
    final date = penalty['deduction_date']?.toString() ?? '--';
    final amount = (penalty['amount'] as num?)?.toDouble() ?? 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    employeeName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '- ${amount.toStringAsFixed(2)} ج.م',
                    style: const TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('تاريخ الجزاء: $date'),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'السبب: $reason',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    if (_penalties.isEmpty) {
      return const Center(child: Text('لا يوجد جزاءات في الشهر المحدد'));
    }

    return ListView.builder(
      itemCount: _penalties.length,
      itemBuilder: (context, index) => _buildPenaltyCard(_penalties[index]),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _employees.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: AppColors.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _bootstrap,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (_employees.isEmpty) {
      return const Center(child: Text('لا يوجد موظفين في هذا الفرع'));
    }

    return Column(
      children: [
        _buildCreatePenaltyCard(),
        _buildHistoryHeader(),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadPenalties,
            child: _buildHistoryList(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('إدارة الجزاءات - ${widget.branchName}'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }
}
