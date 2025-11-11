import 'package:flutter/material.dart';
import '../../../models/attendance_request.dart';
import '../../../services/requests_api_service.dart';
import '../../../services/supabase_requests_service.dart';
import '../../../theme/app_colors.dart';

class AttendanceRequestsTab extends StatefulWidget {
  const AttendanceRequestsTab({super.key, required this.employeeId});
  final String employeeId;

  @override
  State<AttendanceRequestsTab> createState() => _AttendanceRequestsTabState();
}

class _AttendanceRequestsTabState extends State<AttendanceRequestsTab> {
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
      final requestsData = await SupabaseRequestsService.getAttendanceRequests(
        employeeId: widget.employeeId,
      );
      
      // Convert from Supabase format to AttendanceRequest model
      final requests = requestsData.map((data) => AttendanceRequest.fromJson(data)).toList();
      
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
      builder: (context) => _AttendanceRequestSheet(employeeId: widget.employeeId),
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
  const _AttendanceRequestSheet({required this.employeeId});
  final String employeeId;

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
      final response = await SupabaseRequestsService.createAttendanceRequest(
        employeeId: widget.employeeId,
        requestType: _requestType, // 'check_in' or 'check_out'
        reason: _reasonController.text,
        requestedTime: requestedTime,
      );
      
      if (response == null) {
        throw Exception('فشل إرسال الطلب');
      }
      
      // Convert response to AttendanceRequest model
      final request = AttendanceRequest.fromJson(response);
      
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
              style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _RequestTypeButton(
                    isSelected: _requestType == 'check_in',
                    icon: Icons.login,
                    label: 'تسجيل حضور',
                    subtitle: 'نسيت الحضور',
                    color: Colors.green,
                    onTap: () => setState(() => _requestType = 'check_in'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RequestTypeButton(
                    isSelected: _requestType == 'check_out',
                    icon: Icons.logout,
                    label: 'تسجيل انصراف',
                    subtitle: 'نسيت الانصراف',
                    color: Colors.orange,
                    onTap: () => setState(() => _requestType = 'check_out'),
                  ),
                ),
              ],
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

// --- زر اختيار نوع الطلب ---
class _RequestTypeButton extends StatelessWidget {
  const _RequestTypeButton({
    required this.isSelected,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final bool isSelected;
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey.shade100,
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? color : Colors.grey.shade600,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? color : Colors.grey.shade700,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? color.withOpacity(0.8) : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
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
      case RequestStatus.pending: return AppColors.warning;
      case RequestStatus.approved: return AppColors.success;
      case RequestStatus.rejected: return AppColors.error;
    }
  }

  String _statusText() {
    switch (request.status) {
      case RequestStatus.pending: return 'معلق';
      case RequestStatus.approved: return 'مُعتمد';
      case RequestStatus.rejected: return 'مرفوض';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isApproved = request.status == RequestStatus.approved;
    final isRejected = request.status == RequestStatus.rejected;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isApproved || isRejected ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isApproved 
              ? AppColors.success 
              : isRejected 
                  ? AppColors.error 
                  : Colors.transparent,
          width: isApproved || isRejected ? 2 : 0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (request.requestType == AttendanceRequestType.checkIn 
                        ? Colors.green 
                        : Colors.orange).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    request.requestType == AttendanceRequestType.checkIn 
                        ? Icons.login 
                        : Icons.logout,
                    color: request.requestType == AttendanceRequestType.checkIn 
                        ? Colors.green 
                        : Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.requestType == AttendanceRequestType.checkIn 
                            ? 'طلب تسجيل حضور' 
                            : 'طلب تسجيل انصراف',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'الوقت المطلوب: ${_formatDate(request.requestedTime)} ${request.requestedTime.hour.toString().padLeft(2, '0')}:${request.requestedTime.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _statusColor(),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusText(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.description, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      const Text(
                        'السبب:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    request.reason,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  'تاريخ الطلب: ${_formatDate(request.createdAt)}',
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
              ],
            ),
            // عرض نتيجة المراجعة
            if (isApproved || isRejected) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (isApproved ? AppColors.success : AppColors.error).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isApproved ? AppColors.success : AppColors.error,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isApproved ? Icons.check_circle : Icons.cancel,
                          size: 18,
                          color: isApproved ? AppColors.success : AppColors.error,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isApproved ? 'تم القبول ✓' : 'تم الرفض ✗',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isApproved ? AppColors.success : AppColors.error,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    if (request.reviewedBy != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'المراجع: ${request.reviewedBy}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                    if (isRejected && request.rejectionReason != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'سبب الرفض: ${request.rejectionReason}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}