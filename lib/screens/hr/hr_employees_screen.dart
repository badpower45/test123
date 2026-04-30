import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/employee.dart';
import '../../theme/app_colors.dart';

class HREmployeesScreen extends StatefulWidget {
  final String hrId;

  const HREmployeesScreen({super.key, required this.hrId});

  @override
  State<HREmployeesScreen> createState() => _HREmployeesScreenState();
}

class _HREmployeesScreenState extends State<HREmployeesScreen> {
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;
  String? _error;
  String? _filterBranch;
  String? _filterRole;
  String _searchQuery = '';

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _loadEmployees();
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await _supabase.from('branches').select('id, name').order('name');
      if (mounted) {
        setState(() => _branches = List<Map<String, dynamic>>.from(branches));
      }
    } catch (e) {
      print('Load branches error: $e');
    }
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var query = _supabase
          .from('employees')
          .select('id, full_name, role, branch, is_active, hourly_rate, phone, email, created_at')
          .neq('role', 'owner');

      if (_filterBranch != null && _filterBranch!.isNotEmpty) {
        query = query.eq('branch', _filterBranch!);
      }
      if (_filterRole != null && _filterRole!.isNotEmpty) {
        query = query.eq('role', _filterRole!);
      }

      final response = await query.order('full_name');

      final allEmployees = List<Map<String, dynamic>>.from(response);

      var filtered = allEmployees;
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        filtered = allEmployees.where((e) {
          return (e['full_name']?.toString().toLowerCase().contains(q) ?? false) ||
              (e['id']?.toString().toLowerCase().contains(q) ?? false) ||
              (e['branch']?.toString().toLowerCase().contains(q) ?? false);
        }).toList();
      }

      if (!mounted) return;
      setState(() {
        _employees = filtered;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'hr':
        return 'موارد بشرية';
      case 'admin':
        return 'إداري';
      case 'manager':
        return 'مدير';
      case 'staff':
        return 'موظف';
      case 'monitor':
        return 'مراقب';
      default:
        return role;
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'owner':
        return Colors.purple;
      case 'hr':
        return Colors.blue;
      case 'admin':
        return Colors.teal;
      case 'manager':
        return AppColors.primaryOrange;
      case 'staff':
        return Colors.green;
      case 'monitor':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildSearchAndFilters(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : _employees.isEmpty
                        ? _buildEmpty()
                        : _buildEmployeeList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'البحث عن موظف...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onChanged: (value) {
              _searchQuery = value;
              _loadEmployees();
            },
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('الكل'),
                  selected: _filterBranch == null && _filterRole == null,
                  onSelected: (_) {
                    setState(() {
                      _filterBranch = null;
                      _filterRole = null;
                    });
                    _loadEmployees();
                  },
                ),
                const SizedBox(width: 8),
                ..._branches.map((branch) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(branch['name']?.toString() ?? ''),
                    selected: _filterBranch == branch['name'],
                    onSelected: (selected) {
                      setState(() {
                        _filterBranch = selected ? branch['name'] : null;
                      });
                      _loadEmployees();
                    },
                  ),
                )),
                const SizedBox(width: 16),
                FilterChip(
                  label: const Text('مديرين'),
                  selected: _filterRole == 'manager',
                  onSelected: (selected) {
                    setState(() {
                      _filterRole = selected ? 'manager' : null;
                    });
                    _loadEmployees();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('موظفين'),
                  selected: _filterRole == 'staff',
                  onSelected: (selected) {
                    setState(() {
                      _filterRole = selected ? 'staff' : null;
                    });
                    _loadEmployees();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeList() {
    return RefreshIndicator(
      onRefresh: _loadEmployees,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _employees.length,
        itemBuilder: (context, index) {
          final employee = _employees[index];
          return _buildEmployeeCard(employee);
        },
      ),
    );
  }

  Widget _buildEmployeeCard(Map<String, dynamic> employee) {
    final role = (employee['role'] as String?) ?? 'staff';
    final isActive = employee['is_active'] as bool? ?? true;
    final branch = employee['branch']?.toString() ?? '';
    final fullName = employee['full_name']?.toString() ?? '';
    final employeeId = employee['id']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getRoleColor(role).withOpacity(0.2),
          child: Icon(
            Icons.person,
            color: _getRoleColor(role),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                fullName,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'غير نشط',
                  style: TextStyle(fontSize: 10, color: Colors.red),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'معرف: $employeeId',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Chip(
                  label: Text(
                    _getRoleLabel(role),
                    style: TextStyle(fontSize: 10, color: _getRoleColor(role)),
                  ),
                  backgroundColor: _getRoleColor(role).withOpacity(0.1),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 8),
                Icon(Icons.store, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    branch,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'view') {
              _showEmployeeDetails(employee);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'view', child: Text('عرض التفاصيل')),
          ],
        ),
      ),
    );
  }

  void _showEmployeeDetails(Map<String, dynamic> employee) {
    final branch = employee['branch']?.toString() ?? '';
    final role = _getRoleLabel(employee['role']?.toString() ?? 'staff');
    final isActive = employee['is_active'] as bool? ?? true;
    final hourlyRate = (employee['hourly_rate'] as num?)?.toDouble() ?? 0;
    final phone = employee['phone']?.toString() ?? '';
    final email = employee['email']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              employee['full_name']?.toString() ?? '',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _detailRow('معرف الموظف', employee['id']?.toString() ?? ''),
            _detailRow('الوظيفة', role),
            _detailRow('الفرع', branch),
            _detailRow('السعر بالساعة', '$hourlyRate ج.م'),
            _detailRow('الحالة', isActive ? 'نشط' : 'غير نشط'),
            if (phone.isNotEmpty) _detailRow('ا��ها��ف', phone),
            if (email.isNotEmpty) _detailRow('البريد', email),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadEmployees,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('لا يوجد موظفين', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}