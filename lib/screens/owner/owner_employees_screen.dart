import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/employee.dart';
import '../../services/supabase_auth_service.dart';
import '../../services/supabase_branch_service.dart';
import '../../theme/app_colors.dart';

class OwnerEmployeesScreen extends StatefulWidget {
  const OwnerEmployeesScreen({super.key});

  @override
  State<OwnerEmployeesScreen> createState() => _OwnerEmployeesScreenState();
}

class _OwnerEmployeesScreenState extends State<OwnerEmployeesScreen> {
  List<Employee> _employees = [];
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;
  String? _error;
  String? _filterBranch;
  String? _filterRole;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _loadEmployees();
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await SupabaseBranchService.getAllBranches();
      if (mounted) {
        setState(() => _branches = branches);
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
      final employees = await SupabaseAuthService.getAllEmployees();

      // Apply filters
      var filtered = employees;
      if (_filterBranch != null) {
        filtered = filtered.where((e) => e.branch == _filterBranch).toList();
      }
      if (_filterRole != null) {
        filtered = filtered
            .where((e) => e.role.toString().split('.').last == _filterRole)
            .toList();
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        filtered = filtered.where((e) {
          return e.id.toLowerCase().contains(q) ||
              e.fullName.toLowerCase().contains(q) ||
              e.branch.toLowerCase().contains(q);
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

  Future<void> _showEditEmployeeDialog(Employee employee) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _EmployeeFormDialog(employee: employee, branches: _branches),
    );

    if (result == true) {
      _loadEmployees();
    }
  }

  Future<void> _deleteEmployee(Employee employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف الموظف "${employee.fullName}"؟'),
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

    if (confirmed != true) return;

    // Show loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Use Supabase directly to delete employee
      final success = await SupabaseAuthService.deleteEmployee(employee.id);

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

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
            content: Text('فشل في حذف الموظف. قد يكون هناك سجلات مرتبطة به.'),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('إدارة الموظفين'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: 'استيراد سريع',
            onPressed: _showQuickImportDialog,
          ),
          IconButton(
            icon: const Icon(Icons.filter_alt_off),
            tooltip: 'مسح الفلاتر',
            onPressed: () {
              setState(() {
                _filterBranch = null;
                _filterRole = null;
                _searchQuery = '';
              });
              _loadEmployees();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Card(
              elevation: 0,
              color: const Color(0xFFFFF4EC),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFFFDEC9)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'بحث بالكود أو الاسم أو الفرع',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                        _loadEmployees();
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            value: _filterBranch,
                            decoration: const InputDecoration(
                              labelText: 'الفرع',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('الكل'),
                              ),
                              ..._branches.map(
                                (b) => DropdownMenuItem(
                                  value: b['name'] as String,
                                  child: Text(b['name'] as String),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() => _filterBranch = value);
                              _loadEmployees();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            value: _filterRole,
                            decoration: const InputDecoration(
                              labelText: 'الدور',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem<String>(
                                value: null,
                                child: Text('الكل'),
                              ),
                              DropdownMenuItem(
                                value: 'owner',
                                child: Text('مالك'),
                              ),
                              DropdownMenuItem(
                                value: 'manager',
                                child: Text('مدير'),
                              ),
                              DropdownMenuItem(
                                value: 'hr',
                                child: Text('موارد بشرية'),
                              ),
                              DropdownMenuItem(
                                value: 'staff',
                                child: Text('موظف'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() => _filterRole = value);
                              _loadEmployees();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _StatChip(
                          icon: Icons.groups_2,
                          label: 'العدد الحالي',
                          value: '${_employees.length}',
                          color: AppColors.info,
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          icon: Icons.upload_file,
                          label: 'استيراد سريع',
                          value: 'CSV/نص',
                          color: AppColors.primaryOrange,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Employees List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 56,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: 16),
                        Text('خطأ: $_error'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadEmployees,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                : _employees.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 56,
                          color: AppColors.textTertiary,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'لا يوجد موظفون',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadEmployees,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                      itemCount: _employees.length,
                      itemBuilder: (context, index) {
                        final employee = _employees[index];
                        return _EmployeeCard(
                          employee: employee,
                          onEdit: () => _showEditEmployeeDialog(employee),
                          onDelete: () => _deleteEmployee(employee),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddEmployeeDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة موظف'),
        backgroundColor: AppColors.primaryOrange,
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(fontWeight: FontWeight.w700, color: color),
                  ),
                ],
              ),
            ),
          ],
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
      'id,full_name,pin,role,branch,hourly_rate,shift_start,shift_end\n'
      'EMP001,محمد أحمد,1234,staff,فرع مدينة نصر,20,09:00,17:00\n'
      'EMP002,سارة علي,5678,manager,فرع المعادي,35,10:00,18:00';

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
        return 'admin';
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

      rows.add({
        'id': id,
        'full_name': fullName,
        'pin': pin,
        'role': role,
        'branch': branch,
        'hourly_rate': hourlyRate,
        'shift_start_time': shiftStart,
        'shift_end_time': shiftEnd,
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
                      'EMP001,محمد أحمد,1234,staff,فرع مدينة نصر,20,09:00,17:00\nEMP002,سارة علي,5678,manager,فرع المعادي,35,10:00,18:00',
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

class _EmployeeCard extends StatelessWidget {
  final Employee employee;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EmployeeCard({
    required this.employee,
    required this.onEdit,
    required this.onDelete,
  });

  String _getRoleText(EmployeeRole role) {
    switch (role) {
      case EmployeeRole.owner:
        return 'مالك';
      case EmployeeRole.manager:
        return 'مدير';
      case EmployeeRole.hr:
        return 'موارد بشرية';
      case EmployeeRole.staff:
        return 'موظف';
      case EmployeeRole.monitor:
        return 'مراقب';
      default:
        return 'موظف';
    }
  }

  Color _getRoleColor(EmployeeRole role) {
    switch (role) {
      case EmployeeRole.owner:
        return Colors.purple;
      case EmployeeRole.manager:
        return Colors.blue;
      case EmployeeRole.hr:
        return Colors.green;
      case EmployeeRole.staff:
        return Colors.orange;
      case EmployeeRole.monitor:
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFFFDEC9)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: _getRoleColor(employee.role).withOpacity(0.12),
          child: Text(
            employee.fullName.substring(0, 1),
            style: TextStyle(
              color: _getRoleColor(employee.role),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          employee.fullName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getRoleColor(employee.role).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getRoleText(employee.role),
                    style: TextStyle(
                      fontSize: 12,
                      color: _getRoleColor(employee.role),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    employee.branch,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'الكود: ${employee.id} | PIN: ${employee.pin}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        trailing: SizedBox(
          width: 92,
          child: Row(
            children: [
              IconButton(
                tooltip: 'تعديل',
                onPressed: onEdit,
                icon: const Icon(
                  Icons.edit_rounded,
                  color: AppColors.primaryOrange,
                ),
              ),
              IconButton(
                tooltip: 'حذف',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeFormDialog extends StatefulWidget {
  final Employee? employee; // null = add, not null = edit
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
  TimeOfDay? _shiftStartTime;
  TimeOfDay? _shiftEndTime;

  String? _selectedBranch;
  String _selectedRole = 'staff';
  bool _isActive = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final emp = widget.employee;
    _idController = TextEditingController(text: emp?.id ?? '');
    _nameController = TextEditingController(text: emp?.fullName ?? '');
    _pinController = TextEditingController(text: emp?.pin ?? '');
    _hourlyRateController = TextEditingController(
      text: emp?.hourlyRate != null ? emp!.hourlyRate.toString() : '',
    );

    // Parse shift times
    if (emp?.shiftStartTime != null) {
      final parts = emp!.shiftStartTime!.split(':');
      _shiftStartTime = TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    }
    if (emp?.shiftEndTime != null) {
      final parts = emp!.shiftEndTime!.split(':');
      _shiftEndTime = TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    }

    _selectedBranch = emp?.branch;
    _selectedRole = emp?.role.toString().split('.').last ?? 'staff';
    _isActive = emp?.isActive ?? true;
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _pinController.dispose();
    _hourlyRateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBranch == null) {
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
      final data = {
        'id': _idController.text.trim(),
        'full_name': _nameController.text.trim(),
        'pin': _pinController.text.trim(),
        'role': _selectedRole,
        'branch': _selectedBranch,
        'hourly_rate': double.tryParse(_hourlyRateController.text.trim()) ?? 0,
        'shift_start_time': _shiftStartTime != null
            ? '${_shiftStartTime!.hour.toString().padLeft(2, '0')}:${_shiftStartTime!.minute.toString().padLeft(2, '0')}'
            : null,
        'shift_end_time': _shiftEndTime != null
            ? '${_shiftEndTime!.hour.toString().padLeft(2, '0')}:${_shiftEndTime!.minute.toString().padLeft(2, '0')}'
            : null,
        'is_active': _isActive,
      };

      if (widget.employee == null) {
        // Add new employee
        final employee = await SupabaseAuthService.createEmployee(data);
        if (employee == null) {
          throw Exception('فشل في إضافة الموظف');
        }
      } else {
        // Update existing employee
        final success = await SupabaseAuthService.updateEmployee(
          widget.employee!.id,
          data,
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
            widget.employee == null
                ? '✓ تم إضافة الموظف بنجاح'
                : '✓ تم تحديث الموظف بنجاح',
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
        constraints: const BoxConstraints(maxWidth: 500),
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

                // Employee ID
                TextFormField(
                  controller: _idController,
                  enabled: !isEdit, // Can't change ID when editing
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

                // Full Name
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

                // PIN
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
                    if (value.length != 4) {
                      return 'PIN يجب أن يكون 4 أرقام';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Branch
                DropdownButtonFormField<String>(
                  value: _selectedBranch,
                  decoration: const InputDecoration(
                    labelText: 'الفرع',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                  ),
                  items: widget.branches.map((branch) {
                    return DropdownMenuItem(
                      value: branch['name'] as String,
                      child: Text(branch['name'] as String),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedBranch = value);
                  },
                  validator: (value) {
                    if (value == null) return 'يرجى اختيار الفرع';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Role
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
                    DropdownMenuItem(value: 'owner', child: Text('مالك')),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedRole = value!);
                  },
                ),
                const SizedBox(height: 16),

                // Hourly Rate
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
                    if (double.tryParse(value) == null) {
                      return 'يرجى إدخال رقم صحيح';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Shift Start Time
                ListTile(
                  title: const Text('بداية الشيفت'),
                  subtitle: Text(
                    _shiftStartTime != null
                        ? _shiftStartTime!.format(context)
                        : 'لم يتم التحديد',
                  ),
                  leading: const Icon(Icons.access_time),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime:
                          _shiftStartTime ??
                          const TimeOfDay(hour: 9, minute: 0),
                    );
                    if (time != null) {
                      setState(() => _shiftStartTime = time);
                    }
                  },
                  trailing: _shiftStartTime != null
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () =>
                              setState(() => _shiftStartTime = null),
                        )
                      : null,
                ),
                const Divider(),

                // Shift End Time
                ListTile(
                  title: const Text('نهاية الشيفت'),
                  subtitle: Text(
                    _shiftEndTime != null
                        ? _shiftEndTime!.format(context)
                        : 'لم يتم التحديد',
                  ),
                  leading: const Icon(Icons.access_time_filled),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime:
                          _shiftEndTime ?? const TimeOfDay(hour: 17, minute: 0),
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

                // Active Status
                SwitchListTile(
                  title: const Text('نشط'),
                  value: _isActive,
                  onChanged: (value) {
                    setState(() => _isActive = value);
                  },
                  activeColor: AppColors.success,
                ),
                const SizedBox(height: 24),

                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryOrange,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
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
