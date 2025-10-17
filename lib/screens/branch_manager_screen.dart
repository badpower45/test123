import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/branch_manager_api_service.dart';


class BranchManagerScreen extends StatefulWidget {
  final String managerId;
  final String branchName;
  const BranchManagerScreen({super.key, required this.managerId, required this.branchName});

  @override
  State<BranchManagerScreen> createState() => _BranchManagerScreenState();
}

class _BranchManagerScreenState extends State<BranchManagerScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _requests;
  Map<String, dynamic>? _attendanceReport;

  @override
  void initState() {
    super.initState();
    _fetchData();
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
      await BranchManagerApiService.actOnRequest(type: type, id: id, action: action);
      await _fetchData();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تنفيذ العملية بنجاح')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: ${e.toString()}'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('لوحة مدير الفرع (${widget.branchName})'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildSectionTitle('طلبات الموظفين'),
                    _buildRequestsList(),
                    const SizedBox(height: 24),
                    _buildSectionTitle('تقرير الحضور اليومي'),
                    _buildAttendanceReport(),
                    const SizedBox(height: 24),
                    _buildSectionTitle('تنبيهات الغياب بدون إذن'),
                    _buildAbsenceAlerts(),
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

  Widget _buildRequestsList() {
    if (_requests == null) return const SizedBox();
    final leave = _requests!['leaveRequests'] as List? ?? [];
    final advance = _requests!['advanceRequests'] as List? ?? [];
    final attendance = _requests!['attendanceRequests'] as List? ?? [];
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
    if (items.isEmpty) return const Text('لا يوجد طلبات حالياً', style: TextStyle(color: Colors.grey));
    return Column(children: items);
  }

  Widget _buildRequestCard(Map req, String type) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('نوع الطلب: $type', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('الموظف: ${req['employeeId'] ?? ''}'),
            if (type == 'leave') ...[
              Text('من: ${req['startDate'] ?? ''} إلى: ${req['endDate'] ?? ''}'),
              Text('السبب: ${req['reason'] ?? ''}'),
            ],
            if (type == 'advance') ...[
              Text('المبلغ: ${req['amount'] ?? ''}'),
              Text('تاريخ الطلب: ${req['requestDate'] ?? ''}'),
            ],
            if (type == 'attendance') ...[
              Text('نوع الطلب: ${req['requestType'] ?? ''}'),
              Text('السبب: ${req['reason'] ?? ''}'),
            ],
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => _actOnRequest(type, req['id'], 'approve'),
                  child: const Text('موافقة'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => _actOnRequest(type, req['id'], 'reject'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('رفض'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceReport() {
    if (_attendanceReport == null) return const SizedBox();
    final report = _attendanceReport!['report'] as List? ?? [];
    if (report.isEmpty) return const Text('لا يوجد حضور اليوم', style: TextStyle(color: Colors.grey));
    return Column(
      children: report.map<Widget>((att) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            title: Text('الموظف: ${att['employeeId'] ?? ''}'),
            subtitle: Text('دخول: ${att['checkInTime'] ?? '-'} | خروج: ${att['checkOutTime'] ?? '-'}'),
            trailing: Text('ساعات العمل: ${att['workHours'] ?? '-'}'),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAbsenceAlerts() {
    if (_requests == null) return const SizedBox();
    final absence = _requests!['absenceNotifications'] as List? ?? [];
    if (absence.isEmpty) return const Text('لا يوجد تنبيهات غياب حالياً', style: TextStyle(color: Colors.grey));
    return Column(
      children: absence.map<Widget>((alert) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الموظف: ${alert['employeeId'] ?? ''}'),
                Text('تاريخ الغياب: ${alert['absenceDate'] ?? ''}'),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () => _actOnRequest('absence', alert['id'], 'approve'),
                      child: const Text('موافقة على الخصم'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => _actOnRequest('absence', alert['id'], 'reject'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('رفض'),
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
