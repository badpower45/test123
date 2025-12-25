import 'package:flutter/material.dart';
import '../../models/detailed_leave_request.dart';
import '../../services/manager_api_service.dart';
import '../../services/supabase_attendance_service.dart';
import '../../services/branch_manager_api_service.dart';
import '../../theme/app_colors.dart';

class ManagerLeaveRequestsTab extends StatefulWidget {
  const ManagerLeaveRequestsTab({
    super.key,
    required this.managerId,
  });

  final String managerId;

  @override
  State<ManagerLeaveRequestsTab> createState() => _ManagerLeaveRequestsTabState();
}

class _ManagerLeaveRequestsTabState extends State<ManagerLeaveRequestsTab> {
  List<DetailedLeaveRequest> _requests = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get manager's branch name first
      final employeeStatus = await SupabaseAttendanceService.getEmployeeStatus(widget.managerId);
      final employeeData = employeeStatus['employee'];

      String? branchName;
      if (employeeData is Map<String, dynamic>) {
        branchName = employeeData['branch'] as String?;
        if (branchName == null || branchName.isEmpty) {
          final branchInfo = employeeData['branches'];
          if (branchInfo is Map<String, dynamic>) {
            branchName = branchInfo['name'] as String?;
          }
        }
      }

      if (branchName == null || branchName.toString().isEmpty) {
        throw Exception('المدير غير مرتبط بفرع');
      }
      
      // Use Supabase Edge Function to get branch requests
      final requestsData = await BranchManagerApiService.getBranchRequests(branchName);
      
      if (requestsData['success'] == true) {
        final leaveRequests = requestsData['leaveRequests'] as List? ?? [];
        setState(() {
          _requests = leaveRequests
              .map((json) => DetailedLeaveRequest.fromJson(json))
              .toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _requests = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading leave requests: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _approveRequest(String requestId) async {
    try {
      await ManagerApiService.reviewLeaveRequest(
        requestId: requestId,
        managerId: widget.managerId,
        approve: true,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت الموافقة على الطلب بنجاح'), backgroundColor: AppColors.success),
      );
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الموافقة: ${e.toString()}'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    try {
      await ManagerApiService.reviewLeaveRequest(
        requestId: requestId,
        managerId: widget.managerId,
        approve: false,
        notes: 'تم رفض الطلب',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض الطلب'), backgroundColor: AppColors.error),
      );
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الرفض: ${e.toString()}'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('خطأ: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadRequests,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (_requests.isEmpty) {
      return const Center(
        child: Text('لا توجد طلبات إجازة معلقة'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final request = _requests[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      request.employeeId,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 16),
                    const SizedBox(width: 8),
                    Text('${request.startDate} - ${request.endDate}'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.event_available, size: 16),
                    const SizedBox(width: 8),
                    Text('${request.daysCount} يوم'),
                  ],
                ),
                if (request.reason != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.note, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(request.reason!)),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _rejectRequest(request.requestId),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      child: const Text('رفض'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _approveRequest(request.requestId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                      ),
                      child: const Text('موافقة'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
