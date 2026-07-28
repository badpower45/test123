import 'package:flutter/material.dart';
import '../../services/payroll_service.dart';
import '../../services/supabase_branch_service.dart';
import '../../theme/app_colors.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class HRPayrollPage extends StatefulWidget {
  const HRPayrollPage({super.key});

  @override
  State<HRPayrollPage> createState() => _HRPayrollPageState();
}

class _HRPayrollPageState extends State<HRPayrollPage> {
  bool _isCurrentPeriod = true;
  bool _isLoading = false;
  bool _isBranchesLoading = true;
  List<Map<String, dynamic>> _allBranches = [];
  List<Map<String, dynamic>> _allEmployeesData = [];
  String _selectedBranchId = '';
  String _selectedBranchName = '';
  String _searchQuery = '';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _calculateCurrentPeriod();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() => _isBranchesLoading = true);
    try {
      final branches = await SupabaseBranchService.getAllBranches();
      setState(() {
        _allBranches = branches;
        _isBranchesLoading = false;
        if (branches.isNotEmpty) {
          _selectedBranchId = branches[0]['id'];
          _selectedBranchName = branches[0]['name'] ?? 'الفرع الأول';
          _loadPayrollDataForBranch();
        }
      });
    } catch (e) {
      setState(() => _isBranchesLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل الفروع: $e')),
        );
      }
    }
  }

  void _calculateCurrentPeriod() {
    final now = DateTime.now();
    if (now.day >= 16) {
      // Current period: 16th of this month to 15th of next month
      _startDate = DateTime(now.year, now.month, 16);
      _endDate = DateTime(now.year, now.month + 1, 15);
    } else {
      // Current period: 16th of last month to 15th of this month
      _startDate = DateTime(now.year, now.month - 1, 16);
      _endDate = DateTime(now.year, now.month, 15);
    }
  }

  void _togglePeriod() {
    setState(() {
      _isCurrentPeriod = !_isCurrentPeriod;
      if (_isCurrentPeriod) {
        _calculateCurrentPeriod();
      } else {
        // Previous period
        final prevStart = DateTime(_startDate.year, _startDate.month - 1, 16);
        final prevEnd = DateTime(_startDate.year, _startDate.month, 15);
        _startDate = prevStart;
        _endDate = prevEnd;
      }
      _loadPayrollDataForBranch();
    });
  }

  Future<void> _loadPayrollDataForBranch() async {
    if (_selectedBranchName.isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      // Get all employees attendance data
      final data = await PayrollService.getAllEmployeesAttendanceReport(
        startDate: _startDate,
        endDate: _endDate,
      );
      
      // Filter by selected branch
      final filteredData = data.where((emp) {
        final branch = (emp['branch'] ?? '').toString();
        return branch == _selectedBranchName;
      }).toList();

      setState(() {
        _allEmployeesData = filteredData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e')),
        );
      }
    }
  }

  void _onBranchChanged(String? branchId) {
    if (branchId == null) return;
    
    final selectedBranch = _allBranches.firstWhere(
      (b) => b['id'] == branchId,
      orElse: () => <String, dynamic>{},
    );
    
    if (selectedBranch.isNotEmpty) {
      setState(() {
        _selectedBranchId = branchId;
        _selectedBranchName = selectedBranch['name'] ?? '';
        _searchQuery = '';
      });
      _loadPayrollDataForBranch();
    }
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _allEmployeesData;

    return _allEmployeesData.where((employee) {
      final employeeName = (employee['employee_name'] ?? '').toString().toLowerCase();
      final employeeId = (employee['employee_id'] ?? '').toString().toLowerCase();
      return employeeName.contains(query) || employeeId.contains(query);
    }).toList();
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  Future<void> _printBranchPayroll() async {
    final font = await PdfGoogleFonts.cairoRegular();
    final boldFont = await PdfGoogleFonts.cairoBold();
    final pdf = pw.Document();
    final employees = _filteredEmployees;

    final totalHours = employees.fold<double>(0, (sum, emp) {
      final summary = emp['summary'] as Map<String, dynamic>?;
      return sum + ((summary?['total_hours'] as num?)?.toDouble() ?? 0);
    });
    final totalNet = employees.fold<double>(0, (sum, emp) {
      final summary = emp['summary'] as Map<String, dynamic>?;
      return sum + ((summary?['net_salary'] as num?)?.toDouble() ?? 0);
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text(
            'قائمة مرتبات فرع $_selectedBranchName',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'الفترة: ${_formatDate(_startDate)} - ${_formatDate(_endDate)}',
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            context: context,
            border: pw.TableBorder.all(color: PdfColors.grey300),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple100),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignment: pw.Alignment.centerRight,
            data: [
              ['الاسم', 'الساعات', 'سعر الساعة', 'المرتب الأساسي', 'الخصومات', 'الصافي'],
              ...employees.map((employee) {
                final summary = employee['summary'] as Map<String, dynamic>?;
                final name = (employee['employee_name'] ?? '').toString();
                final hours = ((summary?['total_hours'] as num?)?.toDouble() ?? 0).toStringAsFixed(1);
                final hourlyRate = ((summary?['hourly_rate'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
                final baseSalary = ((summary?['base_salary'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
                final deductions = ((summary?['total_deductions'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
                final net = ((summary?['net_salary'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
                return [name, hours, hourlyRate, baseSalary, deductions, net];
              }),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text('إجمالي الساعات: ${totalHours.toStringAsFixed(1)}'),
          pw.Text('إجمالي الصافي: ${totalNet.toStringAsFixed(2)}'),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'قائمة_مرتبات_${_selectedBranchName}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('رواتب الفروع'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _allEmployeesData.isEmpty ? null : _printBranchPayroll,
            tooltip: 'طباعة قائمة المرتبات',
          ),
          IconButton(
            icon: Icon(_isCurrentPeriod ? Icons.history : Icons.calendar_today),
            onPressed: _togglePeriod,
            tooltip: _isCurrentPeriod ? 'عرض الفترة السابقة' : 'عرض الفترة الحالية',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPayrollDataForBranch,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isBranchesLoading
          ? const Center(child: CircularProgressIndicator())
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Branch Selector
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'اختر الفرع',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white,
                            ),
                            child: DropdownButton<String>(
                              value: _selectedBranchId.isEmpty ? null : _selectedBranchId,
                              isExpanded: true,
                              underline: const SizedBox(),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              items: _allBranches.map((branch) {
                                return DropdownMenuItem<String>(
                                  value: branch['id'],
                                  child: Text(branch['name'] ?? 'فرع بدون اسم'),
                                );
                              }).toList(),
                              onChanged: _onBranchChanged,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Search Box
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: TextField(
                        onChanged: (value) => setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          hintText: 'ابحث بالاسم أو الكود',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Period Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.primaryOrange, AppColors.primaryOrange.withOpacity(0.8)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            _isCurrentPeriod ? 'الفترة الحالية' : 'الفترة السابقة',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_formatDate(_startDate)} - ${_formatDate(_endDate)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Summary Cards
                    _buildSummarySection(),

                    // Employees List
                    Expanded(
                      child: _filteredEmployees.isEmpty
                          ? const Center(
                              child: Text(
                                'لا توجد نتائج مطابقة',
                                style: TextStyle(fontSize: 16, color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredEmployees.length,
                              itemBuilder: (context, index) {
                                final employeeData = _filteredEmployees[index];
                                return _buildEmployeeCard(employeeData);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSummarySection() {
    double totalHours = 0;
    double totalBaseSalary = 0;
    double totalNetSalary = 0;
    int totalEmployees = _allEmployeesData.length;

    for (var emp in _allEmployeesData) {
      final summary = emp['summary'] as Map<String, dynamic>?;
      if (summary != null) {
        totalHours += (summary['total_hours'] as num?)?.toDouble() ?? 0;
        totalBaseSalary += (summary['base_salary'] as num?)?.toDouble() ?? 0;
        totalNetSalary += (summary['net_salary'] as num?)?.toDouble() ?? 0;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'إجمالي الموظفين',
                  totalEmployees.toString(),
                  Icons.people,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'إجمالي الساعات',
                  totalHours.toStringAsFixed(1),
                  Icons.access_time,
                  Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'إجمالي المرتبات',
                  '${totalBaseSalary.toStringAsFixed(0)} ج',
                  Icons.payments,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'صافي الإجمالي',
                  '${totalNetSalary.toStringAsFixed(0)} ج',
                  Icons.account_balance_wallet,
                  AppColors.primaryOrange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(Map<String, dynamic> employeeData) {
    final summary = employeeData['summary'] as Map<String, dynamic>?;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employeeData['employee_name'] ?? 'موظف',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    employeeData['employee_id'] ?? '',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Text(
              '${((summary?['net_salary'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} ج',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('الساعات', '${((summary?['total_hours'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} ساعة'),
                _buildDetailRow('سعر الساعة', '${((summary?['hourly_rate'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} ج'),
                _buildDetailRow('المرتب الأساسي', '${((summary?['base_salary'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} ج'),
                _buildDetailRow('بدل الإجازة', '${((summary?['leave_allowance'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} ج'),
                _buildDetailRow('السلفات', '${((summary?['total_advances'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} ج'),
                _buildDetailRow('الخصومات', '${((summary?['total_deductions'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} ج'),
                _buildDetailRow('أيام الغياب', '${(summary?['absence_days'] as num?)?.toInt() ?? 0}'),
                const Divider(),
                _buildDetailRow(
                  'الصافي',
                  '${((summary?['net_salary'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} ج',
                  isBold: true,
                  color: Colors.green,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
