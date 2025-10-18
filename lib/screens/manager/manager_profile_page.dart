import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class ManagerProfilePage extends StatelessWidget {
  final String managerId;

  const ManagerProfilePage({Key? key, required this.managerId}) : super(key: key);

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
          ],
        ),
      ),
    );
  }
}
