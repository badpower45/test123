// Comprehensive Owner Management System
// This screen provides complete management functionality for owners

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../../services/branch_manager_api_service.dart';
import '../../services/owner_api_service.dart';
import '../../services/branch_api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../login_screen.dart';

class OwnerMainScreen extends StatefulWidget {
  const OwnerMainScreen({super.key, required this.ownerId, this.ownerName});

  final String ownerId;
  final String? ownerName;

  @override
  State<OwnerMainScreen> createState() => _OwnerMainScreenState();
}

class _OwnerMainScreenState extends State<OwnerMainScreen> {
  int _currentIndex = 0;
  late final List<Widget> _tabs;
  String? _ownerName;
  late final GlobalKey<_OwnerBranchesTabState> _branchesTabKey;
  late final GlobalKey<_OwnerEmployeesTabState> _employeesTabKey;

  @override
  void initState() {
    super.initState();
    _ownerName = widget.ownerName;
    _branchesTabKey = GlobalKey<_OwnerBranchesTabState>();
    _employeesTabKey = GlobalKey<_OwnerEmployeesTabState>();
    _tabs = [
      _OwnerDashboardTab(
        ownerId: widget.ownerId,
        onOwnerInfo: _handleOwnerInfo,
      ),
      _OwnerEmployeesTab(key: _employeesTabKey, ownerId: widget.ownerId),
      _OwnerBranchesTab(key: _branchesTabKey, ownerId: widget.ownerId),
      _OwnerPresenceTab(ownerId: widget.ownerId),
      _OwnerPayrollTab(ownerId: widget.ownerId),
    ];
  }

  void _handleOwnerInfo(Map<String, dynamic>? owner) {
    if (owner == null) return;
    final fetchedName = owner['name']?.toString();
    if (fetchedName != null && fetchedName.isNotEmpty && fetchedName != _ownerName) {
      setState(() {
        _ownerName = fetchedName;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_ownerName?.isNotEmpty == true ? _ownerName! : 'لوحة المالك'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث البيانات',
            onPressed: () {
              setState(() {}); // Trigger refresh of current tab
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل الخروج',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('تسجيل الخروج'),
                  content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('إلغاء'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('تسجيل الخروج'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                await AuthService.logout();
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: AppColors.primaryOrange,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'الطلبات'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'الموظفون'),
          BottomNavigationBarItem(icon: Icon(Icons.store), label: 'الفروع'),
          BottomNavigationBarItem(icon: Icon(Icons.visibility), label: 'الحضور'),
          BottomNavigationBarItem(icon: Icon(Icons.payments), label: 'المرتبات'),
        ],
      ),
      floatingActionButton: _getFloatingActionButton(),
    );
  }

  Widget? _getFloatingActionButton() {
    switch (_currentIndex) {
      case 1: // Employees tab
        return FloatingActionButton.extended(
          onPressed: () => _showAddEmployeeDialog(context),
          icon: const Icon(Icons.person_add),
          label: const Text('إضافة موظف'),
          backgroundColor: AppColors.primaryOrange,
        );
      case 2: // Branches tab
        return FloatingActionButton.extended(
          onPressed: () => _showAddBranchDialog(context),
          icon: const Icon(Icons.store),
          label: const Text('إضافة فرع'),
          backgroundColor: AppColors.primaryOrange,
        );
      default:
        return null;
    }
  }

  Future<void> _showAddEmployeeDialog(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddEmployeeSheet(ownerId: widget.ownerId),
    );
    if (result == true) {
      _employeesTabKey.currentState?._refresh();
    }
  }

  Future<void> _showAddBranchDialog(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddBranchSheet(),
    );
    if (result == true) {
      _branchesTabKey.currentState?._refresh();
    }
  }
}

// Owner Dashboard Tab - Manager Request Approval
class _OwnerDashboardTab extends StatefulWidget {
  const _OwnerDashboardTab({required this.ownerId, this.onOwnerInfo});

  final String ownerId;
  final ValueChanged<Map<String, dynamic>?>? onOwnerInfo;

  @override
  State<_OwnerDashboardTab> createState() => _OwnerDashboardTabState();
}

