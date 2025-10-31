import 'package:flutter/material.dart';

import '../../../models/leave_request.dart';
import '../../../services/requests_api_service.dart';
import '../../../theme/app_colors.dart';

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
  List<LeaveRequest> _requests = <LeaveRequest>[];
  bool _loading = true;
  bool _deleting = false;
  String? _error;

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
      final requests = await RequestsApiService.fetchLeaveRequests(widget.managerId);
      if (!mounted) {
        return;
      }
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openNewRequestSheet() async {
    final request = await showModalBottomSheet<LeaveRequest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LeaveRequestSheet(managerId: widget.managerId),
    );

    if (request != null && mounted) {
      setState(() {
        _requests = <LeaveRequest>[request, ..._requests];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم إرسال طلب الإجازة بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _deleteRejectedRequests() async {
    setState(() => _deleting = true);
    try {
      await RequestsApiService.deleteRejectedLeaves(widget.managerId);
      await _loadRequests();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف الطلبات المرفوضة'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر الحذف: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRejected = _requests.any((r) => r.isRejected);

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ElevatedButton.icon(
            onPressed: _openNewRequestSheet,
            icon: const Icon(Icons.add),
            label: const Text('طلب إجازة جديد'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (hasRejected) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _deleting ? null : _deleteRejectedRequests,
              icon: _deleting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_forever),
              label: const Text('حذف الطلبات المرفوضة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'الطلبات السابقة',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            _LeaveRequestsErrorState(onRetry: _loadRequests, error: _error!)
          else if (_requests.isEmpty)
            const _LeaveRequestsEmptyState()
          else ...[
            for (final request in _requests) _LeaveRequestCard(request: request),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _LeaveRequestCard extends StatelessWidget {
  const _LeaveRequestCard({required this.request});

  final LeaveRequest request;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(request);
    final statusText = _statusText(request);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.beach_access, color: statusColor),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  _formatDate(request.createdAt),
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _LeaveInfoRow(label: 'من', value: _formatDate(request.startDate)),
            _LeaveInfoRow(label: 'إلى', value: _formatDate(request.endDate)),
            if (request.daysCount > 0)
              _LeaveInfoRow(label: 'عدد الأيام', value: request.daysCount.toString()),
            if (request.allowanceAmount > 0)
              _LeaveInfoRow(
                label: 'بدل الإجازة',
                value: '${request.allowanceAmount.toStringAsFixed(0)} جنيه',
              ),
            if (request.reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'السبب: ${request.reason}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            if (request.rejectionReason != null && request.rejectionReason!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'ملاحظة: ${request.rejectionReason}',
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(LeaveRequest request) {
    if (request.isApproved) {
      return AppColors.success;
    }
    if (request.isRejected) {
      return AppColors.error;
    }
  return AppColors.statusPending;
  }

  String _statusText(LeaveRequest request) {
    if (request.isApproved) {
      return 'موافق عليها';
    }
    if (request.isRejected) {
      return 'مرفوضة';
    }
    return 'قيد المراجعة';
  }

  String _formatDate(DateTime date) => '${date.year}-${_twoDigits(date.month)}-${_twoDigits(date.day)}';

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
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
          Text(
            value,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _LeaveRequestsEmptyState extends StatelessWidget {
  const _LeaveRequestsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.inbox, size: 56, color: AppColors.textTertiary),
          SizedBox(height: 12),
          Text(
            'لا توجد طلبات بعد',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.textSecondary),
          ),
          SizedBox(height: 8),
          Text(
            'ابدأ بإرسال أول طلب إجازة الآن',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _LeaveRequestsErrorState extends StatelessWidget {
  const _LeaveRequestsErrorState({required this.onRetry, required this.error});

  final Future<void> Function() onRetry;
  final String error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 56, color: AppColors.error),
          const SizedBox(height: 12),
          Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

class _LeaveRequestSheet extends StatefulWidget {
  const _LeaveRequestSheet({required this.managerId});

  final String managerId;

  @override
  State<_LeaveRequestSheet> createState() => _LeaveRequestSheetState();
}

class _LeaveRequestSheetState extends State<_LeaveRequestSheet> {
  LeaveType _selectedType = LeaveType.normal;
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primaryOrange),
        ),
        child: child!,
      ),
    );
    if (result != null) {
      setState(() {
        _startDate = result;
        if (_endDate != null && _endDate!.isBefore(result)) {
          _endDate = result;
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    final base = _startDate ?? DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: _endDate ?? base,
      firstDate: base,
      lastDate: base.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primaryOrange),
        ),
        child: child!,
      ),
    );
    if (result != null) {
      setState(() => _endDate = result);
    }
  }

  Future<void> _submit() async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار تاريخ البداية والنهاية'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final reason = _reasonController.text.trim();
    if (_selectedType == LeaveType.emergency && reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('السبب مطلوب للإجازة الطارئة'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final request = await RequestsApiService.submitLeaveRequest(
        employeeId: widget.managerId,
        startDate: _startDate!,
        endDate: _endDate!,
        reason: reason.isEmpty ? null : reason,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(request);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر إرسال الطلب: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: bottomPadding + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'طلب إجازة جديد',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'نوع الإجازة',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _LeaveTypeCard(
                    type: LeaveType.normal,
                    isSelected: _selectedType == LeaveType.normal,
                    title: 'إجازة عادية',
                    subtitle: 'يُفضل طلبها قبل 48 ساعة',
                    icon: Icons.event_available,
                    onTap: () => setState(() => _selectedType = LeaveType.normal),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LeaveTypeCard(
                    type: LeaveType.emergency,
                    isSelected: _selectedType == LeaveType.emergency,
                    title: 'إجازة طارئة',
                    subtitle: 'يمكن طلبها قبل 24 ساعة',
                    icon: Icons.warning,
                    onTap: () => setState(() => _selectedType = LeaveType.emergency),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _selectStartDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _startDate == null
                    ? 'تاريخ البداية'
                    : _formatDate(_startDate!),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryOrange,
                side: const BorderSide(color: AppColors.primaryOrange),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: (_startDate == null || _isSubmitting) ? null : _selectEndDate,
              icon: const Icon(Icons.calendar_month),
              label: Text(
                _endDate == null
                    ? 'تاريخ النهاية'
                    : _formatDate(_endDate!),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryOrange,
                side: const BorderSide(color: AppColors.primaryOrange),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _selectedType == LeaveType.emergency
                    ? 'السبب (إلزامي)' : 'السبب (اختياري)',
                hintText: 'اكتب سبب طلب الإجازة... ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primaryOrange, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'إرسال الطلب',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _LeaveTypeCard extends StatelessWidget {
  const _LeaveTypeCard({
    required this.type,
    required this.isSelected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final LeaveType type;
  final bool isSelected;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryOrange.withOpacity(0.08) : Colors.white,
          border: Border.all(
            color: isSelected ? AppColors.primaryOrange : AppColors.surfaceVariant,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon,
                color: isSelected ? AppColors.primaryOrange : AppColors.textTertiary, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? AppColors.primaryOrange : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
