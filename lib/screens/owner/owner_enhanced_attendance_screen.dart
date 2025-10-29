import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/attendance_summary.dart';
import '../../models/employee_attendance_status.dart';
import '../../services/owner_api_service.dart';

class OwnerEnhancedAttendanceScreen extends StatefulWidget {
  const OwnerEnhancedAttendanceScreen({Key? key}) : super(key: key);

  @override
  State<OwnerEnhancedAttendanceScreen> createState() => _OwnerEnhancedAttendanceScreenState();
}

class _OwnerEnhancedAttendanceScreenState extends State<OwnerEnhancedAttendanceScreen> {
  DateTime _selectedDate = DateTime.now();
  String? _selectedBranchId;
  String _searchText = '';
  bool _isLoading = false;

  EmployeeStatusResult? _attendanceResult;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAttendanceData();
  }

  Future<void> _loadAttendanceData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await OwnerApiService.getEmployeeAttendanceStatus(
        branchId: _selectedBranchId,
        date: _selectedDate,
      );

      setState(() {
        _attendanceResult = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل البيانات: $e')),
        );
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadAttendanceData();
    }
  }

  List<EmployeeAttendanceStatus> _getFilteredEmployees() {
    if (_attendanceResult == null) return [];

    return _attendanceResult!.employees.where((employee) {
      final matchesSearch = _searchText.isEmpty ||
          employee.employeeName.toLowerCase().contains(_searchText.toLowerCase()) ||
          employee.employeeRole.toLowerCase().contains(_searchText.toLowerCase());

      return matchesSearch;
    }).toList();
  }

  Future<void> _handleManualCheckIn(String employeeId) async {
    try {
      await OwnerApiService.manualCheckIn(employeeId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسجيل الحضور بنجاح')),
        );
      }
      _loadAttendanceData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل في تسجيل الحضور: $e')),
        );
      }
    }
  }

  Future<void> _handleManualCheckOut(String employeeId) async {
    try {
      await OwnerApiService.manualCheckOut(employeeId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسجيل الانصراف بنجاح')),
        );
      }
      _loadAttendanceData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل في تسجيل الانصراف: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الحضور'),
        backgroundColor: const Color(0xFF1976D2),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: () => _selectDate(context),
            tooltip: 'اختيار التاريخ',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters Section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              children: [
                // Date and Branch Filter Row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'التاريخ: ${DateFormat('yyyy-MM-dd', 'ar').format(_selectedDate)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _selectDate(context),
                      icon: const Icon(Icons.calendar_today),
                      label: const Text('تغيير التاريخ'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Search Bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'البحث في الموظفين...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchText = value;
                    });
                  },
                ),
              ],
            ),
          ),

          // Summary Section
          if (_attendanceResult != null)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.blue.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem('حاضر', _attendanceResult!.summary.present, Colors.green),
                  _buildSummaryItem('منصرف', _attendanceResult!.summary.checkedOut, Colors.blue),
                  _buildSummaryItem('غائب', _attendanceResult!.summary.absent, Colors.red),
                  _buildSummaryItem('إجازة', _attendanceResult!.summary.onLeave, Colors.orange),
                ],
              ),
            ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadAttendanceData,
                    child: _attendanceResult == null || _attendanceResult!.employees.isEmpty
                        ? const Center(child: Text('لا توجد بيانات'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _getFilteredEmployees().length,
                            itemBuilder: (context, index) {
                              final employee = _getFilteredEmployees()[index];
                              return _buildEmployeeCard(employee);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeCard(EmployeeAttendanceStatus employee) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (employee.status) {
      case 'present':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'حاضر';
        break;
      case 'checked_out':
        statusColor = Colors.blue;
        statusIcon = Icons.exit_to_app;
        statusText = 'منصرف';
        break;
      case 'absent':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'غائب';
        break;
      case 'on_leave':
        statusColor = Colors.orange;
        statusIcon = Icons.beach_access;
        statusText = 'إجازة';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
        statusText = 'غير محدد';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Employee Header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor.withOpacity(0.2),
                  child: Icon(statusIcon, color: statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.employeeName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        employee.employeeRole,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                      if (employee.branchName != null)
                        Text(
                          employee.branchName!,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Time Information
            if (employee.checkInTime != null || employee.checkOutTime != null)
              Row(
                children: [
                  if (employee.checkInTime != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'وقت الحضور',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            DateFormat('HH:mm', 'ar').format(employee.checkInTime!),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (employee.checkOutTime != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'وقت الانصراف',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            DateFormat('HH:mm', 'ar').format(employee.checkOutTime!),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

            const SizedBox(height: 12),

            // Action Buttons
            Row(
              children: [
                if (employee.status == 'absent')
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _handleManualCheckIn(employee.employeeId),
                      icon: const Icon(Icons.login),
                      label: const Text('تسجيل حضور'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                if (employee.status == 'present')
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _handleManualCheckOut(employee.employeeId),
                      icon: const Icon(Icons.logout),
                      label: const Text('تسجيل انصراف'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}