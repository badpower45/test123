import 'package:flutter/material.dart';
import '../../../models/detailed_attendance_request.dart';
import '../../../services/owner_api_service.dart';
import '../../../theme/app_colors.dart';

class OwnerAttendanceRequestsScreen extends StatefulWidget {
  const OwnerAttendanceRequestsScreen({super.key});

  @override
  State<OwnerAttendanceRequestsScreen> createState() => _OwnerAttendanceRequestsScreenState();
}

class _OwnerAttendanceRequestsScreenState extends State<OwnerAttendanceRequestsScreen> {
  List<DetailedAttendanceRequest> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() { _loading = true; _error = null; });
    try {
      final requests = await OwnerApiService.getPendingAttendanceRequests('OWNER001');
      if (mounted) setState(() { _requests = requests; _loading = false; });
    } catch (error) {
      if (mounted) setState(() { _error = error.toString(); _loading = false; });
    }
  }

  Future<void> _approveRequest(String requestId) async {
    try {
      await OwnerApiService.approveAttendanceRequest(
        requestId: requestId,
        ownerUserId: 'OWNER001',
      );
      if (mounted) {
        setState(() {
          _requests.removeWhere((req) => req.requestId == requestId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت الموافقة على الطلب وتحديث الحضور بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: ${error.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('طلبات الحضور المعلقة'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadRequests,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 56, color: AppColors.error),
                        const SizedBox(height: 16),
                        Text(
                          'حدث خطأ: $_error',
                          style: const TextStyle(color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadRequests,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                : _requests.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox, size: 56, color: AppColors.textTertiary),
                            const SizedBox(height: 16),
                            Text(
                              'لا توجد طلبات حضور معلقة',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'جميع الطلبات تم مراجعتها',
                              style: TextStyle(color: AppColors.textTertiary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _requests.length,
                        itemBuilder: (context, index) {
                          final request = _requests[index];
                          return _AttendanceRequestCard(
                            request: request.toJson(),
                            onApprove: () => _approveRequest(request.requestId),
                          );
                        },
                      ),
      ),
    );
  }
}

class _AttendanceRequestCard extends StatelessWidget {
  const _AttendanceRequestCard({
    required this.request,
    required this.onApprove,
  });

  final Map<String, dynamic> request;
  final VoidCallback onApprove;

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(String dateStr) {
    final date = DateTime.parse(dateStr);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  request['requestType'] == 'check_in' ? Icons.login : Icons.logout,
                  color: AppColors.primaryOrange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request['employeeName'] ?? 'غير محدد',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        request['employeeRole'] ?? 'غير محدد',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('موافقة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'التاريخ: ${_formatDate(request['requestedTime'])}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.access_time, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'الوقت: ${_formatTime(request['requestedTime'])}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'نوع الطلب: ${request['requestType'] == 'check_in' ? 'تصحيح حضور' : 'تصحيح انصراف'}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'السبب: ${request['reason']}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (request['branchName'] != null) ...[
              const SizedBox(height: 4),
              Text(
                'الفرع: ${request['branchName']}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'تاريخ الطلب: ${_formatDate(request['createdAt'])}',
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}