class _OwnerDashboardTabState extends State<_OwnerDashboardTab> {
  late Future<Map<String, dynamic>> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = OwnerApiService.getDashboard(ownerId: widget.ownerId);
  }

  Future<void> _refresh() async {
    final future = OwnerApiService.getDashboard(ownerId: widget.ownerId);
    setState(() {
      _dashboardFuture = future;
    });
    await future;
  }

  List<Map<String, dynamic>> _asRequestList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => e.map((key, dynamic val) => MapEntry(key.toString(), val)))
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Future<void> _actOnRequest(String type, String id, String action) async {
    try {
      await BranchManagerApiService.actOnRequest(type: type, id: id, action: action);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تنفيذ ${action == 'approve' ? 'الموافقة' : 'الرفض'} بنجاح')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildSummary(Map<String, dynamic> summary) {
    final pending = (summary['totalPendingRequests'] as num?)?.toInt() ?? 0;
    final attendance = (summary['attendanceRequestsCount'] as num?)?.toInt() ?? 0;
    final leave = (summary['leaveRequestsCount'] as num?)?.toInt() ?? 0;
    final advances = (summary['advancesCount'] as num?)?.toInt() ?? 0;
    final absences = (summary['absencesCount'] as num?)?.toInt() ?? 0;
    final breaks = (summary['breakRequestsCount'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _SummaryChip(label: 'إجمالي المعلقات', value: pending, color: AppColors.primaryOrange),
          _SummaryChip(label: 'الحضور', value: attendance, color: Colors.blue),
          _SummaryChip(label: 'الإجازات', value: leave, color: Colors.teal),
          _SummaryChip(label: 'السلف', value: advances, color: Colors.green),
          _SummaryChip(label: 'الغياب', value: absences, color: Colors.redAccent),
          _SummaryChip(label: 'الاستراحات', value: breaks, color: Colors.deepPurple),
        ],
      ),
    );
  }

  Widget _buildRequestsSection({
    required String title,
    required String type,
    required List<Map<String, dynamic>> requests,
  }) {
    if (requests.isEmpty) {
      return const SizedBox();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...requests.map((request) => _RequestTile(
                    request: request,
                    onApprove: () => _actOnRequest(type, '${request['id']}', 'approve'),
                    onReject: () => _actOnRequest(type, '${request['id']}', 'reject'),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Icon(Icons.error_outline, size: 64, color: AppColors.error.withOpacity(0.8)),
                const SizedBox(height: 16),
                Center(child: Text(snapshot.error.toString())),
                const SizedBox(height: 16),
              ],
            );
          }
          final data = snapshot.data ?? const {};
          final owner = data['owner'] is Map
              ? Map<String, dynamic>.from(data['owner'] as Map)
              : null;
          if (owner != null) {
            widget.onOwnerInfo?.call(owner);
          }
          final dashboard = data['dashboard'] as Map<String, dynamic>?;
          if (dashboard == null) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('لا توجد بيانات متاحة حالياً')),
              ],
            );
          }
          final summary = dashboard['summary'] as Map<String, dynamic>? ?? const {};
          final leaveRequests = _asRequestList(dashboard['leaveRequests']);
          final advanceRequests = _asRequestList(dashboard['advances']);
          final absenceNotifications = _asRequestList(dashboard['absences']);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (owner != null) _OwnerInfoCard(owner: owner),
              _buildSummary(summary),
              _buildRequestsSection(title: 'طلبات الإجازة من المديرين', type: 'leave', requests: leaveRequests),
              _buildRequestsSection(title: 'طلبات السلف من المديرين', type: 'advance', requests: advanceRequests),
              _buildRequestsSection(title: 'تنبيهات الغياب للمديرين', type: 'absence', requests: absenceNotifications),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// Owner Employees Tab - Employee Management
class _OwnerEmployeesTab extends StatefulWidget {
  const _OwnerEmployeesTab({super.key, required this.ownerId});

  final String ownerId;

  @override
  State<_OwnerEmployeesTab> createState() => _OwnerEmployeesTabState();
}

class _OwnerEmployeesTabState extends State<_OwnerEmployeesTab> {
  late Future<Map<String, dynamic>> _employeesFuture;

  @override
  void initState() {
    super.initState();
    _employeesFuture = OwnerApiService.getEmployees(ownerId: widget.ownerId);
  }

  Future<void> _refresh() async {
    final future = OwnerApiService.getEmployees(ownerId: widget.ownerId);
    setState(() {
      _employeesFuture = future;
    });
    await future;
  }

