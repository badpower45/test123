import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'dart:async';
import '../../services/supabase_branch_service.dart';
import '../../services/supabase_auth_service.dart';
import '../../services/wifi_service.dart';
import '../../models/employee.dart';
import '../../theme/app_colors.dart';

class OwnerBranchesScreen extends StatefulWidget {
  const OwnerBranchesScreen({super.key});

  @override
  State<OwnerBranchesScreen> createState() => _OwnerBranchesScreenState();
}

class _OwnerBranchesScreenState extends State<OwnerBranchesScreen> {
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final branches = await SupabaseBranchService.getAllBranches();
      
      // Load employee count and manager for each branch
      for (var branch in branches) {
        final employees = await SupabaseBranchService.getEmployeesByBranch(
          branch['name'] as String,
        );
        branch['employee_count'] = employees.length;
        
        // Find all managers
        final managers = employees.where((e) => e['role'] == 'manager').toList();
        branch['managers'] = managers;
        final managerNames = managers.map((e) => e['full_name'] as String).toList();
        final managerIds = managers.map((e) => e['id'] as String).toList();
        branch['manager_names'] = managerNames;
        branch['manager_ids'] = managerIds;

        if (managerNames.isNotEmpty) {
          branch['manager_name'] = managerNames.join('، ');
          branch['manager_id'] = managerIds.first;
        }
      }

      if (!mounted) return;
      setState(() {
        _branches = branches;
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

  Future<void> _showAddBranchDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const _BranchFormDialog(),
    );

    if (result == true) {
      _loadBranches();
    }
  }

