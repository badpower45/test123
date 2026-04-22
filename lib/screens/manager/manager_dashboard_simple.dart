import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';
import '../../services/branch_manager_api_service.dart';
import '../../services/manager_attendance_admin_service.dart';
import '../../services/supabase_branch_service.dart';
import '../../services/supabase_requests_service.dart';
import '../manager/manager_absences_page.dart';

class ManagerDashboardSimple extends StatefulWidget {
  const ManagerDashboardSimple({
    super.key,
    required this.managerId,
    required this.branchName,
    this.initialTabIndex = 0,
  });

  final String managerId;
  final String branchName;
  final int initialTabIndex;

  @override
  State<ManagerDashboardSimple> createState() => _ManagerDashboardSimpleState();
}

class _ManagerDashboardSimpleState extends State<ManagerDashboardSimple>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _attendanceSearchController =
      TextEditingController();

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
  List<Map<String, dynamic>> _dailyAttendanceRows = [];
  bool _processingAttendance = false;
  String _attendanceSearch = '';
  String _attendanceStatusFilter =
      'all'; // all | present | active | on_leave | absent
  String _attendanceSort = 'status'; // status | name | check_in
  DateTime _selectedAttendanceDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );

  // Realtime subscription for requests
  RealtimeChannel? _requestsChannel;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.initialTabIndex.clamp(0, 3);
    _tabController = TabController(
      length: 4,
      initialIndex: initialIndex,
      vsync: this,
    ); // Changed from 3 to 4
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _ensureBranchId();
    await Future.wait([
      _loadRequests(),
      _loadPresentEmployees(),
      _loadDailyAttendanceRows(),
    ]);
    _setupRealtimeSubscription();
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
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
    _attendanceSearchController.dispose();
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
      final employees =
          await SupabaseBranchService.getCurrentlyPresentEmployees(
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

  String _dateKey(DateTime value) {
    return DateFormat('yyyy-MM-dd').format(value);
  }

  Future<void> _loadDailyAttendanceRows() async {
    setState(() {
      _loadingAttendance = true;
      _attendanceError = null;
    });

    try {
      final employees = await ManagerAttendanceAdminService.getBranchEmployees(
        managerId: widget.managerId,
        branchName: widget.branchName,
      );

      final dateKey = _dateKey(_selectedAttendanceDate);
      final month = DateTime(
        _selectedAttendanceDate.year,
        _selectedAttendanceDate.month,
      );

      final rows = await Future.wait(
        employees.map((employee) async {
          final employeeId = employee['id']?.toString() ?? '';
          if (employeeId.isEmpty) {
            return {
              ...employee,
              'employee_id': '',
              'date': dateKey,
              'status': 'none',
              'check_in_time': null,
              'check_out_time': null,
              'has_record': false,
            };
          }

          Map<String, dynamic>? targetDay;
          String status = 'absent';
          String? checkInTime;
          String? checkOutTime;
          double totalHours = 0;

          try {
            final monthly =
                await ManagerAttendanceAdminService.getMonthlyAttendance(
                  managerId: widget.managerId,
                  branchName: widget.branchName,
                  employeeId: employeeId,
                  month: month,
                );

            final days = _asMapList(monthly['days']);
            for (final day in days) {
              if (day['date']?.toString() == dateKey) {
                targetDay = day;
                break;
              }
            }

            checkInTime = targetDay?['check_in_time']?.toString();
            checkOutTime = targetDay?['check_out_time']?.toString();
            totalHours = (targetDay?['total_hours'] as num?)?.toDouble() ?? 0;

            final dayStatus = targetDay?['status']?.toString();
            if (dayStatus != null && dayStatus.isNotEmpty) {
              status = dayStatus;
            } else if ((checkInTime ?? '').isNotEmpty) {
              status = 'present';
            }
          } catch (_) {
            // Keep fallback status for this employee to avoid failing whole list.
          }

          return {
            ...employee,
            'employee_id': employeeId,
            'date': dateKey,
            'status': status,
            'check_in_time': checkInTime,
            'check_out_time': checkOutTime,
            'total_hours': totalHours,
            'has_record': targetDay != null,
          };
        }),
      );

      rows.sort((a, b) {
        return _compareByName(a, b);
      });

      final firstBranchId = employees.isNotEmpty
          ? employees.first['branch_id']?.toString()
          : null;

      setState(() {
        _dailyAttendanceRows = rows;
        if ((_branchId == null || _branchId!.isEmpty) &&
            firstBranchId != null &&
            firstBranchId.isNotEmpty) {
          _branchId = firstBranchId;
        }
        _loadingAttendance = false;
      });
    } catch (e) {
      setState(() {
        _attendanceError = e.toString();
        _loadingAttendance = false;
      });
    }
  }

  TimeOfDay? _parseTime(String? text) {
    if (text == null || text.trim().isEmpty) {
      return null;
    }

    final trimmed = text.trim();
    final direct = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(trimmed);

    if (direct != null) {
      final hour = int.tryParse(direct.group(1) ?? '');
      final minute = int.tryParse(direct.group(2) ?? '');

      if (hour != null &&
          minute != null &&
          hour >= 0 &&
          hour <= 23 &&
          minute >= 0 &&
          minute <= 59) {
        return TimeOfDay(hour: hour, minute: minute);
      }
    }

    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) return null;

    final local = parsed.toLocal();
    return TimeOfDay(hour: local.hour, minute: local.minute);
  }

  String _timeText(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _displayTime(String? text) {
    final parsed = _parseTime(text);
    if (parsed == null) return '--';
    return _timeText(parsed);
  }

  int _timeToMinutes(TimeOfDay time) {
    return (time.hour * 60) + time.minute;
  }

  Future<void> _pickAttendanceDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedAttendanceDate,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );

    if (picked == null) return;

    setState(() {
      _selectedAttendanceDate = DateTime(picked.year, picked.month, picked.day);
    });
    await _loadDailyAttendanceRows();
  }

  Future<void> _editAttendanceTimes(Map<String, dynamic> row) async {
    final employeeId = row['employee_id']?.toString() ?? '';
    if (employeeId.isEmpty) return;

    final date = _dateKey(_selectedAttendanceDate);
    final employeeName = row['full_name']?.toString() ?? 'الموظف';

    TimeOfDay checkIn =
        _parseTime(row['check_in_time']?.toString()) ??
        _parseTime(row['shift_start_time']?.toString()) ??
        const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay checkOut =
        _parseTime(row['check_out_time']?.toString()) ??
        _parseTime(row['shift_end_time']?.toString()) ??
        const TimeOfDay(hour: 17, minute: 0);

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('تعديل حضور $employeeName'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'التاريخ: $date',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.login, color: AppColors.success),
                    title: const Text('وقت الحضور'),
                    subtitle: Text(_timeText(checkIn)),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: dialogContext,
                        initialTime: checkIn,
                      );
                      if (picked != null) {
                        setDialogState(() {
                          checkIn = picked;
                        });
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.logout, color: AppColors.error),
                    title: const Text('وقت الانصراف'),
                    subtitle: Text(_timeText(checkOut)),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: dialogContext,
                        initialTime: checkOut,
                      );
                      if (picked != null) {
                        setDialogState(() {
                          checkOut = picked;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_timeToMinutes(checkOut) <= _timeToMinutes(checkIn)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'وقت الانصراف لازم يكون بعد وقت الحضور',
                          ),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      return;
                    }

                    Navigator.pop(dialogContext, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSave != true) return;

    setState(() => _processingAttendance = true);
    try {
      await ManagerAttendanceAdminService.updateDayTimes(
        managerId: widget.managerId,
        branchName: widget.branchName,
        employeeId: employeeId,
        date: date,
        checkInTime: _timeText(checkIn),
        checkOutTime: _timeText(checkOut),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم حفظ وقت الحضور والانصراف'),
          backgroundColor: AppColors.success,
        ),
      );

      await Future.wait([_loadDailyAttendanceRows(), _loadPresentEmployees()]);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processingAttendance = false);
      }
    }
  }

  Future<void> _clearEmployeeDay(Map<String, dynamic> row) async {
    final employeeId = row['employee_id']?.toString() ?? '';
    if (employeeId.isEmpty) return;

    final hasCheckIn =
        (row['check_in_time']?.toString().trim() ?? '').isNotEmpty;
    final hasCheckOut =
        (row['check_out_time']?.toString().trim() ?? '').isNotEmpty;
    final hasRecord = row['has_record'] == true;

    if (!hasCheckIn && !hasCheckOut && !hasRecord) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد بيانات حضور مسجلة لهذا اليوم')),
      );
      return;
    }

    final date = _dateKey(_selectedAttendanceDate);
    final employeeName = row['full_name']?.toString() ?? 'الموظف';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مسح حضور اليوم'),
        content: Text(
          'هيمسح كل بيانات الحضور لـ $employeeName بتاريخ $date.\n\nمتأكد؟',
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
            child: const Text('مسح'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processingAttendance = true);
    try {
      await ManagerAttendanceAdminService.deleteDay(
        managerId: widget.managerId,
        branchName: widget.branchName,
        employeeId: employeeId,
        date: date,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم مسح حضور اليوم'),
          backgroundColor: AppColors.success,
        ),
      );

      await Future.wait([_loadDailyAttendanceRows(), _loadPresentEmployees()]);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processingAttendance = false);
      }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تنفيذ العملية بنجاح')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('لوحة المدير - ${widget.branchName}'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.75),
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.assignment_turned_in), text: 'الطلبات'),
            Tab(icon: Icon(Icons.warning_amber_rounded), text: 'الغياب'),
            Tab(icon: Icon(Icons.groups_2), text: 'المتواجدون الآن'),
            Tab(icon: Icon(Icons.fact_check_outlined), text: 'حضور الموظفين'),
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
                _loadDailyAttendanceRows(),
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
        _buildQuickStatsRow(),
        const SizedBox(height: 12),
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

  Widget _buildQuickStatsRow() {
    final totalPending =
        _leaveRequests
            .where((r) => (r['status'] ?? '').toString() == 'pending')
            .length +
        _advanceRequests
            .where((r) => (r['status'] ?? '').toString() == 'pending')
            .length +
        _attendanceRequests
            .where((r) => (r['status'] ?? '').toString() == 'pending')
            .length +
        _breakRequests
            .where((r) => (r['status'] ?? '').toString() == 'pending')
            .length;

    return Card(
      elevation: 0,
      color: const Color(0xFFFFF3EB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFFFDEC9)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.insights_rounded, color: AppColors.primaryOrange),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'طلبات تحتاج قرار: $totalPending',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryOrange,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _requestsFilter == 'all'
                    ? 'كل الحالات'
                    : 'تصفية: $_requestsFilter',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> req, String type) {
    final String typeLabel = switch (type) {
      'leave' => 'إجازة',
      'advance' => 'سلفة',
      'attendance' => 'حضور',
      'break' => 'استراحة',
      _ => 'طلب',
    };
    final IconData typeIcon = switch (type) {
      'leave' => Icons.beach_access,
      'advance' => Icons.payments,
      'attendance' => Icons.calendar_today,
      'break' => Icons.free_breakfast,
      _ => Icons.assignment,
    };

    final employee = req['employees'] ?? req['employee'];
    final employeeName = (employee is Map)
        ? (employee['full_name'] ?? '')
        : (req['employeeName'] ?? '');
    final status = (req['status'] ?? 'pending')
        .toString()
        .toLowerCase(); // Normalize to lowercase
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
                    Text(
                      'طلب $typeLabel',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                _statusChip(status),
              ],
            ),
            const Divider(),
            Text('الموظف: $employeeName'),
            if (branch.toString().isNotEmpty || role.toString().isNotEmpty)
              Text(
                'الفرع: ${branch.isEmpty ? '—' : branch} • الدور: ${role.isEmpty ? '—' : role}',
              ),
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
              Text(
                'نوع الطلب: ${req['request_type'] ?? req['requestType'] ?? '-'}',
              ),
              if ((req['requested_time'] ?? req['requestedTime']) != null)
                Text(
                  'الوقت المطلوب: ${req['requested_time'] ?? req['requestedTime']}',
                ),
              if ((req['reason'] ?? '').toString().isNotEmpty)
                Text('السبب: ${req['reason']}'),
            ],
            if (type == 'break') ...[
              Text(
                'المدة المطلوبة: ${req['requested_duration_minutes'] ?? req['duration_minutes'] ?? req['requestedDurationMinutes'] ?? req['durationMinutes'] ?? '-'} دقيقة',
              ),
              Text(
                'تاريخ الطلب: ${req['created_at'] ?? req['createdAt'] ?? '-'}',
              ),
            ],
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _actOnRequest(type, req['id'] as String, 'approve'),
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
                      onPressed: () =>
                          _actOnRequest(type, req['id'] as String, 'reject'),
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
                  onPressed: () =>
                      _actOnRequest(type, req['id'] as String, 'postpone'),
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
              Text(
                'يمكن للموظف بدء الاستراحة الآن',
                style: const TextStyle(color: AppColors.primaryOrange),
              ),
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
    return ManagerAbsencesPage(
      managerId: widget.managerId,
      branchId: _branchId!,
    );
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
        final shift =
            '${emp?['shift_start_time'] ?? '--'} - ${emp?['shift_end_time'] ?? '--'}';
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.success.withOpacity(0.12),
              child: const Icon(Icons.person, color: AppColors.success),
            ),
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'دخول: ${_displayTime(checkIn)}  •  شيفت: $shift',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(
              Icons.verified_rounded,
              color: AppColors.success,
            ),
          ),
        );
      },
    );
  }

  String _attendanceStatusLabel(String status) {
    switch (status) {
      case 'present':
        return 'حاضر';
      case 'active':
        return 'داخل ولم ينصرف';
      case 'on_leave':
        return 'إجازة';
      case 'absent':
        return 'غائب';
      case 'checked_out':
      case 'completed':
        return 'أتم اليوم';
      case 'none':
        return 'لا يوجد تسجيل';
      default:
        return 'غير محدد';
    }
  }

  Color _attendanceStatusColor(String status) {
    switch (status) {
      case 'present':
        return AppColors.success;
      case 'active':
        return Colors.blue;
      case 'on_leave':
        return Colors.indigo;
      case 'absent':
        return AppColors.error;
      case 'checked_out':
      case 'completed':
        return Colors.teal;
      case 'none':
        return AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  String _normalizedAttendanceStatus(Map<String, dynamic> row) {
    final raw = row['status']?.toString().trim().toLowerCase() ?? '';
    final hasCheckIn =
        (row['check_in_time']?.toString().trim() ?? '').isNotEmpty;

    if (raw == 'completed' || raw == 'checked_out') {
      return 'present';
    }

    if (raw.isEmpty || raw == 'none') {
      return hasCheckIn ? 'present' : 'absent';
    }

    return raw;
  }

  bool _isRowPresent(Map<String, dynamic> row) {
    final status = _normalizedAttendanceStatus(row);
    if (status == 'present' || status == 'active') {
      return true;
    }

    final checkIn = row['check_in_time']?.toString() ?? '';
    return checkIn.isNotEmpty;
  }

  bool _matchesAttendanceStatusFilter(Map<String, dynamic> row) {
    if (_attendanceStatusFilter == 'all') return true;

    final normalized = _normalizedAttendanceStatus(row);
    if (_attendanceStatusFilter == 'present') {
      return _isRowPresent(row);
    }
    return normalized == _attendanceStatusFilter;
  }

  bool _matchesAttendanceSearch(Map<String, dynamic> row) {
    final query = _attendanceSearch.trim().toLowerCase();
    if (query.isEmpty) return true;

    final name = row['full_name']?.toString().toLowerCase() ?? '';
    final role = row['role']?.toString().toLowerCase() ?? '';
    final employeeId = row['employee_id']?.toString().toLowerCase() ?? '';
    final shiftStart = row['shift_start_time']?.toString().toLowerCase() ?? '';

    return name.contains(query) ||
        role.contains(query) ||
        employeeId.contains(query) ||
        shiftStart.contains(query);
  }

  List<Map<String, dynamic>> _filteredAttendanceRows() {
    final filtered = _dailyAttendanceRows
        .where(_matchesAttendanceStatusFilter)
        .where(_matchesAttendanceSearch)
        .toList(growable: false);

    filtered.sort(_compareAttendanceRows);
    return filtered;
  }

  int _statusRank(Map<String, dynamic> row) {
    final normalized = _normalizedAttendanceStatus(row);
    switch (normalized) {
      case 'active':
        return 0;
      case 'present':
        return 1;
      case 'on_leave':
        return 2;
      case 'absent':
        return 3;
      default:
        return 4;
    }
  }

  int _compareByName(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aName = a['full_name']?.toString() ?? '';
    final bName = b['full_name']?.toString() ?? '';
    return aName.compareTo(bName);
  }

  int _compareByCheckIn(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aCheckIn = _parseTime(a['check_in_time']?.toString());
    final bCheckIn = _parseTime(b['check_in_time']?.toString());

    if (aCheckIn == null && bCheckIn == null) {
      return _compareByName(a, b);
    }
    if (aCheckIn == null) return 1;
    if (bCheckIn == null) return -1;

    final aMinutes = _timeToMinutes(aCheckIn);
    final bMinutes = _timeToMinutes(bCheckIn);

    if (aMinutes != bMinutes) {
      return aMinutes.compareTo(bMinutes);
    }

    return _compareByName(a, b);
  }

  int _compareAttendanceRows(Map<String, dynamic> a, Map<String, dynamic> b) {
    switch (_attendanceSort) {
      case 'name':
        return _compareByName(a, b);
      case 'check_in':
        return _compareByCheckIn(a, b);
      default:
        final statusCompare = _statusRank(a).compareTo(_statusRank(b));
        if (statusCompare != 0) return statusCompare;
        return _compareByName(a, b);
    }
  }

  Widget _buildAttendanceFilterChip({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final selected = _attendanceStatusFilter == value;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) {
        setState(() {
          _attendanceStatusFilter = value;
        });
      },
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? Colors.white : AppColors.textSecondary,
      ),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.textPrimary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      backgroundColor: Colors.white,
      selectedColor: AppColors.primaryOrange,
      side: BorderSide(
        color: selected ? AppColors.primaryOrange : const Color(0xFFE6E6E6),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }

  Widget _buildMetricBox({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      width: 112,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyAttendanceCard(Map<String, dynamic> row) {
    final name = row['full_name']?.toString() ?? 'غير معروف';
    final role = row['role']?.toString() ?? '';
    final checkIn = _displayTime(row['check_in_time']?.toString());
    final checkOut = _displayTime(row['check_out_time']?.toString());
    final shiftStart = row['shift_start_time']?.toString() ?? '--';
    final shiftEnd = row['shift_end_time']?.toString() ?? '--';
    final status = _normalizedAttendanceStatus(row);
    final statusColor = _attendanceStatusColor(status);
    final totalHours = (row['total_hours'] as num?)?.toDouble() ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor.withOpacity(0.12),
                  child: Text(
                    name.isNotEmpty ? name.characters.first : '؟',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'شيفت: $shiftStart - $shiftEnd${role.isNotEmpty ? '  •  $role' : ''}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _attendanceStatusLabel(status),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFFAF4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.login,
                        size: 16,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 6),
                      Text('دخول: $checkIn'),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.logout,
                        size: 16,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 6),
                      Text('انصراف: $checkOut'),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF4FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, size: 16, color: Colors.blue),
                      const SizedBox(width: 6),
                      Text('الساعات: ${totalHours.toStringAsFixed(1)}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _processingAttendance
                      ? null
                      : () => _editAttendanceTimes(row),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  label: Text(
                    _isRowPresent(row) ? 'تعديل الوقت' : 'إضافة حضور',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _processingAttendance
                      ? null
                      : () => _clearEmployeeDay(row),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('مسح اليوم'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyAttendancePage() {
    if (_loadingAttendance) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_attendanceError != null) {
      return _errorState(_attendanceError!, onRetry: _loadDailyAttendanceRows);
    }

    final filteredRows = _filteredAttendanceRows();
    final total = _dailyAttendanceRows.length;
    final present = _dailyAttendanceRows.where(_isRowPresent).length;
    final absent = total - present;
    final visiblePresent = filteredRows.where(_isRowPresent).length;
    final visibleAbsent = filteredRows.length - visiblePresent;
    final formattedDate = DateFormat(
      'EEEE، d MMMM yyyy',
      'ar',
    ).format(_selectedAttendanceDate);

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _loadDailyAttendanceRows(),
          _loadPresentEmployees(),
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: const Color(0xFFFFF4EC),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFFFDEC9)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_month,
                        color: AppColors.primaryOrange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          formattedDate,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _loadingAttendance
                            ? null
                            : _pickAttendanceDate,
                        icon: const Icon(Icons.edit_calendar, size: 18),
                        label: const Text('تغيير اليوم'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildMetricBox(
                          label: 'كل الموظفين',
                          value: '$total',
                          color: AppColors.info,
                          icon: Icons.group,
                        ),
                        const SizedBox(width: 8),
                        _buildMetricBox(
                          label: 'حاضرين',
                          value: '$present',
                          color: AppColors.success,
                          icon: Icons.check_circle,
                        ),
                        const SizedBox(width: 8),
                        _buildMetricBox(
                          label: 'غائبين',
                          value: '$absent',
                          color: AppColors.error,
                          icon: Icons.person_off,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFF0F0F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _attendanceSearchController,
                    onChanged: (value) {
                      setState(() {
                        _attendanceSearch = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'بحث بالاسم أو الدور أو رقم الموظف',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _attendanceSearch.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _attendanceSearchController.clear();
                                setState(() {
                                  _attendanceSearch = '';
                                });
                              },
                              icon: const Icon(Icons.close),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildAttendanceFilterChip(
                        value: 'all',
                        label: 'الكل',
                        icon: Icons.apps,
                      ),
                      _buildAttendanceFilterChip(
                        value: 'present',
                        label: 'حاضرين',
                        icon: Icons.check_circle,
                      ),
                      _buildAttendanceFilterChip(
                        value: 'active',
                        label: 'داخل الآن',
                        icon: Icons.login,
                      ),
                      _buildAttendanceFilterChip(
                        value: 'on_leave',
                        label: 'إجازة',
                        icon: Icons.beach_access,
                      ),
                      _buildAttendanceFilterChip(
                        value: 'absent',
                        label: 'غائبين',
                        icon: Icons.person_off,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _attendanceSort,
                    decoration: InputDecoration(
                      labelText: 'ترتيب الجدول',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'status',
                        child: Text('الحاضرين أولاً ثم الاسم'),
                      ),
                      DropdownMenuItem(
                        value: 'name',
                        child: Text('الاسم (أ - ي)'),
                      ),
                      DropdownMenuItem(
                        value: 'check_in',
                        child: Text('وقت الحضور (الأبكر أولاً)'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _attendanceSort = value;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'المعروض: ${filteredRows.length} من $total  •  حاضر: $visiblePresent  •  غائب: $visibleAbsent',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_dailyAttendanceRows.isEmpty)
            _emptyHint('لا يوجد موظفون في هذا الفرع')
          else if (filteredRows.isEmpty)
            _emptyHint('لا توجد نتائج مطابقة للبحث أو التصفية')
          else
            ...filteredRows.map(_buildDailyAttendanceCard),
        ],
      ),
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
