import 'dart:async';

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../models/leave_request.dart';
import '../../models/advance_request.dart';
import '../../models/break.dart';
import '../../services/requests_api_service.dart';


class RequestsPage extends StatefulWidget {
  final String employeeId;
  final bool hideBreakTab;

  const RequestsPage({super.key, required this.employeeId, this.hideBreakTab = false});

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}


class _RequestsPageState extends State<RequestsPage> with SingleTickerProviderStateMixin {
          else ..._buildBreaksList(),

  List<Widget> _buildBreaksList() {
    final widgets = <Widget>[];
    if (_breaks.any((b) => b.status == BreakStatus.rejected)) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.delete),
            label: const Text('حذف جميع الطلبات المرفوضة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _deleteRejectedBreaks,
          ),
        ),
      );
    }
    widgets.addAll(_breaks.map(_buildBreakCard));
    return widgets;
  }

  Future<void> _deleteRejectedBreaks() async {
    setState(() => _isLoading = true);
    try {
      await RequestsApiService.deleteRejectedBreaks(widget.employeeId);
      await _loadBreaks(showLoadingIndicator: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف جميع الطلبات المرفوضة بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر حذف الطلبات المرفوضة: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }
                            Tab(
                              icon: Icon(Icons.payments),
                              text: 'السلف'
                            ),
                            Tab(
                              icon: Icon(Icons.free_breakfast),
                              text: 'الاستراحات'
                            )
                          ]
                  )
                )
              ],
            ),
          ),
          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: widget.hideBreakTab
                  ? [
                      _LeaveRequestsTab(
                        employeeId: widget.employeeId,
                        onNewRequest: _showLeaveRequestSheet,
                      ),
                      _AdvanceRequestsTab(
                        employeeId: widget.employeeId,
                        onNewRequest: _showAdvanceRequestSheet,
                      ),
                    ]
                  : [
                      _LeaveRequestsTab(
                        employeeId: widget.employeeId,
                        onNewRequest: _showLeaveRequestSheet,
                      ),
                      _AdvanceRequestsTab(
                        employeeId: widget.employeeId,
                        onNewRequest: _showAdvanceRequestSheet,
                      ),
                      _BreaksView(
                        employeeId: widget.employeeId,
                      ),
                    ],
            ),
          ),
        ],
      ),
    );
  }
}
  }
}

// Leave Requests Tab
class _LeaveRequestsTab extends StatefulWidget {
  final String employeeId;
  final VoidCallback onNewRequest;

  const _LeaveRequestsTab({
    required this.employeeId,
    required this.onNewRequest,
  });

  @override
  State<_LeaveRequestsTab> createState() => _LeaveRequestsTabState();
}

