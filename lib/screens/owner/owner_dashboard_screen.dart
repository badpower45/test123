import 'package:flutter/material.dart';
import '../../services/supabase_owner_service.dart';
import '../../services/supabase_branch_service.dart';
import '../../theme/app_colors.dart';
import 'owner_leave_requests_screen.dart';
import 'owner_attendance_requests_screen.dart';

/// Owner Dashboard - Simplified version using Supabase
class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key, required this.ownerId});

  final String ownerId;

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _presentEmployees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() => _loading = true);
    
    try {
      final stats = await SupabaseOwnerService.getDashboardStats();
      final present = await SupabaseBranchService.getCurrentlyPresentEmployees();
      
      if (mounted) {
        setState(() {
          _stats = stats;
          _presentEmployees = present;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('لوحة المالك'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboard,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Statistics Cards
                  const Text(
                    'الإحصائيات',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildStatsGrid(),
                  const SizedBox(height: 24),

                  // Pending Requests
                  const Text(
                    'الطلبات المعلقة',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildRequestsSection(),
                  const SizedBox(height: 24),

                  // Currently Present Employees
                  const Text(
                    'الموظفون الحاليون',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildPresentEmployees(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsGrid() {
    final totalEmployees = _stats['total_employees'] ?? 0;
    final todayAttendance = _stats['today_attendance'] ?? 0;
    final currentlyPresent = _stats['currently_present'] ?? 0;
    final totalPending = _stats['total_pending_requests'] ?? 0;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _StatCard(
          title: 'إجمالي الموظفين',
          value: '$totalEmployees',
          icon: Icons.people,
          color: Colors.blue,
        ),
        _StatCard(
          title: 'حضور اليوم',
          value: '$todayAttendance',
          icon: Icons.check_circle,
          color: Colors.green,
        ),
        _StatCard(
          title: 'الموجودون الآن',
          value: '$currentlyPresent',
          icon: Icons.person_pin_circle,
          color: Colors.orange,
        ),
        _StatCard(
          title: 'طلبات معلقة',
          value: '$totalPending',
          icon: Icons.notifications_active,
          color: Colors.red,
        ),
      ],
    );
  }

  Widget _buildRequestsSection() {
    final pendingLeave = _stats['pending_leave_requests'] ?? 0;
    final pendingAttendance = _stats['pending_attendance_requests'] ?? 0;
    final pendingAdvances = _stats['pending_advance_requests'] ?? 0;

    return Column(
      children: [
        _RequestCard(
          title: 'طلبات الإجازات',
          count: pendingLeave,
          icon: Icons.event_busy,
          color: Colors.purple,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => OwnerLeaveRequestsScreen(ownerId: widget.ownerId),
              ),
            ).then((_) => _loadDashboard());
          },
        ),
        const SizedBox(height: 12),
        _RequestCard(
          title: 'طلبات الحضور',
          count: pendingAttendance,
          icon: Icons.access_time,
          color: Colors.teal,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => OwnerAttendanceRequestsScreen(ownerId: widget.ownerId),
              ),
            ).then((_) => _loadDashboard());
          },
        ),
        const SizedBox(height: 12),
        _RequestCard(
          title: 'طلبات السلف',
          count: pendingAdvances,
          icon: Icons.payments,
          color: Colors.amber,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('شاشة طلبات السلف قيد التطوير')),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPresentEmployees() {
    if (_presentEmployees.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'لا يوجد موظفون حالياً',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    return Column(
      children: _presentEmployees.map((emp) {
        final employeeData = emp['employees'] as Map<String, dynamic>?;
        final name = employeeData?['full_name'] ?? 'غير معروف';
        final role = employeeData?['role'] ?? 'staff';
        final branch = employeeData?['branch'] ?? '';
        final checkInTime = emp['check_in_time'] as String?;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primaryOrange,
              child: Text(
                name.substring(0, 1),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(name),
            subtitle: Text('$role • $branch'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                if (checkInTime != null)
                  Text(
                    DateTime.parse(checkInTime).toLocal().toString().substring(11, 16),
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _RequestCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: count > 0 ? Colors.red : Colors.grey,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
