import 'package:flutter/material.dart';
import '../../models/employee.dart';
import '../../services/supabase_auth_service.dart';
import '../../theme/app_colors.dart';

class EmployeeProfileScreen extends StatefulWidget {
  const EmployeeProfileScreen({
    super.key,
    required this.employeeId,
  });

  final String employeeId;

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  Employee? _employee;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEmployeeData();
  }

  Future<void> _loadEmployeeData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final employee = await SupabaseAuthService.getEmployee(widget.employeeId);
      
      if (!mounted) return;
      
      setState(() {
        _employee = employee;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'غير محدد';
    return '${date.day}/${date.month}/${date.year}';
  }

  String _getRoleText(EmployeeRole role) {
    switch (role) {
      case EmployeeRole.owner:
        return 'مالك';
      case EmployeeRole.admin:
        return 'مسؤول';
      case EmployeeRole.manager:
        return 'مدير';
      case EmployeeRole.hr:
        return 'موارد بشرية';
      case EmployeeRole.monitor:
        return 'مراقب';
      case EmployeeRole.staff:
        return 'موظف';
    }
  }

  Color _getRoleColor(EmployeeRole role) {
    switch (role) {
      case EmployeeRole.owner:
        return Colors.purple;
      case EmployeeRole.admin:
        return Colors.red;
      case EmployeeRole.manager:
        return Colors.blue;
      case EmployeeRole.hr:
        return Colors.green;
      case EmployeeRole.monitor:
        return Colors.teal;
      case EmployeeRole.staff:
        return AppColors.primaryOrange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('الملف الشخصي'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: AppColors.error),
                      const SizedBox(height: 16),
                      Text('حدث خطأ: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadEmployeeData,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : _employee == null
                  ? const Center(child: Text('لم يتم العثور على بيانات الموظف'))
                  : RefreshIndicator(
                      onRefresh: _loadEmployeeData,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          children: [
                            // Header with Avatar
                            Container(
                              width: double.infinity,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    AppColors.primaryOrange,
                                    Color(0xFFFF6B35),
                                  ],
                                ),
                              ),
                              child: Column(
                                children: [
                                  const SizedBox(height: 32),
                                  // Avatar
                                  Container(
                                    width: 100,
                                    height: 100,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 4),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        _employee!.fullName.isNotEmpty
                                            ? _employee!.fullName[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          fontSize: 40,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primaryOrange,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // Name
                                  Text(
                                    _employee!.fullName,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  // Role Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _getRoleColor(_employee!.role),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _getRoleText(_employee!.role),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  // Employee ID
                                  Text(
                                    'رقم الموظف: ${_employee!.id}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                ],
                              ),
                            ),
                            
                            // Profile Information Cards
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  // Contact Information
                                  _ProfileCard(
                                    title: 'معلومات الاتصال',
                                    icon: Icons.contact_phone,
                                    children: [
                                      if (_employee!.phone != null && _employee!.phone!.isNotEmpty)
                                        _InfoRow(
                                          icon: Icons.phone,
                                          label: 'رقم الهاتف',
                                          value: _employee!.phone!,
                                        ),
                                      if (_employee!.email != null && _employee!.email!.isNotEmpty)
                                        _InfoRow(
                                          icon: Icons.email,
                                          label: 'البريد الإلكتروني',
                                          value: _employee!.email!,
                                        ),
                                      if (_employee!.address != null && _employee!.address!.isNotEmpty)
                                        _InfoRow(
                                          icon: Icons.location_on,
                                          label: 'العنوان',
                                          value: _employee!.address!,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  
                                  // Employment Information
                                  _ProfileCard(
                                    title: 'معلومات العمل',
                                    icon: Icons.work,
                                    children: [
                                      _InfoRow(
                                        icon: Icons.store,
                                        label: 'الفرع',
                                        value: _employee!.branch.isNotEmpty ? _employee!.branch : 'غير محدد',
                                      ),
                                      _InfoRow(
                                        icon: Icons.badge,
                                        label: 'الوظيفة',
                                        value: _getRoleText(_employee!.role),
                                      ),
                                      if (_employee!.hourlyRate > 0)
                                        _InfoRow(
                                          icon: Icons.attach_money,
                                          label: 'سعر الساعة',
                                          value: '${_employee!.hourlyRate.toStringAsFixed(0)} جنيه',
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  
                                  // Personal Information
                                  _ProfileCard(
                                    title: 'معلومات شخصية',
                                    icon: Icons.person,
                                    children: [
                                      if (_employee!.birthDate != null)
                                        _InfoRow(
                                          icon: Icons.cake,
                                          label: 'تاريخ الميلاد',
                                          value: _formatDate(_employee!.birthDate),
                                        ),
                                      _InfoRow(
                                        icon: Icons.vpn_key,
                                        label: 'رقم التعريف',
                                        value: _employee!.id,
                                      ),
                                      _InfoRow(
                                        icon: Icons.toggle_on,
                                        label: 'الحالة',
                                        value: _employee!.isActive ? 'نشط' : 'غير نشط',
                                        valueColor: _employee!.isActive ? AppColors.success : AppColors.error,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: AppColors.primaryOrange, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
