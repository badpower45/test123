import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../models/employee.dart';
import '../../services/employee_repository.dart';

class ManagerEmployeeDetailPage extends StatefulWidget {
  final String employeeId;

  const ManagerEmployeeDetailPage({
    super.key,
    required this.employeeId,
  });

  @override
  State<ManagerEmployeeDetailPage> createState() => _ManagerEmployeeDetailPageState();
}

class _ManagerEmployeeDetailPageState extends State<ManagerEmployeeDetailPage> {
  Employee? _employee;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEmployee();
  }

  Future<void> _loadEmployee() async {
    setState(() => _loading = true);
    try {
      final emp = await EmployeeRepository.findById(widget.employeeId);
      setState(() {
        _employee = emp;
        _loading = false;
      });
    } catch (e) {
      print('❌ Error loading employee: $e');
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تحميل بيانات الموظف')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _employee == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'لا يوجد بيانات لهذا الموظف',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('العودة'),
                      ),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    // App Bar
                    SliverAppBar(
                      expandedHeight: 200,
                      pinned: true,
                      flexibleSpace: FlexibleSpaceBar(
                        background: Container(
                          decoration: const BoxDecoration(
                            gradient: AppColors.primaryGradient,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 40),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: const CircleAvatar(
                                  radius: 50,
                                  backgroundColor: AppColors.primaryLight,
                                  child: Icon(
                                    Icons.person,
                                    size: 50,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _employee!.fullName,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      iconTheme: const IconThemeData(color: Colors.white),
                    ),

                    // Content
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Work Information
                            _buildSectionTitle('معلومات الوظيفة'),
                            const SizedBox(height: 16),
                            
                            _buildInfoCard(
                              icon: Icons.badge,
                              label: 'رقم الموظف',
                              value: _employee!.id,
                              color: AppColors.primaryDark,
                            ),
                            
                            const SizedBox(height: 12),
                            
                            _buildInfoCard(
                              icon: Icons.work,
                              label: 'الوظيفة',
                              value: _getRoleDisplayName(_employee!.role),
                              color: AppColors.primaryOrange,
                            ),
                            
                            const SizedBox(height: 12),
                            
                            _buildInfoCard(
                              icon: Icons.location_on,
                              label: 'الفرع',
                              value: _employee!.branch,
                              color: AppColors.info,
                            ),
                            
                            const SizedBox(height: 12),
                            
                            if (_employee!.hourlyRate > 0)
                              _buildInfoCard(
                                icon: Icons.payments,
                                label: 'سعر الساعة',
                                value: '${_employee!.hourlyRate.toStringAsFixed(0)} جنيه/ساعة',
                                color: AppColors.success,
                              ),
                            
                            if (_employee!.hourlyRate > 0)
                              const SizedBox(height: 12),
                            
                            if (_employee!.shiftStartTime != null && _employee!.shiftEndTime != null)
                              _buildInfoCard(
                                icon: Icons.access_time,
                                label: 'مواعيد الشيفت',
                                value: '${_employee!.shiftStartTime} - ${_employee!.shiftEndTime}',
                                color: AppColors.info,
                              ),
                            
                            if (_employee!.shiftStartTime != null && _employee!.shiftEndTime != null)
                              const SizedBox(height: 12),
                            
                            _buildInfoCard(
                              icon: _employee!.isActive ? Icons.check_circle : Icons.cancel,
                              label: 'حالة الحساب',
                              value: _employee!.isActive ? 'نشط' : 'غير نشط',
                              color: _employee!.isActive ? AppColors.success : AppColors.error,
                            ),

                            const SizedBox(height: 32),

                            // Personal Information
                            _buildSectionTitle('البيانات الشخصية'),
                            const SizedBox(height: 16),
                            
                            if (_employee!.address != null && _employee!.address!.isNotEmpty) ...[
                              _buildInfoCard(
                                icon: Icons.home,
                                label: 'العنوان',
                                value: _employee!.address!,
                                color: AppColors.primaryDark,
                              ),
                              const SizedBox(height: 12),
                            ],
                            
                            if (_employee!.birthDate != null) ...[
                              _buildInfoCard(
                                icon: Icons.cake,
                                label: 'تاريخ الميلاد',
                                value: _formatDate(_employee!.birthDate!),
                                color: AppColors.warning,
                              ),
                              const SizedBox(height: 12),
                            ],
                            
                            if (_employee!.email != null && _employee!.email!.isNotEmpty) ...[
                              _buildInfoCard(
                                icon: Icons.email,
                                label: 'البريد الإلكتروني',
                                value: _employee!.email!,
                                color: AppColors.info,
                              ),
                              const SizedBox(height: 12),
                            ],
                            
                            if (_employee!.phone != null && _employee!.phone!.isNotEmpty) ...[
                              _buildInfoCard(
                                icon: Icons.phone,
                                label: 'رقم الهاتف',
                                value: _employee!.phone!,
                                color: AppColors.success,
                              ),
                              const SizedBox(height: 12),
                            ],
                            
                            // Show message if no personal info
                            if ((_employee!.address == null || _employee!.address!.isEmpty) &&
                                _employee!.birthDate == null &&
                                (_employee!.email == null || _employee!.email!.isEmpty) &&
                                (_employee!.phone == null || _employee!.phone!.isEmpty))
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.grey.shade600),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'لم يتم إضافة بيانات شخصية لهذا الموظف',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 32),

                            // Created/Updated Info
                            _buildSectionTitle('معلومات إضافية'),
                            const SizedBox(height: 16),
                            
                            _buildInfoCard(
                              icon: Icons.calendar_today,
                              label: 'تاريخ التسجيل',
                              value: _formatDateTime(_employee!.createdAt),
                              color: AppColors.info,
                            ),
                            
                            const SizedBox(height: 12),
                            
                            _buildInfoCard(
                              icon: Icons.update,
                              label: 'آخر تحديث',
                              value: _formatDateTime(_employee!.updatedAt),
                              color: AppColors.warning,
                            ),

                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getRoleDisplayName(EmployeeRole role) {
    switch (role) {
      case EmployeeRole.staff:
        return 'موظف';
      case EmployeeRole.monitor:
        return 'مراقب';
      case EmployeeRole.hr:
        return 'موارد بشرية';
      case EmployeeRole.admin:
        return 'مسؤول';
      case EmployeeRole.manager:
        return 'مدير فرع';
      case EmployeeRole.owner:
        return 'مالك';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${_formatDate(dateTime)} - ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
