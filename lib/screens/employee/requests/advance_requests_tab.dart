import 'package:flutter/material.dart';

import '../../../models/advance_request.dart';
import '../../../services/supabase_requests_service.dart';
import '../../../theme/app_colors.dart';

class AdvanceRequestsTab extends StatefulWidget {
  const AdvanceRequestsTab({
    super.key,
    required this.employeeId,
  });

  final String employeeId;

  @override
  State<AdvanceRequestsTab> createState() => _AdvanceRequestsTabState();
}

class _AdvanceRequestsTabState extends State<AdvanceRequestsTab> {
  List<AdvanceRequest> _requests = <AdvanceRequest>[];
  bool _loading = true;
  String? _error;
  double? _currentEarnings;
  double? _maxAdvance;
  double? _remainingBalance;
  double? _totalAdvancesTaken;
  DateTime? _lastAdvanceDate;
  int? _daysSinceLastAdvance;
  bool _canRequestAdvance = false;
  bool _loadingAdvanceInfo = false;

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
      final requestsData = await SupabaseRequestsService.getSalaryAdvanceRequests(
        employeeId: widget.employeeId,
      );
      
      // Convert from Supabase format to AdvanceRequest model
      final requests = requestsData.map((data) => AdvanceRequest.fromJson(data)).toList();
      
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
    setState(() => _loadingAdvanceInfo = true);
    
