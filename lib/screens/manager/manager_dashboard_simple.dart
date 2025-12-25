import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';
import '../../services/branch_manager_api_service.dart';
import '../../services/supabase_branch_service.dart';
import '../../services/supabase_requests_service.dart';
import '../manager/manager_absences_page.dart';

class ManagerDashboardSimple extends StatefulWidget {
  const ManagerDashboardSimple({
    super.key,
    required this.managerId,
    required this.branchName,
  });

  final String managerId;
  final String branchName;

  @override
  State<ManagerDashboardSimple> createState() => _ManagerDashboardSimpleState();
}

class _ManagerDashboardSimpleState extends State<ManagerDashboardSimple>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Requests data
  bool _loadingRequests = true;
  String? _requestsError;
  List<Map<String, dynamic>> _leaveRequests = [];
  List<Map<String, dynamic>> _advanceRequests = [];
  List<Map<String, dynamic>> _attendanceRequests = [];
  List<Map<String, dynamic>> _breakRequests = [];
  String _requestsFilter = 'pending'; // pending | approved | rejected | all

  // Absence page needs branchId
  String? _branchId;

  // Present employees
  bool _loadingPresent = true;
  String? _presentError;
  List<Map<String, dynamic>> _presentEmployees = [];

  // Daily attendance status
  bool _loadingAttendance = true;
  String? _attendanceError;
  List<Map<String, dynamic>> _dailyAttendance = [];
  bool _processingDeduction = false;

  // Realtime subscription for requests
  RealtimeChannel? _requestsChannel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // Changed from 3 to 4
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _ensureBranchId();
    await Future.wait([
      _loadRequests(),
      _loadPresentEmployees(),
      _loadDailyAttendance(),
    ]);
    _setupRealtimeSubscription();
  }

  Future<void> _ensureBranchId() async {
    try {
      final b = await SupabaseBranchService.getBranchByName(widget.branchName);
      setState(() {
        _branchId = b?['id'] as String?;
      });
    } catch (_) {
      // ignore
    }
  }

  void _setupRealtimeSubscription() {
    final client = Supabase.instance.client;
    _requestsChannel = client
        .channel('manager_simple_${widget.managerId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'leave_requests',
          callback: (_) => _loadRequests(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'salary_advances',
          callback: (_) => _loadRequests(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance_requests',
          callback: (_) => _loadRequests(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'breaks',
          callback: (_) => _loadRequests(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _requestsChannel?.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loadingRequests = true;
      _requestsError = null;
    });
    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        SupabaseRequestsService.getAllLeaveRequestsWithEmployees(
          status: _requestsFilter == 'all' ? null : _requestsFilter,
          managerId: widget.managerId,
        ),
        SupabaseRequestsService.getAllSalaryAdvanceRequestsWithEmployees(
          status: _requestsFilter == 'all' ? null : _requestsFilter,
          managerId: widget.managerId,
        ),
        SupabaseRequestsService.getAllAttendanceRequestsWithEmployees(
          status: _requestsFilter == 'all' ? null : _requestsFilter,
          managerId: widget.managerId,
        ),
        SupabaseRequestsService.getAllBreaksWithEmployees(
          status: _requestsFilter == 'all' ? null : _requestsFilter,
          managerId: widget.managerId,
        ),
      ]);

      setState(() {
        _leaveRequests = results[0];
        _advanceRequests = results[1];
        _attendanceRequests = results[2];
        _breakRequests = results[3];
        _loadingRequests = false;
      });
    } catch (e) {
      setState(() {
        _requestsError = e.toString();
        _loadingRequests = false;
      });
    }
  }

  Future<void> _loadPresentEmployees() async {
    setState(() {
      _loadingPresent = true;
      _presentError = null;
    });
    try {
      final employees = await SupabaseBranchService.getCurrentlyPresentEmployees(
        branchName: widget.branchName,
      );
      setState(() {
        _presentEmployees = employees;
        _loadingPresent = false;
      });
    } catch (e) {
      setState(() {
        _presentError = e.toString();
        _loadingPresent = false;
      });
    }
  }

  Future<void> _loadDailyAttendance() async {
    setState(() {
      _loadingAttendance = true;
      _attendanceError = null;
    });
    try {
      final attendance = await SupabaseBranchService.getDailyAttendanceStatus(
        branchName: widget.branchName,
      );
      setState(() {
        _dailyAttendance = attendance;
        _loadingAttendance = false;
      });
    } catch (e) {
      setState(() {
        _attendanceError = e.toString();
        _loadingAttendance = false;
      });
    }
  }

  Future<void> _applyDeduction(Map<String, dynamic> employee) async {
    if (_branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('خطأ: لم يتم تحديد معرف الفرع'), backgroundColor: Colors.red),
      );
      return;
    }

    final employeeName = employee['full_name'] as String;
    final deductionAmount = employee['deduction_amount'] as double;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الخصم'),
        content: Text(
          'هل أنت متأكد من خصم ${deductionAmount.toStringAsFixed(2)} جنيه من $employeeName؟\n\n'
          'سيتم خصم قيمة يومين عمل من راتب الموظف.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('تأكيد الخصم'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processingDeduction = true);

    try {
      final result = await SupabaseBranchService.applyAbsenceDeduction(
        employeeId: employee['employee_id'] as String,
        managerId: widget.managerId,
        branchId: _branchId!,
        deductionAmount: deductionAmount,
      );

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] as String),
            backgroundColor: AppColors.success,
          ),
        );
        // Reload attendance data
        await _loadDailyAttendance();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] as String),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _processingDeduction = false);
    }
  }

  Future<void> _actOnRequest(String type, String id, String action) async {
    try {
      await BranchManagerApiService.actOnRequest(
        type: type,
        id: id,
        action: action,
        managerId: widget.managerId,
      );
      await _loadRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تنفيذ العملية بنجاح')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: ${e.toString()}'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('لوحة المدير (${widget.branchName})'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.assignment), text: 'الطلبات'),
            Tab(icon: Icon(Icons.warning), text: 'الغياب'),
            Tab(icon: Icon(Icons.person_pin_circle), text: 'المتواجدون الآن'),
            Tab(icon: Icon(Icons.fact_check), text: 'الحضور اليومي'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'تصفية الطلبات',
            onSelected: (val) {
              setState(() => _requestsFilter = val);
              _loadRequests();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'all', child: Text('كل الحالات')),
              PopupMenuItem(value: 'pending', child: Text('قيد الانتظار')),
              PopupMenuItem(value: 'approved', child: Text('موافق عليها')),
              PopupMenuItem(value: 'rejected', child: Text('مرفوضة')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await Future.wait([
                _loadRequests(),
                _loadPresentEmployees(),
                _loadDailyAttendance(),
              ]);
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRequestsPage(),
          _buildAbsencesPage(),
          _buildPresentNowPage(),
          _buildDailyAttendancePage(),
        ],
      ),
    );
  }

  Widget _buildRequestsPage() {
    if (_loadingRequests) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_requestsError != null) {
      return _errorState(_requestsError!, onRetry: _loadRequests);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('طلبات الإجازة (${_leaveRequests.length})'),
        if (_leaveRequests.isEmpty)
          _emptyHint('لا يوجد طلبات إجازة')
        else
          ..._leaveRequests.map((r) => _requestCard(r, 'leave')),
        const SizedBox(height: 16),
        _sectionTitle('طلبات السلف (${_advanceRequests.length})'),
        if (_advanceRequests.isEmpty)
          _emptyHint('لا يوجد طلبات سلف')
        else
          ..._advanceRequests.map((r) => _requestCard(r, 'advance')),
        const SizedBox(height: 16),
        _sectionTitle('طلبات الحضور (${_attendanceRequests.length})'),
        if (_attendanceRequests.isEmpty)
          _emptyHint('لا يوجد طلبات حضور')
        else
          ..._attendanceRequests.map((r) => _requestCard(r, 'attendance')),
        const SizedBox(height: 16),
        _sectionTitle('طلبات الاستراحة (${_breakRequests.length})'),
        if (_breakRequests.isEmpty)
          _emptyHint('لا يوجد طلبات استراحة')
        else
          ..._breakRequests.map((r) => _requestCard(r, 'break')),
      ],
    );
  }

  Widget _requestCard(Map<String, dynamic> req, String type) {
    final String typeLabel = switch (type) {
      'leave' => 'إجازة',
      'advance' => 'سلفة',
      'attendance' => 'حضور',
      'break' => 'استراحة',
      _ => 'طلب'
    };
    final IconData typeIcon = switch (type) {
      'leave' => Icons.beach_access,
      'advance' => Icons.payments,
      'attendance' => Icons.calendar_today,
      'break' => Icons.free_breakfast,
      _ => Icons.assignment
    };

    final employee = req['employees'] ?? req['employee'];
    final employeeName = (employee is Map) ? (employee['full_name'] ?? '') : (req['employeeName'] ?? '');
    final status = (req['status'] ?? 'pending').toString().toLowerCase(); // Normalize to lowercase
    final branch = (employee is Map) ? (employee['branch'] ?? '') : '';
    final role = (employee is Map) ? (employee['role'] ?? '') : '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
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
                Row(
                  children: [
                    Icon(typeIcon, color: AppColors.primaryOrange),
                    const SizedBox(width: 8),
                    Text('طلب $typeLabel', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                _statusChip(status),
              ],
            ),
            const Divider(),
            Text('الموظف: $employeeName'),
            if (branch.toString().isNotEmpty || role.toString().isNotEmpty)
              Text('الفرع: ${branch.isEmpty ? '—' : branch} • الدور: ${role.isEmpty ? '—' : role}'),
            const SizedBox(height: 6),
            if (type == 'leave') ...[
              Text('من: ${req['start_date'] ?? req['startDate'] ?? '-'}'),
              Text('إلى: ${req['end_date'] ?? req['endDate'] ?? '-'}'),
              if ((req['reason'] ?? '').toString().isNotEmpty)
                Text('السبب: ${req['reason']}'),
            ],
            if (type == 'advance') ...[
              Text('المبلغ: ${_numFormat(req['amount'])} ج.م'),
              if ((req['reason'] ?? '').toString().isNotEmpty)
                Text('السبب: ${req['reason']}'),
            ],
            if (type == 'attendance') ...[
              Text('نوع الطلب: ${req['request_type'] ?? req['requestType'] ?? '-'}'),
              if ((req['requested_time'] ?? req['requestedTime']) != null)
                Text('الوقت المطلوب: ${req['requested_time'] ?? req['requestedTime']}'),
              if ((req['reason'] ?? '').toString().isNotEmpty)
                Text('السبب: ${req['reason']}'),
            ],
            if (type == 'break') ...[
              Text('المدة المطلوبة: ${req['requested_duration_minutes'] ?? req['duration_minutes'] ?? req['requestedDurationMinutes'] ?? req['durationMinutes'] ?? '-'} دقيقة'),
              Text('تاريخ الطلب: ${req['created_at'] ?? req['createdAt'] ?? '-'}'),
            ],
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _actOnRequest(type, req['id'] as String, 'approve'),
                      icon: const Icon(Icons.check),
                      label: const Text('موافقة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _actOnRequest(type, req['id'] as String, 'reject'),
                      icon: const Icon(Icons.close),
                      label: const Text('رفض'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              if (type == 'break') ...[
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _actOnRequest(type, req['id'] as String, 'postpone'),
                  icon: const Icon(Icons.hourglass_empty),
                  label: const Text('تأجيل'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
            if (type == 'break' && status == 'approved') ...[
              const SizedBox(height: 8),
              Text('يمكن للموظف بدء الاستراحة الآن', style: const TextStyle(color: AppColors.primaryOrange)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    Color bg;
    String label;
    switch (status) {
      case 'approved':
        bg = AppColors.success;
        label = 'موافق عليها';
        break;
      case 'rejected':
        bg = AppColors.error;
        label = 'مرفوضة';
        break;
      case 'active':
        bg = Colors.blue;
        label = 'نشطة';
        break;
      case 'completed':
        bg = Colors.green;
        label = 'مكتملة';
        break;
      case 'postponed':
        bg = Colors.blueGrey;
        label = 'مؤجلة';
        break;
      default:
        bg = Colors.orange;
        label = 'قيد الانتظار';
    }
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: bg,
    );
  }

  Widget _buildAbsencesPage() {
    // Reuse the existing absences page if branchId is available
    if (_branchId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text('جاري تحميل بيانات الفرع (${widget.branchName})...'),
          ],
        ),
      );
    }
    return ManagerAbsencesPage(managerId: widget.managerId, branchId: _branchId!);
  }

  Widget _buildPresentNowPage() {
    if (_loadingPresent) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_presentError != null) {
      return _errorState(_presentError!, onRetry: _loadPresentEmployees);
    }
    if (_presentEmployees.isEmpty) {
      return _emptyHint('لا يوجد موظفون متواجدون حالياً');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _presentEmployees.length,
      itemBuilder: (context, index) {
        final att = _presentEmployees[index];
        final emp = att['employees'] as Map<String, dynamic>?;
        final name = emp?['full_name'] ?? '—';
        final checkIn = att['check_in_time'] as String?;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          elevation: 2,
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('تسجيل دخول: ${checkIn ?? '-'}'),
            trailing: const Icon(Icons.check_circle, color: AppColors.success),
          ),
        );
      },
    );
  }

  Widget _buildDailyAttendancePage() {
    final now = DateTime.now();
    final isAfterNoon = now.hour >= 12;

    if (_loadingAttendance) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_attendanceError != null) {
      return _errorState(_attendanceError!, onRetry: _loadDailyAttendance);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header info
        Card(
          color: isAfterNoon ? Colors.orange[50] : Colors.blue[50],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'جدول الحضور اليومي',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isAfterNoon ? Colors.orange[900] : Colors.blue[900],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'التاريخ: ${DateFormat('yyyy-MM-dd').format(now)}',
                  style: const TextStyle(fontSize: 14),
                ),
                if (isAfterNoon) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '⚠️ بعد الساعة 12:00 - يمكن خصم الموظفين الغائبين',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    'الوقت الحالي: ${DateFormat('HH:mm').format(now)} (قبل الساعة 12:00)',
                    style: const TextStyle(color: Colors.blue),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Attendance list
        if (_dailyAttendance.isEmpty)
          _emptyHint('لا يوجد موظفون في هذا الفرع')
        else
          ..._dailyAttendance.map((emp) {
            final isPresent = emp['is_present'] as bool;
            final canDeduct = emp['can_deduct'] as bool;
            final deductionAmount = emp['deduction_amount'] as double;
            final name = emp['full_name'] as String;
            final checkInTime = emp['check_in_time'] as String?;
            final hourlyRate = (emp['hourly_rate'] as num?)?.toDouble() ?? 0.0;
            final shiftStart = emp['shift_start_time'] as String?;
            final shiftEnd = emp['shift_end_time'] as String?;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              elevation: 3,
              color: isPresent ? Colors.green[50] : Colors.red[50],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isPresent ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isPresent ? Icons.check_circle : Icons.cancel,
                          color: isPresent ? Colors.green : Colors.red,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                isPresent ? 'حضر ✓' : 'لم يحضر ✗',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isPresent ? Colors.green[700] : Colors.red[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Text('الشيفت: ${shiftStart ?? '-'} إلى ${shiftEnd ?? '-'}'),
                    Text('سعر الساعة: ${hourlyRate.toStringAsFixed(2)} جنيه'),
                    if (isPresent && checkInTime != null)
                      Builder(builder: (context) {
                        try {
                          return Text(
                            'وقت الحضور: ${DateFormat('HH:mm').format(DateTime.parse(checkInTime))}',
                            style: const TextStyle(color: Colors.green),
                          );
                        } catch (e) {
                          return const Text('وقت الحضور: -', style: TextStyle(color: Colors.green));
                        }
                      }),
                    if (!isPresent && canDeduct) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange, width: 2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '💰 قيمة الخصم (يومين):',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${deductionAmount.toStringAsFixed(2)} جنيه',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _processingDeduction ? null : () => _applyDeduction(emp),
                          icon: _processingDeduction
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.remove_circle),
                          label: Text(
                            _processingDeduction
                                ? 'جاري تطبيق الخصم...'
                                : 'تطبيق خصم الغياب',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  // Helpers
  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryOrange,
          ),
        ),
      );

  Widget _emptyHint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(text, style: const TextStyle(color: Colors.grey)),
        ),
      );

  Widget _errorState(String text, {Future<void> Function()? onRetry}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  String _numFormat(dynamic n) {
    if (n == null) return '0';
    final v = (n is num) ? n.toDouble() : double.tryParse(n.toString()) ?? 0.0;
    return NumberFormat('#,##0.##', 'ar').format(v);
  }
}
