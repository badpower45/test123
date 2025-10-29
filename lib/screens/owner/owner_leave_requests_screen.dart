import 'package:flutter/material.dart';

import '../../models/detailed_leave_request.dart';
import '../../services/owner_api_service.dart';
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
  late Future<List<DetailedLeaveRequest>> _requestsFuture;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  void _loadRequests() {
    setState(() {
      _requestsFuture = OwnerApiService.getPendingLeaveRequests(widget.ownerId);
    });
  }

  Future<void> _approveRequest(String requestId) async {
    try {
      await OwnerApiService.approveLeaveRequest(
        leaveRequestId: requestId,
        ownerUserId: widget.ownerId,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تمت الموافقة على الطلب وتسجيل الإجازة'),
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
    if (reason == null) return;

    try {
      await OwnerApiService.rejectLeaveRequest(
        leaveRequestId: requestId,
        ownerUserId: widget.ownerId,
        reason: reason,
      );
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
        title: const Text('طلبات الإجازات المعلقة'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<DetailedLeaveRequest>>(
        future: _requestsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 56, color: AppColors.error),
                  const SizedBox(height: 16),
                  Text(
                    'خطأ: ${snapshot.error}',
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
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 56, color: AppColors.textTertiary),
                  SizedBox(height: 16),
                  Text(
                    'لا توجد طلبات معلقة',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          final requests = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _loadRequests(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              itemBuilder: (context, index) {
                return _DetailedLeaveRequestCard(
                  request: requests[index],
                  onApproved: () => _approveRequest(requests[index].requestId),
                  onRejected: () => _rejectRequest(requests[index].requestId),
                );
              },
            ),
          );
        },
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Employee name and branch
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    request.employeeName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  request.branchName ?? 'بدون فرع',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
            if (request.employeeRole.isNotEmpty)
              Text(
                'الرتبة: ${request.employeeRole}',
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
              ),
            if (request.employeeSalary != null)
              Text(
                'الراتب: ${request.employeeSalary} جنيه',
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
              ),

            const Divider(height: 24),

            // Leave details
            _LeaveInfoRow(label: 'من', value: _formatDate(request.startDate)),
            _LeaveInfoRow(label: 'إلى', value: _formatDate(request.endDate)),
            if (request.reason != null && request.reason!.isNotEmpty)
              _LeaveInfoRow(label: 'السبب', value: request.reason!),
            if (request.daysCount > 0)
              _LeaveInfoRow(label: 'عدد الأيام', value: request.daysCount.toString()),
            if (request.allowanceAmount > 0)
              _LeaveInfoRow(
                label: 'بدل الإجازة',
                value: '${request.allowanceAmount.toStringAsFixed(0)} جنيه',
              ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: onRejected,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('رفض'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onApproved,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('موافقة'),
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
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _LeaveInfoRow extends StatelessWidget {
  const _LeaveInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}