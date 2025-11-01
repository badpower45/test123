import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/employee_attendance_status.dart';
import '../../services/owner_api_service.dart';
import '../../theme/app_colors.dart';

class OwnerAttendanceControlScreen extends StatefulWidget {
  const OwnerAttendanceControlScreen({super.key});

  static const routeName = '/owner/attendance-control';

  @override
  State<OwnerAttendanceControlScreen> createState() =>
      _OwnerAttendanceControlScreenState();
}

class _OwnerAttendanceControlScreenState
    extends State<OwnerAttendanceControlScreen> {
  List<EmployeeAttendanceStatus> _employees = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Auto refresh every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await OwnerApiService.getEmployeeAttendanceStatus();
      if (mounted) {
        setState(() {
          _employees = result.employees;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _manualCheckIn(EmployeeAttendanceStatus employee) async {
    try {
      final reason = await _showReasonDialog('تسجيل حضور يدوي', employee.employeeName);
      if (reason == null) return;

      await OwnerApiService.manualCheckIn(employee.employeeId, reason: reason);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text('تم تسجيل الحضور لـ ${employee.employeeName}'),
        ),
      );

      _loadData(); // Refresh data
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('فشل تسجيل الحضور: $e'),
        ),
      );
    }
  }

  Future<void> _manualCheckOut(EmployeeAttendanceStatus employee) async {
    try {
      final reason = await _showReasonDialog('تسجيل انصراف يدوي', employee.employeeName);
      if (reason == null) return;

      await OwnerApiService.manualCheckOut(employee.employeeId, reason: reason);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text('تم تسجيل الانصراف لـ ${employee.employeeName}'),
        ),
      );

      _loadData(); // Refresh data
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('فشل تسجيل الانصراف: $e'),
        ),
      );
    }
  }

  Future<String?> _showReasonDialog(String title, String employeeName) async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الموظف: $employeeName'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'سبب التعديل (اختياري)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim().isEmpty ? null : controller.text.trim()),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'present':
        return AppColors.success;
      case 'absent':
        return AppColors.danger;
      case 'checked_out':
        return Colors.grey.shade600;
      case 'on_leave':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'present':
        return 'حاضر';
      case 'absent':
        return 'غائب';
      case 'checked_out':
        return 'انصرف';
      case 'on_leave':
        return 'إجازة';
      default:
        return status;
    }
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.onPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: AppColors.onPrimary,
        title: const Text('التحكم في الحضور'),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('خطأ: $_errorMessage'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _employees.length,
                    itemBuilder: (context, index) {
                      final employee = _employees[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          employee.employeeName,
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '${employee.employeeRole} ${employee.branchName != null ? '• ${employee.branchName}' : ''}',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(employee.status).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      _getStatusText(employee.status),
                                      style: TextStyle(
                                        color: _getStatusColor(employee.status),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildTimeInfo(
                                      'الحضور',
                                      employee.checkInTime,
                                    ),
                                  ),
                                  Expanded(
                                    child: _buildTimeInfo(
                                      'الانصراف',
                                      employee.checkOutTime,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  if (employee.isAbsent || employee.isCheckedOut)
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => _manualCheckIn(employee),
                                        icon: const Icon(Icons.login),
                                        label: const Text('تسجيل حضور'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.success,
                                          foregroundColor: AppColors.onPrimary,
                                        ),
                                      ),
                                    ),
                                  if (employee.isPresent)
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => _manualCheckOut(employee),
                                        icon: const Icon(Icons.logout),
                                        label: const Text('تسجيل انصراف'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.danger,
                                          foregroundColor: AppColors.onPrimary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildTimeInfo(String label, DateTime? time) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formatTime(time),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}