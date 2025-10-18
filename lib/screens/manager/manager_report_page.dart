import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class ManagerReportPage extends StatelessWidget {
  final String managerId;
  final String branch;

  const ManagerReportPage({Key? key, required this.managerId, required this.branch}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Replace with actual report data from API
    return Scaffold(
      appBar: AppBar(title: const Text('تقرير المدير')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('إحصائيات الحضور والانصراف', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_month, color: AppColors.info),
                title: const Text('عدد أيام الحضور'),
                trailing: Text('22 يوم'), // Replace with API data
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule, color: AppColors.success),
                title: const Text('إجمالي الساعات'),
                trailing: Text('176 ساعة'), // Replace with API data
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.money, color: AppColors.primaryOrange),
                title: const Text('إجمالي الخصومات'),
                trailing: Text('500 جنيه'), // Replace with API data
              ),
            ),
          ],
        ),
      ),
    );
  }
}
