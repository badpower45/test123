import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/absence_service.dart';

class ManagerAbsencesPage extends StatefulWidget {
  final String managerId;
  final String branchId;

  const ManagerAbsencesPage({
    super.key,
    required this.managerId,
    required this.branchId,
  });

  @override
  State<ManagerAbsencesPage> createState() => _ManagerAbsencesPageState();
}

class _ManagerAbsencesPageState extends State<ManagerAbsencesPage> {
  List<Map<String, dynamic>> _absences = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAbsences();
  }

  Future<void> _loadAbsences() async {
    setState(() => _loading = true);
    try {
      final absences = await AbsenceService.getPendingAbsences(widget.branchId);
      setState(() {
        _absences = absences;
        _loading = false;
      });
    } catch (e) {
      print('❌ Error loading absences: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _approveAbsence(Map<String, dynamic> absence) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('موافقة على الغياب'),
        content: Text(
          'هل تريد الموافقة على غياب ${absence['employee']['full_name']}؟\n\n'
          'لن يتم خصم أي مبلغ من الموظف.',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('موافق'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await AbsenceService.approveAbsence(
        absenceId: absence['id'],
        managerId: widget.managerId,
        reason: 'موافق على الغياب',
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تمت الموافقة على الغياب'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAbsences();
      }
    }
  }

  Future<void> _rejectAbsence(Map<String, dynamic> absence) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final employee = absence['employee'];
        final hourlyRate = (employee['hourly_rate'] as num?)?.toDouble() ?? 0.0;
        final shiftStart = absence['shift_start_time'] ?? '09:00';
        final shiftEnd = absence['shift_end_time'] ?? '17:00';
        
        // Calculate shift hours
        final shiftHours = _calculateShiftHours(shiftStart, shiftEnd);
        final deduction = 2 * shiftHours * hourlyRate;

        return AlertDialog(
          title: const Text('رفض الغياب', style: TextStyle(color: AppColors.error)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'هل تريد رفض غياب ${employee['full_name']}؟',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text('سيتم خصم يومين من الموظف:'),
              const SizedBox(height: 8),
              _buildDeductionRow('ساعات الشيفت', '$shiftHours ساعة'),
              _buildDeductionRow('سعر الساعة', '$hourlyRate ج.م'),
              _buildDeductionRow('عدد الأيام', 'يومين (2)'),
              const Divider(thickness: 2),
              _buildDeductionRow(
                'المبلغ المخصوم',
                '${deduction.toStringAsFixed(2)} ج.م',
                isTotal: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('رفض وخصم'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final employee = absence['employee'];
      final hourlyRate = (employee['hourly_rate'] as num?)?.toDouble() ?? 0.0;
      
      final success = await AbsenceService.rejectAbsence(
        absenceId: absence['id'],
        employeeId: absence['employee_id'],
        managerId: widget.managerId,
        hourlyRate: hourlyRate,
        shiftStartTime: absence['shift_start_time'] ?? '09:00',
        shiftEndTime: absence['shift_end_time'] ?? '17:00',
        reason: 'مرفوض - خصم يومين',
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تم رفض الغياب وخصم يومين'),
            backgroundColor: AppColors.warning,
          ),
        );
        _loadAbsences();
      }
    }
  }

  double _calculateShiftHours(String startTime, String endTime) {
    try {
      final startParts = startTime.split(':');
      final endParts = endTime.split(':');
      
      final startHour = int.parse(startParts[0]);
      final startMinute = int.parse(startParts[1]);
      final endHour = int.parse(endParts[0]);
      final endMinute = int.parse(endParts[1]);
      
      final startTotalMinutes = (startHour * 60) + startMinute;
      final endTotalMinutes = (endHour * 60) + endMinute;
      
      final diffMinutes = endTotalMinutes - startTotalMinutes;
      return diffMinutes / 60.0;
    } catch (e) {
      return 8.0; // Default
    }
  }

  Widget _buildDeductionRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? AppColors.error : AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: FontWeight.bold,
              color: isTotal ? AppColors.error : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('طلبات الغياب', style: TextStyle(color: Colors.white)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAbsences,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _absences.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'لا توجد طلبات غياب معلقة',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _absences.length,
                  itemBuilder: (context, index) {
                    final absence = _absences[index];
                    final employee = absence['employee'];
                    DateTime absenceDate;
                    try {
                      absenceDate = DateTime.parse(absence['absence_date']?.toString() ?? '');
                    } catch (e) {
                      absenceDate = DateTime.now();
                    }
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppColors.warning.withOpacity(0.2),
                                  child: const Icon(Icons.person, color: AppColors.warning),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        employee['full_name'],
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'تأخر عن الحضور',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            _buildInfoRow(Icons.calendar_today, 'التاريخ', _formatDate(absenceDate)),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              Icons.access_time,
                              'وقت الشيفت',
                              '${absence['shift_start_time']} - ${absence['shift_end_time']}',
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              Icons.payments,
                              'سعر الساعة',
                              '${employee['hourly_rate']} ج.م/ساعة',
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _approveAbsence(absence),
                                    icon: const Icon(Icons.check),
                                    label: const Text('موافق'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.success,
                                      side: const BorderSide(color: AppColors.success),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _rejectAbsence(absence),
                                    icon: const Icon(Icons.close),
                                    label: const Text('رفض وخصم'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