  Future<void> _editEmployee(Map<String, dynamic> employee) async {
    final nameController = TextEditingController(text: employee['fullName']?.toString() ?? '');
    final hourlyRateController = TextEditingController(text: employee['hourlyRate']?.toString() ?? '');
    
    // Parse existing shift times
    TimeOfDay? shiftStart;
    TimeOfDay? shiftEnd;
    if (employee['shiftStartTime'] != null) {
      final parts = employee['shiftStartTime'].toString().split(':');
      if (parts.length == 2) {
        shiftStart = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    }
    if (employee['shiftEndTime'] != null) {
      final parts = employee['shiftEndTime'].toString().split(':');
      if (parts.length == 2) {
        shiftEnd = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    }
    String shiftType = employee['shiftType']?.toString() ?? 'AM';
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditEmployeeDialog(
        employee: employee,
        nameController: nameController,
        hourlyRateController: hourlyRateController,
        initialShiftStart: shiftStart,
        initialShiftEnd: shiftEnd,
        initialShiftType: shiftType,
      ),
    );
    
    if (result == null) return;
    
    try {
      await OwnerApiService.updateEmployee(
        employeeId: '${employee['id']}',
        fullName: result['fullName'],
        hourlyRate: result['hourlyRate'],
        shiftStartTime: result['shiftStartTime'],
        shiftEndTime: result['shiftEndTime'],
        shiftType: result['shiftType'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث بيانات الموظف بنجاح')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _deleteEmployee(String employeeId, String employeeName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف الموظف "$employeeName"؟\n\nسيتم حذف جميع البيانات المرتبطة به.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await OwnerApiService.deleteEmployee(employeeId: employeeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الموظف بنجاح')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _formatCurrency(dynamic value) {
    if (value == null) {
      return '—';
    }
    final parsed = value is num ? value.toDouble() : double.tryParse(value.toString());
    if (parsed == null) {
      return value.toString();
    }
    return parsed.toStringAsFixed(parsed.truncateToDouble() == parsed ? 0 : 2);
  }

  Widget _buildSummary(Map<String, dynamic> summary) {
    final totalEmployees = (summary['totalEmployees'] as num?)?.toInt() ?? 0;
    final active = (summary['activeEmployees'] as num?)?.toInt() ?? 0;
    final managers = (summary['managersCount'] as num?)?.toInt() ?? 0;
    final totalHourly = (summary['totalHourlyRateAssigned'] as num?)?.toDouble() ?? 0;
    final totalMonthly = (summary['totalMonthlySalary'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _SummaryChip(label: 'إجمالي الموظفين', value: totalEmployees, color: Colors.blueGrey),
          _SummaryChip(label: 'النشطون', value: active, color: Colors.green),
          _SummaryChip(label: 'عدد المديرين', value: managers, color: Colors.deepPurple),
          _SummaryChip(label: 'إجمالي أسعار الساعة', value: totalHourly, color: Colors.orangeAccent, isCurrency: true),
          _SummaryChip(label: 'إجمالي الرواتب الشهرية', value: totalMonthly, color: Colors.teal, isCurrency: true),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _employeesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Icon(Icons.error_outline, size: 64, color: AppColors.error.withOpacity(0.8)),
                const SizedBox(height: 16),
                Center(child: Text(snapshot.error.toString())),
              ],
            );
          }
          final data = snapshot.data ?? const {};
          final employees = (data['employees'] as List?)?.whereType<Map>().map(Map<String, dynamic>.from).toList() ?? const [];
          final summary = data['summary'] as Map<String, dynamic>? ?? const {};
          final owner = data['owner'] is Map ? Map<String, dynamic>.from(data['owner'] as Map) : null;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (owner != null) _OwnerInfoCard(owner: owner),
              _buildSummary(summary),
              ...employees.map((employee) {
                final name = employee['fullName']?.toString() ?? '';
                final employeeId = employee['id']?.toString() ?? '';
                final role = employee['role']?.toString() ?? '';
                final branch = employee['branch']?.toString() ?? '';
                final hourlyRate = _formatCurrency(employee['hourlyRate']);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primaryOrange.withOpacity(0.15),
                        foregroundColor: AppColors.primaryOrange,
                        child: Text(name.isNotEmpty ? name.substring(0, 1) : '?'),
                      ),
                      title: Text(name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('الدور: $role • الفرع: ${branch.isEmpty ? 'غير محدد' : branch}'),
                          Text('سعر الساعة: $hourlyRate جنيه', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            tooltip: 'تعديل',
                            onPressed: () => _editEmployee(employee),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            tooltip: 'حذف',
                            onPressed: () => _deleteEmployee(employeeId, name),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                    ),
                  ),
                );
              }),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// Owner Branches Tab - Branch Management
class _OwnerBranchesTab extends StatefulWidget {
  const _OwnerBranchesTab({super.key, required this.ownerId});

  final String ownerId;

  @override
  State<_OwnerBranchesTab> createState() => _OwnerBranchesTabState();
}

class _OwnerBranchesTabState extends State<_OwnerBranchesTab> {
  late Future<List<Map<String, dynamic>>> _branchesFuture;

  @override
  void initState() {
    super.initState();
    _branchesFuture = _loadBranches();
  }

  Future<List<Map<String, dynamic>>> _loadBranches() async {
    try {
      return await BranchApiService.getBranches();
    } catch (error) {
      throw Exception('Failed to load branches: $error');
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _branchesFuture = _loadBranches();
    });
    await _branchesFuture;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _branchesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Icon(Icons.error_outline, size: 64, color: AppColors.error.withOpacity(0.8)),
                const SizedBox(height: 16),
                Center(child: Text(snapshot.error.toString())),
              ],
            );
          }
          final branches = snapshot.data ?? [];
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (branches.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(64),
                    child: Column(
                      children: [
                        Icon(Icons.store, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('لا توجد فروع بعد', style: TextStyle(fontSize: 18)),
                        SizedBox(height: 8),
                        Text('اضغط على زر إضافة فرع لبدء إنشاء الفروع'),
                      ],
                    ),
                  ),
                )
              else
                ...branches.map((branch) => _BranchCard(branch: branch, onRefresh: _refresh, ownerId: widget.ownerId)),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// Owner Presence Tab - Current Presence Monitoring
class _OwnerPresenceTab extends StatefulWidget {
  const _OwnerPresenceTab({required this.ownerId});

