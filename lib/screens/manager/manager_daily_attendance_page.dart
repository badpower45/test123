import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/manager_attendance_admin_service.dart';
import '../../theme/app_colors.dart';

class ManagerDailyAttendancePage extends StatefulWidget {
  const ManagerDailyAttendancePage({
    super.key,
    required this.managerId,
    required this.branchName,
  });

  final String managerId;
  final String branchName;

  @override
  State<ManagerDailyAttendancePage> createState() =>
      _ManagerDailyAttendancePageState();
}

class _ManagerDailyAttendancePageState
    extends State<ManagerDailyAttendancePage> {
  bool _loadingEmployees = true;
  bool _loadingDays = false;
  bool _processing = false;
  String? _error;

  List<Map<String, dynamic>> _employees = [];
  String? _selectedEmployeeId;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  List<Map<String, dynamic>> _days = [];
  double _dayPenaltyValue = 100;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadEmployees();
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _loadingEmployees = true;
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
        _loadingEmployees = false;
      });

      await _loadDays();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loadingEmployees = false;
      });
    }
  }

  Future<void> _loadDays() async {
    final employeeId = _selectedEmployeeId;
    if (employeeId == null || employeeId.isEmpty) {
      setState(() {
        _days = [];
      });
      return;
    }

    setState(() {
      _loadingDays = true;
      _error = null;
    });

    try {
      final result = await ManagerAttendanceAdminService.getMonthlyAttendance(
        managerId: widget.managerId,
        branchName: widget.branchName,
        employeeId: employeeId,
        month: _selectedMonth,
      );

      if (!mounted) return;

      final loadedDays = _asMapList(result['days']);
      final dayPenaltyValue =
          (result['day_penalty_value'] as num?)?.toDouble() ?? _dayPenaltyValue;

      setState(() {
        _days = loadedDays;
        _dayPenaltyValue = dayPenaltyValue > 0 ? dayPenaltyValue : 100;
        _loadingDays = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loadingDays = false;
      });
    }
  }

  String _monthLabel(DateTime date) {
    return DateFormat('MMMM yyyy', 'ar').format(date);
  }

  String _dateLabel(String dateRaw) {
    try {
      final date = DateTime.parse(dateRaw);
      return DateFormat('EEEE - dd/MM/yyyy', 'ar').format(date);
    } catch (_) {
      return dateRaw;
    }
  }

  TimeOfDay? _parseTime(String? text) {
    if (text == null || text.trim().isEmpty) {
      return null;
    }

    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(text.trim());
    if (match == null) return null;

    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');

    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return TimeOfDay(hour: hour, minute: minute);
  }

  String _timeText(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  int _toMinutes(TimeOfDay time) => (time.hour * 60) + time.minute;

  Future<void> _pickMonth({required int delta}) async {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
    await _loadDays();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'present':
        return AppColors.success;
      case 'active':
        return Colors.orange;
      case 'absent':
        return AppColors.error;
      case 'on_leave':
        return Colors.blue;
      default:
        return AppColors.textSecondary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'present':
        return 'حاضر';
      case 'active':
        return 'لم ينصرف';
      case 'absent':
        return 'غائب';
      case 'on_leave':
        return 'إجازة';
      default:
        return 'لا يوجد';
    }
  }

  Future<void> _showEditTimeDialog(Map<String, dynamic> day) async {
    final employeeId = _selectedEmployeeId;
    final date = day['date']?.toString() ?? '';
    if (employeeId == null || date.isEmpty) return;

    TimeOfDay checkIn =
        _parseTime(day['check_in_time']?.toString()) ??
        const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay checkOut =
        _parseTime(day['check_out_time']?.toString()) ??
        const TimeOfDay(hour: 17, minute: 0);

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('تعديل وقت الحضور والانصراف'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _dateLabel(date),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.login, color: AppColors.success),
                    title: const Text('وقت الحضور'),
                    subtitle: Text(_timeText(checkIn)),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: dialogContext,
                        initialTime: checkIn,
                      );
                      if (picked != null) {
                        setDialogState(() {
                          checkIn = picked;
                        });
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout, color: AppColors.error),
                    title: const Text('وقت الانصراف'),
                    subtitle: Text(_timeText(checkOut)),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: dialogContext,
                        initialTime: checkOut,
                      );
                      if (picked != null) {
                        setDialogState(() {
                          checkOut = picked;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_toMinutes(checkOut) <= _toMinutes(checkIn)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'وقت الانصراف لازم يكون بعد وقت الحضور',
                          ),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSave != true) return;

    setState(() => _processing = true);

    try {
      await ManagerAttendanceAdminService.updateDayTimes(
        managerId: widget.managerId,
        branchName: widget.branchName,
        employeeId: employeeId,
        date: date,
        checkInTime: _timeText(checkIn),
        checkOutTime: _timeText(checkOut),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم تعديل وقت الحضور والانصراف'),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadDays();
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

  Future<void> _deleteDay(Map<String, dynamic> day) async {
    final employeeId = _selectedEmployeeId;
    final date = day['date']?.toString() ?? '';
    if (employeeId == null || date.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف يوم كامل'),
        content: Text(
          'هيمسح كل بيانات اليوم ${_dateLabel(date)} بما فيها الحضور والجزاءات.\n\nمتأكد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف اليوم'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processing = true);

    try {
      await ManagerAttendanceAdminService.deleteDay(
        managerId: widget.managerId,
        branchName: widget.branchName,
        employeeId: employeeId,
        date: date,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم حذف اليوم بالكامل'),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadDays();
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

  double _penaltyAmount(ManagerPenaltyType type, String customText) {
    switch (type) {
      case ManagerPenaltyType.halfDay:
        return _dayPenaltyValue / 2;
      case ManagerPenaltyType.day:
        return _dayPenaltyValue;
      case ManagerPenaltyType.twoDays:
        return _dayPenaltyValue * 2;
      case ManagerPenaltyType.custom:
        return double.tryParse(customText) ?? 0;
    }
  }

  Future<void> _showPenaltyDialog(Map<String, dynamic> day) async {
    final employeeId = _selectedEmployeeId;
    final date = day['date']?.toString() ?? '';
    if (employeeId == null || date.isEmpty) return;

    ManagerPenaltyType selectedType = ManagerPenaltyType.day;
    final customAmountController = TextEditingController();
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final amount = _penaltyAmount(
              selectedType,
              customAmountController.text,
            );

            return AlertDialog(
              title: const Text('إضافة جزاء'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _dateLabel(date),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 12),
                    RadioListTile<ManagerPenaltyType>(
                      value: ManagerPenaltyType.halfDay,
                      groupValue: selectedType,
                      title: Text(
                        'نصف يوم (${(_dayPenaltyValue / 2).toStringAsFixed(0)} ج.م)',
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedType = value);
                      },
                    ),
                    RadioListTile<ManagerPenaltyType>(
                      value: ManagerPenaltyType.day,
                      groupValue: selectedType,
                      title: Text(
                        'يوم (${_dayPenaltyValue.toStringAsFixed(0)} ج.م)',
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedType = value);
                      },
                    ),
                    RadioListTile<ManagerPenaltyType>(
                      value: ManagerPenaltyType.twoDays,
                      groupValue: selectedType,
                      title: Text(
                        'يومين (${(_dayPenaltyValue * 2).toStringAsFixed(0)} ج.م)',
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedType = value);
                      },
                    ),
                    RadioListTile<ManagerPenaltyType>(
                      value: ManagerPenaltyType.custom,
                      groupValue: selectedType,
                      title: const Text('قيمة مخصصة'),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedType = value);
                      },
                    ),
                    if (selectedType == ManagerPenaltyType.custom)
                      TextField(
                        controller: customAmountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'المبلغ',
                          suffixText: 'ج.م',
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonController,
                      decoration: const InputDecoration(
                        labelText: 'السبب (اختياري)',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'قيمة الجزاء: ${amount.toStringAsFixed(2)} ج.م',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final amount = _penaltyAmount(
                      selectedType,
                      customAmountController.text,
                    );
                    if (amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('قيمة الجزاء لازم تكون أكبر من صفر'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('تطبيق الجزاء'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final customAmount = selectedType == ManagerPenaltyType.custom
        ? double.tryParse(customAmountController.text)
        : null;

    setState(() => _processing = true);

    try {
      await ManagerAttendanceAdminService.applyPenalty(
        managerId: widget.managerId,
        branchName: widget.branchName,
        employeeId: employeeId,
        date: date,
        penaltyType: selectedType,
        customAmount: customAmount,
        reason: reasonController.text,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم تطبيق الجزاء بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadDays();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      customAmountController.dispose();
      reasonController.dispose();
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Widget _buildTopFilters() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
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
                    (employee) => DropdownMenuItem<String>(
                      value: employee['id']?.toString(),
                      child: Text(
                        employee['full_name']?.toString() ?? 'غير معروف',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) async {
                setState(() {
                  _selectedEmployeeId = value;
                });
                await _loadDays();
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  onPressed: _loadingDays ? null : () => _pickMonth(delta: -1),
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'الشهر السابق',
                ),
                Expanded(
                  child: Text(
                    _monthLabel(_selectedMonth),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _loadingDays ? null : () => _pickMonth(delta: 1),
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'الشهر التالي',
                ),
                IconButton(
                  onPressed: _loadingDays ? null : _loadDays,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'تحديث',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'قيمة اليوم في الجزاءات: ${_dayPenaltyValue.toStringAsFixed(0)} ج.م',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCard(Map<String, dynamic> day) {
    final date = day['date']?.toString() ?? '';
    final checkIn = day['check_in_time']?.toString();
    final checkOut = day['check_out_time']?.toString();
    final totalHours = (day['total_hours'] as num?)?.toDouble() ?? 0.0;
    final deduction = (day['deduction_amount'] as num?)?.toDouble() ?? 0.0;
    final status = day['status']?.toString() ?? 'none';
    final reasons = day['penalty_reasons']?.toString() ?? '';

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
                    _dateLabel(date),
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
                    color: _statusColor(status).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      color: _statusColor(status),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text(
                  'دخول: ${checkIn == null || checkIn.isEmpty ? '--' : checkIn}',
                ),
                Text(
                  'انصراف: ${checkOut == null || checkOut.isEmpty ? '--' : checkOut}',
                ),
                Text('الساعات: ${totalHours.toStringAsFixed(2)}'),
                Text(
                  'الجزاء: ${deduction.toStringAsFixed(2)} ج.م',
                  style: TextStyle(
                    color: deduction > 0
                        ? AppColors.error
                        : AppColors.textSecondary,
                    fontWeight: deduction > 0
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'سبب الجزاء: $reasons',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _processing
                      ? null
                      : () => _showEditTimeDialog(day),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('تعديل الوقت'),
                ),
                OutlinedButton.icon(
                  onPressed: _processing ? null : () => _deleteDay(day),
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('حذف اليوم'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _processing ? null : () => _showPenaltyDialog(day),
                  icon: const Icon(Icons.gavel, size: 18),
                  label: const Text('إضافة جزاء'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingEmployees) {
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
        _buildTopFilters(),
        if (_loadingDays)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_days.isEmpty)
          const Expanded(
            child: Center(child: Text('لا توجد بيانات حضور لهذا الشهر')),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadDays,
              child: ListView.builder(
                itemCount: _days.length,
                itemBuilder: (context, index) => _buildDayCard(_days[index]),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('جدول الحضور اليومي - ${widget.branchName}'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }
}
