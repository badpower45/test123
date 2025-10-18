import 'package:flutter/material.dart';
import '../../services/attendance_api_service.dart';
import '../../models/attendance_report.dart';
import '../../theme/app_colors.dart';

class AttendancePage extends StatefulWidget {
  final String managerId;
  final String branch;

  const AttendancePage({Key? key, required this.managerId, required this.branch}) : super(key: key);

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  late Future<List<Map<String, dynamic>>> _attendanceRecords;

  @override
  void initState() {
    super.initState();
    _attendanceRecords = _fetchAttendanceRecords();
  }

  Future<List<Map<String, dynamic>>> _fetchAttendanceRecords() async {
    // Replace with actual API call for manager's branch
    final report = await AttendanceApiService.fetchAttendanceReport(
      employeeId: widget.managerId,
      startDate: DateTime.now().subtract(const Duration(days: 30)),
      endDate: DateTime.now(),
    );
    return report.attendance;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجلات الحضور والغياب')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _attendanceRecords,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('خطأ: ${snapshot.error}'));
          }
          final records = snapshot.data ?? [];
          if (records.isEmpty) {
            return const Center(child: Text('لا توجد سجلات حضور أو غياب')); 
          }
          return ListView.builder(
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: Icon(
                    record['status'] == 'checked_in' ? Icons.login : Icons.logout,
                    color: record['status'] == 'checked_in' ? AppColors.success : AppColors.error,
                  ),
                  title: Text(record['employee_name'] ?? 'موظف'),
                  subtitle: Text('التاريخ: ${record['date'] ?? ''}\nالحالة: ${record['status'] ?? ''}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
