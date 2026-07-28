import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_requests_service.dart';
import '../../theme/app_colors.dart';

class HRRequestsScreen extends StatefulWidget {
  final String hrId;

  const HRRequestsScreen({super.key, required this.hrId});

  @override
  State<HRRequestsScreen> createState() => _HRRequestsScreenState();
}

class _HRRequestsScreenState extends State<HRRequestsScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  late TabController _tabController;

  List<Map<String, dynamic>> _leaveRequests = [];
  List<Map<String, dynamic>> _advanceRequests = [];
  List<Map<String, dynamic>> _attendanceRequests = [];
  List<Map<String, dynamic>> _breakRequests = [];

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<dynamic>> _safeFetchList(Future<dynamic> future, String label) async {
    try {
      final response = await future;
      return (response as List).toList();
    } catch (e) {
      debugPrint('[HR] $label error: $e');
      return <dynamic>[];
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _safeFetchList(
          _supabase.from('leave_requests').select().eq('status', 'pending').limit(50),
          'Leave',
        ),
        _safeFetchList(
          _supabase.from('salary_advances').select().eq('status', 'pending').limit(50),
          'Advance',
        ),
        _safeFetchList(
          _supabase.from('attendance_requests').select().eq('status', 'pending').limit(50),
          'Attendance',
        ),
        _safeFetchList(
          _supabase.from('breaks').select().eq('status', 'pending').limit(50),
          'Break',
        ),
        _safeFetchList(
          _supabase.from('employees').select('id, full_name, role, branch').neq('role', 'owner'),
          'Employees',
        ),
      ]);

      final leaveResp = results[0];
      final advanceResp = results[1];
      final attendanceResp = results[2];
      final breakResp = results[3];
      final employeesResp = results[4];

      final employeeMap = <String, Map<String, dynamic>>{};
      for (final emp in employeesResp) {
        final id = emp['id']?.toString();
        if (id != null) employeeMap[id] = Map<String, dynamic>.from(emp);
      }

      List<Map<String, dynamic>> enrich(List<dynamic> reqs) {
        return reqs.map((r) {
          final empId = r['employee_id']?.toString();
          final enriched = Map<String, dynamic>.from(r);
          if (empId != null && employeeMap.containsKey(empId)) {
            enriched['employees'] = employeeMap[empId];
          }
          return enriched;
        }).toList();
      }

      setState(() {
        _leaveRequests = enrich(leaveResp);
        _advanceRequests = enrich(advanceResp);
        _attendanceRequests = enrich(attendanceResp);
        _breakRequests = enrich(breakResp);
        _loading = false;
      });
    } catch (e) {
      debugPrint('[HR] Main error: $e');
      setState(() {
        _leaveRequests = [];
        _advanceRequests = [];
        _attendanceRequests = [];
        _breakRequests = [];
        _loading = false;
      });
    }
  }

  Future<void> _actOnRequest(String type, String id, String action, {String? reason}) async {
    try {
      final approved = action == 'approve';
      final status = approved ? 'approved' : 'rejected';
      bool success = false;

      switch (type) {
        case 'leave':
          success = await SupabaseRequestsService.reviewLeaveRequest(
            requestId: id,
            reviewedBy: widget.hrId,
            status: status,
            reviewNotes: reason,
          );
          break;
        case 'advance':
          success = await SupabaseRequestsService.reviewSalaryAdvanceRequest(
            requestId: id,
            approvedBy: widget.hrId,
            status: status,
            notes: reason,
          );
          break;
        case 'attendance':
          success = await SupabaseRequestsService.reviewAttendanceRequest(
            requestId: id,
            reviewedBy: widget.hrId,
            status: status,
            reviewNotes: reason,
          );
          break;
        case 'break':
          success = await SupabaseRequestsService.reviewBreakRequest(
            requestId: id,
            reviewedBy: widget.hrId,
            status: status,
          );
          break;
        default:
          return;
      }

      if (!success) {
        throw Exception('فشل تنفيذ الإجراء');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'approve' ? '✓ تم الموافقة' : '✓ تم الرفض'),
          backgroundColor: approved ? AppColors.success : AppColors.error,
        ),
      );

      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : _buildTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primaryOrange,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primaryOrange,
            tabs: [
              Tab(
                text: 'الإجازات (${_leaveRequests.length})',
                icon: const Icon(Icons.beach_access),
              ),
              Tab(
                text: 'السلف (${_advanceRequests.length})',
                icon: const Icon(Icons.payments),
              ),
              Tab(
                text: 'الحضور (${_attendanceRequests.length})',
                icon: const Icon(Icons.access_time),
              ),
              Tab(
                text: 'الاستراحات (${_breakRequests.length})',
                icon: const Icon(Icons.free_breakfast),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildRequestsList(_leaveRequests, 'leave'),
        _buildRequestsList(_advanceRequests, 'advance'),
        _buildRequestsList(_attendanceRequests, 'attendance'),
        _buildRequestsList(_breakRequests, 'break'),
      ],
    );
  }

  Widget _buildRequestsList(List<Map<String, dynamic>> requests, String type) {
    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type == 'leave'
                  ? Icons.beach_access
                  : type == 'advance'
                      ? Icons.payments
                      : type == 'attendance'
                          ? Icons.access_time
                          : Icons.free_breakfast,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'لا توجد طلبات',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: requests.length,
        itemBuilder: (context, index) {
          final request = requests[index];
          return _buildRequestCard(request, type);
        },
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request, String type) {
    final employee = request['employees'] as Map<String, dynamic>?;
    final employeeName = employee?['full_name']?.toString() ?? 'غير معروف';
    final employeeBranch = employee?['branch']?.toString() ?? '';

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
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primaryOrange.withOpacity(0.1),
                  child: Icon(
                    type == 'leave'
                        ? Icons.beach_access
                        : type == 'advance'
                            ? Icons.payments
                            : type == 'attendance'
                                ? Icons.access_time
                                : Icons.free_breakfast,
                    color: AppColors.primaryOrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employeeName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        employeeBranch,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'معلق',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildRequestDetails(request, type),
            const SizedBox(height: 12),
            _buildActionButtons(request, type),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestDetails(Map<String, dynamic> request, String type) {
    switch (type) {
      case 'leave':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'من: ${request['start_date'] ?? ''} إلى: ${request['end_date'] ?? ''}',
              style: const TextStyle(fontSize: 14),
            ),
            if (request['reason'] != null)
              Text(
                'السبب: ${request['reason']}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        );
      case 'advance':
        final amount = (request['amount'] as num?)?.toDouble() ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المبلغ المطلوب: $amount ج.م',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (request['reason'] != null)
              Text(
                'السبب: ${request['reason']}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
          ],
        );
      case 'attendance':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'نوع الطلب: ${request['request_type'] ?? ''}',
              style: const TextStyle(fontSize: 14),
            ),
            Text(
              'الوقت المطلوب: ${request['requested_time'] ?? ''}',
              style: const TextStyle(fontSize: 14),
            ),
            if (request['reason'] != null)
              Text(
                'السبب: ${request['reason']}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
          ],
        );
      case 'break':
        final duration = request['requested_duration_minutes'] ??
            request['duration_minutes'] ??
            request['break_duration_minutes'] ??
            request['requestedDurationMinutes'] ??
            0;
        final reason = request['reason']?.toString();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'مدة الاستراحة: $duration دقيقة',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            if (reason != null && reason.trim().isNotEmpty)
              Text(
                'السبب: $reason',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
          ],
        );
      default:
        return const SizedBox();
    }
  }

  Widget _buildActionButtons(Map<String, dynamic> request, String type) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _showDecisionDialog(request, type, 'approve'),
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
            onPressed: () => _showDecisionDialog(request, type, 'reject'),
            icon: const Icon(Icons.close),
            label: const Text('رفض'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  void _showDecisionDialog(
      Map<String, dynamic> request, String type, String action) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action == 'approve' ? 'موافقة' : 'رفض'),
        content: TextField(
          controller: reasonController,
          decoration: InputDecoration(
            labelText: action == 'approve' ? 'ملاحظة (اختياري)' : 'سبب الرفض',
            border: const OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _actOnRequest(
                type,
                request['id']?.toString() ?? '',
                action,
                reason: reasonController.text.isNotEmpty ? reasonController.text : null,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: action == 'approve' ? AppColors.success : AppColors.error,
            ),
            child: Text(action == 'approve' ? 'موافقة' : 'رفض'),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            const Text(
              'فشل تحميل الطلبات',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'خطأ غير معروف',
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}