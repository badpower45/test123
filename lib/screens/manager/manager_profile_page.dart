import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/auth_service.dart';
import '../login_screen.dart';

class ManagerProfilePage extends StatefulWidget {
  final String managerId;

  const ManagerProfilePage({Key? key, required this.managerId}) : super(key: key);

  @override
  State<ManagerProfilePage> createState() => _ManagerProfilePageState();
}

class _ManagerProfilePageState extends State<ManagerProfilePage> {
  @override
  Widget build(BuildContext context) {
    // Replace with actual manager data from API
    return Scaffold(
      appBar: AppBar(title: const Text('الملف الشخصي للمدير')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.primaryOrange,
              child: Icon(Icons.person, size: 48, color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text('اسم المدير', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('البريد الإلكتروني: manager@email.com'),
            const SizedBox(height: 8),
            const Text('الفرع: فرع المعادي'),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.phone, color: AppColors.info),
                title: const Text('رقم الهاتف'),
                trailing: const Text('01000000000'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.badge, color: AppColors.success),
                title: const Text('الوظيفة'),
                trailing: const Text('مدير الفرع'),
              ),
            ),
            const SizedBox(height: 24),
            // Logout Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
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
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
