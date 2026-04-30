import 'package:flutter/material.dart';
import '../../models/detailed_leave_request.dart';
import '../../services/manager_api_service.dart';
import '../../services/supabase_attendance_service.dart';
import '../../services/supabase_requests_service.dart';
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

      // ✅ Use Supabase directly instead of broken edge function
      final rawList = await SupabaseRequestsService.getAllLeaveRequestsWithEmployees(
        status: 'pending',
        branchName: branchName,
      );

      setState(() {
        _requests = rawList.map((json) => DetailedLeaveRequest.fromJson(json)).toList();
        _isLoading = false;
      });
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
        const SnackBar(
          content: Text('تمت الموافقة على الطلب بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل الموافقة: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفض طلب الإجازة'),
        content: TextField(
          controller: notesController,
          decoration: const InputDecoration(
            labelText: 'سبب الرفض (اختياري)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('رفض'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ManagerApiService.reviewLeaveRequest(
        requestId: requestId,
        managerId: widget.managerId,
        approve: false,
        notes: notesController.text.trim().isEmpty ? 'تم رفض الطلب' : notesController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم رفض الطلب'),
          backgroundColor: AppColors.error,
        ),
      );
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل الرفض: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 56, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadRequests,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (_requests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 56, color: AppColors.textTertiary),
            SizedBox(height: 12),
            Text(
              'لا توجد طلبات إجازة معلقة',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length,
        itemBuilder: (context, index) {
          final request = _requests[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.primaryOrange,
                        child: Icon(Icons.person, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request.employeeName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (request.branchName != null)
                              Text(
                                request.branchName!,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'معلق',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        '${_formatDate(request.startDate)} - ${_formatDate(request.endDate)}',
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${request.daysCount} يوم',
                          style: const TextStyle(
                            color: AppColors.primaryOrange,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (request.reason != null && request.reason!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.note, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            request.reason!,
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => _rejectRequest(request.requestId),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('رفض'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _approveRequest(request.requestId),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
