import 'package:flutter/material.dart';
import '../../models/advance_request.dart';
import '../../services/manager_api_service.dart';
import '../../services/supabase_attendance_service.dart';
import '../../services/branch_manager_api_service.dart';
import '../../theme/app_colors.dart';

class ManagerAdvanceRequestsTab extends StatefulWidget {
  const ManagerAdvanceRequestsTab({
    super.key,
    required this.managerId,
  });

  final String managerId;

  @override
  State<ManagerAdvanceRequestsTab> createState() => _ManagerAdvanceRequestsTabState();
}

class _ManagerAdvanceRequestsTabState extends State<ManagerAdvanceRequestsTab> {
  List<AdvanceRequest> _requests = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get manager's branch name first
      final employeeStatus = await SupabaseAttendanceService.getEmployeeStatus(widget.managerId);
      final employeeData = employeeStatus['employee'];

      String? branchName;
      if (employeeData is Map<String, dynamic>) {
        branchName = employeeData['branch'] as String?;
        if (branchName == null || branchName.isEmpty) {
          final branchInfo = employeeData['branches'];
          if (branchInfo is Map<String, dynamic>) {
            branchName = branchInfo['name'] as String?;
          }
        }
      }

      if (branchName == null || branchName.toString().isEmpty) {
        throw Exception('المدير غير مرتبط بفرع');
      }
      
      // Use Supabase Edge Function to get branch requests
      final requestsData = await BranchManagerApiService.getBranchRequests(branchName);
      
      if (requestsData['success'] == true) {
        final advanceRequests = requestsData['advanceRequests'] as List? ?? [];
        setState(() {
          _requests = advanceRequests
              .map((json) => AdvanceRequest.fromJson(json))
              .toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _requests = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading advance requests: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _approveRequest(String advanceId) async {
    try {
      await ManagerApiService.reviewAdvanceRequest(
        advanceId: advanceId,
        managerId: widget.managerId,
        approve: true,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت الموافقة على طلب السلفة بنجاح'), backgroundColor: AppColors.success),
      );
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الموافقة: ${e.toString()}'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _rejectRequest(String advanceId) async {
    try {
      await ManagerApiService.reviewAdvanceRequest(
        advanceId: advanceId,
        managerId: widget.managerId,
        approve: false,
        notes: 'تم رفض الطلب',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض طلب السلفة'), backgroundColor: AppColors.error),
      );
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الرفض: ${e.toString()}'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('خطأ: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadRequests,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (_requests.isEmpty) {
      return const Center(
        child: Text('لا توجد طلبات سلف معلقة'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final request = _requests[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      request.employeeId,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.attach_money, size: 16),
                    const SizedBox(width: 8),
                    Text('المبلغ المطلوب: ${request.amount.toStringAsFixed(2)} ج.م'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.account_balance_wallet, size: 16),
                    const SizedBox(width: 8),
                    Text('الأرباح الحالية: ${request.currentEarnings.toStringAsFixed(2)} ج.م'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 16),
                    const SizedBox(width: 8),
                    Text('تاريخ الطلب: ${request.createdAt.toString().split(' ')[0]}'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _rejectRequest(request.id),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      child: const Text('رفض'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _approveRequest(request.id),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                      ),
                      child: const Text('موافقة'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
