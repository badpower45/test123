import 'package:flutter/material.dart';
import '../../services/supabase_requests_service.dart';
import '../../theme/app_colors.dart';

class OwnerSalaryAdvanceScreen extends StatefulWidget {
  const OwnerSalaryAdvanceScreen({super.key, required this.ownerId});

  final String ownerId;

  @override
  State<OwnerSalaryAdvanceScreen> createState() => _OwnerSalaryAdvanceScreenState();
}

class _OwnerSalaryAdvanceScreenState extends State<OwnerSalaryAdvanceScreen> {
  List<Map<String, dynamic>> _requests = [];
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
      final requestsData = await SupabaseRequestsService.getAllSalaryAdvanceRequestsWithEmployees(
        status: _filterStatus == 'all' ? null : _filterStatus,
      );

      if (!mounted) return;
      setState(() {
        _requests = requestsData;
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
      final success = await SupabaseRequestsService.reviewSalaryAdvanceRequest(
        requestId: requestId,
        approvedBy: widget.ownerId,
        status: 'approved',
      );

      if (!success) {
        throw Exception('فشل في الموافقة على الطلب');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تمت الموافقة على طلب السلفة'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadRequests();
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
      final success = await SupabaseRequestsService.reviewSalaryAdvanceRequest(
        requestId: requestId,
        approvedBy: widget.ownerId,
        status: 'rejected',
        notes: reason,
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
      _loadRequests();
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
        title: const Text('طلبات السلف'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
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
                          final request = _requests[index];
                          final employeeData = request['employees'] as Map<String, dynamic>?;
                          final employeeName = employeeData?['full_name'] ?? 'غير معروف';
                          final employeeBranch = employeeData?['branch'] ?? '';
                          final monthlySalary = (employeeData?['monthly_salary'] as num?)?.toDouble() ?? 0;
                          final amount = (request['amount'] as num?)?.toDouble() ?? 0;
                          final reason = request['reason'] ?? '';
                          final status = request['status'] ?? 'pending';
                          final createdAt = DateTime.parse(request['created_at'] as String);
                          final requestId = request['id'] as String;

                          final percentage = (monthlySalary > 0 ? (amount / monthlySalary * 100) : 0).toDouble();

                          return _AdvanceRequestCard(
                            employeeName: employeeName,
                            employeeBranch: employeeBranch,
                            monthlySalary: monthlySalary,
                            amount: amount,
                            percentage: percentage,
                            reason: reason,
                            status: status,
                            createdAt: createdAt,
                            onApprove: status == 'pending' ? () => _approveRequest(requestId) : null,
                            onReject: status == 'pending' ? () => _rejectRequest(requestId) : null,
                          );
                        },
                      ),
                    ),
    );
  }
}

class _AdvanceRequestCard extends StatelessWidget {
  final String employeeName;
  final String employeeBranch;
  final double monthlySalary;
  final double amount;
  final double percentage;
  final String reason;
  final String status;
  final DateTime createdAt;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _AdvanceRequestCard({
    required this.employeeName,
    required this.employeeBranch,
    required this.monthlySalary,
    required this.amount,
    required this.percentage,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.onApprove,
    this.onReject,
  });

  Color get _statusColor {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  String get _statusText {
    switch (status) {
      case 'approved':
        return 'موافق عليها';
      case 'rejected':
        return 'مرفوضة';
      default:
        return 'معلقة';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Employee & Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employeeName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        employeeBranch,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.1),
                    border: Border.all(color: _statusColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusText,
                    style: TextStyle(
                      color: _statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Amount & Salary Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _InfoColumn(
                  label: 'المبلغ المطلوب',
                  value: '${amount.toStringAsFixed(0)} ج.م',
                  valueColor: AppColors.primaryOrange,
                ),
                _InfoColumn(
                  label: 'المرتب الشهري',
                  value: '${monthlySalary.toStringAsFixed(0)} ج.م',
                ),
                _InfoColumn(
                  label: 'النسبة',
                  value: '${percentage.toStringAsFixed(1)}%',
                  valueColor: percentage > 30 ? AppColors.error : AppColors.success,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Reason
            if (reason.isNotEmpty) ...[
              const Text(
                'السبب:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                reason,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Date
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${createdAt.day}/${createdAt.month}/${createdAt.year} - ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),

            // Action Buttons
            if (onApprove != null || onReject != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (onReject != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onReject,
                        icon: const Icon(Icons.close),
                        label: const Text('رفض'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  if (onReject != null && onApprove != null) const SizedBox(width: 12),
                  if (onApprove != null)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onApprove,
                        icon: const Icon(Icons.check),
                        label: const Text('موافقة'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoColumn({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
