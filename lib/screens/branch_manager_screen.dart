import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';
import '../services/branch_manager_api_service.dart';
import '../services/manager_pending_requests_service.dart';
import '../services/offline_data_service.dart';
import '../services/sync_service.dart';
import '../database/offline_database.dart';
import '../config/supabase_config.dart';
import '../utils/time_utils.dart';
import 'manager/manager_absences_page.dart';
import 'manager/manager_dashboard_simple.dart';
import 'manager/manager_daily_attendance_page.dart';
import 'manager/manager_penalties_page.dart';

class BranchManagerScreen extends StatefulWidget {
  final String managerId;
  final String branchName;
  const BranchManagerScreen({
    super.key,
    required this.managerId,
    required this.branchName,
  });

  @override
  State<BranchManagerScreen> createState() => _BranchManagerScreenState();
}

class _BranchManagerScreenState extends State<BranchManagerScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _requests;
  Map<String, dynamic>? _attendanceReport;
  Map<String, dynamic>? _pulseSummary;
  late TabController _tabController;
  String _filterStatus = 'all'; // all, pending, approved, rejected
  String? _branchId;
  int _pendingCount = 0;
  final OfflineDataService _offlineService = OfflineDataService();
  final SyncService _syncService = SyncService.instance;
  final _supabase = SupabaseConfig.client;
  RealtimeChannel? _requestsChannel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _downloadBranchData();
    _loadPendingCount();
    _syncService.startPeriodicSync();
    _fetchData();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _requestsChannel?.unsubscribe();
    _tabController.dispose();
    _syncService.stopPeriodicSync();
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    print(
      '🔔 Setting up realtime subscription for manager: ${widget.managerId}',
    );

    // Subscribe to all request tables for this manager's branch employees
    _requestsChannel = _supabase
        .channel('manager_requests_${widget.managerId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'leave_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'assigned_manager_id',
            value: widget.managerId,
          ),
          callback: (payload) {
            print('🔔 Leave request changed: ${payload.eventType}');
            _fetchData();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'salary_advances',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'assigned_manager_id',
            value: widget.managerId,
          ),
          callback: (payload) {
            print('🔔 Salary advance changed: ${payload.eventType}');
            _fetchData();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'assigned_manager_id',
            value: widget.managerId,
          ),
          callback: (payload) {
            print('🔔 Attendance request changed: ${payload.eventType}');
            _fetchData();
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            print('✅ Realtime subscription active for manager requests');
          } else if (error != null) {
            print('❌ Realtime subscription error: $error');
          }
        });
  }

  Future<void> _downloadBranchData() async {
    try {
      await _offlineService.downloadBranchData(
        widget.branchName,
        employeeId: widget.managerId,
      );
      print('✅ تم تنزيل بيانات الفرع للمدير');
    } catch (e) {
      print('❌ فشل تنزيل بيانات الفرع: $e');
    }
  }

  Future<void> _loadPendingCount() async {
    try {
      final db = OfflineDatabase.instance;
      final count = await db.getPendingCount();
      if (mounted) {
        setState(() {
          _pendingCount = count;
        });
      }
    } catch (e) {
      print('❌ Error loading pending count: $e');
    }
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Use the new Edge Function for pending requests aggregation
      final pendingReqs =
          await ManagerPendingRequestsService.getAllPendingRequests(
            widget.managerId,
          );
      final report = await BranchManagerApiService.getAttendanceReport(
        widget.branchName,
      );
      final pulses = await BranchManagerApiService.getBranchPulseSummary(
        widget.branchName,
      );

      print('🔍 [DEBUG] Manager Pending Requests API response:');
      print(pendingReqs);
      print('🔍 [DEBUG] Attendance Report API response:');
      print(report);
      print('🔍 [DEBUG] Pulse Summary API response:');
      print(pulses);

      setState(() {
        _requests = pendingReqs;
        _attendanceReport = report;
        _pulseSummary = pulses;
        _branchId = (pulses['branch'] is Map<String, dynamic>)
            ? (pulses['branch']['id'] as String?)
            : _branchId;
        _loading = false;
      });
      await _loadPendingCount();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _pulseSummary = null;
        _loading = false;
      });
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
      await _fetchData();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم تنفيذ العملية بنجاح')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _actOnAbsence(
    Map<String, dynamic> alert, {
    required bool applyDeduction,
  }) async {
    try {
      if (applyDeduction) {
        // Apply deduction - use the branch-request-action endpoint
        await BranchManagerApiService.actOnRequest(
          type: 'absence',
          id: alert['id'],
          action: 'approve', // This will trigger deduction
          managerId: widget.managerId,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تم تطبيق خصم الغياب'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        // No deduction - excuse the absence
        await BranchManagerApiService.actOnRequest(
          type: 'absence',
          id: alert['id'],
          action: 'reject', // This will excuse without deduction
          managerId: widget.managerId,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تم قبول عذر الغياب بدون خصم'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      await _fetchData();
    } catch (e) {
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
        title: Text('لوحة مدير الفرع (${widget.branchName})'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'إدارة المدير',
            onSelected: (value) {
              if (value == 'penalties') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ManagerPenaltiesPage(
                      managerId: widget.managerId,
                      branchName: widget.branchName,
                    ),
                  ),
                ).then((_) => _fetchData());
                return;
              }

              if (value == 'daily_attendance') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ManagerDailyAttendancePage(
                      managerId: widget.managerId,
                      branchName: widget.branchName,
                    ),
                  ),
                ).then((_) => _fetchData());
                return;
              }

              if (value == 'daily_verification') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ManagerDashboardSimple(
                      managerId: widget.managerId,
                      branchName: widget.branchName,
                      initialTabIndex: 3,
                    ),
                  ),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'penalties', child: Text('إدارة الجزاءات')),
              PopupMenuItem(
                value: 'daily_attendance',
                child: Text('جدول الحضور اليومي'),
              ),
              PopupMenuItem(
                value: 'daily_verification',
                child: Text('التحقق اليومي (الواجهة القديمة)'),
              ),
            ],
            icon: const Icon(Icons.tune),
          ),
          if (_pendingCount > 0)
            IconButton(
              icon: Badge(
                label: Text('$_pendingCount'),
                child: const Icon(Icons.cloud_upload),
              ),
              onPressed: () async {
                final result = await _syncService.syncPendingData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result['message'] ?? 'تم'),
                      backgroundColor: result['success']
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  );
                  await _loadPendingCount();
                }
              },
              tooltip: 'رفع البيانات المعلقة',
            ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'تصفية',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
            tooltip: 'تحديث',
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
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _fetchData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryOrange,
                    ),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (_pulseSummary != null) _buildPulseHighlights(),
                _buildStatisticsCards(),
                _buildTabBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildRequestsTab(),
                      _buildPulseTab(),
                      _buildAttendanceTab(),
                      _buildAbsenceTab(),
                      _buildBreaksTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryOrange,
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تصفية الطلبات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('كل الطلبات'),
              leading: Radio<String>(
                value: 'all',
                groupValue: _filterStatus,
                onChanged: (value) {
                  setState(() => _filterStatus = value!);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('قيد الانتظار'),
              leading: Radio<String>(
                value: 'pending',
                groupValue: _filterStatus,
                onChanged: (value) {
                  setState(() => _filterStatus = value!);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('موافق عليها'),
              leading: Radio<String>(
                value: 'approved',
                groupValue: _filterStatus,
                onChanged: (value) {
                  setState(() => _filterStatus = value!);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('مرفوضة'),
              leading: Radio<String>(
                value: 'rejected',
                groupValue: _filterStatus,
                onChanged: (value) {
                  setState(() => _filterStatus = value!);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCards() {
    if (_requests == null) return const SizedBox();
    final leave = (_requests!['leaveRequests'] as List? ?? [])
        .where((r) => r['status'] == 'pending')
        .length;
    final advance = (_requests!['advanceRequests'] as List? ?? [])
        .where((r) => r['status'] == 'pending')
        .length;
    final attendance = (_requests!['attendanceRequests'] as List? ?? [])
        .where((r) => r['status'] == 'pending')
        .length;
    final absence = (_requests!['absenceNotifications'] as List? ?? []).length;

    return Container(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 800 ? 4 : 2;
          return GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildStatCard(
                'طلبات الإجازة',
                leave.toString(),
                Icons.beach_access,
                AppColors.primaryOrange,
              ),
              _buildStatCard(
                'طلبات السلف',
                advance.toString(),
                Icons.payments,
                Colors.green,
              ),
              _buildStatCard(
                'طلبات الحضور',
                attendance.toString(),
                Icons.calendar_today,
                Colors.blue,
              ),
              _buildStatCard(
                'تنبيهات الغياب',
                absence.toString(),
                Icons.warning,
                AppColors.error,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    // Check if this is the absence card
    final isAbsenceCard = title == 'تنبيهات الغياب';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: isAbsenceCard
            ? () {
                // Navigate to absences page
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ManagerAbsencesPage(
                      managerId: widget.managerId,
                      branchId: _branchId ?? '',
                    ),
                  ),
                ).then((_) => _fetchData()); // Refresh when coming back
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              if (isAbsenceCard &&
                  int.tryParse(value) != null &&
                  int.parse(value) > 0)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primaryOrange,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primaryOrange,
        tabs: const [
          Tab(icon: Icon(Icons.assignment), text: 'الطلبات'),
          Tab(icon: Icon(Icons.favorite), text: 'النبضات'),
          Tab(icon: Icon(Icons.people), text: 'الحضور'),
          Tab(icon: Icon(Icons.warning), text: 'الغياب'),
          Tab(icon: Icon(Icons.free_breakfast), text: 'الاستراحات'),
        ],
      ),
    );
  }

  Widget _buildPulseHighlights() {
    final summary = _pulseSummary?['summary'] as Map<String, dynamic>?;
    if (summary == null) {
      return const SizedBox.shrink();
    }

    final numberFormat = NumberFormat('#,##0', 'ar');
    final currencyFormat = NumberFormat.currency(
      locale: 'ar',
      symbol: 'ج.م',
      decimalDigits: 2,
    );

    final totalValid = numberFormat.format(_asNum(summary['totalValidPulses']));
    final totalEarnings = currencyFormat.format(
      _asDouble(summary['totalEarnings']),
    );
    final activeCount = _asNum(summary['activeEmployeeCount']).toInt();
    final employeeCount = _asNum(summary['employeeCount']).toInt();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _buildSummaryMetric(
                icon: Icons.favorite,
                title: 'النبضات الصحيحة',
                value: totalValid,
                color: Colors.pink,
                width: 160,
              ),
              _buildSummaryMetric(
                icon: Icons.payments,
                title: 'إجمالي الأرباح',
                value: totalEarnings,
                color: Colors.green,
                width: 160,
              ),
              _buildSummaryMetric(
                icon: Icons.person_pin_circle,
                title: 'المتواجدون الآن',
                value: '$activeCount / $employeeCount',
                color: Colors.indigo,
                width: 160,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPulseTab() {
    if (_pulseSummary == null) {
      return const Center(
        child: Text(
          'لا توجد بيانات نبضات',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final summary = _pulseSummary!['summary'] as Map<String, dynamic>? ?? {};
    final employees =
        (_pulseSummary!['employees'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle('ملخص النبضات'),
        _buildPulseSummaryCard(summary),
        const SizedBox(height: 24),
        _buildSectionTitle('أداء الموظفين'),
        if (employees.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'لا يوجد نبضات في الفترة المحددة',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          ...employees.map((employee) => _buildPulseEmployeeCard(employee)),
      ],
    );
  }

  Widget _buildPulseSummaryCard(Map<String, dynamic> summary) {
    final numberFormat = NumberFormat('#,##0', 'ar');
    final currencyFormat = NumberFormat.currency(
      locale: 'ar',
      symbol: 'ج.م',
      decimalDigits: 2,
    );

    final totalPulses = numberFormat.format(_asNum(summary['totalPulses']));
    final validPulses = numberFormat.format(
      _asNum(summary['totalValidPulses']),
    );
    final invalidPulses = numberFormat.format(
      _asNum(summary['totalInvalidPulses']),
    );
    final averageEarnings = currencyFormat.format(
      _asDouble(summary['averageEarningsPerEmployee']),
    );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _buildSummaryMetric(
              icon: Icons.timelapse,
              title: 'إجمالي النبضات',
              value: totalPulses,
              color: Colors.blueGrey,
              width: 160,
            ),
            _buildSummaryMetric(
              icon: Icons.favorite,
              title: 'نبضات مقبولة',
              value: validPulses,
              color: Colors.pink,
              width: 160,
            ),
            _buildSummaryMetric(
              icon: Icons.favorite_border,
              title: 'نبضات مرفوضة',
              value: invalidPulses,
              color: Colors.orange,
              width: 160,
            ),
            _buildSummaryMetric(
              icon: Icons.trending_up,
              title: 'متوسط الأرباح للفرد',
              value: averageEarnings,
              color: Colors.green,
              width: 160,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPulseEmployeeCard(Map<String, dynamic> employee) {
    final numberFormat = NumberFormat('#,##0', 'ar');
    final currencyFormat = NumberFormat.currency(
      locale: 'ar',
      symbol: 'ج.م',
      decimalDigits: 2,
    );

    final fullName = employee['fullName'] as String? ?? 'غير معروف';
    final validPulses = numberFormat.format(_asNum(employee['validPulses']));
    final invalidPulses = numberFormat.format(
      _asNum(employee['invalidPulses']),
    );
    final totalPulses = numberFormat.format(_asNum(employee['totalPulses']));
    final earnings = currencyFormat.format(_asDouble(employee['earnings']));
    final isCheckedIn = employee['isCheckedIn'] == true;
    final checkIn = _formatPulseDate(employee['checkInTime']);

    final firstPulse = _formatPulseDate(employee['firstPulseAt']);
    final lastPulse = _formatPulseDate(employee['lastPulseAt']);

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
                Expanded(
                  child: Text(
                    fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Chip(
                  avatar: Icon(
                    isCheckedIn
                        ? Icons.check_circle
                        : Icons.remove_circle_outline,
                    size: 18,
                    color: isCheckedIn ? Colors.green : Colors.grey,
                  ),
                  label: Text(
                    isCheckedIn ? 'متواجد (${checkIn ?? '-'})' : 'غير متواجد',
                  ),
                  backgroundColor: isCheckedIn
                      ? Colors.green.withOpacity(0.12)
                      : Colors.grey.withOpacity(0.12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _buildSummaryMetric(
                  icon: Icons.favorite,
                  title: 'نبضات صحيحة',
                  value: validPulses,
                  color: Colors.pink,
                  width: 140,
                ),
                _buildSummaryMetric(
                  icon: Icons.favorite_border,
                  title: 'نبضات مرفوضة',
                  value: invalidPulses,
                  color: Colors.orange,
                  width: 140,
                ),
                _buildSummaryMetric(
                  icon: Icons.timelapse,
                  title: 'إجمالي النبضات',
                  value: totalPulses,
                  color: Colors.blueGrey,
                  width: 140,
                ),
                _buildSummaryMetric(
                  icon: Icons.payments,
                  title: 'الأرباح',
                  value: earnings,
                  color: Colors.green,
                  width: 140,
                ),
              ],
            ),
            if (firstPulse != null || lastPulse != null) ...[
              const SizedBox(height: 12),
              Text(
                'الفترة: ${firstPulse ?? '—'} → ${lastPulse ?? '—'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMetric({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    double width = 150,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  num _asNum(dynamic value) {
    if (value is num) return value;
    if (value is String) {
      return num.tryParse(value) ?? 0;
    }
    return 0;
  }

  double _asDouble(dynamic value) => _asNum(value).toDouble();

  String? _formatPulseDate(dynamic value) {
    if (value == null) return null;
    DateTime? parsed;
    if (value is DateTime) {
      parsed = value;
    } else if (value is String) {
      parsed = DateTime.tryParse(value);
    }
    if (parsed == null) {
      return null;
    }
    return DateFormat('dd/MM HH:mm', 'ar').format(parsed.toLocal());
  }

  Widget _buildRequestsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [_buildSectionTitle('طلبات الموظفين'), _buildRequestsList()],
    );
  }

  Widget _buildAttendanceTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle('طلبات الحضور والانصراف'),
        _buildAttendanceRequests(),
        const SizedBox(height: 24),
        _buildSectionTitle('تقرير الحضور اليومي'),
        _buildAttendanceReport(),
      ],
    );
  }

  Widget _buildAbsenceTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle('تنبيهات الغياب بدون إذن'),
        _buildAbsenceAlerts(),
      ],
    );
  }

  Widget _buildBreaksTab() {
    if (_requests == null) return const Center(child: Text('لا توجد بيانات'));
    // Try both keys: break_requests (from API) and breakRequests (legacy)
    final breaks =
        (_requests!['break_requests'] ?? _requests!['breakRequests'])
            as List? ??
        [];
    if (breaks.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد طلبات استراحة',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: breaks.length,
      itemBuilder: (context, index) {
        final breakReq = breaks[index];
        return _buildBreakCard(breakReq);
      },
    );
  }

  Widget _buildBreakCard(Map breakReq) {
    // Check status - can be PENDING, pending, or null/empty
    final breakStatus = (breakReq['status'] ?? '').toString();
    final showActions =
        breakStatus.isEmpty ||
        breakStatus.toLowerCase() == 'pending' ||
        breakStatus.toUpperCase() == 'PENDING';

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
                Expanded(
                  child: Text(
                    'الموظف: ${breakReq['employee']?['full_name'] ?? breakReq['employeeName'] ?? breakReq['employeeId'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Chip(
                  label: Text(_getStatusText(breakReq['status'] ?? 'PENDING')),
                  backgroundColor: _getStatusColor(breakReq['status']),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'مدة الاستراحة: ${breakReq['requestedDurationMinutes'] ?? breakReq['durationMinutes'] ?? breakReq['requested_duration_minutes'] ?? ''} دقيقة',
            ),
            Text(
              'تاريخ الطلب: ${breakReq['createdAt'] ?? breakReq['created_at'] ?? ''}',
            ),
            if (showActions) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _reviewBreakRequest(breakReq['id'], 'approve'),
                      icon: const Icon(Icons.check),
                      label: const Text('موافقة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _reviewBreakRequest(breakReq['id'], 'reject'),
                      icon: const Icon(Icons.close),
                      label: const Text('رفض'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _reviewBreakRequest(breakReq['id'], 'postpone'),
                      icon: const Icon(Icons.access_time),
                      label: const Text('تأجيل'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
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

  Color _getStatusColor(String? status) {
    final statusUpper = status?.toString().toUpperCase() ?? 'PENDING';
    switch (statusUpper) {
      case 'APPROVED':
        return AppColors.success.withOpacity(0.2);
      case 'REJECTED':
        return AppColors.error.withOpacity(0.2);
      case 'ACTIVE':
        return Colors.blue.withOpacity(0.2);
      case 'POSTPONED':
        return Colors.orange.withOpacity(0.2);
      case 'PENDING':
      default:
        return Colors.orange.withOpacity(0.2);
    }
  }

  Future<void> _reviewBreakRequest(String breakId, String action) async {
    try {
      await BranchManagerApiService.actOnRequest(
        type: 'break',
        id: breakId,
        action: action,
        managerId: widget.managerId,
      );
      await _fetchData();

      String actionText = action == 'approve'
          ? 'الموافقة على'
          : action == 'reject'
          ? 'رفض'
          : 'تأجيل';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم $actionText طلب الاستراحة'),
          backgroundColor: action == 'approve'
              ? AppColors.success
              : action == 'reject'
              ? AppColors.error
              : Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _getStatusText(String? status) {
    final statusUpper = status?.toString().toUpperCase() ?? 'PENDING';
    switch (statusUpper) {
      case 'APPROVED':
        return 'مقبول';
      case 'REJECTED':
        return 'مرفوض';
      case 'ACTIVE':
        return 'نشط';
      case 'POSTPONED':
        return 'مؤجل';
      case 'PENDING':
      default:
        return 'قيد الانتظار';
    }
  }

  Widget _buildRequestsList() {
    if (_requests == null) return const SizedBox();

    var leave = _requests!['leaveRequests'] as List? ?? [];
    var advance = _requests!['advanceRequests'] as List? ?? [];
    var attendance = _requests!['attendanceRequests'] as List? ?? [];

    // Apply filter
    if (_filterStatus != 'all') {
      leave = leave.where((r) => r['status'] == _filterStatus).toList();
      advance = advance.where((r) => r['status'] == _filterStatus).toList();
      attendance = attendance
          .where((r) => r['status'] == _filterStatus)
          .toList();
    }

    List<Widget> items = [];
    for (final req in leave) {
      items.add(_buildRequestCard(req, 'leave'));
    }
    for (final req in advance) {
      items.add(_buildRequestCard(req, 'advance'));
    }
    for (final req in attendance) {
      items.add(_buildRequestCard(req, 'attendance'));
    }

    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'لا يوجد طلبات حالياً',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    return Column(children: items);
  }

  Widget _buildRequestCard(Map req, String type) {
    final String typeLabel = type == 'leave'
        ? 'إجازة'
        : type == 'advance'
        ? 'سلفة'
        : 'حضور';
    final IconData typeIcon = type == 'leave'
        ? Icons.beach_access
        : type == 'advance'
        ? Icons.payments
        : Icons.calendar_today;

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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                Chip(
                  label: Text(_getStatusLabel(req['status'])),
                  backgroundColor: _getStatusColor(req['status']),
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const Divider(),
            Text(
              'الموظف: ${req['employeeId'] ?? ''}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            if (type == 'leave') ...[
              Text(
                'من: ${req['startDate'] ?? ''}',
                style: const TextStyle(fontSize: 14),
              ),
              Text(
                'إلى: ${req['endDate'] ?? ''}',
                style: const TextStyle(fontSize: 14),
              ),
              if (req['reason'] != null && req['reason'].toString().isNotEmpty)
                Text(
                  'السبب: ${req['reason']}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
            if (type == 'advance') ...[
              Text(
                'المبلغ: ${req['amount'] ?? ''} جنيه',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'تاريخ الطلب: ${req['requestDate'] ?? ''}',
                style: const TextStyle(fontSize: 14),
              ),
            ],
            if (type == 'attendance') ...[
              Text(
                'نوع الطلب: ${req['requestType'] ?? ''}',
                style: const TextStyle(fontSize: 14),
              ),
              if (req['reason'] != null && req['reason'].toString().isNotEmpty)
                Text(
                  'السبب: ${req['reason']}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
            if (req['status'] == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _actOnRequest(type, req['id'], 'approve'),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('موافقة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _actOnRequest(type, req['id'], 'reject'),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('رفض'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
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

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'approved':
        return 'موافق عليه';
      case 'rejected':
        return 'مرفوض';
      case 'pending':
      default:
        return 'قيد الانتظار';
    }
  }

  Widget _buildAttendanceRequests() {
    if (_requests == null) return const SizedBox();
    final attendanceReqs = _requests!['attendanceRequests'] as List? ?? [];

    if (attendanceReqs.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'لا توجد طلبات حضور/انصراف معلقة',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Column(
      children: attendanceReqs
          .map<Widget>((req) => _buildAttendanceRequestCard(req))
          .toList(),
    );
  }

  Widget _buildAttendanceRequestCard(Map req) {
    final isCheckIn = (req['requestType'] ?? 'check-in') == 'check-in';
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
                    Icon(
                      isCheckIn ? Icons.login : Icons.logout,
                      color: isCheckIn ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isCheckIn ? 'طلب حضور' : 'طلب انصراف',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                Chip(
                  label: Text(_getStatusLabel(req['status'])),
                  backgroundColor: _getStatusColor(req['status']),
                ),
              ],
            ),
            const Divider(),
            Text(
              'الموظف: ${req['employeeName'] ?? req['employeeId'] ?? ''}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'الوقت المطلوب: ${req['requestedTime'] ?? ''}',
              style: const TextStyle(fontSize: 14),
            ),
            if (req['reason'] != null &&
                req['reason'].toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'السبب: ${req['reason']}',
                style: const TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (req['status'] == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _reviewAttendanceRequest(req['id'], 'approve'),
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
                          _reviewAttendanceRequest(req['id'], 'reject'),
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
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _reviewAttendanceRequest(String requestId, String action) async {
    try {
      await BranchManagerApiService.reviewAttendanceRequest(
        requestId: requestId,
        action: action,
        reviewerId: widget.managerId,
      );
      await _fetchData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم ${action == 'approve' ? 'الموافقة على' : 'رفض'} طلب الحضور',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildAttendanceReport() {
    if (_attendanceReport == null) return const SizedBox();
    final report = _attendanceReport!['report'] as List? ?? [];
    if (report.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.people_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'لا يوجد حضور اليوم',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: report.map<Widget>((att) {
        final bool isPresent = att['checkInTime'] != null;
        final bool hasCheckedOut = att['checkOutTime'] != null;
        final checkInText = _formatAttendanceTime(att['checkInTime']);
        final checkOutText = _formatAttendanceTime(att['checkOutTime']);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isPresent ? AppColors.success : AppColors.error,
              child: Icon(
                isPresent ? Icons.check : Icons.close,
                color: Colors.white,
              ),
            ),
            title: Text(
              'الموظف: ${att['employeeId'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('دخول: $checkInText'),
                Text('خروج: $checkOutText'),
                if (att['workHours'] != null)
                  Text(
                    'ساعات العمل: ${att['workHours']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryOrange,
                    ),
                  ),
              ],
            ),
            trailing: hasCheckedOut
                ? const Icon(Icons.done_all, color: AppColors.success)
                : isPresent
                ? const Icon(Icons.access_time, color: Colors.orange)
                : null,
          ),
        );
      }).toList(),
    );
  }

  String _formatAttendanceTime(dynamic value) {
    if (value == null) return 'لم يحضر';

    final raw = value.toString().trim();
    if (raw.isEmpty || raw == '-' || raw == '--' || raw == 'null') {
      return 'لم يحضر';
    }

    final formatted = TimeUtils.formatTimeShort(raw);
    if (formatted == '-') return raw;
    return formatted;
  }

  Widget _buildAbsenceAlerts() {
    if (_requests == null) return const SizedBox();
    final absence = _requests!['absenceNotifications'] as List? ?? [];
    if (absence.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.sentiment_satisfied, size: 64, color: Colors.green),
              SizedBox(height: 16),
              Text(
                'لا يوجد تنبيهات غياب حالياً',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'جميع الموظفين ملتزمون',
                style: TextStyle(color: Colors.green, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: absence.map<Widget>((alert) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning, color: AppColors.error),
                    const SizedBox(width: 8),
                    const Text(
                      'تنبيه غياب بدون إذن',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
                const Divider(),
                Text(
                  'الموظف: ${alert['employee']?['full_name'] ?? alert['employeeId'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'تاريخ الغياب: ${alert['absenceDate'] ?? ''}',
                  style: const TextStyle(fontSize: 14),
                ),
                if (alert['deductionAmount'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'مبلغ الخصم: ${alert['deductionAmount']} جنيه',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _actOnAbsence(alert, applyDeduction: true),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('موافق - خصم'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _actOnAbsence(alert, applyDeduction: false),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('موافق - بدون خصم'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
