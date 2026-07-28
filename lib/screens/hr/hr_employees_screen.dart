import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/employee.dart';
import '../../services/supabase_auth_service.dart';
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
      debugPrint('Load branches error: $e');
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
          .select(
            'id, full_name, role, branch, is_active, hourly_rate, leave_allowance, shift_start_time, shift_end_time, phone, email, created_at',
          )
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
        filtered = allEmployees.where((employee) {
          return (employee['full_name']?.toString().toLowerCase().contains(q) ?? false) ||
              (employee['id']?.toString().toLowerCase().contains(q) ?? false) ||
              (employee['branch']?.toString().toLowerCase().contains(q) ?? false);
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

  Future<void> _showAddEmployeeDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _EmployeeFormDialog(branches: _branches),
    );

    if (result == true) {
      _loadEmployees();
    }
  }

  Future<void> _showQuickImportDialog() async {
    if (_branches.isEmpty) {
      await _loadBranches();
    }

    if (!mounted) return;
    final payload = await showDialog<_BulkImportPayload>(
      context: context,
      builder: (context) => _BulkImportDialog(branches: _branches),
    );

    if (payload == null || payload.rows.isEmpty) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final summary = await SupabaseAuthService.upsertEmployeesBulk(
        payload.rows,
      );

      if (!mounted) return;
      Navigator.pop(context);

      final failedIds =
          (summary['failedIds'] as List?)?.map((e) => e.toString()).toList() ??
          <String>[];
      final total = summary['total'] ?? 0;
      final success = summary['success'] ?? 0;
      final failed = summary['failed'] ?? 0;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: failed == 0
              ? AppColors.success
              : AppColors.primaryOrange,
          duration: const Duration(seconds: 6),
          content: Text(
            failedIds.isEmpty
                ? '✓ تم استيراد $success من أصل $total موظف'
                : '✓ تم استيراد $success من أصل $total. فشل $failed: ${failedIds.take(6).join(', ')}',
          ),
        ),
      );

      await _loadEmployees();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'فشل الاستيراد: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _showEditEmployeeDialog(Map<String, dynamic> employee) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _EmployeeFormDialog(
        employee: Employee.fromJson(employee),
        branches: _branches,
      ),
    );

    if (result == true) {
      _loadEmployees();
    }
  }

  Future<void> _deleteEmployee(Map<String, dynamic> employee) async {
    final employeeId = employee['id']?.toString() ?? '';
    final employeeName = employee['full_name']?.toString() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف الموظف "$employeeName"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || employeeId.isEmpty) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await SupabaseAuthService.deleteEmployee(employeeId);

      if (!mounted) return;
      Navigator.pop(context);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تم حذف الموظف بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadEmployees();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل في حذف الموظف'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: AppColors.error,
        ),
      );
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'hr_quick_import_fab',
            onPressed: _showQuickImportDialog,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('استيراد سريع'),
            backgroundColor: Colors.teal,
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'hr_employees_fab',
            onPressed: _showAddEmployeeDialog,
            icon: const Icon(Icons.person_add),
            label: const Text('إضافة موظف'),
            backgroundColor: AppColors.primaryOrange,
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
          Row(
            children: [
              Expanded(
                child: TextField(
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
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showQuickImportDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.upload_file_rounded, size: 20),
                label: const Text('استيراد بيانات'),
              ),
            ],
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
                ..._branches.map(
                  (branch) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(branch['name']?.toString() ?? ''),
                      selected: _filterBranch == branch['name'],
                      onSelected: (selected) {
                        setState(() {
                          _filterBranch = selected ? branch['name']?.toString() : null;
                        });
                        _loadEmployees();
                      },
                    ),
                  ),
                ),
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
    final hourlyRate = (employee['hourly_rate'] as num?)?.toDouble() ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => _showEmployeeDetails(employee),
        leading: CircleAvatar(
          backgroundColor: _getRoleColor(role).withOpacity(0.2),
          child: Icon(Icons.person, color: _getRoleColor(role)),
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
                const Icon(Icons.store, size: 14, color: Colors.grey),
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
            const SizedBox(height: 4),
            Text(
              'سعر الساعة: $hourlyRate ج.م',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'view') {
              _showEmployeeDetails(employee);
            } else if (value == 'edit') {
              _showEditEmployeeDialog(employee);
            } else if (value == 'delete') {
              _deleteEmployee(employee);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'view', child: Text('عرض التفاصيل')),
            PopupMenuItem(value: 'edit', child: Text('تعديل')),
            PopupMenuItem(value: 'delete', child: Text('حذف')),
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
    final leaveAllowance = (employee['leave_allowance'] as num?)?.toDouble() ?? 0;
    final phone = employee['phone']?.toString() ?? '';
    final email = employee['email']?.toString() ?? '';
    final shiftStart = employee['shift_start_time']?.toString() ?? '';
    final shiftEnd = employee['shift_end_time']?.toString() ?? '';

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    employee['full_name']?.toString() ?? '',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showEditEmployeeDialog(employee);
                  },
                  icon: const Icon(Icons.edit_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _detailRow('معرف الموظف', employee['id']?.toString() ?? ''),
            _detailRow('الوظيفة', role),
            _detailRow('الفرع', branch),
            _detailRow('السعر بالساعة', '$hourlyRate ج.م'),
            _detailRow('بدل الإجازة', '$leaveAllowance ج.م'),
            _detailRow('الشيفت', '${shiftStart.isEmpty ? '-' : shiftStart} - ${shiftEnd.isEmpty ? '-' : shiftEnd}'),
            _detailRow('الحالة', isActive ? 'نشط' : 'غير نشط'),
            if (phone.isNotEmpty) _detailRow('الهاتف', phone),
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
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
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

class _EmployeeFormDialog extends StatefulWidget {
  final Employee? employee;
  final List<Map<String, dynamic>> branches;

  const _EmployeeFormDialog({this.employee, required this.branches});

  @override
  State<_EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<_EmployeeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _idController;
  late TextEditingController _nameController;
  late TextEditingController _pinController;
  late TextEditingController _hourlyRateController;
  late TextEditingController _leaveAllowanceController;
  TimeOfDay? _shiftStartTime;
  TimeOfDay? _shiftEndTime;

  String? _selectedBranch;
  String _selectedRole = 'staff';
  bool _isActive = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final employee = widget.employee;
    _idController = TextEditingController(text: employee?.id ?? '');
    _nameController = TextEditingController(text: employee?.fullName ?? '');
    _pinController = TextEditingController(text: employee?.pin ?? '');
    _hourlyRateController = TextEditingController(
      text: employee != null ? employee.hourlyRate.toString() : '',
    );
    _leaveAllowanceController = TextEditingController(
      text: employee != null ? employee.leaveAllowance.toString() : '100',
    );

    if (employee?.shiftStartTime != null) {
      final parts = employee!.shiftStartTime!.split(':');
      if (parts.length >= 2) {
        _shiftStartTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 0,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }

    if (employee?.shiftEndTime != null) {
      final parts = employee!.shiftEndTime!.split(':');
      if (parts.length >= 2) {
        _shiftEndTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 0,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }

    _selectedBranch = employee?.branch;
    _selectedRole = employee?.role.toString().split('.').last ?? 'staff';
    _isActive = employee?.isActive ?? true;
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _pinController.dispose();
    _hourlyRateController.dispose();
    _leaveAllowanceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBranch == null || _selectedBranch!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار الفرع'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final baseData = <String, dynamic>{
        'full_name': _nameController.text.trim(),
        'pin': _pinController.text.trim(),
        'role': _selectedRole,
        'branch': _selectedBranch,
        'hourly_rate': double.tryParse(_hourlyRateController.text.trim()) ?? 0,
        'leave_allowance': double.tryParse(_leaveAllowanceController.text.trim()) ?? 100,
        'shift_start_time': _shiftStartTime != null
            ? '${_shiftStartTime!.hour.toString().padLeft(2, '0')}:${_shiftStartTime!.minute.toString().padLeft(2, '0')}'
            : null,
        'shift_end_time': _shiftEndTime != null
            ? '${_shiftEndTime!.hour.toString().padLeft(2, '0')}:${_shiftEndTime!.minute.toString().padLeft(2, '0')}'
            : null,
        'is_active': _isActive,
      };

      if (widget.employee == null) {
        final payload = <String, dynamic>{
          ...baseData,
          'id': _idController.text.trim(),
        };

        final employee = await SupabaseAuthService.createEmployee(payload);
        if (employee == null) {
          throw Exception('فشل في إضافة الموظف');
        }
      } else {
        final success = await SupabaseAuthService.updateEmployee(
          widget.employee!.id,
          baseData,
        );
        if (!success) {
          throw Exception('فشل في تحديث الموظف');
        }
      }

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.employee == null ? '✓ تم إضافة الموظف بنجاح' : '✓ تم تحديث الموظف بنجاح',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.employee != null;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? 'تعديل موظف' : 'إضافة موظف جديد',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _idController,
                  enabled: !isEdit,
                  decoration: const InputDecoration(
                    labelText: 'كود الموظف',
                    hintText: 'EMP001',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'يرجى إدخال كود الموظف';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الكامل',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'يرجى إدخال الاسم';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pinController,
                  decoration: const InputDecoration(
                    labelText: 'رقم PIN',
                    hintText: '1234',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'يرجى إدخال PIN';
                    }
                    if (value.trim().length != 4) {
                      return 'PIN يجب أن يكون 4 أرقام';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedBranch,
                  decoration: const InputDecoration(
                    labelText: 'الفرع',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                  ),
                  items: widget.branches.map((branch) {
                    return DropdownMenuItem(
                      value: branch['name']?.toString(),
                      child: Text(branch['name']?.toString() ?? ''),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedBranch = value);
                  },
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'يرجى اختيار الفرع';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'الدور الوظيفي',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.work),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'staff', child: Text('موظف')),
                    DropdownMenuItem(value: 'manager', child: Text('مدير')),
                    DropdownMenuItem(value: 'hr', child: Text('موارد بشرية')),
                    DropdownMenuItem(value: 'admin', child: Text('إداري')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedRole = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _hourlyRateController,
                  decoration: const InputDecoration(
                    labelText: 'سعر الساعة',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payments),
                    suffixText: 'ج.م/ساعة',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'يرجى إدخال سعر الساعة';
                    }
                    if (double.tryParse(value.trim()) == null) {
                      return 'يرجى إدخال رقم صحيح';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _leaveAllowanceController,
                  decoration: const InputDecoration(
                    labelText: 'بدل الإجازة',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.card_giftcard),
                    suffixText: 'ج.م',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'يرجى إدخال بدل الإجازة';
                    }
                    if (double.tryParse(value.trim()) == null) {
                      return 'يرجى إدخال رقم صحيح';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('بداية الشيفت'),
                  subtitle: Text(
                    _shiftStartTime != null ? _shiftStartTime!.format(context) : 'لم يتم التحديد',
                  ),
                  leading: const Icon(Icons.access_time),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: _shiftStartTime ?? const TimeOfDay(hour: 9, minute: 0),
                    );
                    if (time != null) {
                      setState(() => _shiftStartTime = time);
                    }
                  },
                  trailing: _shiftStartTime != null
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _shiftStartTime = null),
                        )
                      : null,
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('نهاية الشيفت'),
                  subtitle: Text(
                    _shiftEndTime != null ? _shiftEndTime!.format(context) : 'لم يتم التحديد',
                  ),
                  leading: const Icon(Icons.access_time_filled),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: _shiftEndTime ?? const TimeOfDay(hour: 17, minute: 0),
                    );
                    if (time != null) {
                      setState(() => _shiftEndTime = time);
                    }
                  },
                  trailing: _shiftEndTime != null
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _shiftEndTime = null),
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('نشط'),
                  value: _isActive,
                  onChanged: (value) {
                    setState(() => _isActive = value);
                  },
                  activeColor: AppColors.success,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submitting ? null : () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryOrange,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(isEdit ? 'تحديث' : 'إضافة'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BulkImportPayload {
  final List<Map<String, dynamic>> rows;

  const _BulkImportPayload({required this.rows});
}

class _BulkImportDialog extends StatefulWidget {
  final List<Map<String, dynamic>> branches;

  const _BulkImportDialog({required this.branches});

  @override
  State<_BulkImportDialog> createState() => _BulkImportDialogState();
}

class _BulkImportDialogState extends State<_BulkImportDialog> {
  final TextEditingController _inputController = TextEditingController();
  String? _defaultBranch;
  String _defaultRole = 'staff';
  String _statusText = '';

  static const String _template =
      'id,full_name,pin,role,branch,hourly_rate,shift_start,shift_end,leave_allowance\n'
      'EMP001,محمد أحمد,1234,staff,فرع مدينة نصر,20,09:00,17:00,100\n'
      'EMP002,سارة علي,5678,manager,فرع المعادي,35,10:00,18:00,150';

  @override
  void initState() {
    super.initState();
    if (widget.branches.isNotEmpty) {
      _defaultBranch = widget.branches.first['name']?.toString();
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  String _normalizeRole(String raw) {
    final value = raw.trim().toLowerCase();
    switch (value) {
      case 'owner':
      case 'مالك':
        return 'owner';
      case 'manager':
      case 'مدير':
        return 'manager';
      case 'hr':
      case 'موارد':
      case 'موارد بشرية':
        return 'hr';
      case 'admin':
      case 'إداري':
      case 'اداري':
        return 'admin';
      case 'monitor':
      case 'مراقب':
        return 'monitor';
      default:
        return 'staff';
    }
  }

  String _detectDelimiter(String line) {
    if (line.contains('\t')) return '\t';
    if (line.contains(';')) return ';';
    return ',';
  }

  bool _looksLikeHeader(String firstLine) {
    final line = firstLine.toLowerCase();
    return line.contains('id') ||
        line.contains('full_name') ||
        line.contains('name') ||
        line.contains('كود') ||
        line.contains('الاسم');
  }

  String? _normalizeTime(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(trimmed);
    if (match == null) return null;

    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> _parseRows() {
    final raw = _inputController.text.trim();
    if (raw.isEmpty) {
      throw Exception('الصق البيانات أولًا');
    }

    final lines = raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      throw Exception('لا توجد سطور صالحة للاستيراد');
    }

    final delimiter = _detectDelimiter(lines.first.replaceAll('،', ','));
    final startIndex = _looksLikeHeader(lines.first) ? 1 : 0;
    final rows = <Map<String, dynamic>>[];

    for (var i = startIndex; i < lines.length; i++) {
      final normalizedLine = lines[i].replaceAll('،', ',');
      final parts = normalizedLine
          .split(delimiter)
          .map((e) => e.trim())
          .toList(growable: false);

      if (parts.length < 3) {
        continue;
      }

      final id = parts[0];
      final fullName = parts[1];
      final pin = parts[2];

      if (id.isEmpty || fullName.isEmpty || pin.isEmpty) {
        continue;
      }

      if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
        continue;
      }

      final role = parts.length > 3 && parts[3].isNotEmpty
          ? _normalizeRole(parts[3])
          : _defaultRole;
      final branch = parts.length > 4 && parts[4].isNotEmpty
          ? parts[4]
          : (_defaultBranch ?? '');
      if (branch.trim().isEmpty) {
        continue;
      }
      final hourlyRate = parts.length > 5
          ? (double.tryParse(parts[5]) ?? 0)
          : 0.0;
      final shiftStart = parts.length > 6 ? _normalizeTime(parts[6]) : null;
      final shiftEnd = parts.length > 7 ? _normalizeTime(parts[7]) : null;
      final leaveAllowance = parts.length > 8
          ? (double.tryParse(parts[8]) ?? 100.0)
          : 100.0;

      rows.add({
        'id': id,
        'full_name': fullName,
        'pin': pin,
        'role': role,
        'branch': branch,
        'hourly_rate': hourlyRate,
        'shift_start_time': shiftStart,
        'shift_end_time': shiftEnd,
        'leave_allowance': leaveAllowance,
        'is_active': true,
      });
    }

    if (rows.isEmpty) {
      throw Exception(
        'لم يتم العثور على سطور صالحة. تأكد من التنسيق وPIN = 4 أرقام',
      );
    }

    return rows;
  }

  void _submit() {
    try {
      final rows = _parseRows();
      Navigator.pop(context, _BulkImportPayload(rows: rows));
    } catch (e) {
      setState(
        () => _statusText = e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 760),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'استيراد سريع للموظفين',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: 8),
            const Text(
              'الصق CSV أو نص مفصول بفاصلة/فاصلة منقوطة/Tab. أقل أعمدة مطلوبة: id, full_name, pin',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _defaultBranch,
                    decoration: const InputDecoration(
                      labelText: 'الفرع الافتراضي (لو مش موجود بالسطر)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: widget.branches
                        .map(
                          (branch) => DropdownMenuItem(
                            value: branch['name']?.toString(),
                            child: Text(branch['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _defaultBranch = value);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _defaultRole,
                    decoration: const InputDecoration(
                      labelText: 'الدور الافتراضي',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'staff', child: Text('موظف')),
                      DropdownMenuItem(value: 'manager', child: Text('مدير')),
                      DropdownMenuItem(value: 'hr', child: Text('موارد بشرية')),
                      DropdownMenuItem(value: 'admin', child: Text('إداري')),
                      DropdownMenuItem(value: 'monitor', child: Text('مراقب')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _defaultRole = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _inputController,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  hintText:
                      'EMP001,محمد أحمد,1234,staff,فرع مدينة نصر,20,09:00,17:00,100\nEMP002,سارة علي,5678,manager,فرع المعادي,35,10:00,18:00,150',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            if (_statusText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_statusText, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      const ClipboardData(text: _template),
                    );
                    if (!mounted) return;
                    setState(() => _statusText = 'تم نسخ نموذج جاهز');
                  },
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('نسخ نموذج'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.cloud_upload_rounded),
                  label: const Text('استيراد الآن'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}