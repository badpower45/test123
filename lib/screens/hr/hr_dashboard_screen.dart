import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../config/supabase_config.dart';
import '../login_screen.dart';

class HRDashboardScreen extends StatefulWidget {
  final String hrId;

  const HRDashboardScreen({super.key, required this.hrId});

  @override
  State<HRDashboardScreen> createState() => _HRDashboardScreenState();
}

class _HRDashboardScreenState extends State<HRDashboardScreen> {
  bool _loading = true;
  String? _error;

  int _totalEmployees = 0;
  int _totalBranches = 0;
  int _pendingRequests = 0;
  int _checkedInToday = 0;
  int _absencesToday = 0;
  double _totalPayroll = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  final _supabase = Supabase.instance.client;

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final employeesResp = await _supabase.from('employees').select('id').neq('role', 'owner');
      final branchesResp = await _supabase.from('branches').select('id');
      final leaveResp = await _supabase.from('leave_requests').select('id').eq('status', 'pending');
      final advanceResp = await _supabase.from('salary_advances').select('id').eq('status', 'pending');
      final attendanceResp = await _supabase.from('attendance_requests').select('id').eq('status', 'pending');
      final todayStats = await _getTodayStats();

      setState(() {
        _totalEmployees = (employeesResp as List).length;
        _totalBranches = (branchesResp as List).length;
        _pendingRequests = (leaveResp as List).length + (advanceResp as List).length + (attendanceResp as List).length;
        _checkedInToday = todayStats['checkedIn'] as int? ?? 0;
        _absencesToday = todayStats['absences'] as int? ?? 0;
        _totalPayroll = todayStats['totalPayroll'] as double? ?? 0;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>> _getTodayStats() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final pulsesResp = await _supabase
        .from('pulses')
        .select('id, employee_id')
        .gte('created_at', '${today}T00:00:00.000Z')
        .lt('created_at', '${today}T23:59:59.999Z')
        ;

    final uniqueEmployees = <String>{};
    for (final p in pulsesResp) {
      final empId = p['employee_id']?.toString();
      if (empId != null && empId.isNotEmpty) {
        uniqueEmployees.add(empId);
      }
    }

    final absencesResp = await _supabase
        .from('absences')
        .select('id')
        .eq('absence_date', today)
        ;

    return {
      'checkedIn': uniqueEmployees.length,
      'absences': absencesResp.length,
      'totalPayroll': 0.0,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadStats,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildStatsGrid(),
            const SizedBox(height: 24),
            _buildQuickActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              AppColors.primaryOrange,
              AppColors.primaryOrange.withOpacity(0.8),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dashboard, color: Colors.white, size: 32),
                const SizedBox(width: 12),
                Text(
                  'لوحة تحكم الموارد البشرية',
                  style: GoogleFonts.tajawal(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'مرحباً بك! هذه لوحة التحكم المركزية للموارد البشرية',
              style: GoogleFonts.tajawal(
                fontSize: 14,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final currencyFormat = NumberFormat.currency(
      locale: 'ar',
      symbol: 'ج.م',
      decimalDigits: 0,
    );

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        _StatCard(
          title: 'إجمالي الموظفين',
          value: _totalEmployees.toString(),
          icon: Icons.people,
          color: Colors.blue,
        ),
        _StatCard(
          title: 'عدد الفروع',
          value: _totalBranches.toString(),
          icon: Icons.store,
          color: Colors.green,
        ),
        _StatCard(
          title: 'طلبات معلقة',
          value: _pendingRequests.toString(),
          icon: Icons.pending_actions,
          color: Colors.orange,
        ),
        _StatCard(
          title: 'متواجدين اليوم',
          value: '$_checkedInToday / $_totalEmployees',
          icon: Icons.check_circle,
          color: Colors.teal,
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'إجراءات سريعة',
          style: GoogleFonts.tajawal(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.person_add,
                label: 'إضافة موظف',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ميزة الإضافة القادمة قريباً')),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                icon: Icons.request_quote,
                label: 'الطلبات',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('شاشة الطلبات في التبويب المناسب')),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل الخروج'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
  
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await SupabaseConfig.client.auth.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تسجيل الخروج: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 28, color: AppColors.primaryOrange),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}