  Future<void> _showEditBranchDialog(Map<String, dynamic> branch) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _BranchFormDialog(branch: branch),
    );

    if (result == true) {
      _loadBranches();
    }
  }

  Future<void> _showAssignManagerDialog(Map<String, dynamic> branch) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _AssignManagerDialog(branch: branch),
    );

    if (result == true) {
      _loadBranches();
    }
  }

  Future<void> _deleteBranch(Map<String, dynamic> branch) async {
    final branchName = branch['name'] as String;
    final employeeCount = branch['employee_count'] as int? ?? 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text(
          employeeCount > 0
              ? 'هل أنت متأكد من حذف فرع "$branchName"؟\n\nسيتم فك ارتباط $employeeCount موظف من هذا الفرع تلقائياً.'
              : 'هل أنت متأكد من حذف فرع "$branchName"؟',
        ),
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

    try {
      final branchId = branch['id'] as String;
      await SupabaseBranchService.deleteBranch(branchId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            employeeCount > 0
                ? '✓ تم حذف الفرع بنجاح وتم فك ارتباط $employeeCount موظف'
                : '✓ تم حذف الفرع بنجاح',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      _loadBranches();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _viewBranchEmployees(Map<String, dynamic> branch) async {
    final branchName = branch['name'] as String;
    
    try {
      final employees = await SupabaseBranchService.getEmployeesByBranch(branchName);
      
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => _BranchEmployeesDialog(
          branchName: branchName,
          employees: employees,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تحميل الموظفين: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الفروع'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 56, color: AppColors.error),
                      const SizedBox(height: 16),
                      Text('خطأ: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadBranches,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : _branches.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.store_outlined, size: 56, color: AppColors.textTertiary),
                          SizedBox(height: 16),
                          Text(
                            'لا توجد فروع',
                            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadBranches,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _branches.length,
                        itemBuilder: (context, index) {
                          final branch = _branches[index];
                          return _BranchCard(
                            branch: branch,
                            onEdit: () => _showEditBranchDialog(branch),
                            onDelete: () => _deleteBranch(branch),
                            onAssignManager: () => _showAssignManagerDialog(branch),
                            onViewEmployees: () => _viewBranchEmployees(branch),
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'owner_branches_fab',
        onPressed: _showAddBranchDialog,
        icon: const Icon(Icons.add_business),
        label: const Text('إضافة فرع'),
        backgroundColor: AppColors.primaryOrange,
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  final Map<String, dynamic> branch;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAssignManager;
  final VoidCallback onViewEmployees;

  const _BranchCard({
    required this.branch,
    required this.onEdit,
    required this.onDelete,
    required this.onAssignManager,
    required this.onViewEmployees,
  });

  @override
  Widget build(BuildContext context) {
    final name = branch['name'] as String? ?? '';
    final address = branch['address'] as String? ?? '';
    final employeeCount = branch['employee_count'] as int? ?? 0;
    final managerName = branch['manager_name'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ExpansionTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.blue,
          child: Icon(Icons.store, color: Colors.white),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (address.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      address,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.people, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '$employeeCount موظف',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                if (managerName != null && managerName.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.manage_accounts, size: 14, color: Colors.blue),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'المديرون: $managerName',
                      style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Branch Details
                if (branch['wifi_bssid'] != null || 
                    branch['latitude'] != null || 
                    branch['geofence_radius'] != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تفاصيل BLV:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (branch['wifi_bssid'] != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.wifi, size: 16, color: Colors.green),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'BSSID: ${branch['wifi_bssid']}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (branch['latitude'] != null && branch['longitude'] != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 16, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Location: ${branch['latitude']}, ${branch['longitude']}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (branch['geofence_radius'] != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.circle_outlined, size: 16, color: Colors.orange),
                              const SizedBox(width: 8),
                              Text(
                                'نصف القطر: ${branch['geofence_radius']} متر',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // Action buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: onViewEmployees,
                      icon: const Icon(Icons.people, size: 18),
                      label: Text('الموظفين ($employeeCount)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: onAssignManager,
                      icon: const Icon(Icons.person_add, size: 18),
                      label: Text(managerName != null && managerName.isNotEmpty ? 'تعيين/تغيير المديرين' : 'تعيين مديرين'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('تعديل'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryOrange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text('حذف'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchFormDialog extends StatefulWidget {
  final Map<String, dynamic>? branch;

  const _BranchFormDialog({this.branch});

  @override
  State<_BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends State<_BranchFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _bssidController;
  late TextEditingController _latitudeController;
  late TextEditingController _longitudeController;
  late TextEditingController _radiusController;
  late TextEditingController _distanceFromRadiusController;
  bool _submitting = false;
  bool _isGettingLocation = false;
  bool _isGettingBssid = false;
  List<String> _additionalBssids = []; // Multiple BSSIDs support

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.branch?['name'] ?? '');
    _addressController = TextEditingController(text: widget.branch?['address'] ?? '');
    _phoneController = TextEditingController(text: widget.branch?['phone'] ?? '');
    
    // Parse existing BSSIDs (comma-separated)
    final existingBssid = widget.branch?['wifi_bssid'] ?? '';
    if (existingBssid.toString().contains(',')) {
      final bssids = existingBssid.toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      _bssidController = TextEditingController(text: bssids.isNotEmpty ? bssids.first : '');
      _additionalBssids = bssids.skip(1).toList();
    } else {
      _bssidController = TextEditingController(text: existingBssid.toString());
    }
    
    _latitudeController = TextEditingController(
      text: widget.branch?['latitude']?.toString() ?? '',
    );
    _longitudeController = TextEditingController(
      text: widget.branch?['longitude']?.toString() ?? '',
    );
    _radiusController = TextEditingController(
      text: widget.branch?['geofence_radius']?.toString() ?? '100',
    );
    _distanceFromRadiusController = TextEditingController(
      text: widget.branch?['distance_from_radius']?.toString() ?? '100',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _bssidController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    _distanceFromRadiusController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);

    try {
      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('يجب السماح بالوصول للموقع');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('تم رفض الوصول للموقع بشكل دائم');
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;
      setState(() {
        _latitudeController.text = position.latitude.toStringAsFixed(6);
        _longitudeController.text = position.longitude.toStringAsFixed(6);
        _isGettingLocation = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم الحصول على الموقع الحالي'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGettingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _getCurrentBssid() async {
    setState(() => _isGettingBssid = true);

    try {
      final bssid = await WiFiService.getCurrentWifiBssidValidated();
      
      if (!mounted) return;
      setState(() {
        _bssidController.text = bssid;
        _isGettingBssid = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ تم الحصول على BSSID: $bssid'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGettingBssid = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _showAddBssidDialog() async {
    final controller = TextEditingController();
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة WiFi إضافي', textAlign: TextAlign.right),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'يمكنك إضافة BSSID يدويًا أو كشفه تلقائيًا',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'WiFi BSSID',
                hintText: '00:11:22:33:44:55',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
              ),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    final bssid = await WiFiService.getCurrentWifiBssidValidated();
                    controller.text = bssid;
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.wifi_find),
                label: const Text('كشف تلقائي'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final bssid = controller.text.trim();
              if (bssid.isNotEmpty) {
                Navigator.pop(context, bssid);
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    
    if (result != null && result.isNotEmpty) {
      setState(() {
        if (!_additionalBssids.contains(result)) {
          _additionalBssids.add(result);
        }
      });
    }
  }

  Future<void> _pickLocationOnMap() async {
    final radius = double.tryParse(_radiusController.text) ?? 100.0;
    final result = await showDialog<Map<String, double>>(
      context: context,
      builder: (context) => _MapPickerDialog(
        initialLat: double.tryParse(_latitudeController.text),
        initialLng: double.tryParse(_longitudeController.text),
        radius: radius,
      ),
    );

    if (result != null) {
      setState(() {
        _latitudeController.text = result['lat']!.toStringAsFixed(6);
        _longitudeController.text = result['lng']!.toStringAsFixed(6);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
      final latitude = _latitudeController.text.trim().isNotEmpty
          ? double.tryParse(_latitudeController.text.trim())
          : null;
      final longitude = _longitudeController.text.trim().isNotEmpty
          ? double.tryParse(_longitudeController.text.trim())
          : null;
      final radius = _radiusController.text.trim().isNotEmpty
          ? double.tryParse(_radiusController.text.trim())
          : 100.0;
      final distanceFromRadius = _distanceFromRadiusController.text.trim().isNotEmpty
          ? double.tryParse(_distanceFromRadiusController.text.trim())
          : 100.0;

      // Combine all BSSIDs (comma-separated)
      String? combinedBssids;
      final allBssids = <String>[];
      if (_bssidController.text.trim().isNotEmpty) {
        allBssids.add(_bssidController.text.trim());
      }
      allBssids.addAll(_additionalBssids);
      if (allBssids.isNotEmpty) {
        combinedBssids = allBssids.join(',');
      }

      if (widget.branch == null) {
        // Add new branch
        final branch = await SupabaseBranchService.createBranch(
          name: _nameController.text.trim(),
          address: _addressController.text.trim(),
          wifiBssid: combinedBssids,
          latitude: latitude,
          longitude: longitude,
          geofenceRadius: radius,
          distanceFromRadius: distanceFromRadius,
        );
        if (branch == null) {
          throw Exception('فشل في إضافة الفرع');
        }
      } else {
        // Update existing branch
        final branchId = widget.branch!['id'] as String;
        final success = await SupabaseBranchService.updateBranch(
          branchId: branchId,
          name: _nameController.text.trim(),
          address: _addressController.text.trim(),
          wifiBssid: combinedBssids,
          latitude: latitude,
          longitude: longitude,
          geofenceRadius: radius,
          distanceFromRadius: distanceFromRadius,
        );
        if (!success) {
          throw Exception('فشل في تحديث الفرع');
        }
      }

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.branch == null ? '✓ تم إضافة الفرع بنجاح' : '✓ تم تحديث الفرع بنجاح'),
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
    final isEdit = widget.branch != null;

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
                  isEdit ? 'تعديل فرع' : 'إضافة فرع جديد',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),

                // Branch Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم الفرع',
                    hintText: 'الفرع الرئيسي',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'يرجى إدخال اسم الفرع';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Address
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'العنوان',
                    hintText: 'القاهرة، شارع...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                  maxLines: 2,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'يرجى إدخال العنوان';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Phone
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    hintText: '01XXXXXXXXX',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),

                // BSSID (WiFi MAC Address) with Auto-Detect Button and Multiple BSSIDs
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.wifi, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'شبكات WiFi للفرع',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _bssidController,
                      decoration: const InputDecoration(
                        labelText: 'WiFi BSSID الأساسي',
                        hintText: '00:11:22:33:44:55',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.wifi),
                        helperText: 'عنوان MAC للواي فاي الرئيسي',
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isGettingBssid ? null : _getCurrentBssid,
                        icon: _isGettingBssid
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.wifi_find),
                        label: Text(_isGettingBssid ? 'جاري الكشف التلقائي...' : 'كشف تلقائي عن WiFi'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        ),
                      ),
                    ),
                    
                    // Additional BSSIDs Section
                    if (_additionalBssids.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'شبكات WiFi إضافية:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(_additionalBssids.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green.withOpacity(0.2)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.wifi, size: 18, color: Colors.green),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _additionalBssids[index],
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _additionalBssids.removeAt(index);
                                  });
                                },
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: 'حذف',
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    
                    // Add BSSID Button
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showAddBssidDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة WiFi إضافي'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green,
                          side: const BorderSide(color: Colors.green),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Location Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on, color: Colors.blue, size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'الموقع الجغرافي (Geofence)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Location Buttons - Full Width on Mobile
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isGettingLocation ? null : _getCurrentLocation,
                              icon: _isGettingLocation
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.my_location),
                              label: Text(_isGettingLocation ? 'جاري تحديد الموقع...' : 'استخدم موقعي الحالي'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _pickLocationOnMap,
                              icon: const Icon(Icons.map),
                              label: const Text('اختر من الخريطة'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Lat/Lng Input - Stack vertically on mobile for better readability
                      Column(
                        children: [
                          TextFormField(
                            controller: _latitudeController,
                            decoration: const InputDecoration(
                              labelText: 'Latitude (خط العرض)',
                              hintText: '30.0444',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.south),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _longitudeController,
                            decoration: const InputDecoration(
                              labelText: 'Longitude (خط الطول)',
                              hintText: '31.2357',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.east),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _radiusController,
                        decoration: const InputDecoration(
                          labelText: 'نصف قطر الدائرة (متر)',
                          hintText: '100',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.circle_outlined),
                          helperText: 'المسافة المسموح بها للحضور (افتراضي: 100 متر)',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            final radius = double.tryParse(value.trim());
                            if (radius == null || radius <= 0) {
                              return 'يرجى إدخال قيمة صحيحة';
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _distanceFromRadiusController,
                        decoration: const InputDecoration(
                          labelText: 'المسافة الإضافية للنبضات (متر)',
                          hintText: '100',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.radar),
                          helperText: 'المسافة الإضافية المسموح بها للنبضات خارج نصف القطر',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            final distance = double.tryParse(value.trim());
                            if (distance == null || distance < 0) {
                              return 'يرجى إدخال قيمة صحيحة';
                            }
                          }
                          return null;
                        },
                        onChanged: (value) {
                          // Update UI on change
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      // معلومة عن المسافة
                      if (_latitudeController.text.isNotEmpty && 
                          _longitudeController.text.isNotEmpty &&
                          _radiusController.text.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: Colors.green),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'الموظفون يمكنهم الحضور في دائرة نصف قطرها ${_radiusController.text} متر من الموقع المحدد',
                                  style: const TextStyle(fontSize: 11, color: Colors.green),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Buttons
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
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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

class _AssignManagerDialog extends StatefulWidget {
  final Map<String, dynamic> branch;

  const _AssignManagerDialog({required this.branch});

  @override
  State<_AssignManagerDialog> createState() => _AssignManagerDialogState();
}

class _AssignManagerDialogState extends State<_AssignManagerDialog> {
  List<Employee> _employees = [];
  Set<String> _selectedManagerIds = {};
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    try {
      final employees = await SupabaseAuthService.getAllEmployees();

      // Find current managers for this branch
      final currentManagerIds = <String>{};
      final branchManagerIds = widget.branch['manager_ids'];
      if (branchManagerIds is List) {
        currentManagerIds.addAll(branchManagerIds.map((e) => e.toString()));
      }
      if (widget.branch['manager_id'] != null) {
        currentManagerIds.add(widget.branch['manager_id'].toString());
      }

      if (!mounted) return;
      setState(() {
        _employees = employees;
        _selectedManagerIds = currentManagerIds;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);

    try {
      final branchId = widget.branch['id'] as String;
      final branchName = widget.branch['name'] as String;

      final supabase = Supabase.instance.client;

      // 1. Assign all selected employees as managers for this branch
      for (final empId in _selectedManagerIds) {
        await supabase
            .from('employees')
            .update({
              'role': 'manager',
              'branch': branchName,
              'branch_id': branchId,
            })
            .eq('id', empId);
      }

      // 2. Unassign any unselected previous managers
      final previousManagerIds = (widget.branch['manager_ids'] as List?)?.map((e) => e.toString()).toList() ?? [];
      for (final prevId in previousManagerIds) {
        if (!_selectedManagerIds.contains(prevId)) {
          await supabase
              .from('employees')
              .update({'role': 'staff'})
              .eq('id', prevId);
        }
      }

      // 3. Update main manager_id in branches table
      final primaryId = _selectedManagerIds.isNotEmpty ? _selectedManagerIds.first : null;
      await SupabaseBranchService.assignManager(
        branchId: branchId,
        managerId: primaryId ?? '',
      );

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ تم تحديد مديري فرع "$branchName" بنجاح (${_selectedManagerIds.length} مدير)'),
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
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.manage_accounts_rounded, color: AppColors.primaryOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'تعيين/تعديل مديري فرع ${widget.branch['name']}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: _loading
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          : _employees.isEmpty
              ? const Text('لا يوجد موظفون متاحيين')
              : SizedBox(
                  width: 380,
                  height: 320,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'قم بتحديد الموظفين المراد تعيينهم كمديرين لهذا الفرع:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _employees.length,
                          itemBuilder: (context, index) {
                            final emp = _employees[index];
                            final isSelected = _selectedManagerIds.contains(emp.id);

                            return CheckboxListTile(
                              value: isSelected,
                              activeColor: AppColors.primaryOrange,
                              title: Text(
                                emp.fullName,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                'الفرع الحقيقي: ${emp.branch} • الدور: ${emp.role.name}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedManagerIds.add(emp.id);
                                  } else {
                                    _selectedManagerIds.remove(emp.id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text('حفظ المديرين (${_selectedManagerIds.length})'),
        ),
      ],
    );
  }
}

class _BranchEmployeesDialog extends StatelessWidget {
  final String branchName;
  final List<Map<String, dynamic>> employees;

  const _BranchEmployeesDialog({
    required this.branchName,
    required this.employees,
  });

  String _getRoleText(String role) {
    switch (role) {
      case 'owner':
        return 'مالك';
      case 'manager':
        return 'مدير';
      case 'hr':
        return 'موارد بشرية';
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
      case 'manager':
        return Colors.blue;
      case 'hr':
        return Colors.green;
      case 'staff':
        return Colors.orange;
      case 'monitor':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people, color: AppColors.primaryOrange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'موظفو فرع $branchName',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'إجمالي: ${employees.length} موظف',
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: employees.isEmpty
                  ? const Center(child: Text('لا يوجد موظفون في هذا الفرع'))
                  : ListView.builder(
                      itemCount: employees.length,
                      itemBuilder: (context, index) {
                        final emp = employees[index];
                        final name = emp['full_name'] as String;
                        final id = emp['id'] as String;
                        final role = emp['role'] as String;
                        final isActive = emp['is_active'] as bool? ?? true;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getRoleColor(role).withOpacity(0.2),
                              child: Text(
                                name.substring(0, 1),
                                style: TextStyle(
                                  color: _getRoleColor(role),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isActive ? AppColors.textPrimary : AppColors.textTertiary,
                              ),
                            ),
                            subtitle: Text(
                              id,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getRoleColor(role).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _getRoleText(role),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _getRoleColor(role),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Map Picker Dialog Widget (OpenStreetMap + Geofence CircleMarker + Zoom Controls)
class _MapPickerDialog extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final double radius;

  const _MapPickerDialog({
    this.initialLat,
    this.initialLng,
    this.radius = 100.0,
  });

  @override
  State<_MapPickerDialog> createState() => _MapPickerDialogState();
}

class _MapPickerDialogState extends State<_MapPickerDialog> {
  late double _selectedLat;
  late double _selectedLng;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    // Default to Cairo if no initial location
    _selectedLat = widget.initialLat ?? 30.0444;
    _selectedLng = widget.initialLng ?? 31.2357;
  }

  void _onMapTapped(TapPosition tapPosition, ll.LatLng point) {
    setState(() {
      _selectedLat = point.latitude;
      _selectedLng = point.longitude;
    });
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(ll.LatLng(_selectedLat, _selectedLng), currentZoom + 0.5);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(ll.LatLng(_selectedLat, _selectedLng), currentZoom - 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final currentPoint = ll.LatLng(_selectedLat, _selectedLng);

    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.map_rounded, color: AppColors.primaryOrange),
                const SizedBox(width: 8),
                const Text(
                  'اختر موقع الفرع على الخريطة التفاعلية',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Current coordinates & Radius display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryOrange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primaryOrange.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.south, size: 16, color: AppColors.primaryOrange),
                  const SizedBox(width: 4),
                  Text(
                    'Lat: ${_selectedLat.toStringAsFixed(6)}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 14),
                  const Icon(Icons.east, size: 16, color: AppColors.primaryOrange),
                  const SizedBox(width: 4),
                  Text(
                    'Lng: ${_selectedLng.toStringAsFixed(6)}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 14),
                  const Icon(Icons.circle_outlined, size: 16, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    'الدائرة: ${widget.radius.toInt()} م',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // FlutterMap OpenStreetMap Widget with Geofence Circle & Zoom Controls
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: currentPoint,
                        initialZoom: 16.0,
                        onTap: _onMapTapped,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.oldies.workers.app',
                        ),
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: currentPoint,
                              radius: widget.radius,
                              useRadiusInMeter: true,
                              color: AppColors.primaryOrange.withOpacity(0.25),
                              borderColor: AppColors.primaryOrange,
                              borderStrokeWidth: 2,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: currentPoint,
                              width: 50,
                              height: 50,
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Colors.red,
                                size: 48,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Floating Interactive Zoom Controls (+ / -)
                    Positioned(
                      bottom: 20,
                      right: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FloatingActionButton.small(
                            heroTag: 'zoom_in_btn',
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primaryOrange,
                            onPressed: _zoomIn,
                            child: const Icon(Icons.add, size: 22),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'zoom_out_btn',
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primaryOrange,
                            onPressed: _zoomOut,
                            child: const Icon(Icons.remove, size: 22),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Instructions
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'انقر في أي مكان على الخريطة لتحديد الموقع؛ ستلاحظ ظهور الدائرة الزرقاء التي تمثل نصف القطر المسموح به للحضور (${widget.radius.toInt()} متر).',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context, {
                      'lat': _selectedLat,
                      'lng': _selectedLng,
                    });
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('تأكيد الموقع'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
