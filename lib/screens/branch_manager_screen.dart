import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/branch_manager_api_service.dart';
import 'manager/manager_absences_page.dart';


class BranchManagerScreen extends StatefulWidget {
  final String managerId;
  final String branchName;
  const BranchManagerScreen({super.key, required this.managerId, required this.branchName});

  @override
  State<BranchManagerScreen> createState() => _BranchManagerScreenState();
}

class _BranchManagerScreenState extends State<BranchManagerScreen> with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _requests;
  Map<String, dynamic>? _attendanceReport;
  late TabController _tabController;
  String _filterStatus = 'all'; // all, pending, approved, rejected

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final reqs = await BranchManagerApiService.getBranchRequests(widget.branchName);
      final report = await BranchManagerApiService.getAttendanceReport(widget.branchName);
      setState(() {
        _requests = reqs;
        _attendanceReport = report;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تنفيذ العملية بنجاح')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: ${e.toString()}'), backgroundColor: Colors.red));
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
                      const Icon(Icons.error_outline, size: 64, color: AppColors.error),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: AppColors.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchData,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _buildStatisticsCards(),
                    _buildTabBar(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildRequestsTab(),
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
    final leave = (_requests!['leaveRequests'] as List? ?? []).where((r) => r['status'] == 'pending').length;
    final advance = (_requests!['advanceRequests'] as List? ?? []).where((r) => r['status'] == 'pending').length;
    final attendance = (_requests!['attendanceRequests'] as List? ?? []).where((r) => r['status'] == 'pending').length;
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
              _buildStatCard('طلبات الإجازة', leave.toString(), Icons.beach_access, AppColors.primaryOrange),
              _buildStatCard('طلبات السلف', advance.toString(), Icons.payments, Colors.green),
              _buildStatCard('طلبات الحضور', attendance.toString(), Icons.calendar_today, Colors.blue),
              _buildStatCard('تنبيهات الغياب', absence.toString(), Icons.warning, AppColors.error),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    // Check if this is the absence card
    final isAbsenceCard = title == 'تنبيهات الغياب';
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: isAbsenceCard ? () {
          // Navigate to absences page
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ManagerAbsencesPage(
                managerId: widget.managerId,
                branchId: '', // TODO: Get actual branch ID
              ),
            ),
          ).then((_) => _fetchData()); // Refresh when coming back
        } : null,
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
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              if (isAbsenceCard && int.tryParse(value) != null && int.parse(value) > 0)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(Icons.arrow_forward, size: 16, color: AppColors.textSecondary),
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
          Tab(icon: Icon(Icons.people), text: 'الحضور'),
          Tab(icon: Icon(Icons.warning), text: 'الغياب'),
          Tab(icon: Icon(Icons.free_breakfast), text: 'الاستراحات'),
        ],
      ),
    );
  }

  Widget _buildRequestsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle('طلبات الموظفين'),
        _buildRequestsList(),
      ],
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
    final breaks = _requests!['breakRequests'] as List? ?? [];
    if (breaks.isEmpty) {
      return const Center(child: Text('لا توجد طلبات استراحة', style: TextStyle(color: Colors.grey)));
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
                Text(
                  'الموظف: ${breakReq['employeeName'] ?? breakReq['employeeId'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Chip(
                  label: Text(breakReq['status'] ?? 'PENDING'),
                  backgroundColor: _getStatusColor(breakReq['status']),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('مدة الاستراحة: ${breakReq['requestedDurationMinutes'] ?? breakReq['durationMinutes'] ?? ''} دقيقة'),
            Text('تاريخ الطلب: ${breakReq['createdAt'] ?? ''}'),
            if (breakReq['status'] == 'PENDING' || breakReq['status'] == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _reviewBreakRequest(breakReq['id'], 'approve'),
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
                      onPressed: () => _reviewBreakRequest(breakReq['id'], 'reject'),
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
                      onPressed: () => _reviewBreakRequest(breakReq['id'], 'postpone'),
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

  Future<void> _reviewBreakRequest(String breakId, String action) async {
    try {
      await BranchManagerApiService.reviewBreakRequest(
        breakId: breakId,
        action: action,
        managerId: widget.managerId,
      );
      await _fetchData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم ${action == 'approve' ? 'الموافقة على' : action == 'reject' ? 'رفض' : 'تأجيل'} طلب الاستراحة')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: ${e.toString()}'), backgroundColor: Colors.red),
      );
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'approved':
        return AppColors.success.withOpacity(0.2);
      case 'rejected':
        return AppColors.error.withOpacity(0.2);
      case 'pending':
      default:
        return Colors.orange.withOpacity(0.2);
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
      attendance = attendance.where((r) => r['status'] == _filterStatus).toList();
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
          child: Text('لا يوجد طلبات حالياً', style: TextStyle(color: Colors.grey, fontSize: 16)),
        ),
      );
    }
    
    return Column(children: items);
  }

  Widget _buildRequestCard(Map req, String type) {
    final String typeLabel = type == 'leave' ? 'إجازة' : type == 'advance' ? 'سلفة' : 'حضور';
    final IconData typeIcon = type == 'leave' ? Icons.beach_access : type == 'advance' ? Icons.payments : Icons.calendar_today;
    
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                Chip(
                  label: Text(_getStatusLabel(req['status'])),
                  backgroundColor: _getStatusColor(req['status']),
                  labelStyle: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ],
            ),
            const Divider(),
            Text('الموظف: ${req['employeeId'] ?? ''}', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            if (type == 'leave') ...[
              Text('من: ${req['startDate'] ?? ''}', style: const TextStyle(fontSize: 14)),
              Text('إلى: ${req['endDate'] ?? ''}', style: const TextStyle(fontSize: 14)),
              if (req['reason'] != null && req['reason'].toString().isNotEmpty)
                Text('السبب: ${req['reason']}', style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
            ],
            if (type == 'advance') ...[
              Text('المبلغ: ${req['amount'] ?? ''} جنيه', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text('تاريخ الطلب: ${req['requestDate'] ?? ''}', style: const TextStyle(fontSize: 14)),
            ],
            if (type == 'attendance') ...[
              Text('نوع الطلب: ${req['requestType'] ?? ''}', style: const TextStyle(fontSize: 14)),
              if (req['reason'] != null && req['reason'].toString().isNotEmpty)
                Text('السبب: ${req['reason']}', style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
            ],
            if (req['status'] == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _actOnRequest(type, req['id'], 'approve'),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('موافقة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            child: Text('لا توجد طلبات حضور/انصراف معلقة', style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    return Column(
      children: attendanceReqs.map<Widget>((req) => _buildAttendanceRequestCard(req)).toList(),
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
            Text('الموظف: ${req['employeeName'] ?? req['employeeId'] ?? ''}', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text('الوقت المطلوب: ${req['requestedTime'] ?? ''}', style: const TextStyle(fontSize: 14)),
            if (req['reason'] != null && req['reason'].toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('السبب: ${req['reason']}', style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
            ],
            if (req['status'] == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _reviewAttendanceRequest(req['id'], 'approve'),
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
                      onPressed: () => _reviewAttendanceRequest(req['id'], 'reject'),
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
        SnackBar(content: Text('تم ${action == 'approve' ? 'الموافقة على' : 'رفض'} طلب الحضور')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: ${e.toString()}'), backgroundColor: Colors.red),
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
              Text('لا يوجد حضور اليوم', style: TextStyle(color: Colors.grey, fontSize: 16)),
            ],
          ),
        ),
      );
    }
    
    return Column(
      children: report.map<Widget>((att) {
        final bool isPresent = att['checkInTime'] != null;
        final bool hasCheckedOut = att['checkOutTime'] != null;
        
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                Text('دخول: ${att['checkInTime'] ?? 'لم يحضر'}'),
                Text('خروج: ${att['checkOutTime'] ?? 'لم ينصرف'}'),
                if (att['workHours'] != null)
                  Text(
                    'ساعات العمل: ${att['workHours']}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryOrange),
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
              Text('لا يوجد تنبيهات غياب حالياً', style: TextStyle(color: Colors.grey, fontSize: 16)),
              SizedBox(height: 8),
              Text('جميع الموظفين ملتزمون', style: TextStyle(color: Colors.green, fontSize: 14)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.error),
                    ),
                  ],
                ),
                const Divider(),
                Text('الموظف: ${alert['employeeId'] ?? ''}', style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 4),
                Text('تاريخ الغياب: ${alert['absenceDate'] ?? ''}', style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 4),
                const Text(
                  'سيتم خصم يومين من المرتب في حالة الموافقة',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _actOnRequest('absence', alert['id'], 'approve'),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('موافقة على الخصم'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _actOnRequest('absence', alert['id'], 'reject'),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('إلغاء التنبيه'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
