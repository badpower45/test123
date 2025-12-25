import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../models/employee.dart';
import '../../services/branch_api_service.dart';
import 'manager_employee_detail_page.dart';
import 'manager_add_employee_page.dart';

/// Helper function for safe date parsing
DateTime? _safeParseDate(dynamic value) {
  if (value == null) return null;
  try {
    return DateTime.parse(value.toString());
  } catch (e) {
    return null;
  }
}

class ManagerEmployeesPage extends StatefulWidget {
  final String managerId;
  final String branchId;
  final String branchName;
  
  const ManagerEmployeesPage({
    super.key,
    required this.managerId,
    required this.branchId,
    required this.branchName,
  });

  @override
  State<ManagerEmployeesPage> createState() => _ManagerEmployeesPageState();
}

class _ManagerEmployeesPageState extends State<ManagerEmployeesPage> {
  List<Employee> _employees = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() => _loading = true);
    try {
      // ✅ Fetch employees directly from API instead of local cache
      final employeesData = await BranchApiService.getBranchEmployees(widget.branchId);
      
      // Convert API response to Employee models
      final branchEmployees = employeesData.map((empData) {
        return Employee(
          id: empData['id'] as String,
          fullName: empData['full_name'] as String,
          pin: empData['pin'] as String,
          role: _parseRole(empData['role'] as String),
          permissions: _parsePermissions(empData['permissions']),
          isActive: empData['is_active'] as bool? ?? true,
          branch: widget.branchName,
          hourlyRate: (empData['hourly_rate'] as num?)?.toDouble() ?? 0.0,
          shiftStartTime: empData['shift_start_time'] as String?,
          shiftEndTime: empData['shift_end_time'] as String?,
          address: empData['address'] as String?,
          birthDate: _safeParseDate(empData['birth_date']),
          email: empData['email'] as String?,
          phone: empData['phone'] as String?,
          createdAt: _safeParseDate(empData['created_at']) ?? DateTime.now(),
          updatedAt: _safeParseDate(empData['updated_at']) ?? DateTime.now(),
        );
      }).toList();
      
      setState(() {
        _employees = branchEmployees;
        _loading = false;
      });
    } catch (e) {
      print('❌ Error loading employees: $e');
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل الموظفين: ${e.toString()}')),
        );
      }
    }
  }

  EmployeeRole _parseRole(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return EmployeeRole.owner;
      case 'manager':
        return EmployeeRole.manager;
      case 'admin':
        return EmployeeRole.admin;
      case 'hr':
        return EmployeeRole.hr;
      case 'monitor':
        return EmployeeRole.monitor;
      default:
        return EmployeeRole.staff;
    }
  }

  List<EmployeePermission> _parsePermissions(dynamic permissions) {
    if (permissions == null) return [];
    if (permissions is List) {
      return permissions.map((p) {
        switch (p.toString().toLowerCase()) {
          case 'monitor_access':
          case 'monitoraccess':
            return EmployeePermission.monitorAccess;
          case 'manage_scheduling':
          case 'managescheduling':
            return EmployeePermission.manageScheduling;
          case 'view_payroll':
          case 'viewpayroll':
            return EmployeePermission.viewPayroll;
          case 'apply_discounts':
          case 'applydiscounts':
            return EmployeePermission.applyDiscounts;
          case 'manage_employees':
          case 'manageemployees':
            return EmployeePermission.manageEmployees;
          default:
            return null;
        }
      }).whereType<EmployeePermission>().toList();
    }
    return [];
  }

  List<Employee> get _filteredEmployees {
    if (_searchQuery.isEmpty) return _employees;
    return _employees
        .where((emp) =>
            emp.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            emp.id.contains(_searchQuery))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'موظفي الفرع',
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEmployees,
            tooltip: 'تحديث',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ManagerAddEmployeePage(
                managerId: widget.managerId,
                managerBranch: widget.branchName,
              ),
            ),
          );
          if (result == true) {
            _loadEmployees();
          }
        },
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة موظف'),
        backgroundColor: AppColors.primaryOrange,
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'ابحث عن موظف بالاسم أو الرقم...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.background,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),

          // Employees Count
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.primaryLight.withOpacity(0.1),
            child: Text(
              'عدد الموظفين: ${_filteredEmployees.length}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
          ),

          // Employee List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredEmployees.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _searchQuery.isEmpty
                                  ? Icons.people_outline
                                  : Icons.search_off,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'لا يوجد موظفين في هذا الفرع'
                                  : 'لا توجد نتائج للبحث',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadEmployees,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredEmployees.length,
                          itemBuilder: (context, index) {
                            final employee = _filteredEmployees[index];
                            return _buildEmployeeCard(employee);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(Employee employee) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ManagerEmployeeDetailPage(
                employeeId: employee.id,
              ),
            ),
          );
          if (result == true) {
            _loadEmployees();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              
              // Employee Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getRoleDisplayName(employee.role),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.badge,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'ID: ${employee.id}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    if (employee.phone != null && employee.phone!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.phone,
                            size: 14,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            employee.phone!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              
              // Arrow Icon
              Icon(
                Icons.chevron_left,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
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
}
