import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/supabase_owner_service.dart';
import '../../services/supabase_branch_service.dart';
import '../../theme/app_colors.dart';

class OwnerAttendanceTableScreen extends StatefulWidget {
  const OwnerAttendanceTableScreen({super.key});

  @override
  State<OwnerAttendanceTableScreen> createState() => _OwnerAttendanceTableScreenState();
}

class _OwnerAttendanceTableScreenState extends State<OwnerAttendanceTableScreen> {
  List<Map<String, dynamic>> _attendanceRecords = [];
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;
  String? _error;

  // Filters
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedBranch;
  String? _selectedEmployee;

  @override
  void initState() {
    super.initState();
    _initializeFilters();
    _loadBranches();
    _loadAttendance();
  }

  void _initializeFilters() {
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1); // First day of month
    _endDate = now; // Today
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await SupabaseBranchService.getAllBranches();
      if (mounted) {
        setState(() => _branches = branches);
      }
    } catch (e) {
      print('Load branches error: $e');
    }
  }

  Future<void> _loadAttendance() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final records = await SupabaseOwnerService.getAttendanceTable(
        startDate: _startDate,
        endDate: _endDate,
        branchName: _selectedBranch,
        employeeId: _selectedEmployee,
      );

      if (!mounted) return;
      setState(() {
        _attendanceRecords = records;
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

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _startDate ?? DateTime.now().subtract(const Duration(days: 30)),
        end: _endDate ?? DateTime.now(),
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryOrange,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadAttendance();
    }
  }

  void _clearFilters() {
    setState(() {
      _initializeFilters();
      _selectedBranch = null;
      _selectedEmployee = null;
    });
    _loadAttendance();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('جدول الحضور'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_off),
            tooltip: 'مسح الفلاتر',
            onPressed: _clearFilters,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters Section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                // Date Range Filter
                InkWell(
                  onTap: _pickDateRange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range, color: AppColors.primaryOrange),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _startDate != null && _endDate != null
                                ? '${DateFormat('dd/MM/yyyy').format(_startDate!)} - ${DateFormat('dd/MM/yyyy').format(_endDate!)}'
                                : 'اختر الفترة',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Branch Filter
                DropdownButtonFormField<String>(
                  value: _selectedBranch,
                  decoration: const InputDecoration(
                    labelText: 'الفرع',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store, color: AppColors.primaryOrange),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('الكل')),
                    ..._branches.map((branch) => DropdownMenuItem(
                          value: branch['name'] as String,
                          child: Text(branch['name'] as String),
                        )),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedBranch = value);
                    _loadAttendance();
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Table Section
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 56, color: AppColors.error),
                            const SizedBox(height: 16),
                            Text('خطأ: $_error'),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadAttendance,
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      )
                    : _attendanceRecords.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox, size: 56, color: AppColors.textTertiary),
                                SizedBox(height: 16),
                                Text(
                                  'لا توجد سجلات حضور',
                                  style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadAttendance,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(
                                    AppColors.primaryOrange.withOpacity(0.1),
                                  ),
                                  columns: const [
                                    DataColumn(label: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('الموظف', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('الفرع', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('وقت الحضور', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('وقت الانصراف', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('إجمالي الساعات', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                  rows: _attendanceRecords.map((record) {
                                    final employeeData = record['employees'] as Map<String, dynamic>?;
                                    final employeeName = employeeData?['full_name'] ?? 'غير معروف';
                                    final branch = employeeData?['branch'] ?? '';
                                    final date = record['date'] as String;
                                    final checkInTime = record['check_in_time'] as String?;
                                    final checkOutTime = record['check_out_time'] as String?;
                                    final totalHours = (record['total_hours'] as num?)?.toDouble() ?? 0;

                                    final checkInFormatted = checkInTime != null
                                        ? DateFormat('HH:mm').format(DateTime.parse(checkInTime).toLocal())
                                        : '-';
                                    final checkOutFormatted = checkOutTime != null
                                        ? DateFormat('HH:mm').format(DateTime.parse(checkOutTime).toLocal())
                                        : '-';

                                    final isActive = checkOutTime == null;

                                    return DataRow(
                                      cells: [
                                        DataCell(Text(DateFormat('dd/MM/yyyy').format(DateTime.parse(date)))),
                                        DataCell(Text(employeeName)),
                                        DataCell(Text(branch)),
                                        DataCell(Text(checkInFormatted)),
                                        DataCell(Text(checkOutFormatted)),
                                        DataCell(Text(
                                          totalHours > 0 ? '${totalHours.toStringAsFixed(1)} ساعة' : '-',
                                        )),
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isActive ? AppColors.success.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              isActive ? 'حاضر' : 'انصرف',
                                              style: TextStyle(
                                                color: isActive ? AppColors.success : Colors.grey,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
          ),

          // Summary Section
          if (!_loading && _attendanceRecords.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryItem(
                    label: 'إجمالي السجلات',
                    value: '${_attendanceRecords.length}',
                    icon: Icons.list_alt,
                  ),
                  _SummaryItem(
                    label: 'الحاضرون الآن',
                    value: '${_attendanceRecords.where((r) => r['check_out_time'] == null).length}',
                    icon: Icons.person_pin_circle,
                    color: AppColors.success,
                  ),
                  _SummaryItem(
                    label: 'متوسط الساعات',
                    value: _calculateAverageHours(),
                    icon: Icons.access_time,
                    color: AppColors.primaryOrange,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _calculateAverageHours() {
    final completedRecords = _attendanceRecords.where((r) => r['total_hours'] != null).toList();
    if (completedRecords.isEmpty) return '0';

    final totalHours = completedRecords.fold<double>(
      0,
      (sum, r) => sum + ((r['total_hours'] as num?)?.toDouble() ?? 0),
    );

    return (totalHours / completedRecords.length).toStringAsFixed(1);
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color ?? AppColors.textSecondary, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color ?? AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