class _LeaveRequestsTabState extends State<_LeaveRequestsTab> {
  List<LeaveRequest> _requests = [];
  bool _loading = true;
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
      final requests = await RequestsApiService.fetchLeaveRequests(widget.employeeId);
      if (mounted) {
        setState(() {
          _requests = requests;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: widget.onNewRequest,
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
              _buildErrorState(_error!)
            else if (_requests.isEmpty)
              _buildEmptyState(
                icon: Icons.inbox,
                title: 'لا توجد طلبات سابقة',
                subtitle: 'سيتم عرض طلباتك هنا',
              )
            else
              ..._requests.map((request) => _buildLeaveRequestCard(request)),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveRequestCard(LeaveRequest request) {
    Color statusColor;
    String statusText;
    if (request.isApproved) {
      statusColor = AppColors.success;
      statusText = 'موافق عليها';
    } else if (request.isRejected) {
      statusColor = AppColors.error;
      statusText = 'مرفوضة';
    } else {
      statusColor = AppColors.pending;
      statusText = 'قيد الانتظار';
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('من: ${request.startDate}'),
            Text('إلى: ${request.endDate}'),
            Text('عدد الأيام: ${request.daysCount}'),
            if (request.allowanceAmount > 0)
              Text('بدل الإجازة: ${request.allowanceAmount} جنيه'),
            if (request.reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'السبب: ${request.reason}',
                style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            'حدث خطأ',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: const TextStyle(fontSize: 14, color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadRequests,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// Advance Requests Tab
class _AdvanceRequestsTab extends StatefulWidget {
  final String employeeId;
  final VoidCallback onNewRequest;

  const _AdvanceRequestsTab({
    required this.employeeId,
    required this.onNewRequest,
  });

  @override
  State<_AdvanceRequestsTab> createState() => _AdvanceRequestsTabState();
}

class _AdvanceRequestsTabState extends State<_AdvanceRequestsTab> {
  List<AdvanceRequest> _requests = [];
  bool _loading = true;
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
      final requests = await RequestsApiService.fetchAdvanceRequests(widget.employeeId);
      if (mounted) {
        setState(() {
          _requests = requests;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: widget.onNewRequest,
              icon: const Icon(Icons.add),
              label: const Text('طلب سلفة جديد'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            
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
              _buildErrorState(_error!)
            else if (_requests.isEmpty)
              _buildEmptyState()
            else
              ..._requests.map((request) => _buildAdvanceRequestCard(request)),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvanceRequestCard(AdvanceRequest request) {
    Color statusColor;
    String statusText;
    if (request.isApproved) {
      statusColor = AppColors.success;
      statusText = 'موافق عليها';
    } else if (request.isRejected) {
      statusColor = AppColors.error;
      statusText = 'مرفوضة';
    } else {
      statusColor = Colors.orange;
      statusText = 'قيد الانتظار';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'المبلغ: ${request.amount.toStringAsFixed(2)} جنيه',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryOrange),
            ),
            if (request.eligibleAmount != null)
              Text('الحد الأقصى المتاح: ${request.eligibleAmount!.toStringAsFixed(2)} جنيه'),
            Text('تاريخ الطلب: ${request.requestDate}'),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          const Text(
            'حدث خطأ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: const TextStyle(fontSize: 14, color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadRequests,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.inbox,
            size: 64,
            color: AppColors.textTertiary,
          ),
          SizedBox(height: 16),
          Text(
            'لا توجد طلبات سابقة',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'سيتم عرض طلباتك هنا',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// Breaks View
class _BreaksView extends StatefulWidget {
  final String employeeId;

  const _BreaksView({required this.employeeId});

  @override
  State<_BreaksView> createState() => _BreaksViewState();
}

class _BreaksViewState extends State<_BreaksView> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  List<Break> _breaks = <Break>[];
  String? _actioningBreakId;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _startTicker();
    _loadBreaks();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) {
        return;
      }
      final hasActive = _breaks.any(
        (item) => item.status == BreakStatus.active && item.startTime != null,
      );
      if (hasActive) {
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
    }

    try {
      final breaks =
          await RequestsApiService.fetchBreaks(employeeId: widget.employeeId);
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

  Future<void> _openBreakRequestSheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BreakRequestSheet(
        employeeId: widget.employeeId,
      ),
    );

    if (result == true && mounted) {
      await _loadBreaks();
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
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم بدء الاستراحة'),
          backgroundColor: AppColors.success,
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () {
        setState(() => _isRefreshing = true);
        return _loadBreaks(showLoadingIndicator: false);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          ElevatedButton.icon(
            onPressed: _openBreakRequestSheet,
            icon: const Icon(Icons.add),
            label: const Text('طلب استراحة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
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
            _BreaksErrorState(
              message: _errorMessage!,
              onRetry: _loadBreaks,
            )
          else if (_breaks.isEmpty)
            const _BreaksEmptyState()
          else ..._buildBreaksList(),

  List<Widget> _buildBreaksList() {
    final widgets = <Widget>[];
    if (_breaks.any((b) => b.status == BreakStatus.rejected)) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.delete),
            label: const Text('حذف جميع الطلبات المرفوضة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _deleteRejectedBreaks,
          ),
        ),
      );
    }
    widgets.addAll(_breaks.map(_buildBreakCard));
    return widgets;
  }

  Future<void> _deleteRejectedBreaks() async {
    setState(() => _isLoading = true);
    try {
      await RequestsApiService.deleteRejectedBreaks(widget.employeeId);
      await _loadBreaks(showLoadingIndicator: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف جميع الطلبات المرفوضة بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر حذف الطلبات المرفوضة: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
        ],
      ),
    );
  }

  Widget _buildBreakCard(Break breakItem) {
    final statusLabel = _statusLabel(breakItem.status);
    final isActioning = _actioningBreakId == breakItem.id;
    final actionButton = _buildActionButton(breakItem, isActioning);
    final remainingLabel = _remainingTimeLabel(breakItem);

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
                label: Text(statusLabel),
                backgroundColor: _statusColor(breakItem.status).withOpacity(0.1),
                labelStyle: TextStyle(
                  color: _statusColor(breakItem.status),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _BreakDetailsRow(
            label: 'بداية الطلب',
            value: _formatDateTime(breakItem.createdAt),
          ),
          if (breakItem.startTime != null) ...[
            const SizedBox(height: 8),
            _BreakDetailsRow(
              label: 'بدء الاستراحة',
              value: _formatDateTime(breakItem.startTime!),
            ),
          ],
          if (breakItem.endTime != null) ...[
            const SizedBox(height: 8),
            _BreakDetailsRow(
              label: 'انتهاء الاستراحة',
              value: _formatDateTime(breakItem.endTime!),
            ),
          ],
          if (remainingLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              remainingLabel,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryOrange,
              ),
            ),
          ],
          if (actionButton != null) ...[
            const SizedBox(height: 16),
            actionButton,
          ],
        ],
      ),
    );
  }

  Widget? _buildActionButton(Break breakItem, bool isActioning) {
    if (breakItem.status == BreakStatus.approved) {
      return ElevatedButton(
        onPressed: isActioning ? null : () => _handleStartBreak(breakItem.id),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryOrange,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
        onPressed: isActioning ? null : () => _handleEndBreak(breakItem.id),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryOrange,
          side: const BorderSide(color: AppColors.primaryOrange, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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

    return 'الوقت المتبقي: ${_formatRemainingDuration(remaining)}';
  }

  String _formatRemainingDuration(Duration duration) {
    final parts = <String>[];
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

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

  String _statusLabel(BreakStatus status) {
    switch (status) {
      case BreakStatus.approved:
        return 'موافق عليه';
      case BreakStatus.rejected:
        return 'مرفوض';
      case BreakStatus.active:
        return 'قيد التنفيذ';
      case BreakStatus.completed:
        return 'مكتمل';
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
        return AppColors.textSecondary;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final date = '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)}';
    final time = '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
    return '$date $time';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
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
          Icon(
            Icons.free_breakfast,
            size: 64,
            color: AppColors.textTertiary,
          ),
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
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreaksErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function({bool showLoadingIndicator}) onRetry;

  const _BreaksErrorState({
    required this.message,
    required this.onRetry,
  });

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
          const Icon(
            Icons.error_outline,
            size: 48,
            color: AppColors.error,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => onRetry(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
            ),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

class _BreakDetailsRow extends StatelessWidget {
  final String label;
  final String value;

  const _BreakDetailsRow({
    required this.label,
    required this.value,
  });

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
  final String employeeId;

  const _BreakRequestSheet({required this.employeeId});

  @override
  State<_BreakRequestSheet> createState() => _BreakRequestSheetState();
}

class _BreakRequestSheetState extends State<_BreakRequestSheet> {
  final _durationController = TextEditingController();
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
        employeeId: widget.employeeId,
        durationMinutes: minutes,
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } catch (error) {
      setState(() => _isSubmitting = false);
      if (!mounted) {
        return;
      }
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
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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


// Leave Request Sheet
class _LeaveRequestSheet extends StatefulWidget {
  final String employeeId;

  const _LeaveRequestSheet({required this.employeeId});

  @override
  State<_LeaveRequestSheet> createState() => _LeaveRequestSheetState();
}

class _LeaveRequestSheetState extends State<_LeaveRequestSheet> {
  LeaveType _selectedType = LeaveType.normal;
  DateTime? _startDate;
  DateTime? _endDate;
  final _reasonController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now.add(const Duration(days: 2)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryOrange,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      setState(() {
        _startDate = date;
        if (_endDate != null && _endDate!.isBefore(date)) {
          _endDate = date;
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    final baseDate = _startDate ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate ?? baseDate,
      firstDate: baseDate,
      lastDate: baseDate.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryOrange,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      setState(() => _endDate = date);
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
        employeeId: widget.employeeId,
        startDate: _startDate!,
        endDate: _endDate!,
        reason: reason.isEmpty ? null : reason,
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context, request);
    } catch (error) {
      setState(() => _isSubmitting = false);
      if (!mounted) {
        return;
      }
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
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'طلب إجازة جديد',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            
            const SizedBox(height: 24),
            
            const Text(
              'نوع الإجازة',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            
            Row(
              children: [
                Expanded(
                  child: _buildTypeCard(
                    type: LeaveType.normal,
                    title: 'إجازة عادية',
                    subtitle: 'قبلها ب 48 ساعة',
                    icon: Icons.event_available,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTypeCard(
                    type: LeaveType.emergency,
                    title: 'إجازة طارئة',
                    subtitle: 'قبلها ب 24 ساعة',
                    icon: Icons.warning_amber,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _selectStartDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _startDate != null
                    ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}'
                    : 'تاريخ البداية',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryOrange,
                side: const BorderSide(color: AppColors.primaryOrange),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 16),

            OutlinedButton.icon(
              onPressed: (_startDate == null || _isSubmitting)
                  ? null
                  : _selectEndDate,
              icon: const Icon(Icons.calendar_month),
              label: Text(
                _endDate != null
                    ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}'
                    : 'تاريخ النهاية',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryOrange,
                side: const BorderSide(color: AppColors.primaryOrange),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 16),

            const SizedBox(height: 16),

            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: _selectedType == LeaveType.emergency
                    ? 'السبب (إلزامي للطوارئ)'
                    : 'السبب (اختياري)',
                hintText: 'اكتب سبب طلب الإجازة...',
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
              maxLines: 3,
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
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeCard({
    required LeaveType type,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedType == type;
    
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryOrange.withOpacity(0.1) : Colors.white,
          border: Border.all(
            color: isSelected ? AppColors.primaryOrange : AppColors.surfaceVariant,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primaryOrange : AppColors.textTertiary,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isSelected ? AppColors.primaryOrange : AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// Advance Request Sheet
class _AdvanceRequestSheet extends StatefulWidget {
  final String employeeId;
  final double? currentEarnings;
  final double? maxAdvance;

  const _AdvanceRequestSheet({
    required this.employeeId,
    this.currentEarnings,
    this.maxAdvance,
  });

  @override
  State<_AdvanceRequestSheet> createState() => _AdvanceRequestSheetState();
}

class _AdvanceRequestSheetState extends State<_AdvanceRequestSheet> {
  final _amountController = TextEditingController();
  late double _maxAdvance;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _maxAdvance = widget.maxAdvance ??
        (widget.currentEarnings != null ? widget.currentEarnings! * 0.3 : 0);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rawAmount = double.tryParse(_amountController.text.replaceAll(',', '.'));

    if (rawAmount == null || rawAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال مبلغ صالح'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_maxAdvance > 0 && rawAmount > _maxAdvance) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'الحد الأقصى للسلفة المتاحة هو ${_maxAdvance.toStringAsFixed(0)} جنيه',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final request = await RequestsApiService.submitAdvanceRequest(
        employeeId: widget.employeeId,
        amount: rawAmount,
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context, request);
    } catch (error) {
      setState(() => _isSubmitting = false);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر إرسال طلب السلفة: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'طلب سلفة جديد',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            
            const SizedBox(height: 24),
            
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'المرتب الحالي',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        widget.currentEarnings != null
                            ? '${widget.currentEarnings!.toStringAsFixed(0)} جنيه'
                            : 'لم يتم تحديده',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'الحد الأقصى للسلفة المتاحة',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        _maxAdvance > 0
                            ? '${_maxAdvance.toStringAsFixed(0)} جنيه'
                            : 'لم يتم تحديده',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryOrange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),

            if (_maxAdvance > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'الحد الأقصى للسلفة المتاحة: ${_maxAdvance.toStringAsFixed(0)} جنيه',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryOrange,
                  ),
                ),
              ),

            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'المبلغ المطلوب',
                hintText: 'أدخل المبلغ...',
                suffixText: 'جنيه',
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
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