  final String ownerId;

  @override
  State<_OwnerPresenceTab> createState() => _OwnerPresenceTabState();
}

class _OwnerPresenceTabState extends State<_OwnerPresenceTab> {
  late Future<Map<String, dynamic>> _presenceFuture;
  String? _selectedBranch;
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _presenceFuture = _loadPresenceData();
  }

  Future<Map<String, dynamic>> _loadPresenceData() async {
    try {
      // Fetch branches from API
      final branches = await BranchApiService.getBranches();
      final branchNames = branches.map((branch) => branch['name'] as String).toList();
      // For now, return sample data with real branches
      return {
        'present': [],
        'absent': [],
        'offline': [],
        'branches': branchNames,
        'totalEmployees': 0,
        'presentCount': 0,
        'absentCount': 0,
      };
    } catch (error) {
      throw Exception('Failed to load presence data: $error');
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _presenceFuture = _loadPresenceData();
    });
    await _presenceFuture;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _presenceFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Icon(Icons.error_outline, size: 64, color: AppColors.error.withOpacity(0.8)),
                const SizedBox(height: 16),
                Center(child: Text(snapshot.error.toString())),
              ],
            );
          }
          final data = snapshot.data ?? {};
          final branches = data['branches'] as List<String>? ?? [];
          final presentCount = data['presentCount'] as int? ?? 0;
          final absentCount = data['absentCount'] as int? ?? 0;
          final totalEmployees = data['totalEmployees'] as int? ?? 0;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              // Filter Section
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('فلترة الحضور', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      if (branches.isNotEmpty) ...[
                        DropdownButtonFormField<String?>(
                          value: _selectedBranch,
                          decoration: const InputDecoration(
                            labelText: 'الفرع',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('جميع الفروع')),
                            ...branches.map((branch) => DropdownMenuItem<String?>(value: branch, child: Text(branch))),
                          ],
                          onChanged: (value) => setState(() => _selectedBranch = value),
                        ),
                        const SizedBox(height: 16),
                      ],
                      DropdownButtonFormField<String?>(
                        value: _selectedStatus,
                        decoration: const InputDecoration(
                          labelText: 'حالة الحضور',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem<String?>(value: null, child: Text('الكل')),
                          DropdownMenuItem<String?>(value: 'present', child: Text('موجود')),
                          DropdownMenuItem<String?>(value: 'absent', child: Text('غائب')),
                          DropdownMenuItem<String?>(value: 'offline', child: Text('غير متصل')),
                        ],
                        onChanged: (value) => setState(() => _selectedStatus = value),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Summary Cards
              Row(
                children: [
                  Expanded(
                    child: _PresenceSummaryCard(
                      title: 'الموجودين',
                      count: presentCount,
                      color: Colors.green,
                      icon: Icons.check_circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PresenceSummaryCard(
                      title: 'الغائبين',
                      count: absentCount,
                      color: Colors.red,
                      icon: Icons.cancel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PresenceSummaryCard(
                      title: 'إجمالي',
                      count: totalEmployees,
                      color: Colors.blue,
                      icon: Icons.people,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Employee List
              const Text('قائمة الموظفين', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              // Employee list would go here when API is implemented

              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// Owner Payroll Tab - Payroll Reports
class _OwnerPayrollTab extends StatefulWidget {
  const _OwnerPayrollTab({required this.ownerId});

  final String ownerId;

  @override
  State<_OwnerPayrollTab> createState() => _OwnerPayrollTabState();
}

class _OwnerPayrollTabState extends State<_OwnerPayrollTab> {
  late DateTime _startDate;
  late DateTime _endDate;
  Future<List<Map<String, dynamic>>>? _employeesFuture;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = now;
    _employeesFuture = _loadEmployees();
  }

  String _formatDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<List<Map<String, dynamic>>> _loadEmployees() async {
    try {
      final payrollData = await OwnerApiService.getPayrollSummary(
        ownerId: widget.ownerId,
        startDate: _formatDate(_startDate),
        endDate: _formatDate(_endDate),
      );
      final payroll = (payrollData['payroll'] as List?)
          ?.whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList() ?? [];
      return payroll;
    } catch (e) {
      throw Exception('فشل تحميل بيانات الرواتب: $e');
    }
  }

  Future<void> _refresh() async {
    final future = _loadEmployees();
    setState(() {
      _employeesFuture = future;
    });
    await future;
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
    });
    await _refresh();
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _endDate = picked;
    });
    await _refresh();
  }

  void _showEmployeeDetails(Map<String, dynamic> employee) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _EmployeePayrollDetails(
        employee: employee,
        startDate: _formatDate(_startDate),
        endDate: _formatDate(_endDate),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: Column(
        children: [
          // Date Range Picker
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.date_range),
                    label: Text('من: ${_formatDate(_startDate)}'),
                    onPressed: _pickStartDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text('إلى: ${_formatDate(_endDate)}'),
                    onPressed: _pickEndDate,
                  ),
                ),
              ],
            ),
          ),
          
          // Simple Employee Table
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _employeesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: AppColors.error.withOpacity(0.8)),
                        const SizedBox(height: 16),
                        Text('${snapshot.error}'),
                      ],
                    ),
                  );
                }
                
                final employees = snapshot.data ?? [];
                if (employees.isEmpty) {
                  return const Center(
                    child: Text('لا توجد بيانات رواتب في الفترة المختارة'),
                  );
                }
                
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: DataTable(
                        headingRowColor: MaterialStateProperty.all(
                          AppColors.primaryOrange.withOpacity(0.1),
                        ),
                        columns: const [
                          DataColumn(label: Text('اسم الموظف', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('الدور', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('المبلغ الكلي', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: employees.map((employee) {
                          final name = employee['name']?.toString() ?? 'غير معروف';
                          final role = employee['role']?.toString() ?? '-';
                          final total = (employee['totalComputedPay'] as num?)?.toDouble() ?? 0;
                          
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(name),
                                onTap: () => _showEmployeeDetails(employee),
                              ),
                              DataCell(
                                Text(role),
                                onTap: () => _showEmployeeDetails(employee),
                              ),
                              DataCell(
                                Text(
                                  '${total.toStringAsFixed(2)} جنيه',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                onTap: () => _showEmployeeDetails(employee),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Employee Payroll Details Bottom Sheet
class _EmployeePayrollDetails extends StatelessWidget {
  const _EmployeePayrollDetails({
    required this.employee,
    required this.startDate,
    required this.endDate,
  });

  final Map<String, dynamic> employee;
  final String startDate;
  final String endDate;

  @override
  Widget build(BuildContext context) {
    final name = employee['name']?.toString() ?? 'غير معروف';
    final role = employee['role']?.toString() ?? '-';
    final branch = employee['branch']?.toString() ?? '-';
    final workHours = (employee['totalWorkHours'] as num?)?.toDouble() ?? 0;
    final hourlyRate = (employee['hourlyRate'] as num?)?.toDouble() ?? 0;
    final hourlyPay = (employee['hourlyPay'] as num?)?.toDouble() ?? 0;
    final pulsePay = (employee['pulsePay'] as num?)?.toDouble() ?? 0;
    final total = (employee['totalComputedPay'] as num?)?.toDouble() ?? 0;
    
    return Container(
      padding: const EdgeInsets.all(24),
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primaryOrange,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$role - $branch',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          
          Text(
            'ملخص المرتب',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          
          _DetailRow(label: 'الفترة', value: '$startDate إلى $endDate'),
          _DetailRow(label: 'ساعات العمل', value: '${workHours.toStringAsFixed(2)} ساعة'),
          _DetailRow(label: 'سعر الساعة', value: '${hourlyRate.toStringAsFixed(2)} جنيه'),
          _DetailRow(label: 'أجر الساعات', value: '${hourlyPay.toStringAsFixed(2)} جنيه'),
          _DetailRow(label: 'أجر النبضات', value: '${pulsePay.toStringAsFixed(2)} جنيه'),
          const Divider(height: 32),
          _DetailRow(
            label: 'المبلغ الكلي',
            value: '${total.toStringAsFixed(2)} جنيه',
            isTotal: true,
          ),
          
          const SizedBox(height: 24),
          const Text(
            'ملاحظة: التفاصيل اليومية (التاريخ، وقت الحضور، وقت الانصراف، بدل الإجازة، الخصومات، السلف) ستكون متاحة قريبًا.',
            style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  final String label;
  final String value;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 18 : 16,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 16,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              color: isTotal ? Colors.green : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

// Add Employee Sheet
class _AddEmployeeSheet extends StatefulWidget {
  const _AddEmployeeSheet({super.key, required this.ownerId});

  final String ownerId;

  @override
  State<_AddEmployeeSheet> createState() => _AddEmployeeSheetState();
}

class _AddEmployeeSheetState extends State<_AddEmployeeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _branchesFuture;
  String? _selectedBranchId;  // Changed to store UUID
  String? _selectedBranchName;  // Optional: store name
  bool _isManager = false;  // NEW: Is this employee a manager?
  
  // Shift times
  TimeOfDay? _shiftStartTime;
  TimeOfDay? _shiftEndTime;
  String _shiftType = 'AM'; // Default to AM shift

  @override
  void initState() {
    super.initState();
    _branchesFuture = BranchApiService.getBranches();
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _pinController.dispose();
    _hourlyRateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final hourlyRate = double.parse(_hourlyRateController.text.trim());
      
      // Format shift times as HH:mm strings
      String? shiftStart;
      String? shiftEnd;
      if (_shiftStartTime != null) {
        shiftStart = '${_shiftStartTime!.hour.toString().padLeft(2, '0')}:${_shiftStartTime!.minute.toString().padLeft(2, '0')}';
      }
      if (_shiftEndTime != null) {
        shiftEnd = '${_shiftEndTime!.hour.toString().padLeft(2, '0')}:${_shiftEndTime!.minute.toString().padLeft(2, '0')}';
      }

      await OwnerApiService.createEmployee(
        ownerId: widget.ownerId,
        employeeId: _idController.text.trim(),
        fullName: _nameController.text.trim(),
        pin: _pinController.text.trim(),
        branchId: _selectedBranchId,  // Send branchId (UUID)
        branch: _selectedBranchName,  // Optional: send branch name
        hourlyRate: hourlyRate,
        shiftStartTime: shiftStart,
        shiftEndTime: shiftEnd,
        shiftType: _shiftType,
        role: _isManager ? 'manager' : 'staff',  // Set role based on checkbox
      );

      // If marked as manager and branch selected, assign as branch manager
      if (_isManager && _selectedBranchId != null) {
        try {
          await BranchApiService.assignManager(
            branchId: _selectedBranchId!,
            employeeId: _idController.text.trim(),
          );
        } catch (e) {
          // Log but don't fail the whole operation
          print('Could not assign as branch manager: $e');
        }
      }

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isManager ? 'تم إضافة المدير بنجاح' : 'تم إضافة الموظف بنجاح')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في إضافة الموظف: $error'),
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
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'إضافة موظف جديد',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _idController,
                decoration: const InputDecoration(
                  labelText: 'معرف الموظف',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value?.isEmpty == true ? 'مطلوب' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value?.isEmpty == true ? 'مطلوب' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _pinController,
                decoration: const InputDecoration(
                  labelText: 'الرقم السري',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value?.isEmpty == true ? 'مطلوب' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _hourlyRateController,
                decoration: const InputDecoration(
                  labelText: 'سعر الساعة (جنيه)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) => value?.isEmpty == true ? 'مطلوب' : null,
              ),
              const SizedBox(height: 16),

              FutureBuilder<List<Map<String, dynamic>>>(
                future: _branchesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    return Text('خطأ في تحميل الفروع: ${snapshot.error}');
                  }
                  final branches = snapshot.data ?? [];
                  return DropdownButtonFormField<String>(
                    value: _selectedBranchId,
                    decoration: const InputDecoration(
                      labelText: 'الفرع',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('اختر الفرع')),
                      ...branches.map((branch) {
                        final branchId = branch['id']?.toString();
                        final branchName = branch['name']?.toString() ?? 'فرع بدون اسم';
                        return DropdownMenuItem(
                          value: branchId,
                          child: Text(branchName),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedBranchId = value;
                        // Find and store branch name
                        if (value != null) {
                          final selectedBranch = branches.firstWhere(
                            (b) => b['id']?.toString() == value,
                            orElse: () => {},
                          );
                          _selectedBranchName = selectedBranch['name']?.toString();
                        } else {
                          _selectedBranchName = null;
                        }
                      });
                    },
                    validator: (value) => value == null || value.isEmpty ? 'مطلوب' : null,
                  );
                },
              ),
              const SizedBox(height: 16),

              // Manager Checkbox
              CheckboxListTile(
                title: const Text('تعيين كمدير للفرع'),
                subtitle: const Text('إذا تم التحديد، سيكون هذا الموظف مدير الفرع المختار'),
                value: _isManager,
                onChanged: (value) {
                  setState(() {
                    _isManager = value ?? false;
                  });
                },
                activeColor: AppColors.primaryOrange,
              ),
              const SizedBox(height: 16),

              // Shift Type Selection
              const Text(
                'نوع الشيفت',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('صباحي (AM)'),
                      value: 'AM',
                      groupValue: _shiftType,
                      onChanged: (value) {
                        setState(() {
                          _shiftType = value!;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('مسائي (PM)'),
                      value: 'PM',
                      groupValue: _shiftType,
                      onChanged: (value) {
                        setState(() {
                          _shiftType = value!;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Shift Start Time
              InkWell(
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: _shiftStartTime ?? const TimeOfDay(hour: 9, minute: 0),
                  );
                  if (time != null) {
                    setState(() {
                      _shiftStartTime = time;
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'وقت بداية الشيفت',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.access_time),
                  ),
                  child: Text(
                    _shiftStartTime != null
                        ? '${_shiftStartTime!.hour.toString().padLeft(2, '0')}:${_shiftStartTime!.minute.toString().padLeft(2, '0')}'
                        : 'اختر وقت البداية',
                    style: TextStyle(
                      color: _shiftStartTime != null ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Shift End Time
              InkWell(
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: _shiftEndTime ?? const TimeOfDay(hour: 17, minute: 0),
                  );
                  if (time != null) {
                    setState(() {
                      _shiftEndTime = time;
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'وقت نهاية الشيفت',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.access_time),
                  ),
                  child: Text(
                    _shiftEndTime != null
                        ? '${_shiftEndTime!.hour.toString().padLeft(2, '0')}:${_shiftEndTime!.minute.toString().padLeft(2, '0')}'
                        : 'اختر وقت النهاية',
                    style: TextStyle(
                      color: _shiftEndTime != null ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('إضافة الموظف', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

// Add Branch Sheet
class _AddBranchSheet extends StatefulWidget {
  const _AddBranchSheet({super.key});

  @override
  State<_AddBranchSheet> createState() => _AddBranchSheetState();
}

class _AddBranchSheetState extends State<_AddBranchSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _wifiNameController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _radiusController = TextEditingController(text: '100');

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _wifiNameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _latitudeController.text = position.latitude.toString();
        _longitudeController.text = position.longitude.toString();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الحصول على الموقع: $error')),
      );
    }
  }

  Future<void> _getCurrentWifiBssid() async {
    try {
      final networkInfo = NetworkInfo();
      final wifiBSSID = await networkInfo.getWifiBSSID();
      
      if (wifiBSSID != null && wifiBSSID.isNotEmpty) {
        setState(() {
          _wifiNameController.text = wifiBSSID;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم جلب BSSID بنجاح'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لم يتم العثور على شبكة Wi-Fi. تأكد من الاتصال بالشبكة'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في الحصول على BSSID: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await BranchApiService.createBranch(
        name: _nameController.text.trim(),
        wifiBssid: _wifiNameController.text.trim().isEmpty ? null : _wifiNameController.text.trim(),
        latitude: _latitudeController.text.trim().isEmpty ? null : double.parse(_latitudeController.text.trim()),
        longitude: _longitudeController.text.trim().isEmpty ? null : double.parse(_longitudeController.text.trim()),
        geofenceRadius: int.parse(_radiusController.text.trim()),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إضافة الفرع بنجاح')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في إضافة الفرع: $error'),
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
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'إضافة فرع جديد',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم الفرع',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value?.isEmpty == true ? 'مطلوب' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value?.isEmpty == true ? 'مطلوب' : null,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _wifiNameController,
                      decoration: const InputDecoration(
                        labelText: 'Wi-Fi BSSID',
                        hintText: 'XX:XX:XX:XX:XX:XX',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _getCurrentWifiBssid,
                    icon: const Icon(Icons.wifi),
                    tooltip: 'جلب BSSID الحالي',
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primaryOrange.withOpacity(0.1),
                      foregroundColor: AppColors.primaryOrange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latitudeController,
                      decoration: const InputDecoration(
                        labelText: 'خط العرض',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _longitudeController,
                      decoration: const InputDecoration(
                        labelText: 'خط الطول',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              ElevatedButton.icon(
                onPressed: _getCurrentLocation,
                icon: const Icon(Icons.my_location),
                label: const Text('الحصول على الموقع الحالي'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade200,
                  foregroundColor: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _radiusController,
                decoration: const InputDecoration(
                  labelText: 'نصف القطر المسموح (متر)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) => value?.isEmpty == true ? 'مطلوب' : null,
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('إضافة الفرع', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Supporting Widgets
class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
    this.isCurrency = false,
  });

  final String label;
  final num value;
  final Color color;
  final bool isCurrency;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color.withOpacity(0.15),
        child: Icon(Icons.insert_chart, color: color),
      ),
      label: Text(
        isCurrency ? '${value.toStringAsFixed(0)} ج.م' : value.toString(),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      backgroundColor: Colors.white,
      side: BorderSide(color: color.withOpacity(0.25)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(request['employeeName'] ?? request['employeeId'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(request['status']?.toString() ?? '', style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
            if (request['reason'] != null && request['reason'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(request['reason'].toString()),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check),
                    label: const Text('موافقة'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close),
                    label: const Text('رفض'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerInfoCard extends StatelessWidget {
  const _OwnerInfoCard({required this.owner});

  final Map<String, dynamic> owner;

  @override
  Widget build(BuildContext context) {
    final name = owner['name']?.toString() ?? '';
    final role = owner['role']?.toString() ?? '';
    final id = owner['id']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primaryOrange.withOpacity(0.12),
            foregroundColor: AppColors.primaryOrange,
            child: const Icon(Icons.verified_user),
          ),
          title: Text(name.isNotEmpty ? name : 'مالك النظام'),
          subtitle: Text(role.isNotEmpty ? 'الدور: $role' : 'المعرف: $id'),
          trailing: id.isNotEmpty
              ? SelectableText(
                  '#$id',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : null,
        ),
      ),
    );
  }
}

class _BranchCard extends StatefulWidget {
  const _BranchCard({required this.branch, required this.onRefresh, required this.ownerId});

  final Map<String, dynamic> branch;
  final VoidCallback onRefresh;
  final String ownerId;

  @override
  State<_BranchCard> createState() => _BranchCardState();
}

class _BranchCardState extends State<_BranchCard> {
  late Future<List<Map<String, dynamic>>> _employeesFuture;

  @override
  void initState() {
    super.initState();
    _employeesFuture = BranchApiService.getBranchEmployees(widget.branch['id']);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.store, color: AppColors.primaryOrange),
                const SizedBox(width: 8),
                Text(widget.branch['name'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.branch['wifiBssid'] != null) Text('الواي فاي: ${widget.branch['wifiBssid']}'),
            if (widget.branch['latitude'] != null && widget.branch['longitude'] != null)
              Text('الموقع: ${widget.branch['latitude']}, ${widget.branch['longitude']}'),
            if (widget.branch['geofenceRadius'] != null) Text('نصف القطر: ${widget.branch['geofenceRadius']} متر'),
            const SizedBox(height: 8),
            const Text('الموظفون المعينون:', style: TextStyle(fontWeight: FontWeight.bold)),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _employeesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }
                if (snapshot.hasError) {
                  return Text('خطأ: ${snapshot.error}');
                }
                final employees = snapshot.data ?? [];
                if (employees.isEmpty) {
                  return const Text('لا يوجد موظفون معينون');
                }
                return Column(
                  children: employees.map((emp) => Text('- ${emp['fullName']} (${emp['role']})')).toList(),
                );
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _showAssignManagerDialog(context),
              child: const Text('تعيين مدير'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAssignManagerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعيين مدير للفرع'),
        content: FutureBuilder<Map<String, dynamic>>(
          future: OwnerApiService.getEmployees(ownerId: widget.ownerId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator();
            }
            if (snapshot.hasError) {
              return Text('خطأ: ${snapshot.error}');
            }
            final data = snapshot.data;
            final employees = (data?['employees'] as List?)?.whereType<Map>().map(Map<String, dynamic>.from).toList() ?? [];
            final managers = employees.where((emp) => emp['role'] == 'manager').toList();
            return DropdownButton<String>(
              hint: const Text('اختر مدير'),
              items: managers.map((manager) => DropdownMenuItem(
                value: manager['id'] as String,
                child: Text(manager['fullName'] as String),
              )).toList(),
              onChanged: (value) async {
                if (value != null) {
                  try {
                    await BranchApiService.assignManager(
                      branchId: widget.branch['id'],
                      employeeId: value,
                    );
                    Navigator.pop(context);
                    setState(() {
                      _employeesFuture = BranchApiService.getBranchEmployees(widget.branch['id']);
                    });
                    widget.onRefresh();
                  } catch (error) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ: $error')),
                    );
                  }
                }
              },
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ],
      ),
    );
  }
}

class _EditEmployeeDialog extends StatefulWidget {
  const _EditEmployeeDialog({
    required this.employee,
    required this.nameController,
    required this.hourlyRateController,
    this.initialShiftStart,
    this.initialShiftEnd,
    required this.initialShiftType,
  });

  final Map<String, dynamic> employee;
  final TextEditingController nameController;
  final TextEditingController hourlyRateController;
  final TimeOfDay? initialShiftStart;
  final TimeOfDay? initialShiftEnd;
  final String initialShiftType;

  @override
  State<_EditEmployeeDialog> createState() => _EditEmployeeDialogState();
}

class _EditEmployeeDialogState extends State<_EditEmployeeDialog> {
  TimeOfDay? _shiftStart;
  TimeOfDay? _shiftEnd;
  late String _shiftType;

  @override
  void initState() {
    super.initState();
    _shiftStart = widget.initialShiftStart;
    _shiftEnd = widget.initialShiftEnd;
    _shiftType = widget.initialShiftType;
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return 'غير محدد';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _shiftStart : _shiftEnd) ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _shiftStart = picked;
        } else {
          _shiftEnd = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('تعديل بيانات ${widget.employee['fullName'] ?? 'الموظف'}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: widget.nameController,
              decoration: const InputDecoration(labelText: 'الاسم الكامل'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.hourlyRateController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'سعر الساعة (جنيه)'),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text('مواعيد الشيفت:', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _shiftType,
              decoration: const InputDecoration(
                labelText: 'نوع الشيفت',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'AM', child: Text('صباحي (AM)')),
                DropdownMenuItem(value: 'PM', child: Text('مسائي (PM)')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _shiftType = value);
                }
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _pickTime(isStart: true),
              icon: const Icon(Icons.access_time),
              label: Text('بداية الشيفت: ${_formatTime(_shiftStart)}'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _pickTime(isStart: false),
              icon: const Icon(Icons.access_time),
              label: Text('نهاية الشيفت: ${_formatTime(_shiftEnd)}'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: () {
            final name = widget.nameController.text.trim();
            final hourlyRate = double.tryParse(widget.hourlyRateController.text.trim());
            
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('الاسم مطلوب')),
              );
              return;
            }
            
            if (hourlyRate == null || hourlyRate < 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('يرجى إدخال سعر ساعة صالح')),
              );
              return;
            }
            
            Navigator.pop(context, {
              'fullName': name,
              'hourlyRate': hourlyRate,
              'shiftStartTime': _shiftStart != null ? _formatTime(_shiftStart) : null,
              'shiftEndTime': _shiftEnd != null ? _formatTime(_shiftEnd) : null,
              'shiftType': _shiftType,
            });
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _PresenceSummaryCard extends StatelessWidget {
  const _PresenceSummaryCard({
    required this.title,
    required this.count,
    required this.color,
    required this.icon,
  });

  final String title;
  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}