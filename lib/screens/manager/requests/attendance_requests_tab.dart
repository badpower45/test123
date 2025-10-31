import 'package:flutter/material.dart';
import '../../../models/attendance_request.dart';
import '../../../services/requests_api_service.dart';
import '../../../theme/app_colors.dart';

class ManagerAttendanceRequestsTab extends StatefulWidget {
  const ManagerAttendanceRequestsTab({super.key, required this.managerId});
  final String managerId;

  @override
  State<ManagerAttendanceRequestsTab> createState() => _ManagerAttendanceRequestsTabState();
}

class _ManagerAttendanceRequestsTabState extends State<ManagerAttendanceRequestsTab> {
  List<AttendanceRequest> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() { _loading = true; _error = null; });
    try {
      final requests = await RequestsApiService.fetchAttendanceRequests(widget.managerId);
      if (mounted) setState(() { _requests = requests; _loading = false; });
    } catch (error) {
      if (mounted) setState(() { _error = error.toString(); _loading = false; });
    }
  }

  Future<void> _openNewRequestSheet() async {
    final request = await showModalBottomSheet<AttendanceRequest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AttendanceRequestSheet(managerId: widget.managerId),
    );

    if (request != null && mounted) {
      setState(() { _requests = [request, ..._requests]; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم إرسال طلب تصحيح الحضور بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ElevatedButton.icon(
            onPressed: _openNewRequestSheet,
            icon: const Icon(Icons.edit_calendar),
            label: const Text('طلب تصحيح حضور/انصراف'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'الطلبات السابقة',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Center(
              child: Column(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'حدث خطأ: $_error',
                    style: const TextStyle(color: AppColors.error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadRequests,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            )
          else if (_requests.isEmpty)
            const Center(
              child: Column(
                children: [
                  Icon(Icons.inbox, color: AppColors.textSecondary, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'لا توجد طلبات',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          else
            for (final request in _requests)
              _AttendanceRequestCard(request: request),
        ],
      ),
    );
  }
}

// --- BottomSheet لتقديم الطلب ---
class _AttendanceRequestSheet extends StatefulWidget {
  const _AttendanceRequestSheet({required this.managerId});
  final String managerId;

  @override
  State<_AttendanceRequestSheet> createState() => _AttendanceRequestSheetState();
}

class _AttendanceRequestSheetState extends State<_AttendanceRequestSheet> {
  String _requestType = 'check_in'; // 'check_in' or 'check_out'
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final _reasonController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (time == null) return;

    setState(() {
      _selectedDate = date;
      _selectedTime = time;
    });
  }

  Future<void> _submit() async {
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار التاريخ والوقت'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (_reasonController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى كتابة السبب'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final requestedTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    try {
      final requestType = _requestType == 'check_in' ? AttendanceRequestType.checkIn : AttendanceRequestType.checkOut;
      final request = await RequestsApiService.submitAttendanceRequest(
        employeeId: widget.managerId,
        requestType: requestType,
        requestedTime: requestedTime,
        reason: _reasonController.text,
      );
      if (mounted) Navigator.of(context).pop(request);
    } catch (error) {
      if (mounted) setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ: ${error.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'طلب تصحيح حضور',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'نوع الطلب',
              style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'check_in', label: Text('نسيت حضور')),
                ButtonSegment(value: 'check_out', label: Text('نسيت انصراف')),
              ],
              selected: {_requestType},
              onSelectionChanged: (val) => setState(() => _requestType = val.first),
            ),
            const SizedBox(height: 16),
            const Text(
              'التاريخ والوقت',
              style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _selectDateTime,
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _selectedDate == null
                    ? 'اختر التاريخ والوقت'
                    : '${_selectedDate!.toIso8601String().substring(0, 10)} - ${_selectedTime!.format(context)}'
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: AppColors.primaryOrange),
                foregroundColor: AppColors.primaryOrange,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'السبب',
              style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                hintText: 'اكتب السبب هنا...',
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primaryOrange),
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('إرسال الطلب'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- كارت عرض الطلب ---
class _AttendanceRequestCard extends StatelessWidget {
  const _AttendanceRequestCard({required this.request});
  final AttendanceRequest request;

  Color _statusColor() {
    switch (request.status) {
      case 'pending': return AppColors.warning;
      case 'approved': return AppColors.success;
      case 'rejected': return AppColors.error;
      default: return AppColors.textSecondary;
    }
  }

  String _statusText() {
    switch (request.status) {
      case 'pending': return 'معلق';
      case 'approved': return 'مُعتمد';
      case 'rejected': return 'مرفوض';
      default: return 'غير محدد';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  request.requestType == 'check_in' ? Icons.login : Icons.logout,
                  color: AppColors.primaryOrange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    request.requestType == 'check_in' ? 'تصحيح حضور' : 'تصحيح انصراف',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusText(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'الوقت المطلوب: ${_formatDate(request.requestedTime)}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'السبب: ${request.reason}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (request.createdAt != null)
              Text(
                'تاريخ الطلب: ${_formatDate(request.createdAt!)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
