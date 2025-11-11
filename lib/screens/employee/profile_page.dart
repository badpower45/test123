import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/employee_repository.dart';
import '../../services/supabase_attendance_service.dart';
import '../../services/auth_service.dart';
import '../../services/attendance_api_service.dart';
import '../../models/employee.dart';
import '../login_screen.dart';
import 'employee_payroll_report_page.dart';

class ProfilePage extends StatefulWidget {
  final String employeeId;
  const ProfilePage({super.key, required this.employeeId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Future<void> reloadData() async {
    await _loadEmployee();
  }
  Employee? _employee;
  String? _branchName;
  Map<String, dynamic>? _supabaseEmployee;
  String? _shiftType;
  bool _isActive = true;
  DateTime? _employmentDate;
  String? _branchId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEmployee();
  }

  Future<void> _loadEmployee() async {
    setState(() => _loading = true);
    
    try {
      // Get employee data from Supabase
      final data = await SupabaseAttendanceService.getEmployeeStatus(widget.employeeId);
      final employeeData = data['employee'] as Map<String, dynamic>?;

      Employee? effectiveEmployee = await EmployeeRepository.findById(widget.employeeId);

      if (employeeData != null) {
        final normalized = Map<String, dynamic>.from(employeeData);

        final branchRelation = normalized.remove('branch') ?? normalized.remove('branches');
        if (branchRelation is Map) {
          _branchName = branchRelation['name']?.toString() ?? 'غير محدد';
          _branchId = branchRelation['id']?.toString();
          normalized['branch'] = _branchName ?? branchRelation['id']?.toString();
        } else if (branchRelation is String) {
          _branchName = branchRelation;
          normalized['branch'] = branchRelation;
        } else {
          _branchName = effectiveEmployee?.branch ?? 'غير محدد';
        }

        _shiftType = (employeeData['shift_type'] ?? employeeData['shiftType'])?.toString();

        final activeValue = employeeData['is_active'] ?? employeeData['active'];
        if (activeValue is bool) {
          _isActive = activeValue;
        } else if (activeValue is num) {
          _isActive = activeValue != 0;
        }

        _employmentDate = _parseDate(employeeData['created_at']);

        final supEmployee = _buildEmployeeFromSupabase(normalized);
        if (supEmployee != null) {
          effectiveEmployee = supEmployee;
          await EmployeeRepository.upsert(supEmployee);
        }

        _supabaseEmployee = employeeData;
      } else {
        _branchName = effectiveEmployee?.branch ?? 'غير محدد';
        _supabaseEmployee = null;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _employee = effectiveEmployee;
        _loading = false;
      });
    } catch (e) {
      print('❌ Error loading employee: $e');
      // Fallback to local cache
      final emp = await EmployeeRepository.findById(widget.employeeId);
      if (!mounted) {
        return;
      }
      setState(() {
        _employee = emp;
        _branchName = emp?.branch ?? 'غير محدد';
        _supabaseEmployee = null;
        _loading = false;
      });
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  Employee? _buildEmployeeFromSupabase(Map<String, dynamic> data) {
    try {
      final json = Map<String, dynamic>.from(data);

      final hourlyRate = json['hourly_rate'];
      if (hourlyRate is int) {
        json['hourly_rate'] = hourlyRate.toDouble();
      }

      return Employee.fromJson(json);
    } catch (e) {
      print('⚠️ Failed to convert Supabase employee payload: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final employee = _employee;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : employee == null
                ? Center(child: Text('لا يوجد بيانات لهذا الموظف', style: TextStyle(color: Colors.red)))
                : _buildProfileContent(employee),
      ),
    );
  }


  Widget _buildProfileContent(Employee employee) {
    final shiftTypeLabel = _getShiftTypeLabel();
    final shiftRange = _getShiftRangeLabel();
    final hourlyRate = _getHourlyRateValue();
    final joinDate = _employmentDate;

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header with Profile Info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(32),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: AppColors.primaryLight,
                    child: const Icon(
                      Icons.person,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  employee.fullName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'ID: ${employee.id}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'معلومات الموظف',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoCard(
                  icon: Icons.work,
                  label: 'الوظيفة',
                  value: _getRoleDisplayName(employee.role),
                  color: AppColors.primaryOrange,
                ),
                const SizedBox(height: 12),
                _buildInfoCard(
                  icon: Icons.location_on,
                  label: 'الفرع',
                  value: _branchName ?? 'غير محدد',
                  color: AppColors.info,
                ),
                const SizedBox(height: 12),
                _buildInfoCard(
                  icon: Icons.verified_user,
                  label: 'حالة الموظف',
                  value: _getStatusLabel(),
                  color: _getStatusColor(),
                ),
                if (_branchId != null && _branchId!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    icon: Icons.badge_outlined,
                    label: 'معرف الفرع',
                    value: _branchId!,
                    color: AppColors.textSecondary,
                  ),
                ],
                if (shiftTypeLabel != null && shiftTypeLabel.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    icon: Icons.autorenew,
                    label: 'نوع الشيفت',
                    value: shiftTypeLabel,
                    color: AppColors.primaryLight,
                  ),
                ],
                if (shiftRange != null && shiftRange.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    icon: Icons.access_time,
                    label: 'مواعيد الشيفت',
                    value: shiftRange,
                    color: AppColors.info,
                  ),
                ],
                if (hourlyRate != null) ...[
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    icon: Icons.payments,
                    label: 'سعر الساعة',
                    value: '${_formatCurrency(hourlyRate)} جنيه/ساعة',
                    color: AppColors.success,
                  ),
                ],
                if (joinDate != null) ...[
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    icon: Icons.calendar_month,
                    label: 'تاريخ الانضمام',
                    value: _formatDate(joinDate.toLocal()),
                    color: AppColors.primaryDark,
                  ),
                ],
                const SizedBox(height: 32),
                const Text(
                  'البيانات الشخصية',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                if (employee.address != null && employee.address!.isNotEmpty) ...[
                  _buildInfoCard(
                    icon: Icons.home,
                    label: 'العنوان',
                    value: employee.address!,
                    color: AppColors.primaryDark,
                  ),
                  const SizedBox(height: 12),
                ],
                if (employee.birthDate != null) ...[
                  _buildInfoCard(
                    icon: Icons.cake,
                    label: 'تاريخ الميلاد',
                    value: _formatDate(employee.birthDate!),
                    color: AppColors.warning,
                  ),
                  const SizedBox(height: 12),
                ],
                if (employee.email != null && employee.email!.isNotEmpty) ...[
                  _buildInfoCard(
                    icon: Icons.email,
                    label: 'البريد الإلكتروني',
                    value: employee.email!,
                    color: AppColors.info,
                  ),
                  const SizedBox(height: 12),
                ],
                if (employee.phone != null && employee.phone!.isNotEmpty) ...[
                  _buildInfoCard(
                    icon: Icons.phone,
                    label: 'رقم الهاتف',
                    value: employee.phone!,
                    color: AppColors.success,
                  ),
                  const SizedBox(height: 12),
                ],
                if ((employee.address == null || employee.address!.isEmpty) &&
                    employee.birthDate == null &&
                    (employee.email == null || employee.email!.isEmpty) &&
                    (employee.phone == null || employee.phone!.isEmpty))
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
                            'لم يتم إضافة بيانات شخصية بعد',
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
                const Text(
                  'الإعدادات',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSettingItem(
                  icon: Icons.lock_outline,
                  title: 'تغيير الرقم السري',
                  subtitle: 'تحديث كلمة المرور الخاصة بك',
                  onTap: () {},
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  icon: Icons.notifications_outlined,
                  title: 'الإشعارات',
                  subtitle: 'إدارة إشعارات التطبيق',
                  onTap: () {},
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  icon: Icons.help_outline,
                  title: 'المساعدة والدعم',
                  subtitle: 'تواصل مع فريق الدعم',
                  onTap: () {},
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  icon: Icons.receipt_long,
                  title: 'تقرير المرتب',
                  subtitle: 'عرض تفاصيل الحضور والمرتب',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EmployeePayrollReportPage(
                          employeeId: widget.employeeId,
                          employeeName: employee.fullName,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _buildSettingItem(
                  icon: Icons.info_outline,
                  title: 'حول التطبيق',
                  subtitle: 'الإصدار 1.0.0',
                  onTap: () {},
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      // التحقق من حالة الحضور أولاً
                      try {
                        final status = await AttendanceApiService.fetchEmployeeStatus(widget.employeeId);
                        final isCheckedIn = status['attendance']?['status'] == 'active';

                        if (isCheckedIn) {
                          // منع تسجيل الخروج إذا كان مسجل حضور
                          if (!mounted) return;
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              icon: const Icon(Icons.warning_amber, size: 48, color: AppColors.error),
                              title: const Text('لا يمكن تسجيل الخروج'),
                              content: const Text(
                                'يجب عليك تسجيل الانصراف أولاً قبل تسجيل الخروج من الحساب.\n\n'
                                'الرجاء الضغط على زر "تسجيل الانصراف" من الصفحة الرئيسية.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('حسناً', style: TextStyle(fontSize: 16)),
                                ),
                              ],
                            ),
                          );
                          return; // إيقاف عملية تسجيل الخروج
                        }
                      } catch (e) {
                        print('⚠️ Failed to check attendance status: $e');
                        // في حالة الخطأ، نسمح بالمتابعة
                      }

                      // --- إظهار مؤشر التحميل ---
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(child: CircularProgressIndicator()),
                      );

                      // استدعاء دالة تسجيل الخروج الجديدة
                      await AuthService.logout();

                      // التأكد أن الـ widget لا يزال موجوداً
                      if (mounted) {
                        // إخفاء مؤشر التحميل والانتقال لشاشة تسجيل الدخول
                        Navigator.of(context).pop(); // لإخفاء مؤشر التحميل
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('تسجيل الخروج'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
  double? _getHourlyRateValue() {
    final localRate = _employee?.hourlyRate;
    if (localRate != null && localRate > 0) {
      return localRate;
    }
    final supRate = _supabaseEmployee?['hourly_rate'];
    if (supRate is num && supRate > 0) {
      return supRate.toDouble();
    }
    return null;
  }

  String? _getShiftStartLabel() {
    final local = _employee?.shiftStartTime;
    final sup = _supabaseEmployee?['shift_start_time'] ?? _supabaseEmployee?['shiftStartTime'];
    return _formatShiftTime(local ?? sup?.toString());
  }

  String? _getShiftEndLabel() {
    final local = _employee?.shiftEndTime;
    final sup = _supabaseEmployee?['shift_end_time'] ?? _supabaseEmployee?['shiftEndTime'];
    return _formatShiftTime(local ?? sup?.toString());
  }

  String? _getShiftRangeLabel() {
    final start = _getShiftStartLabel();
    final end = _getShiftEndLabel();
    if (start == null && end == null) {
      return null;
    }
    if (start != null && end != null) {
      return '$start - $end';
    }
    return start ?? end;
  }

  String? _getShiftTypeLabel() {
    final value = _shiftType?.toUpperCase();
    switch (value) {
      case 'AM':
        return 'شيفت صباحي (AM)';
      case 'PM':
        return 'شيفت مسائي (PM)';
      default:
        return _shiftType;
    }
  }

  String _getStatusLabel() => _isActive ? 'نشط' : 'متوقف مؤقتاً';

  Color _getStatusColor() => _isActive ? AppColors.success : AppColors.error;

  String? _formatShiftTime(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final parts = value.split(':');
    if (parts.length >= 2) {
      final hour = parts[0].padLeft(2, '0');
      final minute = parts[1].padLeft(2, '0');
      return '$hour:$minute';
    }
    return value;
  }

  String _formatCurrency(double value) {
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  Widget _buildInfoCard({
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
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

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: AppColors.textSecondary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_left,
              color: AppColors.textTertiary,
            ),
          ],
        ),
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
    // Format: DD/MM/YYYY
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
