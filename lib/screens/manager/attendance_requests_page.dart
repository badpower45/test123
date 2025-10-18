import 'package:flutter/material.dart';
import '../../services/attendance_api_service.dart';
import '../../theme/app_colors.dart';

class AttendanceRequestsPage extends StatefulWidget {
  final String managerId;
  final String branch;

  const AttendanceRequestsPage({Key? key, required this.managerId, required this.branch}) : super(key: key);

  @override
  State<AttendanceRequestsPage> createState() => _AttendanceRequestsPageState();
}

class _AttendanceRequestsPageState extends State<AttendanceRequestsPage> {
  late Future<List<Map<String, dynamic>>> _attendanceRequests;

  @override
  void initState() {
    super.initState();
    _attendanceRequests = _fetchAttendanceRequests();
  }

  Future<List<Map<String, dynamic>>> _fetchAttendanceRequests() async {
    // Replace with actual API call for attendance requests for manager's branch
    // Example: AttendanceApiService.fetchAttendanceRequestsForManager
    return [];
  }

  void _reviewRequest(Map<String, dynamic> request, String action) async {
    // Call API to approve/reject request
    // Example: AttendanceApiService.reviewAttendanceRequest(request['id'], action)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم $action الطلب بنجاح')),
    );
    setState(() {
      _attendanceRequests = _fetchAttendanceRequests();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلبات الحضور والانصراف')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _attendanceRequests,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('خطأ: ${snapshot.error}'));
          }
          final requests = snapshot.data ?? [];
          if (requests.isEmpty) {
            return const Center(child: Text('لا توجد طلبات حضور أو انصراف')); 
          }
          return ListView.builder(
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: const Icon(Icons.event_note, color: AppColors.primaryOrange),
                  title: Text(request['employee_name'] ?? 'موظف'),
                  subtitle: Text('السبب: ${request['reason'] ?? ''}\nالتاريخ: ${request['date'] ?? ''}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check, color: AppColors.success),
                        onPressed: () => _reviewRequest(request, 'الموافقة'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.error),
                        onPressed: () => _reviewRequest(request, 'الرفض'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
