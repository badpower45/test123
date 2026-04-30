import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
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
  String _filter = 'pending';
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

Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      print('[HR] Starting load...');
      
      // Try loading leave_requests first
      List<dynamic> leaveResp = [];
      try {
        final q = _supabase.from('leave_requests').select();
        leaveResp = await q.eq('status', 'pending').limit(50);
        print('[HR] Leave loaded: ${leaveResp.length}');
      } catch (e) {
        print('[HR] Leave error: $e');
      }
        
      // Salary advances
      List<dynamic> advanceResp = [];
      try {
        advanceResp = await _supabase.from('salary_advances').select().eq('status', 'pending').limit(50);
        print('[HR] Advances loaded: ${advanceResp.length}');
      } catch (e) {
        print('[HR] Advances error: $e');
      }
       
      // Attendance requests
      List<dynamic> attendanceResp = [];
      try {
        attendanceResp = await _supabase.from('attendance_requests').select().eq('status', 'pending').limit(50);
        print('[HR] Attendance loaded: ${attendanceResp.length}');
      } catch (e) {
        print('[HR] Attendance error: $e');
      }
       
      // Breaks
      List<dynamic> breakResp = [];
      try {
        breakResp = await _supabase.from('breaks').select().eq('status', 'PENDING').limit(50);
        print('[HR] Breaks loaded: ${breakResp.length}');
      } catch (e) {
        print('[HR] Breaks error: $e');
      } 

      // Load employees
      List<dynamic> employeesResp = [];
      try {
        employeesResp = await _supabase.from('employees').select().neq('role', 'owner');
        print('[HR] Employees loaded: ${employeesResp.length}');
      } catch (e) {
        print('[HR] Employees error: $e');
      }

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
       
      print('[HR] All loaded!');
    } catch (e) {
      print('[HR] Main error: $e');
      setState(() {
        _leaveRequests = [];
        _advanceRequests = [];
        _attendanceRequests = [];
        _breakRequests = [];
        _loading = false;
      });
    }
  }

  // Old enrichment function - keep for backup
  Future<List<Map<String, dynamic>>> _enrichWithEmployeeData(List<dynamic> requests) async {
    if (requests.isEmpty) return [];

    print('[HR Requests] Fetching employee data for ${requests.length} requests...');

    // Get all employees - simpler approach
    final employeesResp = await _supabase
        .from('employees')
        .select('id, full_name, role, branch');

    print('[HR Requests] Total employees found: ${employeesResp.length}');

    final employeeMap = <String, Map<String, dynamic>>{};
    for (final emp in employeesResp) {
      final id = emp['id']?.toString();
      if (id != null) {
        employeeMap[id] = Map<String, dynamic>.from(emp);
      }
    }

    final enriched = requests.map((r) {
      final empId = r['employee_id']?.toString();
      final enrichedItem = Map<String, dynamic>.from(r);
      if (empId != null && employeeMap.containsKey(empId)) {
        enrichedItem['employees'] = employeeMap[empId];
      }
      return enrichedItem;
    }).toList();

    print('[HR Requests] Enriched ${enriched.length} requests with employee data');
    return enriched;
  }

  Future<void> _actOnRequest(String type, String id, String action, {String? reason}) async {
    try {
      String table;
      switch (type) {
        case 'leave':
          table = 'leave_requests';
          break;
        case 'advance':
          table = 'salary_advances';
          break;
        case 'attendance':
          table = 'attendance_requests';
          break;
        case 'break':
          table = 'breaks';
          break;
        default:
          return;
      }

      await _supabase.from(table).update({
        'status': action == 'approve' ? 'approved' : 'rejected',
        if (reason != null) 'manager_response': reason,
      }).eq('id', id);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'approve' ? '✓ تم الموافقة' : '✓ تم الرفض'),
          backgroundColor: action == 'approve' ? AppColors.success : AppColors.error,
        ),
      );

      _load();
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
    final createdAt = request['created_at']?.toString() ?? '';
    final requestId = request['id']?.toString() ?? '';

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
        return Text(
          'مدة الاستراحة: ${request['requested_duration_minutes'] ?? 0} دقيقة',
          style: const TextStyle(fontSize: 14),
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