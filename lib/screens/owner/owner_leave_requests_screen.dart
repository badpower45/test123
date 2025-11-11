import 'package:flutter/material.dart';

import '../../models/detailed_leave_request.dart';
import '../../services/supabase_requests_service.dart';
import '../../theme/app_colors.dart';

class OwnerLeaveRequestsScreen extends StatefulWidget {
  const OwnerLeaveRequestsScreen({
    super.key,
    required this.ownerId,
  });

  final String ownerId;

  @override
  State<OwnerLeaveRequestsScreen> createState() => _OwnerLeaveRequestsScreenState();
}

class _OwnerLeaveRequestsScreenState extends State<OwnerLeaveRequestsScreen> {
  List<DetailedLeaveRequest> _requests = [];
  bool _loading = true;
  String? _error;
  String _filterStatus = 'pending'; // pending, approved, rejected, all

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final requestsData = await SupabaseRequestsService.getAllLeaveRequestsWithEmployees(
        status: _filterStatus == 'all' ? null : _filterStatus,
      );

      final requests = requestsData.map((data) => DetailedLeaveRequest.fromJson(data)).toList();

      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _approveRequest(String requestId) async {
    try {
      final success = await SupabaseRequestsService.reviewLeaveRequest(
        requestId: requestId,
        reviewedBy: widget.ownerId,
        status: 'approved',
      );

      if (!success) {
        throw Exception('فشل في الموافقة على الطلب');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تمت الموافقة على الطلب'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadRequests(); // Refresh the list
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في الموافقة: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    final reason = await _showRejectionReasonDialog();
    if (reason == null || reason.isEmpty) return;

    try {
      final success = await SupabaseRequestsService.reviewLeaveRequest(
        requestId: requestId,
        reviewedBy: widget.ownerId,
        status: 'rejected',
        reviewNotes: reason,
      );

      if (!success) {
        throw Exception('فشل في رفض الطلب');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم رفض الطلب'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadRequests(); // Refresh the list
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في الرفض: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<String?> _showRejectionReasonDialog() async {
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
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
            ),
            child: const Text('رفض'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات الإجازات'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 56, color: AppColors.error),
                      const SizedBox(height: 16),
                      Text(
                        'خطأ: $_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadRequests,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryOrange,
                        ),
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : _requests.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, size: 56, color: AppColors.textTertiary),
                          SizedBox(height: 16),
                          Text(
                            'لا توجد طلبات',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => _loadRequests(),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _requests.length,
                        itemBuilder: (context, index) {
                          return _DetailedLeaveRequestCard(
                            request: _requests[index],
                            onApproved: () => _approveRequest(_requests[index].requestId),
                            onRejected: () => _rejectRequest(_requests[index].requestId),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _DetailedLeaveRequestCard extends StatelessWidget {
  const _DetailedLeaveRequestCard({
    required this.request,
    required this.onApproved,
    required this.onRejected,
  });

  final DetailedLeaveRequest request;
  final VoidCallback onApproved;
  final VoidCallback onRejected;

  @override
  Widget build(BuildContext context) {
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
                color: AppColors.primaryOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryOrange,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.person,
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
                              request.employeeName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.work_outline, size: 14, color: AppColors.textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  request.employeeRole.isNotEmpty ? request.employeeRole : 'موظف',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoChip(
                          icon: Icons.business,
                          label: request.branchName ?? 'بدون فرع',
                          color: AppColors.info,
                        ),
                      ),
                      if (request.employeeSalary != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: _InfoChip(
                            icon: Icons.payments,
                            label: '${request.employeeSalary} جنيه',
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Leave type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: request.type.toString().contains('emergency')
                    ? AppColors.error.withOpacity(0.1)
                    : AppColors.info.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: request.type.toString().contains('emergency')
                      ? AppColors.error
                      : AppColors.info,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    request.type.toString().contains('emergency')
                        ? Icons.warning_amber
                        : Icons.event_available,
                    size: 16,
                    color: request.type.toString().contains('emergency')
                        ? AppColors.error
                        : AppColors.info,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    request.type.toString().contains('emergency') ? 'إجازة طارئة' : 'إجازة عادية',
                    style: TextStyle(
                      color: request.type.toString().contains('emergency')
                          ? AppColors.error
                          : AppColors.info,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Leave details in cards
            Row(
              children: [
                Expanded(
                  child: _DetailCard(
                    icon: Icons.calendar_today,
                    title: 'من',
                    value: _formatDate(request.startDate),
                    color: AppColors.primaryOrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DetailCard(
                    icon: Icons.event,
                    title: 'إلى',
                    value: _formatDate(request.endDate),
                    color: AppColors.primaryOrange,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _DetailCard(
                    icon: Icons.access_time,
                    title: 'عدد الأيام',
                    value: '${request.daysCount} يوم',
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DetailCard(
                    icon: Icons.attach_money,
                    title: 'بدل الإجازة',
                    value: '${request.allowanceAmount.toStringAsFixed(0)} جنيه',
                    color: AppColors.success,
                  ),
                ),
              ],
            ),

            // Reason section
            if (request.reason != null && request.reason!.isNotEmpty) ...[
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
                          'السبب:',
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
                      request.reason!,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Created date
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.schedule, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  'تاريخ الطلب: ${_formatDateTime(request.createdAt)}',
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

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onRejected,
                    icon: const Icon(Icons.close, size: 20),
                    label: const Text('رفض الطلب', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onApproved,
                    icon: const Icon(Icons.check, size: 20),
                    label: const Text('موافقة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';

  String _formatDateTime(DateTime date) =>
      '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

// Helper widget for info chips
class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// Helper widget for detail cards
class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  color: color.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}