    try {
      print('📞 Calling getEmployeeSalaryInfo for employee: ${widget.employeeId}');
      final response = await SupabaseRequestsService.getEmployeeSalaryInfo(widget.employeeId);
      print('📥 getEmployeeSalaryInfo response: $response');
      
      if (!mounted) return;

      final earnings = (response['currentEarnings'] ?? response['current_earnings'] ?? 0) as num?;
      final maxAdvance = (response['maxAdvance'] ?? response['max_advance']) as num?;
      final remaining = (response['remaining_balance'] ?? 0) as num?;
      final advancesTaken = (response['total_advances_taken'] ?? 0) as num?;
      final lastAdvDate = response['last_advance_date'] as String?;
      final daysSince = response['days_since_last_advance'] as int?;
      final canRequest = response['can_request_advance'] as bool? ?? false;
      
      print('💵 Parsed - earnings: $earnings, maxAdvance: $maxAdvance, remaining: $remaining, taken: $advancesTaken, canRequest: $canRequest, daysSince: $daysSince');
      
      setState(() {
        _currentEarnings = earnings?.toDouble();
        _maxAdvance = maxAdvance?.toDouble() ?? (_currentEarnings != null ? _currentEarnings! * 0.3 : null);
        _remainingBalance = remaining?.toDouble();
        _totalAdvancesTaken = advancesTaken?.toDouble();
        _lastAdvanceDate = lastAdvDate != null ? DateTime.parse(lastAdvDate) : null;
        _daysSinceLastAdvance = daysSince;
        _canRequestAdvance = canRequest;
        _loadingAdvanceInfo = false;
      });
      
      print('✅ State updated: earnings=$_currentEarnings, maxAdvance=$_maxAdvance, remaining=$_remainingBalance, canRequest=$_canRequestAdvance');
    } catch (e) {
      print('❌ Error in _loadCurrentEarnings: $e');
      if (mounted) {
        setState(() => _loadingAdvanceInfo = false);
      }
    }
  }

  Future<void> _openAdvanceRequestSheet() async {
    // Check if advance info is loaded
    if (_loadingAdvanceInfo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏳ جاري تحميل بيانات السلفة...'),
          backgroundColor: AppColors.statusPending,
        ),
      );
      return;
    }

    // Check if user has earnings
    if (_currentEarnings == null || _currentEarnings! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ لا يوجد رصيد متاح حتى الآن. يرجى العمل أولاً!'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Check if eligible (5 days passed)
    if (!_canRequestAdvance && _daysSinceLastAdvance != null) {
      final remainingDays = 5 - _daysSinceLastAdvance!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⏰ يمكنك طلب سلفة جديدة بعد $remainingDays أيام'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    final request = await showModalBottomSheet<AdvanceRequest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AdvanceRequestSheet(
        employeeId: widget.employeeId,
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
      // Reload advance info after creating request
      _loadCurrentEarnings();
    }
  }

  @override
  Widget build(BuildContext context) {
    // الطلبات القديمة المرفوضة/الموافق عليها مش هتظهر خالص
    // لأن getSalaryAdvanceRequests بترجع pending بس للموظفين

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ElevatedButton.icon(
            onPressed: _loadingAdvanceInfo ? null : _openAdvanceRequestSheet,
            icon: _loadingAdvanceInfo 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.add),
            label: Text(_loadingAdvanceInfo ? 'جاري التحميل...' : 'طلب سلفة جديد'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),
          if (_loadingAdvanceInfo)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('جاري تحميل معلومات السلفة...'),
                ],
              ),
            )
          else if (_maxAdvance != null && _maxAdvance! > 0)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _canRequestAdvance 
                    ? AppColors.surfaceVariant 
                    : AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _canRequestAdvance 
                      ? Colors.transparent 
                      : AppColors.error.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        _canRequestAdvance ? Icons.check_circle : Icons.schedule,
                        color: _canRequestAdvance ? AppColors.success : AppColors.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _canRequestAdvance ? 'يمكنك طلب سلفة' : 'لا يمكنك طلب سلفة الآن',
                        style: TextStyle(
                          color: _canRequestAdvance ? AppColors.success : AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                  if (_totalAdvancesTaken != null && _totalAdvancesTaken! > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'إجمالي الراتب:',
                                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                              ),
                              Text(
                                '${_currentEarnings!.toStringAsFixed(0)} ج.م',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'سلف مسحوبة:',
                                style: TextStyle(fontSize: 13, color: AppColors.error),
                              ),
                              Text(
                                '- ${_totalAdvancesTaken!.toStringAsFixed(0)} ج.م',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.error),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'الرصيد المتبقي:',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${_remainingBalance!.toStringAsFixed(0)} ج.م',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.success),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (!_canRequestAdvance && _daysSinceLastAdvance != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 18, color: AppColors.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'يمكنك طلب سلفة جديدة بعد ${5 - _daysSinceLastAdvance!} أيام',
                              style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            )
          else if (!_loadingAdvanceInfo)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Icon(Icons.warning_amber, color: AppColors.error, size: 32),
                  SizedBox(height: 8),
                  Text(
                    'لا يوجد رصيد متاح',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'يرجى العمل أولاً لتتمكن من طلب سلفة',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            'الطلبات المعلقة',
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
    final isApproved = request.isApproved;
    final isRejected = request.isRejected;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: isApproved || isRejected ? 3 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isApproved 
              ? AppColors.success 
              : isRejected 
                  ? AppColors.error 
                  : Colors.transparent,
          width: isApproved || isRejected ? 2 : 0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.attach_money,
                    color: AppColors.primaryOrange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'طلب سلفة',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryOrange.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryOrange.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'المبلغ المطلوب',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${request.amount.toStringAsFixed(0)} جنيه',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryOrange,
                    ),
                  ),
                  if (request.eligibleAmount != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '(الحد المتاح: ${request.eligibleAmount!.toStringAsFixed(0)} جنيه)',
                      style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // نتيجة المراجعة
            if (isApproved || isRejected) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (isApproved ? AppColors.success : AppColors.error).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isApproved ? AppColors.success : AppColors.error,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isApproved ? Icons.check_circle : Icons.cancel,
                          size: 18,
                          color: isApproved ? AppColors.success : AppColors.error,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isApproved ? 'تم الموافقة ✓' : 'تم الرفض ✗',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isApproved ? AppColors.success : AppColors.error,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    if (request.reviewedBy != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'تمت المراجعة بواسطة: ${request.reviewedBy}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                    if (isRejected && request.rejectionReason != null && request.rejectionReason!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'سبب الرفض: ${request.rejectionReason}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  'تاريخ الطلب: ${_formatDate(request.createdAt)}',
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
              ],
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
    required this.employeeId,
    this.currentEarnings,
    this.maxAdvance,
  });

  final String employeeId;
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
      final response = await SupabaseRequestsService.createSalaryAdvanceRequest(
        employeeId: widget.employeeId,
        amount: amount,
        reason: 'طلب سلفة',
      );
      
      if (response == null) {
        throw Exception('فشل إرسال الطلب');
      }
      
      // Convert response to AdvanceRequest model  
      final request = AdvanceRequest.fromJson(response);
      
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(request);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSubmitting = false);
      
      // استخراج رسالة الخطأ من Exception
      String errorMessage = error.toString();
      if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring(11);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
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
