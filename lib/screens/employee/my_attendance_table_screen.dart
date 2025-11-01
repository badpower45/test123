import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../constants/api_endpoints.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';

class MyAttendanceTableScreen extends StatefulWidget {
  const MyAttendanceTableScreen({Key? key}) : super(key: key);

  @override
  State<MyAttendanceTableScreen> createState() => _MyAttendanceTableScreenState();
}

class _MyAttendanceTableScreenState extends State<MyAttendanceTableScreen> {
  bool _isLoading = false;
  List<dynamic> _tableRows = [];
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _employeeInfo;
  
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _setDefaultDates();
    _loadData();
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
      final loginData = await AuthService.getLoginData();
      final employeeId = loginData['employeeId'];
      
      if (employeeId == null) {
        throw Exception('لم يتم العثور على معرف الموظف');
      }

      final startDateStr = DateFormat('yyyy-MM-dd').format(_startDate!);
      final endDateStr = DateFormat('yyyy-MM-dd').format(_endDate!);

      final response = await http.get(
        Uri.parse(
          '$apiBaseUrl/owner/employee-attendance/$employeeId?startDate=$startDateStr&endDate=$endDateStr'
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _tableRows = data['tableRows'] ?? [];
          _summary = data['summary'];
          _employeeInfo = data['employee'];
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

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate!, end: _endDate!),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1976D2),
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
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('جدول حضوري'),
        backgroundColor: const Color(0xFF1976D2),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _selectDateRange,
            tooltip: 'اختر الفترة',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // Employee Info Card
                    if (_employeeInfo != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _employeeInfo!['fullName'] ?? '',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('الوظيفة: ${_employeeInfo!['role'] ?? ''}'),
                            Text('الراتب: ${_employeeInfo!['monthlySalary'] ?? '0'} جنيه'),
                          ],
                        ),
                      ),

                    // Date Range Display
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'من ${DateFormat('yyyy-MM-dd').format(_startDate!)} إلى ${DateFormat('yyyy-MM-dd').format(_endDate!)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Table (Horizontal Scrollable)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildTable(),
                    ),

                    const SizedBox(height: 16),

                    // Summary Card
                    if (_summary != null) _buildSummaryCard(),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTable() {
    return DataTable(
      columnSpacing: 20,
      headingRowColor: MaterialStateProperty.all(Colors.blue.shade100),
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
          colors: [Colors.green.shade50, Colors.green.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade300, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.summarize, color: Colors.green),
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
          _summaryRow('حافز الغياب', '${_summary!['attendanceAllowance'] ?? '0.00'} جنيه', color: Colors.green.shade700),
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
            color: Colors.green.shade900,
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
