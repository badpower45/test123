import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../models/employee.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.employeeId});

  final String employeeId;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Employee? _employee;

  @override
  void initState() {
    super.initState();
    _loadEmployeeData();
  }

  Future<void> _loadEmployeeData() async {
    setState(() {
      _employee = Employee(
        id: widget.employeeId,
        fullName: 'مريم حسن',
        pin: '1234',
        role: EmployeeRole.staff,
        branch: 'فرع المعادي',
        monthlySalary: 5000.0,
      );
    });
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'تأكيد تسجيل الخروج',
          style: GoogleFonts.ibmPlexSansArabic(),
        ),
        content: Text(
          'هل تريد بالتأكيد تسجيل الخروج والعودة إلى شاشة الدخول؟',
          style: GoogleFonts.ibmPlexSansArabic(),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'إلغاء',
              style: GoogleFonts.ibmPlexSansArabic(),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: Text(
              'تسجيل الخروج',
              style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_employee == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildInfoSection(),
              const SizedBox(height: 16),
              _buildSettingsSection(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryOrange, Color(0xFFFF9A56)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 50,
              backgroundColor: AppColors.primaryOrange.withOpacity(0.2),
              child: Text(
                _employee!.fullName[0],
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryOrange,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _employee!.fullName,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'رقم الموظف: ${_employee!.id}',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 16,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'المعلومات الشخصية',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.work,
            label: 'الوظيفة',
            value: _getRoleLabel(_employee!.role),
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.location_on,
            label: 'الفرع',
            value: _employee!.branch,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.attach_money,
            label: 'الراتب الشهري',
            value: '${_employee!.monthlySalary.toStringAsFixed(0)} جنيه',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryOrange, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'الإعدادات',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 12),
          _buildSettingItem(
            icon: Icons.lock,
            label: 'تغيير الرقم السري',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'سيتم إضافة ميزة تغيير الرقم السري قريباً',
                    style: GoogleFonts.ibmPlexSansArabic(),
                    textDirection: TextDirection.rtl,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildSettingItem(
            icon: Icons.notifications,
            label: 'إعدادات الإشعارات',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'سيتم إضافة إعدادات الإشعارات قريباً',
                    style: GoogleFonts.ibmPlexSansArabic(),
                    textDirection: TextDirection.rtl,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildSettingItem(
            icon: Icons.help,
            label: 'المساعدة والدعم',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'سيتم إضافة صفحة المساعدة قريباً',
                    style: GoogleFonts.ibmPlexSansArabic(),
                    textDirection: TextDirection.rtl,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildSettingItem(
            icon: Icons.logout,
            label: 'تسجيل الخروج',
            color: AppColors.danger,
            onTap: _confirmLogout,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, color: color ?? AppColors.primaryOrange, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color ?? Colors.black87,
                ),
                textDirection: TextDirection.rtl,
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  String _getRoleLabel(EmployeeRole role) {
    switch (role) {
      case EmployeeRole.staff:
        return 'موظف';
      case EmployeeRole.monitor:
        return 'مراقب';
      case EmployeeRole.hr:
        return 'موارد بشرية';
      case EmployeeRole.admin:
        return 'مدير';
    }
  }
}
