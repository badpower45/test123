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
      final employeeData = data['employee'];
      
      if (employeeData != null) {
        // Extract branch name
        _branchName = employeeData['branch']?['name'] ?? 'غير محدد';
        
        // Get from local cache (for other fields)
        final emp = await EmployeeRepository.findById(widget.employeeId);
        
        setState(() {
          _employee = emp;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading employee: $e');
      // Fallback to local cache
      final emp = await EmployeeRepository.findById(widget.employeeId);
      setState(() {
        _employee = emp;
        _branchName = emp?.branch ?? 'غير محدد';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _employee == null
                ? Center(child: Text('لا يوجد بيانات لهذا الموظف', style: TextStyle(color: Colors.red)))
                : SingleChildScrollView(
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
                                _employee!.fullName,
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
                                  'ID: ${_employee!.id}',
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
                      value: _getRoleDisplayName(_employee!.role),
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
                    
                    const SizedBox(height: 32),
                    
                    // Personal Information Section
                    const Text(
                      'البيانات الشخصية',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    if (_employee!.address != null && _employee!.address!.isNotEmpty)
                      _buildInfoCard(
                        icon: Icons.home,
                        label: 'العنوان',
                        value: _employee!.address!,
                        color: AppColors.primaryDark,
                      ),
                    
                    if (_employee!.address != null && _employee!.address!.isNotEmpty)
                      const SizedBox(height: 12),
                    
                    if (_employee!.birthDate != null)
                      _buildInfoCard(
                        icon: Icons.cake,
                        label: 'تاريخ الميلاد',
                        value: _formatDate(_employee!.birthDate!),
                        color: AppColors.warning,
                      ),
                    
                    if (_employee!.birthDate != null)
                      const SizedBox(height: 12),
                    
                    if (_employee!.email != null && _employee!.email!.isNotEmpty)
                      _buildInfoCard(
                        icon: Icons.email,
                        label: 'البريد الإلكتروني',
                        value: _employee!.email!,
                        color: AppColors.info,
                      ),
                    
                    if (_employee!.email != null && _employee!.email!.isNotEmpty)
                      const SizedBox(height: 12),
                    
                    if (_employee!.phone != null && _employee!.phone!.isNotEmpty)
                      _buildInfoCard(
                        icon: Icons.phone,
                        label: 'رقم الهاتف',
                        value: _employee!.phone!,
                        color: AppColors.success,
                      ),
                    
                    if (_employee!.phone != null && _employee!.phone!.isNotEmpty)
                      const SizedBox(height: 12),
                    
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
                              employeeName: _employee?.fullName ?? 'الموظف',
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
                    
                    // Logout Button
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
        ),
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
