import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../theme/app_colors.dart';
import '../../constants/api_endpoints.dart';
import '../../models/employee.dart';

class ManagerAddEmployeePage extends StatefulWidget {
  final String managerId;
  final String managerBranch;

  const ManagerAddEmployeePage({
    super.key,
    required this.managerId,
    required this.managerBranch,
  });

  @override
  State<ManagerAddEmployeePage> createState() => _ManagerAddEmployeePageState();
}

class _ManagerAddEmployeePageState extends State<ManagerAddEmployeePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  
  EmployeeRole _selectedRole = EmployeeRole.staff;
  DateTime? _birthDate;
  TimeOfDay? _shiftStartTime;
  TimeOfDay? _shiftEndTime;
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    _hourlyRateController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 20)),
      firstDate: DateTime(1960),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryOrange,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _addEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      // Generate employee ID from name and timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
      final namePart = _nameController.text.trim().replaceAll(' ', '_').substring(0, 
        _nameController.text.trim().replaceAll(' ', '_').length > 10 ? 10 : _nameController.text.trim().replaceAll(' ', '_').length
      );
      final generatedId = '${namePart}_$timestamp';
      
      final response = await http.post(
        Uri.parse('$apiBaseUrl/employees'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': generatedId, // Generate unique ID
          'fullName': _nameController.text.trim(),
          'pin': _pinController.text.trim(),
          'role': _selectedRole.name,
          'branch': widget.managerBranch,
          'hourlyRate': double.tryParse(_hourlyRateController.text) ?? 0,
          'shiftStartTime': _shiftStartTime != null 
              ? '${_shiftStartTime!.hour.toString().padLeft(2, '0')}:${_shiftStartTime!.minute.toString().padLeft(2, '0')}'
              : null,
          'shiftEndTime': _shiftEndTime != null
              ? '${_shiftEndTime!.hour.toString().padLeft(2, '0')}:${_shiftEndTime!.minute.toString().padLeft(2, '0')}'
              : null,
          'address': _addressController.text.trim().isNotEmpty 
              ? _addressController.text.trim() 
              : null,
          'birthDate': _birthDate?.toIso8601String(),
          'email': _emailController.text.trim().isNotEmpty 
              ? _emailController.text.trim() 
              : null,
          'phone': _phoneController.text.trim().isNotEmpty 
              ? _phoneController.text.trim() 
              : null,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 201 || response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إضافة الموظف بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate success
      } else {
        final error = jsonDecode(response.body)['error'] ?? 'فشل إضافة الموظف';
        throw Exception(error);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'إضافة موظف جديد',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.info.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.info),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'سيتم إضافة الموظف إلى فرع: ${widget.managerBranch}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Basic Information Section
              _buildSectionTitle('المعلومات الأساسية'),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                decoration: _buildInputDecoration(
                  label: 'الاسم الكامل',
                  icon: Icons.person,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'الرجاء إدخال الاسم';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _pinController,
                decoration: _buildInputDecoration(
                  label: 'الرقم السري (4 أرقام)',
                  icon: Icons.lock,
                ),
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                validator: (value) {
                  if (value == null || value.length != 4) {
                    return 'يجب أن يكون الرقم السري 4 أرقام';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              DropdownButtonFormField<EmployeeRole>(
                value: _selectedRole,
                decoration: _buildInputDecoration(
                  label: 'الوظيفة',
                  icon: Icons.work,
                ),
                items: [
                  EmployeeRole.staff,
                  EmployeeRole.monitor,
                  EmployeeRole.hr,
                ].map((role) {
                  return DropdownMenuItem(
                    value: role,
                    child: Text(_getRoleDisplayName(role)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedRole = value);
                  }
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _hourlyRateController,
                decoration: _buildInputDecoration(
                  label: 'سعر الساعة',
                  icon: Icons.payments,
                  suffix: 'ج.م/ساعة',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'الرجاء إدخال سعر الساعة';
                  }
                  final rate = double.tryParse(value);
                  if (rate == null || rate < 0) {
                    return 'الرجاء إدخال سعر صحيح';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Shift Start Time
              InkWell(
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: _shiftStartTime ?? const TimeOfDay(hour: 9, minute: 0),
                  );
                  if (time != null) {
                    setState(() => _shiftStartTime = time);
                  }
                },
                child: InputDecorator(
                  decoration: _buildInputDecoration(
                    label: 'بداية الشيفت',
                    icon: Icons.access_time,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _shiftStartTime == null
                            ? 'اختر وقت بداية الشيفت'
                            : _shiftStartTime!.format(context),
                        style: TextStyle(
                          color: _shiftStartTime == null
                              ? Colors.grey.shade600
                              : AppColors.textPrimary,
                        ),
                      ),
                      if (_shiftStartTime != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () => setState(() => _shiftStartTime = null),
                        )
                      else
                        const Icon(Icons.schedule, size: 20),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Shift End Time
              InkWell(
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: _shiftEndTime ?? const TimeOfDay(hour: 17, minute: 0),
                  );
                  if (time != null) {
                    setState(() => _shiftEndTime = time);
                  }
                },
                child: InputDecorator(
                  decoration: _buildInputDecoration(
                    label: 'نهاية الشيفت',
                    icon: Icons.access_time_filled,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _shiftEndTime == null
                            ? 'اختر وقت نهاية الشيفت'
                            : _shiftEndTime!.format(context),
                        style: TextStyle(
                          color: _shiftEndTime == null
                              ? Colors.grey.shade600
                              : AppColors.textPrimary,
                        ),
                      ),
                      if (_shiftEndTime != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () => setState(() => _shiftEndTime = null),
                        )
                      else
                        const Icon(Icons.schedule, size: 20),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Personal Information Section
              _buildSectionTitle('البيانات الشخصية (اختيارية)'),
              const SizedBox(height: 16),

              TextFormField(
                controller: _addressController,
                decoration: _buildInputDecoration(
                  label: 'العنوان',
                  icon: Icons.home,
                ),
                maxLines: 2,
              ),

              const SizedBox(height: 16),

              InkWell(
                onTap: _pickBirthDate,
                child: InputDecorator(
                  decoration: _buildInputDecoration(
                    label: 'تاريخ الميلاد',
                    icon: Icons.cake,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _birthDate == null
                            ? 'اختر تاريخ الميلاد'
                            : _formatDate(_birthDate!),
                        style: TextStyle(
                          color: _birthDate == null
                              ? Colors.grey.shade600
                              : AppColors.textPrimary,
                        ),
                      ),
                      const Icon(Icons.calendar_today, size: 20),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _emailController,
                decoration: _buildInputDecoration(
                  label: 'البريد الإلكتروني',
                  icon: Icons.email,
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    if (!emailRegex.hasMatch(value)) {
                      return 'البريد الإلكتروني غير صحيح';
                    }
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _phoneController,
                decoration: _buildInputDecoration(
                  label: 'رقم الهاتف',
                  icon: Icons.phone,
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    if (value.length < 10) {
                      return 'رقم الهاتف قصير جداً';
                    }
                  }
                  return null;
                },
              ),

              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _loading ? null : _addEmployee,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_add, size: 24),
                            SizedBox(width: 8),
                            Text(
                              'إضافة الموظف',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String label,
    required IconData icon,
    String? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.primaryOrange),
      suffixText: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryOrange, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  String _getRoleDisplayName(EmployeeRole role) {
    switch (role) {
      case EmployeeRole.staff:
        return 'موظف';
      case EmployeeRole.monitor:
        return 'مراقب';
      case EmployeeRole.hr:
        return 'موارد بشرية';
      case EmployeeRole.admin:
        return 'مسؤول';
      case EmployeeRole.manager:
        return 'مدير فرع';
      case EmployeeRole.owner:
        return 'مالك';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
