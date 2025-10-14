import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../models/leave_request.dart' as leave;
import '../../models/advance_request.dart' as advance;

class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key, required this.employeeId});

  final String employeeId;

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<leave.LeaveRequest> _leaveRequests = [];
  final List<advance.AdvanceRequest> _advanceRequests = [];
  double _currentEarnings = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _currentEarnings = 3500.0;
    });
  }

  Future<void> _createLeaveRequest() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LeaveRequestForm(),
    );

    if (result == null) return;

    final leaveDate = result['date'] as DateTime;
    final type = result['type'] as leave.LeaveType;
    final reason = result['reason'] as String;

    final now = DateTime.now();
    final diff = leaveDate.difference(now);

    if (type == leave.LeaveType.normal && diff.inHours < 48) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'طلب الإجازة العادية يجب أن يكون قبلها بـ 48 ساعة على الأقل',
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            textDirection: TextDirection.rtl,
          ),
        ),
      );
      return;
    }

    if (type == leave.LeaveType.emergency && diff.inHours < 24) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'طلب الإجازة الطارئة يجب أن يكون قبلها بـ 24 ساعة على الأقل',
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            textDirection: TextDirection.rtl,
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.success,
        content: Text(
          'تم إرسال طلب الإجازة للمدير',
          style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }

  Future<void> _createAdvanceRequest() async {
    final maxAllowed = _currentEarnings * 0.30;

    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AdvanceRequestForm(
        maxAllowed: maxAllowed,
        currentEarnings: _currentEarnings,
      ),
    );

    if (result == null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.success,
        content: Text(
          'تم إرسال طلب السلفة بمبلغ ${result.toStringAsFixed(0)} جنيه للمدير',
          style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'طلباتي',
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryOrange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primaryOrange,
          labelStyle: GoogleFonts.ibmPlexSansArabic(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'الإجازات'),
            Tab(text: 'السلف'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLeaveRequestsTab(),
          _buildAdvanceRequestsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _createLeaveRequest();
          } else {
            _createAdvanceRequest();
          }
        },
        backgroundColor: AppColors.primaryOrange,
        icon: const Icon(Icons.add),
        label: Text(
          _tabController.index == 0 ? 'طلب إجازة' : 'طلب سلفة',
          style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildLeaveRequestsTab() {
    if (_leaveRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'لا توجد طلبات إجازة',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 18,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'اضغط على الزر بالأسفل لتقديم طلب جديد',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 14,
                color: Colors.grey.shade400,
              ),
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _leaveRequests.length,
      itemBuilder: (context, index) {
        final request = _leaveRequests[index];
        return _buildLeaveRequestCard(request);
      },
    );
  }

  Widget _buildAdvanceRequestsTab() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryOrange, Color(0xFFFF9A56)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                'مرتبك الحالي',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_currentEarnings.toStringAsFixed(0)} جنيه',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'يمكنك طلب سلفة حتى ${(_currentEarnings * 0.30).toStringAsFixed(0)} جنيه (30%)',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.8),
                ),
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
        ),
        Expanded(
          child: _advanceRequests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_balance_wallet,
                          size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        'لا توجد طلبات سلف',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 18,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _advanceRequests.length,
                  itemBuilder: (context, index) {
                    final request = _advanceRequests[index];
                    return _buildAdvanceRequestCard(request);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLeaveRequestCard(leave.LeaveRequest request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _getStatusColor(request.status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getStatusIcon(request.status),
              color: _getStatusColor(request.status),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.isEmergency ? 'إجازة طارئة' : 'إجازة عادية',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(request.leaveDate),
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          _buildStatusBadge(request.status),
        ],
      ),
    );
  }

  Widget _buildAdvanceRequestCard(advance.AdvanceRequest request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _getStatusColor(request.status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.attach_money,
              color: _getStatusColor(request.status),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${request.amount.toStringAsFixed(0)} جنيه',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDateTime(request.createdAt),
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          _buildStatusBadge(request.status),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(dynamic status) {
    final statusText = status == advance.RequestStatus.pending ||
            status == leave.RequestStatus.pending
        ? 'قيد المراجعة'
        : status == advance.RequestStatus.approved ||
                status == leave.RequestStatus.approved
            ? 'موافق عليه'
            : 'مرفوض';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getStatusColor(status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _getStatusColor(status)),
      ),
      child: Text(
        statusText,
        style: GoogleFonts.ibmPlexSansArabic(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _getStatusColor(status),
        ),
      ),
    );
  }

  Color _getStatusColor(dynamic status) {
    if (status == advance.RequestStatus.pending ||
        status == leave.RequestStatus.pending) {
      return Colors.orange;
    } else if (status == advance.RequestStatus.approved ||
        status == leave.RequestStatus.approved) {
      return AppColors.success;
    } else {
      return AppColors.danger;
    }
  }

  IconData _getStatusIcon(dynamic status) {
    if (status == leave.RequestStatus.pending) {
      return Icons.pending;
    } else if (status == leave.RequestStatus.approved) {
      return Icons.check_circle;
    } else {
      return Icons.cancel;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} - ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _LeaveRequestForm extends StatefulWidget {
  @override
  State<_LeaveRequestForm> createState() => _LeaveRequestFormState();
}

class _LeaveRequestFormState extends State<_LeaveRequestForm> {
  DateTime? _selectedDate;
  leave.LeaveType _type = leave.LeaveType.normal;
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'طلب إجازة',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Text(
              'نوع الإجازة',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTypeButton(
                    label: 'عادية (قبلها ب48 ساعة)',
                    selected: _type == leave.LeaveType.normal,
                    onTap: () => setState(() => _type = leave.LeaveType.normal),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTypeButton(
                    label: 'طارئة (قبلها ب24 ساعة)',
                    selected: _type == leave.LeaveType.emergency,
                    onTap: () =>
                        setState(() => _type = leave.LeaveType.emergency),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'تاريخ الإجازة',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 3)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) {
                  setState(() => _selectedDate = date);
                }
              },
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _selectedDate == null
                    ? 'اختر التاريخ'
                    : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                style: GoogleFonts.ibmPlexSansArabic(),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                side: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            const SizedBox(height: 20),
            if (_type == leave.LeaveType.emergency) ...[
              Text(
                'السبب (إجباري للإجازة الطارئة)',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                maxLines: 3,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'اكتب سبب الإجازة الطارئة...',
                  hintStyle: GoogleFonts.ibmPlexSansArabic(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            ElevatedButton(
              onPressed: () {
                if (_selectedDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'يرجى اختيار تاريخ الإجازة',
                        style: GoogleFonts.ibmPlexSansArabic(),
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  );
                  return;
                }

                if (_type == leave.LeaveType.emergency &&
                    _reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'يرجى كتابة سبب الإجازة الطارئة',
                        style: GoogleFonts.ibmPlexSansArabic(),
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  );
                  return;
                }

                Navigator.pop(context, {
                  'date': _selectedDate,
                  'type': _type,
                  'reason': _reasonController.text.trim(),
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'إرسال الطلب',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryOrange.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primaryOrange : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 14,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? AppColors.primaryOrange : Colors.grey.shade700,
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }
}

class _AdvanceRequestForm extends StatefulWidget {
  const _AdvanceRequestForm({
    required this.maxAllowed,
    required this.currentEarnings,
  });

  final double maxAllowed;
  final double currentEarnings;

  @override
  State<_AdvanceRequestForm> createState() => _AdvanceRequestFormState();
}

class _AdvanceRequestFormState extends State<_AdvanceRequestForm> {
  final _amountController = TextEditingController();
  double _selectedAmount = 0;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'طلب سلفة',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'الحد الأقصى للسلفة',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.maxAllowed.toStringAsFixed(0)} جنيه',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryOrange,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '(30% من مرتبك الحالي ${widget.currentEarnings.toStringAsFixed(0)} جنيه)',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'المبلغ المطلوب',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.rtl,
              onChanged: (value) {
                setState(() {
                  _selectedAmount = double.tryParse(value) ?? 0;
                });
              },
              decoration: InputDecoration(
                hintText: 'أدخل المبلغ',
                hintStyle: GoogleFonts.ibmPlexSansArabic(),
                suffixText: 'جنيه',
                suffixStyle: GoogleFonts.ibmPlexSansArabic(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                if (_selectedAmount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'يرجى إدخال مبلغ صحيح',
                        style: GoogleFonts.ibmPlexSansArabic(),
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  );
                  return;
                }

                if (_selectedAmount > widget.maxAllowed) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.danger,
                      content: Text(
                        'المبلغ المطلوب أكبر من الحد الأقصى المسموح (${widget.maxAllowed.toStringAsFixed(0)} جنيه)',
                        style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  );
                  return;
                }

                Navigator.pop(context, _selectedAmount);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'إرسال الطلب',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
