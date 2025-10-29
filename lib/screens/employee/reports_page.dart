import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../constants/api_endpoints.dart';
import '../../theme/app_colors.dart';

class ReportsPage extends StatefulWidget {
  final String employeeId;

  const ReportsPage({super.key, required this.employeeId});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool _isLoading = false;
  List<dynamic> _tableRows = [];
  Map<String, dynamic>? _summary;
  // Map<String, dynamic>? _employeeInfo; // Removed unused field

  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _setDefaultDates();
    if (_isReportAvailable) {
      _loadData();
    }
  }

  Future<void> reloadData() async {
    if (_isReportAvailable) {
      await _loadData();
    } else {
      if (mounted) {
        setState(() {});
      }
    }
  }

  bool get _isReportAvailable {
    final day = DateTime.now().day;
    return day == 1 || day == 16;
  }

  int get _daysUntilNextReport {
    final now = DateTime.now();
    final day = now.day;
    
    if (day < 16) {
      return 16 - day;
    } else {
      final nextMonth = DateTime(now.year, now.month + 1, 1);
      return nextMonth.difference(now).inDays;
    }
  }

  String get _nextReportDate {
    final now = DateTime.now();
    final day = now.day;
    
    if (day < 16) {
      return '16 ${_getMonthName(now.month)}';
    } else {
      final nextMonth = now.month == 12 ? 1 : now.month + 1;
      return '1 ${_getMonthName(nextMonth)}';
    }
  }

  String _getMonthName(int month) {
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return months[month - 1];
  }

  void _setDefaultDates() {
    final now = DateTime.now();
    if (now.day <= 15) {
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month, 15);
    } else {
      _startDate = DateTime(now.year, now.month, 16);
      _endDate = DateTime(now.year, now.month + 1, 0);
    }
  }

  Future<void> _loadData() async {
    if (_startDate == null || _endDate == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final startDateStr = DateFormat('yyyy-MM-dd').format(_startDate!);
      final endDateStr = DateFormat('yyyy-MM-dd').format(_endDate!);

      final response = await http.get(
        Uri.parse(
          '$apiBaseUrl/owner/employee-attendance/${widget.employeeId}?startDate=$startDateStr&endDate=$endDateStr'
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _tableRows = data['tableRows'] ?? [];
          _summary = data['summary'];
          // _employeeInfo = data['employee']; // Removed unused field
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('فشل تحميل البيانات')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: AppColors.subtleGradient,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.analytics,
                          color: AppColors.primaryOrange,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'التقارير',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'تقرير الحضور الشهري',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: RefreshIndicator(
                onRefresh: reloadData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isReportAvailable) ...[
                        if (_isLoading)
                          const Center(child: CircularProgressIndicator())
                        else ...[
                          // Date Range Display
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'تقرير الفترة: ${DateFormat('yyyy-MM-dd').format(_startDate!)} إلى ${DateFormat('yyyy-MM-dd').format(_endDate!)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Table
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: _buildTable(),
                          ),
                          const SizedBox(height: 16),
                          // Summary Card
                          if (_summary != null) _buildSummaryCard(),
                        ]
                      ] else ...[
                        // Countdown Card
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primaryOrange.withOpacity(0.1),
                                AppColors.primaryLight.withOpacity(0.1),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.primaryOrange.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.schedule,
                                size: 64,
                                color: AppColors.primaryOrange,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'التقرير غير متاح حالياً',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'التقارير متاحة يوم 1 و 16 من كل شهر',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      color: AppColors.primaryOrange,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'التقرير القادم',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textTertiary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _nextReportDate,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 24),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryOrange.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'بعد $_daysUntilNextReport ${_daysUntilNextReport == 1 ? "يوم" : "أيام"}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primaryOrange,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Quick Stats While Waiting
                        const Text(
                          'إحصائيات سريعة',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),

                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: _buildQuickStat(
                                icon: Icons.event_available,
                                label: 'أيام الحضور',
                                value: '22',
                                color: AppColors.success,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildQuickStat(
                                icon: Icons.schedule,
                                label: 'إجمالي الساعات',
                                value: '176',
                                color: AppColors.info,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: _buildQuickStat(
                                icon: Icons.payments,
                                label: 'السلف',
                                value: '500',
                                color: AppColors.warning,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildQuickStat(
                                icon: Icons.beach_access,
                                label: 'الإجازات',
                                value: '2',
                                color: AppColors.primaryOrange,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return DataTable(
      columnSpacing: 20,
      headingRowColor: MaterialStateProperty.all(AppColors.primaryOrange.withOpacity(0.2)),
      columns: const [
        DataColumn(label: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('حضور', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('انصراف', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('الساعات', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('السلف', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('بدل إجازة', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('الخصومات', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
      rows: _tableRows.map((row) {
        return DataRow(
          cells: [
            DataCell(Text(row['date'] ?? '')),
            DataCell(Text(row['checkIn'] ?? '--')),
            DataCell(Text(row['checkOut'] ?? '--')),
            DataCell(Text(row['workHours'] ?? '0.00')),
            DataCell(
              Text(
                row['advances'] ?? '0.00',
                style: TextStyle(
                  color: double.parse(row['advances'] ?? '0') > 0 ? Colors.red : Colors.black,
                  fontWeight: double.parse(row['advances'] ?? '0') > 0 ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            DataCell(
              Row(
                children: [
                  Text(row['leaveAllowance'] ?? '0.00'),
                  if (row['hasLeave'] == true)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.check_circle, color: Colors.green, size: 16),
                    ),
                ],
              ),
            ),
            DataCell(
              Text(
                row['deductions'] ?? '0.00',
                style: TextStyle(
                  color: double.parse(row['deductions'] ?? '0') > 0 ? Colors.red : Colors.black,
                  fontWeight: double.parse(row['deductions'] ?? '0') > 0 ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryOrange.withOpacity(0.05), AppColors.primaryOrange.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryOrange.withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.summarize, color: AppColors.primaryOrange),
              SizedBox(width: 8),
              Text(
                'الملخص',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(thickness: 2),
          _summaryRow('إجمالي أيام العمل', _summary!['totalWorkDays'].toString()),
          _summaryRow('إجمالي ساعات العمل', _summary!['totalWorkHours'].toString()),
          _summaryRow('إجمالي السلف', '${_summary!['totalAdvances']} جنيه', color: Colors.red.shade700),
          _summaryRow('إجمالي بدل الإجازات', '${_summary!['totalLeaveAllowances']} جنيه', color: Colors.blue.shade700),
          _summaryRow('إجمالي الخصومات', '${_summary!['totalDeductions']} جنيه', color: Colors.red.shade700),
          const Divider(thickness: 2),
          _summaryRow(
            'الراتب الإجمالي',
            '${_summary!['grossSalary']} جنيه',
            isBold: true,
            fontSize: 16,
          ),
          _summaryRow(
            'الصافي بعد خصم السلف',
            '${_summary!['netAfterAdvances']} جنيه',
            isBold: true,
            color: AppColors.primaryOrange,
            fontSize: 18,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {Color? color, bool isBold = false, double fontSize = 14}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: fontSize,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }
}
