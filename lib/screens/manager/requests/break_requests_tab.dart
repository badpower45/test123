import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/break.dart';
import '../../../models/shift_status.dart';
import '../../../services/requests_api_service.dart';
import '../../../theme/app_colors.dart';

class ManagerBreakRequestsTab extends StatefulWidget {
  const ManagerBreakRequestsTab({
    super.key,
    required this.managerId,
    this.shiftStatus,
    this.onShiftStatusChanged,
    this.isShiftStatusLoading = false,
  });

  final String managerId;
  final ShiftStatus? shiftStatus;
  final Future<void> Function()? onShiftStatusChanged;
  final bool isShiftStatusLoading;

  @override
  State<ManagerBreakRequestsTab> createState() => _ManagerBreakRequestsTabState();
}

class _ManagerBreakRequestsTabState extends State<ManagerBreakRequestsTab> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  List<Break> _breaks = <Break>[];
  String? _actioningBreakId;
  Timer? _ticker;
  ShiftStatus? _currentShiftStatus;
  bool _submittingDelete = false;
  bool _isShiftActive = false;
  bool _isLoadingStatus = true;

  @override
  void initState() {
    super.initState();
    _currentShiftStatus = widget.shiftStatus;
    _startTicker();
    _loadBreaks();
    _checkShiftStatus();
  }

  @override
  void didUpdateWidget(covariant ManagerBreakRequestsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shiftStatus != oldWidget.shiftStatus) {
      _currentShiftStatus = widget.shiftStatus;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final hasActiveBreak = _breaks.any((item) => item.status == BreakStatus.active);
      if (hasActiveBreak && mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _loadBreaks({bool showLoadingIndicator = true}) async {
    if (showLoadingIndicator && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      setState(() => _isRefreshing = true);
    }

    try {
      final breaks = await RequestsApiService.fetchBreaks(employeeId: widget.managerId);
      if (!mounted) {
        return;
      }
      setState(() {
        _breaks = breaks;
        _errorMessage = null;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'تعذر تحميل الاستراحات: $error';
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _refreshShiftStatus() async {
    try {
      final status = await RequestsApiService.fetchShiftStatus(widget.managerId);
      if (!mounted) {
        return;
      }
      setState(() => _currentShiftStatus = status);
    } catch (_) {
      // Ignore shift status errors silently.
    }
    if (widget.onShiftStatusChanged != null) {
      await widget.onShiftStatusChanged!.call();
    }
  }

  Future<void> _checkShiftStatus() async {
    if (!mounted) return;
    setState(() {
      _isLoadingStatus = true;
    });
    try {
      final isActive = await RequestsApiService.checkActiveShift(widget.managerId);
      if (mounted) {
        setState(() {
          _isShiftActive = isActive;
          _isLoadingStatus = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isShiftActive = false;
          _isLoadingStatus = false;
        });
      }
      print('Failed to check shift status: $e');
    }
  }

  Future<void> _openBreakRequestSheet() async {
    final hasShift = await RequestsApiService.checkActiveShift(widget.managerId);
    if (!hasShift) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يمكن طلب استراحة بدون تسجيل حضور نشط'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      await _refreshShiftStatus();
      return;
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BreakRequestSheet(managerId: widget.managerId),
    );

    if (result == true && mounted) {
      await _loadBreaks();
      await _refreshShiftStatus();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم إرسال طلب الاستراحة بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _handleStartBreak(String breakId) async {
    setState(() => _actioningBreakId = breakId);
    try {
      await RequestsApiService.startBreak(breakId: breakId);
      await _loadBreaks(showLoadingIndicator: false);
      await _refreshShiftStatus();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم بدء الاستراحة. الوقت الآن غير محسوب ضمن ساعات العمل.'),
          backgroundColor: AppColors.primaryOrange,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر بدء الاستراحة: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _actioningBreakId = null);
      }
    }
  }

  Future<void> _handleEndBreak(String breakId) async {
    setState(() => _actioningBreakId = breakId);
    try {
      await RequestsApiService.endBreak(breakId: breakId);
      await _loadBreaks(showLoadingIndicator: false);
      await _refreshShiftStatus();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إنهاء الاستراحة'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر إنهاء الاستراحة: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _actioningBreakId = null);
      }
    }
  }

  Future<void> _deleteRejectedBreaks() async {
    setState(() => _submittingDelete = true);
    try {
      await RequestsApiService.deleteRejectedBreaks(widget.managerId);
      await _loadBreaks(showLoadingIndicator: false);
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
        setState(() => _submittingDelete = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
  final shiftStatusKnown = !widget.isShiftStatusLoading && _currentShiftStatus != null;
  final hasActiveShift = shiftStatusKnown ? _currentShiftStatus!.hasActiveShift : true;
    Break? activeBreak;
    for (final item in _breaks) {
      if (item.status == BreakStatus.active) {
        activeBreak = item;
        break;
      }
    }
    final hasActiveBreak = activeBreak != null;
    final hasRejected = _breaks.any((b) => b.status == BreakStatus.rejected);

    return RefreshIndicator(
      onRefresh: () {
        setState(() => _isRefreshing = true);
        return _loadBreaks(showLoadingIndicator: false);
      },
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ElevatedButton.icon(
            onPressed: (_isShiftActive && !_isLoadingStatus) ? _openBreakRequestSheet : null,
            icon: const Icon(Icons.add),
            label: _isLoadingStatus
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('طلب استراحة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (widget.isShiftStatusLoading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(minHeight: 4),
            )
          else if (shiftStatusKnown && !hasActiveShift)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'يرجى تسجيل الحضور أولاً قبل طلب استراحة.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          if (hasRejected) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _submittingDelete ? null : _deleteRejectedBreaks,
              icon: _submittingDelete
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
          if (hasActiveBreak)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'الوقت الحالي محسوب كاستراحة ولن يُحتسب من ساعات العمل.',
                  style: TextStyle(
                    color: AppColors.primaryOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            'الاستراحات الحالية والسابقة',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading && !_isRefreshing)
            const Center(child: CircularProgressIndicator())
          else if (_errorMessage != null)
            _BreaksErrorState(message: _errorMessage!, onRetry: ({bool showLoadingIndicator = true}) {
              return _loadBreaks(showLoadingIndicator: showLoadingIndicator);
            })
          else if (_breaks.isEmpty)
            const _BreaksEmptyState()
          else ...[
            for (final breakItem in _breaks) _BreakCard(
              breakItem: breakItem,
              onStart: _handleStartBreak,
              onEnd: _handleEndBreak,
              isActioning: _actioningBreakId == breakItem.id,
              remainingLabel: _remainingTimeLabel(breakItem),
            ),
          ],
        ],
      ),
    );
  }

  String? _remainingTimeLabel(Break breakItem) {
    if (breakItem.status != BreakStatus.active || breakItem.startTime == null) {
      return null;
    }
    final requested = breakItem.requestedDuration;
    final elapsed = DateTime.now().difference(breakItem.startTime!);
    final remaining = requested - elapsed;

    if (remaining.inSeconds <= 0) {
      return 'انتهت مدة الاستراحة المقررة';
    }

    return 'الوقت المتبقي: ${_formatDuration(remaining)}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    final parts = <String>[];

    if (hours > 0) {
      parts.add('$hours ساعة');
    }
    if (minutes > 0) {
      parts.add('$minutes دقيقة');
    }
    if (parts.isEmpty) {
      parts.add('$seconds ثانية');
    }

    return parts.join(' و ');
  }
}

class _BreakCard extends StatelessWidget {
  const _BreakCard({
    required this.breakItem,
    required this.onStart,
    required this.onEnd,
    required this.isActioning,
    required this.remainingLabel,
  });

  final Break breakItem;
  final ValueChanged<String> onStart;
  final ValueChanged<String> onEnd;
  final bool isActioning;
  final String? remainingLabel;

  @override
  Widget build(BuildContext context) {
    final actionButton = _buildActionButton();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'مدة الاستراحة: ${breakItem.requestedDurationMinutes} دقيقة',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Chip(
                label: Text(_statusLabel(breakItem.status)),
                backgroundColor: _statusColor(breakItem.status).withOpacity(0.1),
                labelStyle: TextStyle(
                  color: _statusColor(breakItem.status),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _BreakDetailsRow(label: 'بداية الطلب', value: _formatDateTime(breakItem.createdAt)),
          if (breakItem.startTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _BreakDetailsRow(
                label: 'بدء الاستراحة',
                value: _formatDateTime(breakItem.startTime!),
              ),
            ),
          if (breakItem.endTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _BreakDetailsRow(
                label: 'انتهاء الاستراحة',
                value: _formatDateTime(breakItem.endTime!),
              ),
            ),
          if (remainingLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                remainingLabel!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryOrange,
                ),
              ),
            ),
          if (actionButton != null) ...[
            const SizedBox(height: 16),
            actionButton,
          ],
        ],
      ),
    );
  }

  Widget? _buildActionButton() {
    if (breakItem.status == BreakStatus.approved) {
      return ElevatedButton(
        onPressed: isActioning ? null : () => onStart(breakItem.id),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryOrange,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: isActioning
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('بدء الاستراحة'),
      );
    }
    if (breakItem.status == BreakStatus.active) {
      return OutlinedButton(
        onPressed: isActioning ? null : () => onEnd(breakItem.id),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryOrange,
          side: const BorderSide(color: AppColors.primaryOrange, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: isActioning
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('إنهاء الاستراحة'),
      );
    }
    return null;
  }

  String _statusLabel(BreakStatus status) {
    switch (status) {
      case BreakStatus.approved:
        return 'موافق عليها';
      case BreakStatus.rejected:
        return 'مرفوضة';
      case BreakStatus.active:
        return 'قيد التنفيذ';
      case BreakStatus.completed:
        return 'مكتملة';
      case BreakStatus.pending:
        return 'قيد المراجعة';
    }
  }

  Color _statusColor(BreakStatus status) {
    switch (status) {
      case BreakStatus.approved:
        return AppColors.success;
      case BreakStatus.rejected:
        return AppColors.error;
      case BreakStatus.active:
        return AppColors.primaryOrange;
      case BreakStatus.completed:
        return Colors.blueGrey;
      case BreakStatus.pending:
        return AppColors.statusPending;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final date = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}

class _BreaksEmptyState extends StatelessWidget {
  const _BreaksEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.free_breakfast, size: 64, color: AppColors.textTertiary),
          SizedBox(height: 16),
          Text(
            'لا توجد استراحات بعد',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'اطلب أول استراحة لك الآن',
            style: TextStyle(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _BreaksErrorState extends StatelessWidget {
  const _BreaksErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function({bool showLoadingIndicator}) onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => onRetry(showLoadingIndicator: true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

class _BreakDetailsRow extends StatelessWidget {
  const _BreakDetailsRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _BreakRequestSheet extends StatefulWidget {
  const _BreakRequestSheet({required this.managerId});

  final String managerId;

  @override
  State<_BreakRequestSheet> createState() => _BreakRequestSheetState();
}

class _BreakRequestSheetState extends State<_BreakRequestSheet> {
  final TextEditingController _durationController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final minutes = int.tryParse(_durationController.text.trim());

    if (minutes == null || minutes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال مدة صالحة بالدقائق'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await RequestsApiService.submitBreakRequest(
        employeeId: widget.managerId,
        durationMinutes: minutes,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر إرسال طلب الاستراحة: $error'),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'طلب استراحة جديد',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _durationController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'مدة الاستراحة (بالدقائق)',
              hintText: 'مثال: 15',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primaryOrange,
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'إرسال الطلب',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
    );
  }
}
