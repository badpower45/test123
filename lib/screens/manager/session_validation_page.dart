import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/session_validation_request.dart';
import '../../services/session_validation_service.dart';
import '../../services/app_logger.dart';
import '../../services/auth_service.dart';

class SessionValidationPage extends StatefulWidget {
  const SessionValidationPage({super.key});

  @override
  State<SessionValidationPage> createState() => _SessionValidationPageState();
}

class _SessionValidationPageState extends State<SessionValidationPage> {
  final SessionValidationService _validationService = SessionValidationService.instance;
  List<SessionValidationRequest> _pendingRequests = [];
  bool _isLoading = true;
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPendingRequests();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingRequests() async {
    try {
      setState(() => _isLoading = true);
      
      final authData = await AuthService.getLoginData();
      final managerId = authData['id']?.toString() ?? '';
      
      final requests = await _validationService.getPendingRequestsForManager(managerId);
      
      setState(() {
        _pendingRequests = requests;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.instance.log('Error loading pending requests', level: AppLogger.error, error: e);
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تحميل الطلبات: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleApprove(SessionValidationRequest request) async {
    final notes = await _showNotesDialog(
      title: 'الموافقة على الطلب',
      hint: 'ملاحظات الموافقة (اختياري)',
      confirmText: 'موافقة',
    );

    if (notes == null) return; // User cancelled

    try {
      if (request.id == null) {
        throw Exception('معرف الطلب غير متاح');
      }
      
      await _validationService.approveSessionValidation(
        request.id!,
        notes.isNotEmpty ? notes : 'موافق',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تمت الموافقة على الطلب بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }

      await _loadPendingRequests(); // Refresh list
    } catch (e) {
      AppLogger.instance.log('Error approving request', level: AppLogger.error, error: e);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الموافقة: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleReject(SessionValidationRequest request) async {
    final notes = await _showNotesDialog(
      title: 'رفض الطلب',
      hint: 'سبب الرفض (اختياري)',
      confirmText: 'رفض',
      isReject: true,
    );

    if (notes == null) return; // User cancelled

    try {
      if (request.id == null) {
        throw Exception('معرف الطلب غير متاح');
      }
      
      await _validationService.rejectSessionValidation(
        request.id!,
        notes.isNotEmpty ? notes : 'مرفوض',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تم رفض الطلب'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      await _loadPendingRequests(); // Refresh list
    } catch (e) {
      AppLogger.instance.log('Error rejecting request', level: AppLogger.error, error: e);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الرفض: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _showNotesDialog({
    required String title,
    required String hint,
    required String confirmText,
    bool isReject = false,
  }) async {
    _notesController.clear();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: _notesController,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _notesController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: isReject ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('dd/MM/yyyy hh:mm a', 'ar').format(dateTime);
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    
    if (hours > 0) {
      return '$hours ساعة و $mins دقيقة';
    }
    return '$mins دقيقة';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('طلبات التحقق من الحضور'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadPendingRequests,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _pendingRequests.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 100,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'لا توجد طلبات معلقة',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadPendingRequests,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _pendingRequests.length,
                      itemBuilder: (context, index) {
                        final request = _pendingRequests[index];
                        return _buildRequestCard(request);
                      },
                    ),
                  )
    );
  }

  Widget _buildRequestCard(SessionValidationRequest request) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Employee Info Header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  child: Icon(
                    Icons.person,
                    color: Colors.blue[700],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'موظف ${request.employeeId}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'الفرع: ${request.branchId ?? "غير محدد"}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'معلق',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const Divider(height: 24),

            // Gap Information
            _buildInfoRow(
              icon: Icons.access_time,
              label: 'مدة الانقطاع',
              value: _formatDuration(request.gapDurationMinutes),
              color: Colors.red,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              icon: Icons.calendar_today,
              label: 'بداية الانقطاع',
              value: _formatDateTime(request.gapStartTime),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              icon: Icons.calendar_today,
              label: 'نهاية الانقطاع',
              value: _formatDateTime(request.gapEndTime),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              icon: Icons.error_outline,
              label: 'النبضات المفقودة',
              value: '${request.expectedPulsesCount} نبضة',
              color: Colors.orange,
            ),

            const Divider(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _handleApprove(request),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('موافقة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _handleReject(request),
                    icon: const Icon(Icons.cancel),
                    label: const Text('رفض'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color ?? Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
