import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../services/supabase_requests_service.dart';

class OwnerManagerRequestsScreen extends StatefulWidget {
  const OwnerManagerRequestsScreen({super.key});

  @override
  State<OwnerManagerRequestsScreen> createState() => _OwnerManagerRequestsScreenState();
}

class _OwnerManagerRequestsScreenState extends State<OwnerManagerRequestsScreen> {
  bool _loading = true;
  String? _error;
  String _filter = 'pending'; // pending|approved|rejected|all
  List<Map<String, dynamic>> _leave = [];
  List<Map<String, dynamic>> _advance = [];
  List<Map<String, dynamic>> _attendance = [];
  List<Map<String, dynamic>> _breaks = [];

  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _subscribe() async {
    final client = Supabase.instance.client;
    _channel = client
        .channel('owner_manager_requests')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'leave_requests', callback: (_) => _load())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'salary_advances', callback: (_) => _load())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'attendance_requests', callback: (_) => _load())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'breaks', callback: (_) => _load())
        .subscribe();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        SupabaseRequestsService.getAllLeaveRequestsWithEmployees(status: _filter == 'all' ? null : _filter),
        SupabaseRequestsService.getAllSalaryAdvanceRequestsWithEmployees(status: _filter == 'all' ? null : _filter),
        SupabaseRequestsService.getAllAttendanceRequestsWithEmployees(status: _filter == 'all' ? null : _filter),
        SupabaseRequestsService.getAllBreaksWithEmployees(status: _filter == 'all' ? null : _filter),
      ]);
      // Filter only manager role
      List<Map<String, dynamic>> onlyManagers(List<Map<String, dynamic>> list) {
        return list.where((row) {
          final emp = row['employees'];
          if (emp is Map<String, dynamic>) {
            return (emp['role'] == 'manager');
          }
          return false;
        }).toList();
      }
      setState(() {
        _leave = onlyManagers(results[0]);
        _advance = onlyManagers(results[1]);
        _attendance = onlyManagers(results[2]);
        _breaks = onlyManagers(results[3]);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات المديرين'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'تصفية',
            onSelected: (v){ setState(()=>_filter=v); _load(); },
            icon: const Icon(Icons.filter_list),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'all', child: Text('الكل')),
              PopupMenuItem(value: 'pending', child: Text('قيد الانتظار')),
              PopupMenuItem(value: 'approved', child: Text('موافق عليها')),
              PopupMenuItem(value: 'rejected', child: Text('مرفوضة')),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null ? _errorView() : _content(),
    );
  }

  Widget _errorView(){
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size:48, color: AppColors.error),
            const SizedBox(height:12),
          Text(_error!),
          const SizedBox(height:12),
          ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }

  Widget _content(){
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section('إجازات المديرين', _leave, Icons.beach_access, 'leave'),
        _section('سلف المديرين', _advance, Icons.payments, 'advance'),
        _section('طلبات الحضور (مديرين)', _attendance, Icons.calendar_today, 'attendance'),
        _section('استراحات المديرين', _breaks, Icons.free_breakfast, 'break'),
      ],
    );
  }

  Widget _section(String title, List<Map<String,dynamic>> data, IconData icon, String type){
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children:[
            Icon(icon, color: AppColors.primaryOrange),
            const SizedBox(width:8),
            Text('$title (${data.length})', style: const TextStyle(fontSize:16,fontWeight: FontWeight.bold,color: AppColors.primaryOrange)),
          ],
        ),
        const SizedBox(height:8),
        if (data.isEmpty) const Text('لا يوجد بيانات', style: TextStyle(color: Colors.grey))
        else ...data.map((row) => _requestCard(row, type)),
        const SizedBox(height:20)
      ],
    );
  }

  Future<void> _actOn(String type, String id, String action) async {
    try {
      final client = Supabase.instance.client;
      final newStatus = action == 'approve' ? 'approved' : 'rejected';
      if (type == 'leave') {
        await client.from('leave_requests').update({'status': newStatus}).eq('id', id);
      } else if (type == 'advance') {
        await client.from('salary_advances').update({'status': newStatus}).eq('id', id);
      } else if (type == 'attendance') {
        await client.from('attendance_requests').update({'status': newStatus}).eq('id', id);
      } else if (type == 'break') {
        await client.from('breaks').update({'status': newStatus.toUpperCase()}).eq('id', id);
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ تم تنفيذ العملية')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error));
    }
  }

  Widget _requestCard(Map<String,dynamic> row, String type){
    final emp = row['employees'] as Map<String,dynamic>?;
    final name = emp?['full_name'] ?? '—';
    final role = emp?['role'] ?? '—';
    final branch = emp?['branch'] ?? '—';
    final status = (row['status'] ?? 'pending').toString();
    // Extract detail fields per type
    String details = '';
    if (type == 'leave') {
      final from = row['start_date'] ?? row['startDate'] ?? '-';
      final to = row['end_date'] ?? row['endDate'] ?? '-';
      final reason = (row['reason'] ?? '').toString();
      details = 'من: $from إلى: $to${reason.isNotEmpty ? ' • سبب: $reason' : ''}';
    } else if (type == 'advance') {
      final amount = row['amount'];
      final reason = (row['reason'] ?? '').toString();
      details = 'مبلغ: ${amount ?? '-'}${reason.isNotEmpty ? ' • سبب: $reason' : ''}';
    } else if (type == 'attendance') {
      final reqType = row['request_type'] ?? row['requestType'] ?? '-';
      final requestedTime = row['requested_time'] ?? row['requestedTime'];
      final reason = (row['reason'] ?? '').toString();
      details = 'نوع: $reqType${requestedTime != null ? ' • وقت: $requestedTime' : ''}${reason.isNotEmpty ? ' • سبب: $reason' : ''}';
    } else if (type == 'break') {
      final duration = row['requested_duration_minutes'] ?? row['duration_minutes'] ?? '-';
      final created = row['created_at'] ?? row['createdAt'] ?? '';
      details = 'مدة: $duration دقيقة${created.toString().isNotEmpty ? ' • طلب: $created' : ''}';
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical:6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person)),
                const SizedBox(width:8),
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
                _chip(status),
              ],
            ),
            const SizedBox(height:4),
            Text('فرع: $branch • دور: $role'),
            if (details.isNotEmpty) ...[
              const SizedBox(height:4),
              Text(details, style: const TextStyle(fontSize:12, color: AppColors.textSecondary)),
            ],
            if (status.toLowerCase() == 'pending' || status.toUpperCase() == 'PENDING') ...[
              const SizedBox(height:8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _actOn(type, row['id'] as String, 'approve'),
                      icon: const Icon(Icons.check),
                      label: const Text('موافقة'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(width:8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _actOn(type, row['id'] as String, 'reject'),
                      icon: const Icon(Icons.close),
                      label: const Text('رفض'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
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

  Widget _chip(String status){
    Color c; String l;
    switch(status){
      case 'approved': c= AppColors.success; l='موافق'; break;
      case 'rejected': c= AppColors.error; l='مرفوض'; break;
      case 'active': c= Colors.blue; l='نشط'; break;
      case 'completed': c= Colors.green; l='مكتمل'; break;
      default: c= Colors.orange; l='انتظار';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal:8, vertical:4),
      decoration: BoxDecoration(color: c.withOpacity(.15), borderRadius: BorderRadius.circular(6)),
      child: Text(l, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize:12)),
    );
  }
}
