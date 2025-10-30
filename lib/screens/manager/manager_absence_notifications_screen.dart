import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../services/manager_api_service.dart';
import '../../models/absence_notification_details.dart';

class ManagerAbsenceNotificationsScreen extends StatefulWidget {
  final String managerId;

  const ManagerAbsenceNotificationsScreen({
    super.key,
    required this.managerId,
  });

  @override
  State<ManagerAbsenceNotificationsScreen> createState() =>
      _ManagerAbsenceNotificationsScreenState();
}

class _ManagerAbsenceNotificationsScreenState
    extends State<ManagerAbsenceNotificationsScreen> {
  List<AbsenceNotificationDetails> _notifications = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final notifications = await ManagerApiService.getAbsenceNotifications(widget.managerId);

      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _applyDeduction(AbsenceNotificationDetails notification) async {
    final TextEditingController amountController = TextEditingController();
    final TextEditingController reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تطبيق خصم الغياب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('الموظف: ${notification.employeeName}'),
            Text('تاريخ الغياب: ${notification.absenceDate}'),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'مبلغ الخصم (جنيه)',
                hintText: 'أدخل المبلغ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'السبب (اختياري)',
                hintText: 'وصف سبب الخصم',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text.trim());
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('يرجى إدخال مبلغ صحيح')),
                );
                return;
              }

              try {
                await ManagerApiService.applyAbsenceDeduction(
                  notificationId: notification.id,
                  managerId: widget.managerId,
                  deductionAmount: amount,
                  reason: reasonController.text.trim().isNotEmpty
                      ? reasonController.text.trim()
                      : null,
                );

                if (mounted) {
                  Navigator.pop(context, true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم تطبيق خصم بقيمة $amount جنيه')),
                  );
                  _loadNotifications(); // Refresh list
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('فشل في تطبيق الخصم: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
            ),
            child: const Text('تطبيق الخصم'),
          ),
        ],
      ),
    );

    if (result == true) {
      _loadNotifications();
    }
  }

  Future<void> _excuseAbsence(AbsenceNotificationDetails notification) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('قبول عذر الغياب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('الموظف: ${notification.employeeName}'),
            Text('تاريخ الغياب: ${notification.absenceDate}'),
            const SizedBox(height: 16),
            const Text('هل أنت متأكد من قبول عذر الغياب بدون تطبيق خصم؟'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ManagerApiService.excuseAbsence(
                  notificationId: notification.id,
                  managerId: widget.managerId,
                );

                if (mounted) {
                  Navigator.pop(context, true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم قبول عذر الغياب')),
                  );
                  _loadNotifications(); // Refresh list
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('فشل في قبول العذر: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('قبول العذر'),
          ),
        ],
      ),
    );

    if (result == true) {
      _loadNotifications();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إشعارات الغياب'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        'فشل في تحميل البيانات',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadNotifications,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : _notifications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            'لا توجد إشعارات غياب',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'جميع إشعارات الغياب تمت مراجعتها',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadNotifications,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final notification = _notifications[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.person, color: AppColors.primaryOrange),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          notification.employeeName,
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'غائب',
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontSize: 12,
                                            color: Colors.orange.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        'تاريخ الغياب: ${notification.absenceDate}',
                                        style: GoogleFonts.ibmPlexSansArabic(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time, size: 16, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        'تم الإبلاغ: ${_formatDateTime(notification.notifiedAt)}',
                                        style: GoogleFonts.ibmPlexSansArabic(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _applyDeduction(notification),
                                          icon: const Icon(Icons.money_off, size: 16),
                                          label: const Text('تطبيق خصم'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red.shade600,
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _excuseAbsence(notification),
                                          icon: const Icon(Icons.check_circle, size: 16),
                                          label: const Text('قبول العذر'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green.shade600,
                                            foregroundColor: Colors.white,
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
                    ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return 'منذ ${difference.inMinutes} دقيقة';
      }
      return 'منذ ${difference.inHours} ساعة';
    } else if (difference.inDays == 1) {
      return 'أمس';
    } else if (difference.inDays < 7) {
      return 'منذ ${difference.inDays} أيام';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }
}