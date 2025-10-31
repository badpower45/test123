import 'package:flutter/material.dart';

import '../../../models/advance_request.dart';
import '../../../services/requests_api_service.dart';
import '../../../theme/app_colors.dart';

class ManagerAdvanceRequestsTab extends StatefulWidget {
  const ManagerAdvanceRequestsTab({
    super.key,
    required this.managerId,
  });

  final String managerId;

  @override
  State<ManagerAdvanceRequestsTab> createState() => _ManagerAdvanceRequestsTabState();
}

class _ManagerAdvanceRequestsTabState extends State<ManagerAdvanceRequestsTab> {
  List<AdvanceRequest> _requests = <AdvanceRequest>[];
  bool _loading = true;
  bool _deleting = false;
  String? _error;
  double? _currentEarnings;
  double? _maxAdvance;

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _loadCurrentEarnings();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final requests = await RequestsApiService.fetchAdvanceRequests(widget.managerId);
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

  Future<void> _loadCurrentEarnings() async {
    try {
      final response = await RequestsApiService.fetchCurrentEarnings(widget.managerId);
      if (!mounted) {
        return;
      }

      final earnings = (response['currentEarnings'] ??
              response['current_earnings'] ??
              response['salary'])
          as num?;
      final maxAdvance = (response['maxAdvance'] ?? response['max_advance']) as num?;
      setState(() {
        _currentEarnings = earnings?.toDouble();
        _maxAdvance =
            maxAdvance?.toDouble() ?? (_currentEarnings != null ? _currentEarnings! * 0.3 : null);
      });
    } catch (_) {
      // Earnings information is optional; ignore failures silently.
    }
  }

  Future<void> _openAdvanceRequestSheet() async {
    final request = await showModalBottomSheet<AdvanceRequest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AdvanceRequestSheet(
        managerId: widget.managerId,
        currentEarnings: _currentEarnings,
        maxAdvance: _maxAdvance,
      ),
    );

    if (request != null && mounted) {
      setState(() {
        _requests = <AdvanceRequest>[request, ..._requests];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم إرسال طلب السلفة بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _deleteRejectedRequests() async {
    setState(() => _deleting = true);
    try {
      await RequestsApiService.deleteRejectedAdvances(widget.managerId);
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
    final hasRejected = _requests.any((request) => request.isRejected);

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ElevatedButton.icon(
            onPressed: _openAdvanceRequestSheet,
            icon: const Icon(Icons.add),
            label: const Text('طلب سلفة جديد'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (_maxAdvance != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'الحد الأقصى للسلفة المتاحة',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_maxAdvance!.toStringAsFixed(0)} جنيه',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryOrange,
                    ),
                  ),
                  if (_currentEarnings != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'دخل الشهر الحالي: ${_currentEarnings!.toStringAsFixed(0)} جنيه',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          if (_maxAdvance != null) const SizedBox(height: 24),
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
            _AdvanceErrorState(onRetry: _loadRequests, error: _error!)
          else if (_requests.isEmpty)
            const _AdvanceEmptyState()
          else ...[
            for (final request in _requests) _AdvanceRequestCard(request: request),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _AdvanceRequestCard extends StatelessWidget {
  const _AdvanceRequestCard({required this.request});

  final AdvanceRequest request;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(request);
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
                const Text(
                  'طلب سلفة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    border: Border.all(color: color),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'المبلغ: ${request.amount.toStringAsFixed(2)} جنيه',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryOrange,
              ),
            ),
            if (request.eligibleAmount != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'الحد المتاح: ${request.eligibleAmount!.toStringAsFixed(0)} جنيه',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'تاريخ الطلب: ${_formatDate(request.createdAt)}',
              style: const TextStyle(color: AppColors.textTertiary),
            ),
            if (request.rejectionReason != null && request.rejectionReason!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'سبب الرفض: ${request.rejectionReason}',
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(AdvanceRequest request) {
    if (request.isApproved) {
      return AppColors.success;
    }
    if (request.isRejected) {
      return AppColors.error;
    }
    return AppColors.statusPending;
  }

  String _statusText(AdvanceRequest request) {
    if (request.isApproved) {
      return 'موافق عليها';
    }
    if (request.isRejected) {
      return 'مرفوضة';
    }
    return 'قيد المراجعة';
  }

  String _formatDate(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class _AdvanceEmptyState extends StatelessWidget {
  const _AdvanceEmptyState();

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
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'سيتم عرض طلبات السلف هنا فور إرسالها',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _AdvanceErrorState extends StatelessWidget {
  const _AdvanceErrorState({required this.onRetry, required this.error});

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

class _AdvanceRequestSheet extends StatefulWidget {
  const _AdvanceRequestSheet({
    required this.managerId,
    this.currentEarnings,
    this.maxAdvance,
  });

  final String managerId;
  final double? currentEarnings;
  final double? maxAdvance;

  @override
  State<_AdvanceRequestSheet> createState() => _AdvanceRequestSheetState();
}

class _AdvanceRequestSheetState extends State<_AdvanceRequestSheet> {
  final TextEditingController _amountController = TextEditingController();
  bool _isSubmitting = false;
  late final double? _allowedMax;

  @override
  void initState() {
    super.initState();
    _allowedMax =
        widget.maxAdvance ?? (widget.currentEarnings != null ? widget.currentEarnings! * 0.3 : null);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال مبلغ صالح'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final maxAllowed = _allowedMax;
    if (maxAllowed != null && amount > maxAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('الحد الأقصى للسلفة هو ${maxAllowed.toStringAsFixed(0)} جنيه'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final request = await RequestsApiService.submitAdvanceRequest(
        employeeId: widget.managerId,
        amount: amount,
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
    final maxAllowed = _allowedMax;
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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'طلب سلفة جديد',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            if (widget.currentEarnings != null)
              _InfoRow(
                label: 'دخل الشهر الحالي',
                value: '${widget.currentEarnings!.toStringAsFixed(0)} جنيه',
              ),
            if (maxAllowed != null) ...[
              const SizedBox(height: 12),
              _InfoRow(
                label: 'الحد الأقصى المتاح',
                value: '${maxAllowed.toStringAsFixed(0)} جنيه',
              ),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'مبلغ السلفة',
                hintText: 'مثال: 750',
                suffixText: 'جنيه',
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
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
