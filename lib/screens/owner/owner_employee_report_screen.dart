import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../utils/time_utils.dart';
import '../../theme/app_colors.dart';

class OwnerEmployeeReportScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const OwnerEmployeeReportScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<OwnerEmployeeReportScreen> createState() => _OwnerEmployeeReportScreenState();
}

class _OwnerEmployeeReportScreenState extends State<OwnerEmployeeReportScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _salaryInfo;
  List<Map<String, dynamic>> _approvedLeaves = [];
  List<Map<String, dynamic>> _approvedAdvances = [];
  List<Map<String, dynamic>> _attendanceRecords = [];
  Map<String, dynamic> _summary = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final client = Supabase.instance.client;
    try {
      // جلب معلومات الراتب
      final salaryResp = await client
          .from('up_to_date_salary_with_advances')
          .select()
          .eq('employee_id', widget.employeeId)
          .maybeSingle();

      // جلب الإجازات المعتمدة
      final leavesResp = await client
          .from('leave_requests')
          .select()
          .eq('employee_id', widget.employeeId)
          .eq('status', 'approved')
          .order('created_at', ascending: false)
          .limit(10);

      // جلب السلف المعتمدة
      final advancesResp = await client
          .from('salary_advances')
          .select()
          .eq('employee_id', widget.employeeId)
          .eq('status', 'approved')
          .order('created_at', ascending: false)
          .limit(10);

      // جلب سجلات الحضور الأخيرة
      final attendanceResp = await client
          .from('daily_attendance_summary')
          .select()
          .eq('employee_id', widget.employeeId)
          .order('attendance_date', ascending: false)
          .limit(15);

      // حساب الملخص
      final totalAdvances = (advancesResp as List).fold<double>(
        0,
        (sum, a) => sum + ((a['amount'] as num?)?.toDouble() ?? 0),
      );
      final totalHours = (attendanceResp as List).fold<double>(
        0,
        (sum, a) => sum + ((a['total_hours'] as num?)?.toDouble() ?? 0),
      );
      final totalDays = (attendanceResp as List).length;

      setState(() {
        _salaryInfo = salaryResp;
        _approvedLeaves = (leavesResp as List).cast<Map<String, dynamic>>();
        _approvedAdvances = (advancesResp as List).cast<Map<String, dynamic>>();
        _attendanceRecords = (attendanceResp as List).cast<Map<String, dynamic>>();
        _summary = {
          'totalAdvances': totalAdvances,
          'totalHours': totalHours,
          'totalDays': totalDays,
          'leaveCount': _approvedLeaves.length,
        };
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('تقرير ${widget.employeeName}'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : _contentView(),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 56, color: AppColors.error),
          const SizedBox(height: 12),
          Text(_error!),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }

  Widget _contentView() {
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // بطاقة الراتب
            _salaryCard(),
            const SizedBox(height: 16),

            // ملخص
            _summaryCard(),
            const SizedBox(height: 16),

            // السلف المعتمدة
            _sectionTitle('السلف المعتمدة (${_approvedAdvances.length})'),
            const SizedBox(height: 8),
            if (_approvedAdvances.isEmpty)
              _emptyHint('لا يوجد سلف معتمدة')
            else
              ..._approvedAdvances.map(_advanceCard),
            const SizedBox(height: 16),

            // الإجازات المعتمدة
            _sectionTitle('الإجازات المعتمدة (${_approvedLeaves.length})'),
            const SizedBox(height: 8),
            if (_approvedLeaves.isEmpty)
              _emptyHint('لا يوجد إجازات معتمدة')
            else
              ..._approvedLeaves.map(_leaveCard),
            const SizedBox(height: 16),

            // سجلات الحضور الأخيرة
            _sectionTitle('آخر ${_attendanceRecords.length} يوم حضور'),
            const SizedBox(height: 8),
            if (_attendanceRecords.isEmpty)
              _emptyHint('لا يوجد سجلات حضور')
            else
              _attendanceTable(),
          ],
        ),
      ),
    );
  }

  Widget _salaryCard() {
    final currentSalary = (_salaryInfo?['current_salary'] as num?)?.toDouble() ?? 0;
    final totalNet = (_salaryInfo?['total_net_salary'] as num?)?.toDouble() ?? 0;
    final totalAdvances = (_salaryInfo?['total_approved_advances'] as num?)?.toDouble() ?? 0;
    final availableAdvance = (_salaryInfo?['available_advance_30_percent'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryOrange.withOpacity(0.1),
            AppColors.primaryLight.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryOrange.withOpacity(0.3), width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryOrange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.account_balance_wallet, color: AppColors.primaryOrange, size: 32),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'معلومات الراتب',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 2),
          _salaryRow('الرصيد الحالي', _money(currentSalary), isMain: true),
          _salaryRow('صافي الراتب', _money(totalNet)),
          _salaryRow('إجمالي السلف', _money(totalAdvances), color: Colors.red.shade700),
          _salaryRow('السلف المتاحة (30%)', _money(availableAdvance), color: Colors.green.shade700),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ملخص الأداء', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statBox('أيام', _summary['totalDays'].toString(), Icons.calendar_today, Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _statBox('ساعات', _summary['totalHours'].toStringAsFixed(1), Icons.schedule, Colors.green)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _statBox('إجازات', _summary['leaveCount'].toString(), Icons.beach_access, Colors.orange)),
              const SizedBox(width: 8),
              Expanded(child: _statBox('سلف', _summary['totalAdvances'].toStringAsFixed(0), Icons.payments, Colors.red)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _advanceCard(Map<String, dynamic> adv) {
    final amount = (adv['amount'] as num?)?.toDouble() ?? 0;
    final reason = adv['reason'] ?? '';
    final createdAt = adv['created_at'] ?? adv['createdAt'];
    String date = '-';
    if (createdAt != null) {
      try {
        date = DateFormat('dd/MM/yyyy').format(DateTime.parse(createdAt.toString()));
      } catch (e) {
        date = '-';
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.red,
          child: Icon(Icons.payments, color: Colors.white, size: 20),
        ),
        title: Text(_money(amount), style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${reason.isNotEmpty ? reason : 'بدون سبب'} • $date'),
        trailing: const Icon(Icons.check_circle, color: AppColors.success),
      ),
    );
  }

  Widget _leaveCard(Map<String, dynamic> leave) {
    final startDate = leave['start_date'] ?? leave['startDate'];
    final endDate = leave['end_date'] ?? leave['endDate'];
    final reason = leave['reason'] ?? 'إجازة';
    String from = '-';
    String to = '-';
    if (startDate != null) {
      try {
        from = DateFormat('dd/MM').format(DateTime.parse(startDate.toString()));
      } catch (e) { /* ignore */ }
    }
    if (endDate != null) {
      try {
        to = DateFormat('dd/MM').format(DateTime.parse(endDate.toString()));
      } catch (e) { /* ignore */ }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.orange,
          child: Icon(Icons.beach_access, color: Colors.white, size: 20),
        ),
        title: Text('من $from إلى $to', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(reason),
        trailing: const Icon(Icons.check_circle, color: AppColors.success),
      ),
    );
  }

  Widget _attendanceTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(AppColors.primaryOrange.withOpacity(0.1)),
        columns: const [
          DataColumn(label: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('حضور', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('انصراف', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('الساعات', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: _attendanceRecords.map((att) {
          final date = att['attendance_date'] ?? att['date'];
          String dateStr = '-';
          if (date != null) {
            try {
              dateStr = DateFormat('dd/MM').format(DateTime.parse(date.toString()));
            } catch (e) { /* ignore */ }
          }
          final checkIn = _formatTime(att['check_in_time']);
          final checkOut = _formatTime(att['check_out_time']);
          final hours = (att['total_hours'] as num?)?.toDouble() ?? 0;

          return DataRow(cells: [
            DataCell(Text(dateStr)),
            DataCell(Text(checkIn)),
            DataCell(Text(checkOut)),
            DataCell(Text(hours > 0 ? '${hours.toStringAsFixed(1)} س' : '-')),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryOrange),
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(child: Text(text, style: const TextStyle(color: Colors.grey))),
    );
  }

  Widget _salaryRow(String label, String value, {Color? color, bool isMain = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isMain ? FontWeight.bold : FontWeight.normal,
              fontSize: isMain ? 16 : 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isMain ? FontWeight.bold : FontWeight.w600,
              color: color ?? (isMain ? AppColors.primaryOrange : AppColors.textPrimary),
              fontSize: isMain ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }

  String _money(num v) => '${v.toDouble().toStringAsFixed(2)} ج.م';

  String _formatTime(dynamic time) {
    if (time == null) return '-';
    final timeStr = time.toString();
    return TimeUtils.formatTimeShort(timeStr);
  }
}
