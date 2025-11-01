import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/employee_repository.dart';
import '../../models/employee.dart';
import '../login_screen.dart';

class ManagerProfilePage extends StatefulWidget {
  final String managerId;

  const ManagerProfilePage({Key? key, required this.managerId}) : super(key: key);

  @override
  State<ManagerProfilePage> createState() => _ManagerProfilePageState();
}

class _ManagerProfilePageState extends State<ManagerProfilePage> {
  Employee? _employee;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEmployee();
  }

  Future<void> _loadEmployee() async {
    final emp = await EmployeeRepository.findById(widget.managerId);
    setState(() {
      _employee = emp;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('الملف الشخصي'),
        backgroundColor: AppColors.primaryOrange,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _employee == null
              ? const Center(child: Text('لا يوجد بيانات لهذا المدير', style: TextStyle(color: Colors.red)))
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
                      
                      // Manager Info Cards
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'معلومات المدير',
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
                              value: 'مدير فرع',
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
                            
                            _buildInfoCard(
                              icon: Icons.payments,
                              label: 'الراتب الشهري',
                              value: '${_employee!.monthlySalary.toStringAsFixed(0)} جنيه',
                              color: AppColors.success,
                            ),
                            
                            const SizedBox(height: 32),
                            
                            // Logout Button
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  // Show loading indicator
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => const Center(child: CircularProgressIndicator()),
                                  );

                                  await AuthService.logout();

                                  if (mounted) {
                                    Navigator.of(context).pop(); // Hide loading
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
            child: Icon(
              icon,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
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
}
