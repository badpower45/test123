import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_owner_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/time_utils.dart';

class MyAttendanceTableScreen extends StatefulWidget {
  const MyAttendanceTableScreen({Key? key}) : super(key: key);

  @override
  State<MyAttendanceTableScreen> createState() => _MyAttendanceTableScreenState();
}

class _MyAttendanceTableScreenState extends State<MyAttendanceTableScreen> {
  List<Map<String, dynamic>> _attendanceRecords = [];
  bool _loading = true;
  String? _error;
  String? _employeeId;

  // Filters
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _initializeFilters();
    _loadEmployeeId();
  }

  void _initializeFilters() {
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1); // First day of month
    _endDate = now; // Today
  }

  Future<void> _loadEmployeeId() async {
    try {
      final loginData = await AuthService.getLoginData();
      _employeeId = loginData['employeeId'];
      if (_employeeId != null) {
        _loadAttendance();
      } else {
        setState(() {
          _error = 'لم يتم العثور على معرف الموظف';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'خطأ في تحميل بيانات الموظف';
        _loading = false;
      });
    }
  }

  Future<void> _loadAttendance() async {
    if (_employeeId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // ✅ Use SAME service as Owner - fixes timezone issue
      final records = await SupabaseOwnerService.getAttendanceTable(
        startDate: _startDate,
        endDate: _endDate,
        employeeId: _employeeId,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('جدول حضوري'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Filter Section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Date Range Picker
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
                                    DataColumn(label: Text('وقت الحضور', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('وقت الانصراف', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('ساعات العمل', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('الأجر اليومي', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                  rows: _attendanceRecords.map((record) {
                                    // ✅ FIX: Safe date parsing
                                    final rawDate = record['attendance_date'] ?? record['date'];
                                    String dateFormatted = '-';
                                    if (rawDate != null && rawDate.toString().isNotEmpty) {
                                      try {
                                        dateFormatted = DateFormat('dd/MM/yyyy').format(DateTime.parse(rawDate.toString()));
                                      } catch (e) {
                                        dateFormatted = rawDate.toString();
                                      }
                                    }
                                    
                                    final checkInTime = record['check_in_time'] as String?;
                                    final checkOutTime = record['check_out_time'] as String?;
                                    final totalHours = (record['total_hours'] as num?)?.toDouble() ?? 0.0;
                                    final dailySalary = (record['daily_salary'] as num?)?.toDouble() ?? 0.0;

                                    // ✅ Use TimeUtils - fixes timezone (converts to Cairo time)
                                    final checkInFormatted = TimeUtils.formatTimeShort(checkInTime);
                                    final checkOutFormatted = TimeUtils.formatTimeShort(checkOutTime);

                                    final isActive = checkOutTime == null || checkOutTime.toString().isEmpty;

                                    return DataRow(
                                      cells: [
                                        DataCell(Text(dateFormatted)),
                                        DataCell(Text(checkInFormatted)),
                                        DataCell(Text(checkOutFormatted)),
                                        DataCell(Text(totalHours.toStringAsFixed(2))),
                                        DataCell(Text('${dailySalary.toStringAsFixed(2)} ج.م')),
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
                    label: 'إجمالي الأيام',
                    value: '${_attendanceRecords.length}',
                    icon: Icons.calendar_today,
                  ),
                  _SummaryItem(
                    label: 'متوسط الساعات',
                    value: _calculateAverageHours(),
                    icon: Icons.access_time,
                    color: AppColors.primaryOrange,
                  ),
                  _SummaryItem(
                    label: 'إجمالي الأجور',
                    value: _calculateTotalSalary(),
                    icon: Icons.attach_money,
                    color: Colors.blueAccent,
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

  String _calculateTotalSalary() {
    final totalSalary = _attendanceRecords.fold<double>(
      0,
      (sum, r) => sum + ((r['daily_salary'] as num?)?.toDouble() ?? 0),
    );

    return totalSalary > 0 ? '${totalSalary.toStringAsFixed(2)} ج.م' : '0';
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
