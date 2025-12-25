import 'package:flutter/material.dart';
import '../../../models/detailed_attendance_request.dart';
import '../../../services/supabase_requests_service.dart';
import '../../../theme/app_colors.dart';

class OwnerAttendanceRequestsScreen extends StatefulWidget {
  const OwnerAttendanceRequestsScreen({super.key, required this.ownerId});

  final String ownerId;

  @override
  State<OwnerAttendanceRequestsScreen> createState() => _OwnerAttendanceRequestsScreenState();
}

class _OwnerAttendanceRequestsScreenState extends State<OwnerAttendanceRequestsScreen> {
  List<DetailedAttendanceRequest> _requests = [];
  bool _loading = true;
  String? _error;
  String _filterStatus = 'pending'; // pending, approved, rejected, all

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() { _loading = true; _error = null; });
    try {
      final requestsData = await SupabaseRequestsService.getAllAttendanceRequestsWithEmployees(
        status: _filterStatus == 'all' ? null : _filterStatus,
      );
      
      final requests = requestsData.map((data) => DetailedAttendanceRequest.fromJson(data)).toList();
      
      if (mounted) setState(() { _requests = requests; _loading = false; });
    } catch (error) {
      if (mounted) setState(() { _error = error.toString(); _loading = false; });
    }
  }

  Future<void> _approveRequest(String requestId) async {
    try {
      final success = await SupabaseRequestsService.reviewAttendanceRequest(
        requestId: requestId,
        reviewedBy: widget.ownerId,
        status: 'approved',
      );
      
      if (!success) {
        throw Exception('فشل في الموافقة على الطلب');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تمت الموافقة على الطلب'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadRequests();
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

  Future<void> _rejectRequest(String requestId) async {
    final reason = await _showRejectionDialog();
    if (reason == null || reason.isEmpty) return;

    try {
      final success = await SupabaseRequestsService.reviewAttendanceRequest(
        requestId: requestId,
        reviewedBy: widget.ownerId,
        status: 'rejected',
        reviewNotes: reason,
      );
      
      if (!success) {
        throw Exception('فشل في رفض الطلب');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تم رفض الطلب'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadRequests();
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

  Future<String?> _showRejectionDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('سبب الرفض'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'اكتب سبب رفض الطلب...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
            child: const Text('رفض'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('طلبات الحضور'),
        centerTitle: true,
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Filter dropdown
          PopupMenuButton<String>(
            initialValue: _filterStatus,
            onSelected: (value) {
              setState(() => _filterStatus = value);
              _loadRequests();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'pending', child: Text('المعلقة')),
              const PopupMenuItem(value: 'approved', child: Text('الموافق عليها')),
              const PopupMenuItem(value: 'rejected', child: Text('المرفوضة')),
              const PopupMenuItem(value: 'all', child: Text('الكل')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
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
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '-';
    }
  }

  String _formatTime(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '-';
    }
  }

  String _formatFullDateTime(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year} - ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCheckIn = request['requestType'] == 'check-in' || request['requestType'] == 'check_in';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with employee info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (isCheckIn ? AppColors.success : AppColors.error).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isCheckIn ? AppColors.success : AppColors.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isCheckIn ? Icons.login : Icons.logout,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request['employeeName'] ?? 'غير محدد',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.work_outline, size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              request['employeeRole'] ?? 'موظف',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isCheckIn ? AppColors.success : AppColors.error,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isCheckIn ? 'تصحيح حضور' : 'تصحيح انصراف',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Request details in cards
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primaryOrange.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primaryOrange.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  _DetailRow(
                    icon: Icons.event,
                    label: 'التاريخ المطلوب',
                    value: _formatDate(request['requestedTime']),
                    color: AppColors.primaryOrange,
                  ),
                  const Divider(height: 20),
                  _DetailRow(
                    icon: Icons.access_time,
                    label: 'الوقت المطلوب',
                    value: _formatTime(request['requestedTime']),
                    color: AppColors.info,
                  ),
                ],
              ),
            ),

            // Branch info if available
            if (request['branchName'] != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.info.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.business, size: 16, color: AppColors.info),
                    const SizedBox(width: 8),
                    Text(
                      'الفرع: ${request['branchName']}',
                      style: const TextStyle(
                        color: AppColors.info,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Reason section
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.textTertiary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.description, size: 16, color: AppColors.textSecondary),
                      SizedBox(width: 6),
                      Text(
                        'سبب الطلب:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    request['reason'] ?? 'لا يوجد',
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            // Created date
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.schedule, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  'تاريخ إرسال الطلب: ${_formatFullDateTime(request['createdAt'])}',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Approve button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onApprove,
                icon: const Icon(Icons.check_circle, size: 22),
                label: const Text(
                  'موافقة وتحديث الحضور',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Helper widget for detail rows
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}