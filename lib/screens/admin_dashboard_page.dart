import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/employee.dart';
import '../models/employee_adjustment.dart';
import '../models/pulse.dart';
import '../models/pulse_log_entry.dart';
import '../services/background_pulse_service.dart';
import '../services/employee_adjustment_repository.dart';
import '../services/employee_repository.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';

enum DashboardMode { admin, hr, monitor }

enum DashboardSection { monitor, team, hr }

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({
    super.key,
    this.mode = DashboardMode.admin,
    this.currentUserId,
  });

  static const routeName = '/admin-dashboard';

  final DashboardMode mode;
  final String? currentUserId;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with SingleTickerProviderStateMixin {
  late final Box<PulseLogEntry> _historyBox;
  late final Box<Pulse> _offlineBox;
  late final Box<Employee> _employeeBox;
  late final Box<EmployeeAdjustment> _adjustmentBox;
  late TabController _tabController;
  late List<DashboardSection> _sections;
  late DashboardMode _currentMode;
  late final Future<void> _initializationFuture;
  EmployeeStatus? _monitorStatusFilter;
  String? _monitorBranchFilter;

  bool get _isAdmin => _currentMode == DashboardMode.admin;
  bool get _isHr => _currentMode == DashboardMode.hr;

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تأكيد تسجيل الخروج'),
            content: const Text(
              'هل تريد بالتأكيد تسجيل الخروج والعودة إلى شاشة الدخول؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: AppColors.onPrimary,
                ),
                child: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLogout) {
      return;
    }

    await _handleLogout();
  }

  Future<void> _handleLogout() async {
    await BackgroundPulseService.stop();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(
      LoginScreen.routeName,
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    _currentMode = widget.mode;
    _sections = _sectionsForMode(_currentMode);
    _tabController = TabController(length: _sections.length, vsync: this);
    _attachTabControllerListener();
    _initializationFuture = _ensureBoxesReady();
  }

  @override
  void didUpdateWidget(covariant AdminDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      setState(() {
        _currentMode = widget.mode;
        _reconfigureTabs();
      });
    }
  }

  Future<void> _ensureBoxesReady() async {
    if (!Hive.isAdapterRegistered(3)) {
      registerEmployeeAdapter();
    }
    if (!Hive.isAdapterRegistered(4)) {
      registerAdjustmentAdapter();
    }
    if (!Hive.isAdapterRegistered(1)) {
      registerPulseAdapter();
    }
    if (!Hive.isAdapterRegistered(2)) {
      registerPulseLogEntryAdapter();
    }

    _historyBox = await Hive.openBox<PulseLogEntry>(pulseHistoryBox);
    _offlineBox = await Hive.openBox<Pulse>(offlinePulsesBox);
    _employeeBox = await Hive.openBox<Employee>(employeesBox);
    _adjustmentBox = await Hive.openBox<EmployeeAdjustment>(
      employeeAdjustmentsBox,
    );
  }

  List<DashboardSection> _sectionsForMode(DashboardMode mode) {
    final sections = <DashboardSection>[DashboardSection.monitor];
    if (mode == DashboardMode.admin || mode == DashboardMode.hr) {
      sections.add(DashboardSection.team);
      sections.add(DashboardSection.hr);
    }
    return sections;
  }

  void _reconfigureTabs() {
    final previousIndex = _tabController.index;
    _tabController.removeListener(_handleTabIndexChanged);
    _tabController.dispose();
    _sections = _sectionsForMode(_currentMode);
    _tabController = TabController(length: _sections.length, vsync: this);
    _attachTabControllerListener();
    if (_sections.isNotEmpty) {
      final clampedIndex = previousIndex.clamp(0, _sections.length - 1);
      _tabController.index = clampedIndex;
    }
  }

  void _switchMode(DashboardMode mode) {
    if (_currentMode == mode) {
      return;
    }
    setState(() {
      _currentMode = mode;
      _reconfigureTabs();
    });
  }

  Widget _buildTabBar() {
    return DashboardTabBar(
      controller: _tabController,
      sections: _sections,
      labelBuilder: _sectionLabel,
      iconBuilder: _sectionIcon,
      accentBuilder: _sectionAccent,
      onSelectSection: (section) {
        final index = _sections.indexOf(section);
        if (index != -1) {
          _tabController.animateTo(index);
        }
      },
    );
  }

  void _attachTabControllerListener() {
    _tabController.addListener(_handleTabIndexChanged);
  }

  void _handleTabIndexChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Iterable<_EmployeeSnapshot> _applyMonitorFilters(
    List<_EmployeeSnapshot> snapshots,
  ) {
    return snapshots.where((snapshot) {
      final matchesStatus =
          _monitorStatusFilter == null || snapshot.status == _monitorStatusFilter;
      final matchesBranch =
          _monitorBranchFilter == null || snapshot.branch == _monitorBranchFilter;
      return matchesStatus && matchesBranch;
    });
  }

  void _clearMonitorFilters() {
    setState(() {
      _monitorStatusFilter = null;
      _monitorBranchFilter = null;
    });
  }

  void _showMonitorDetails(_EmployeeSnapshot snapshot) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _MonitorTimelineSheet(snapshot: snapshot),
    );
  }

  String _sectionLabel(DashboardSection section) {
    return switch (section) {
      DashboardSection.monitor => 'المراقبة',
      DashboardSection.team => 'الفريق',
      DashboardSection.hr => 'شؤون الموظفين',
    };
  }

  IconData _sectionIcon(DashboardSection section) {
    return switch (section) {
      DashboardSection.monitor => Icons.monitor_heart_outlined,
      DashboardSection.team => Icons.groups_2_outlined,
      DashboardSection.hr => Icons.receipt_long_outlined,
    };
  }

  Color _sectionAccent(DashboardSection section) {
    return switch (section) {
      DashboardSection.monitor => const Color(0xFF1F7AE0),
      DashboardSection.team => const Color(0xFF22B07D),
      DashboardSection.hr => const Color(0xFFE05A3F),
    };
  }

  String _modeDisplayName(DashboardMode mode) {
    return switch (mode) {
      DashboardMode.admin => 'المدير',
      DashboardMode.hr => 'شؤون الموظفين',
      DashboardMode.monitor => 'المراقب',
    };
  }

  IconData _modeIcon(DashboardMode mode) {
    return switch (mode) {
      DashboardMode.admin => Icons.admin_panel_settings_outlined,
      DashboardMode.hr => Icons.badge_outlined,
      DashboardMode.monitor => Icons.monitor_heart_outlined,
    };
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabIndexChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _DashboardLoadingState();
        }
        if (snapshot.hasError) {
          return _DashboardErrorState(error: snapshot.error);
        }
        return _buildDashboardScaffold(context);
      },
    );
  }

  Widget _buildDashboardScaffold(BuildContext context) {
    final activeSection =
        _sections[_tabController.index.clamp(0, _sections.length - 1)];
    final canManageEmployees = _isAdmin;
    final canRecordAdjustments = _isAdmin || _isHr;

    return Scaffold(
      backgroundColor: AppColors.primaryOrange,
      appBar: AppBar(
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        title: Text('لوحة ${_modeDisplayName(_currentMode)}'),
        actions: [
          PopupMenuButton<DashboardMode>(
            tooltip: 'تغيير الدور',
            initialValue: _currentMode,
            onSelected: _switchMode,
            icon: const Icon(Icons.manage_accounts_outlined),
            itemBuilder: (context) {
              return DashboardMode.values
                  .map(
                    (mode) => PopupMenuItem<DashboardMode>(
                      value: mode,
                      child: Row(
                        children: [
                          Icon(
                            _modeIcon(mode),
                            color: mode == _currentMode
                                ? AppColors.primaryOrange
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 12),
                          Text(_modeDisplayName(mode)),
                          if (mode == _currentMode) ...[
                            const Spacer(),
                            const Icon(Icons.check, size: 18),
                          ],
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false);
            },
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed: () => _confirmLogout(context),
            icon: const Icon(Icons.logout_rounded),
          ),
          IconButton(
            tooltip: 'مسح البيانات المحلية',
            onPressed: _confirmClearLocalData,
            icon: const Icon(Icons.delete_forever_outlined),
          ),
        ],
      ),
      floatingActionButton:
          canManageEmployees && activeSection == DashboardSection.team
          ? FloatingActionButton.extended(
              onPressed: () => _showEmployeeFormSheet(context),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('إضافة موظف'),
            )
          : null,
      body: Column(
        children: [
          const SizedBox(height: 12),
          if (_sections.isNotEmpty) _buildTabBar(),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _sections
                  .map(
                    (section) => _buildSection(
                      section,
                      canManageEmployees: canManageEmployees,
                      canRecordAdjustments: canRecordAdjustments,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    DashboardSection section, {
    required bool canManageEmployees,
    required bool canRecordAdjustments,
  }) {
    switch (section) {
      case DashboardSection.monitor:
        return _buildMonitorSection();
      case DashboardSection.team:
        return _buildTeamSection(
          canManageEmployees: canManageEmployees,
          canRecordAdjustments: canRecordAdjustments,
        );
      case DashboardSection.hr:
        return _buildHrSection(canRecordAdjustments: canRecordAdjustments);
    }
  }

  Widget _buildMonitorSection() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
      ),
      child: ValueListenableBuilder<Box<Employee>>(
        valueListenable: _employeeBox.listenable(),
        builder: (context, employeeBox, _) {
          final employeeDirectory = {
            for (final employee in employeeBox.values) employee.id: employee,
          };
          return ValueListenableBuilder<Box<PulseLogEntry>>(
            valueListenable: _historyBox.listenable(),
            builder: (context, historyBox, __) {
              final historyEntries = historyBox.values.toList(growable: false)
                ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
              return ValueListenableBuilder<Box<Pulse>>(
                valueListenable: _offlineBox.listenable(),
                builder: (context, offlineBox, ___) {
                  final offlinePulses = offlineBox.values.toList(
                    growable: false,
                  );
                  final stats = _PulseStats.from(historyEntries, offlinePulses);
                  final snapshots = _buildEmployeeSnapshots(
                    historyEntries,
                    offlinePulses,
                    employeeDirectory,
                  );

                  final branchOptions = employeeDirectory.values
                      .map(
                        (employee) => employee.branch.isNotEmpty
                            ? employee.branch
                            : 'فرع غير محدد',
                      )
                      .toSet()
                      .toList()
                    ..sort((a, b) => a.compareTo(b));

                  if (snapshots.isEmpty) {
                    return _EmptyAdminState(stats: stats);
                  }

                  final filteredSnapshots =
                      _applyMonitorFilters(snapshots).toList(growable: false);
                  final statusOptions = <MapEntry<EmployeeStatus?, String>>[
                    const MapEntry<EmployeeStatus?, String>(null, 'الكل'),
                    const MapEntry<EmployeeStatus?, String>(
                        EmployeeStatus.checkedIn, 'مسجل حضور'),
                    const MapEntry<EmployeeStatus?, String>(
                        EmployeeStatus.checkedOut, 'موقع مغادرة'),
                    const MapEntry<EmployeeStatus?, String>(
                        EmployeeStatus.offline, 'بدون اتصال'),
                    const MapEntry<EmployeeStatus?, String>(
                        EmployeeStatus.inactive, 'غير نشط'),
                  ];

                  return CustomScrollView(
                    primary: true,
                    slivers: [
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        sliver: SliverToBoxAdapter(
                          child: _PulseStatsSummary(stats: stats),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'عرض حسب الحالة',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final option in statusOptions)
                                    Builder(
                                      builder: (context) {
                                        final isSelected =
                                            _monitorStatusFilter == option.key;
                                        return ChoiceChip(
                                          label: Text(
                                            option.value,
                                            style: TextStyle(
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.black87,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          selected: isSelected,
                                          backgroundColor:
                                              Colors.grey.shade200,
                                          selectedColor:
                                              AppColors.primaryOrange,
                                          showCheckmark: false,
                                          side: BorderSide(
                                            color: isSelected
                                                ? AppColors.primaryOrange
                                                : Colors.grey.shade300,
                                          ),
                                          onSelected: (selected) {
                                            setState(() {
                                              if (option.key == null) {
                                                _monitorStatusFilter = null;
                                              } else {
                                                _monitorStatusFilter =
                                                    selected
                                                        ? option.key
                                                        : null;
                                              }
                                            });
                                          },
                                        );
                                      },
                                    ),
                                ],
                              ),
                              if (branchOptions.length > 1) ...[
                                const SizedBox(height: 18),
                                DropdownButtonFormField<String?>(
                                  value: _monitorBranchFilter,
                                  decoration: InputDecoration(
                                    labelText: 'الفرع',
                                    filled: true,
                                    fillColor: Colors.grey.shade100,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('كل الفروع'),
                                    ),
                                    for (final branch in branchOptions)
                                      DropdownMenuItem<String?>(
                                        value: branch,
                                        child: Text(branch),
                                      ),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _monitorBranchFilter = value;
                                    });
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      if (filteredSnapshots.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: _MonitorFilteredEmptyState(
                              onClear: _clearMonitorFilters,
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          sliver: SliverList.separated(
                            itemCount: filteredSnapshots.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 20),
                            itemBuilder: (context, index) {
                              final snapshot = filteredSnapshots[index];
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _showMonitorDetails(snapshot),
                                child: _EmployeeCard(employee: snapshot),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTeamSection({
    required bool canManageEmployees,
    required bool canRecordAdjustments,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
      ),
      child: ValueListenableBuilder<Box<Employee>>(
        valueListenable: _employeeBox.listenable(),
        builder: (context, employeeBox, _) {
          final employees = employeeBox.values.toList(growable: false);
          if (employees.isEmpty) {
            return const _EmptyTeamState();
          }

          return ValueListenableBuilder<Box<PulseLogEntry>>(
            valueListenable: _historyBox.listenable(),
            builder: (context, historyBox, __) {
              final historyEntries = historyBox.values.toList(growable: false)
                ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
              final offlinePulses = _offlineBox.values.toList(growable: false);
              final directory = {
                for (final employee in employees) employee.id: employee,
              };
              final snapshots = _buildEmployeeSnapshots(
                historyEntries,
                offlinePulses,
                directory,
              );

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
                itemCount: snapshots.length,
                separatorBuilder: (_, __) => const SizedBox(height: 20),
                itemBuilder: (context, index) {
                  final snapshot = snapshots[index];
                  return _EmployeeCard(
                    employee: snapshot,
                    showManagementActions:
                        canManageEmployees || canRecordAdjustments,
                    onToggleActive: canManageEmployees
                        ? () async {
                            await EmployeeRepository.toggleActive(
                              snapshot.employeeId,
                            );
                          }
                        : null,
                    onEdit: canManageEmployees
                        ? () => _showEmployeeFormSheet(
                            context,
                            existing: directory[snapshot.employeeId],
                          )
                        : null,
                    onRecordAdjustment: canRecordAdjustments
                        ? () => _showAdjustmentSheet(context, snapshot)
                        : null,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildHrSection({required bool canRecordAdjustments}) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
      ),
      child: ValueListenableBuilder<Box<Employee>>(
        valueListenable: _employeeBox.listenable(),
        builder: (context, employeeBox, __) {
          final employees = employeeBox.values.toList(growable: false);
          final payrollInsights = _PayrollInsights.from(employees);

          return ValueListenableBuilder<Box<EmployeeAdjustment>>(
            valueListenable: _adjustmentBox.listenable(),
            builder: (context, adjustmentBox, _) {
              final adjustments = adjustmentBox.values.toList(growable: false)
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

              return CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverToBoxAdapter(
                      child: _PayrollSummaryCard(insights: payrollInsights),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  if (adjustments.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: const _EmptyHrState(),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      sliver: SliverList.separated(
                        itemCount: adjustments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final adjustment = adjustments[index];
                          final employee = _employeeBox.get(adjustment.employeeId);
                          final icon = switch (adjustment.type) {
                            AdjustmentType.bonus => Icons.arrow_upward,
                            AdjustmentType.deduction => Icons.arrow_downward,
                            AdjustmentType.note => Icons.sticky_note_2_outlined,
                          };
                          final color = switch (adjustment.type) {
                            AdjustmentType.bonus => AppColors.success,
                            AdjustmentType.deduction => AppColors.danger,
                            AdjustmentType.note => Colors.blueGrey,
                          };

                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            elevation: 4,
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(icon, color: color),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          employee?.fullName ?? adjustment.employeeId,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      Text(
                                        _formatTimestamp(adjustment.createdAt),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(adjustment.reason),
                                  if (adjustment.amount != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                      '${adjustment.type == AdjustmentType.deduction ? '-' : '+'}${_formatCurrency(adjustment.amount!)} ج.م',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: adjustment.type == AdjustmentType.deduction
                                                ? AppColors.danger
                                                : AppColors.success,
                                          ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      const Icon(Icons.person_outline, size: 18),
                                      const SizedBox(width: 6),
                                      Text('سجلها ${adjustment.recordedBy}'),
                                      const Spacer(),
                                      if (canRecordAdjustments)
                                        IconButton(
                                          tooltip: 'حذف السجل',
                                          onPressed: () async {
                                            await EmployeeAdjustmentRepository.remove(
                                              adjustment.id,
                                            );
                                          },
                                          icon: const Icon(Icons.delete_outline),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showEmployeeFormSheet(
    BuildContext context, {
    Employee? existing,
  }) async {
    final result = await showModalBottomSheet<_EmployeeFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EmployeeFormSheet(existing: existing),
    );

    if (result == null) {
      return;
    }

    if (existing == null) {
      final employee = Employee(
        id: result.id,
        fullName: result.fullName,
        pin: result.pin,
        role: result.role,
        permissions: result.permissions,
        branch: result.branch,
        monthlySalary: result.monthlySalary,
      );
      await EmployeeRepository.upsert(employee);
    } else {
      existing
        ..fullName = result.fullName
        ..pin = result.pin
        ..role = result.role
        ..permissions = result.permissions
        ..branch = result.branch
        ..monthlySalary = result.monthlySalary
        ..touch();
      await EmployeeRepository.upsert(existing);
    }
  }

  Future<void> _showAdjustmentSheet(
    BuildContext context,
    _EmployeeSnapshot employee,
  ) async {
    final result = await showModalBottomSheet<_AdjustmentFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AdjustmentFormSheet(employee: employee),
    );

    if (result == null) {
      return;
    }

    await EmployeeAdjustmentRepository.create(
      employeeId: employee.employeeId,
      type: result.type,
      reason: result.reason,
      recordedBy: result.recordedBy,
      amount: result.amount,
    );
  }

  Future<void> _confirmClearLocalData() async {
    final shouldClear =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('مسح البيانات المحلية؟'),
            content: const Text(
              'سيتم حذف سجل النبضات وكل النبضات غير المتزامنة المخزنة على هذا الجهاز.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('مسح البيانات'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldClear) {
      return;
    }

    await Future.wait([_historyBox.clear(), _offlineBox.clear()]);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم مسح بيانات النبضات المحلية.')),
    );
  }
}

class DashboardTabBar extends StatelessWidget {
  const DashboardTabBar({
    super.key,
    required this.controller,
    required this.sections,
    required this.labelBuilder,
    required this.iconBuilder,
    required this.accentBuilder,
    this.onSelectSection,
  });

  final TabController controller;
  final List<DashboardSection> sections;
  final String Function(DashboardSection section) labelBuilder;
  final IconData Function(DashboardSection section) iconBuilder;
  final Color Function(DashboardSection section) accentBuilder;
  final ValueChanged<DashboardSection>? onSelectSection;

  @override
  Widget build(BuildContext context) {
    if (sections.length <= 1) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final backgroundColor = AppColors.primaryOrange;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: backgroundColor.withAlpha((0.4 * 255).round()),
            borderRadius: BorderRadius.circular(24),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                for (var index = 0; index < sections.length; index++)
                  _DashboardTabChip(
                    label: labelBuilder(sections[index]),
                    icon: iconBuilder(sections[index]),
                    accent: accentBuilder(sections[index]),
                    isActive: controller.index == index,
                    onTap: () => onSelectSection?.call(sections[index]),
                    textStyle: theme.textTheme.labelLarge,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashboardLoadingState extends StatelessWidget {
  const _DashboardLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primaryOrange,
      body: Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}

class _DashboardErrorState extends StatelessWidget {
  const _DashboardErrorState({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryOrange,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.white),
              const SizedBox(height: 16),
              Text(
                'حدث خطأ أثناء تجهيز لوحة التحكم.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  '$error',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardTabChip extends StatelessWidget {
  const _DashboardTabChip({
    required this.label,
    required this.icon,
    required this.accent,
    required this.isActive,
    required this.onTap,
    required this.textStyle,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final bool isActive;
  final VoidCallback? onTap;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final pillColor = isActive
        ? Colors.white
        : Colors.white.withAlpha((0.14 * 255).round());
    final foreground = isActive ? accent : Colors.white;
    final borderColor = isActive
        ? accent.withAlpha((0.45 * 255).round())
        : Colors.white.withAlpha((0.18 * 255).round());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: pillColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: accent.withAlpha((0.28 * 255).round()),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: foreground, size: 20),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: (textStyle ?? const TextStyle()).copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseStats {
  const _PulseStats({
    required this.totalLogged,
    required this.monthlyLogged,
    required this.pendingOffline,
    required this.lastActivity,
  });

  final int totalLogged;
  final int monthlyLogged;
  final int pendingOffline;
  final DateTime? lastActivity;

  factory _PulseStats.from(
    List<PulseLogEntry> historyEntries,
    List<Pulse> offlinePulses,
  ) {
    final now = DateTime.now();
    final monthly = historyEntries.where((entry) {
      final local = entry.recordedAt.toLocal();
      return local.year == now.year && local.month == now.month;
    }).length;
    final lastActivity = historyEntries.isEmpty
        ? null
        : historyEntries.first.recordedAt.toLocal();
    return _PulseStats(
      totalLogged: historyEntries.length,
      monthlyLogged: monthly,
      pendingOffline: offlinePulses.length,
      lastActivity: lastActivity,
    );
  }
}

class _PulseStatsSummary extends StatelessWidget {
  const _PulseStatsSummary({required this.stats});

  final _PulseStats stats;

  @override
  Widget build(BuildContext context) {
    final tiles = <_PulseMetricTile>[
      _PulseMetricTile(
        icon: Icons.auto_graph,
        label: 'إجمالي النبضات المسجلة',
        value: stats.totalLogged.toString(),
        color: AppColors.primaryOrange,
      ),
      _PulseMetricTile(
        icon: Icons.calendar_month,
        label: 'نبضات هذا الشهر',
        value: stats.monthlyLogged.toString(),
        color: AppColors.success,
      ),
      _PulseMetricTile(
        icon: Icons.cloud_upload_outlined,
        label: 'قائمة الانتظار بدون اتصال',
        value: stats.pendingOffline.toString(),
        color: Colors.orange.shade600,
        subtitle: stats.pendingOffline == 0
            ? 'تمت مزامنة كل البيانات'
            : 'في انتظار الاتصال',
      ),
    ];

    if (stats.lastActivity != null) {
      tiles.add(
        _PulseMetricTile(
          icon: Icons.schedule_outlined,
          label: 'آخر نشاط',
          value: _formatTimestamp(stats.lastActivity!, short: true),
          color: Colors.blueGrey,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;
        if (isCompact) {
          return Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                tiles[i],
                if (i != tiles.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              Expanded(child: tiles[i]),
              if (i != tiles.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _PulseMetricTile extends StatelessWidget {
  const _PulseMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withAlpha((0.14 * 255).round()),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 16),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyAdminState extends StatelessWidget {
  const _EmptyAdminState({required this.stats});

  final _PulseStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _PulseStatsSummary(stats: stats),
        ),
        const SizedBox(height: 40),
        Icon(Icons.insights_outlined, size: 56, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(
          'لا يوجد نشاط للموظفين بعد',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'عندما يبدأ الموظفون في إرسال النبضات ستظهر لك التحليلات المباشرة وحالة المزامنة وكامل التفاصيل هنا.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _MonitorFilteredEmptyState extends StatelessWidget {
  const _MonitorFilteredEmptyState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد نتائج وفق الفلاتر المحددة',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'أعد ضبط الفلاتر لمشاهدة جميع الموظفين ومتابعة نشاطهم المباشر.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة ضبط الفلاتر'),
              onPressed: onClear,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTeamState extends StatelessWidget {
  const _EmptyTeamState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.group_outlined, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'لا يوجد أعضاء فريق حتى الآن',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'أضف الموظفين لبدء متابعة تسجيل الحضور، ومراقبة النشاط، وإدارة الصلاحيات.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHrState extends StatelessWidget {
  const _EmptyHrState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 72,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد تعديلات موارد بشرية بعد',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'سجل المكافآت أو الخصومات أو الملاحظات لإنشاء سجل موارد بشرية شفاف.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayrollInsights {
  const _PayrollInsights({
    required this.totalActiveSalary,
    required this.activeHeadcount,
    required this.averageSalary,
    required this.branches,
  });

  final double totalActiveSalary;
  final int activeHeadcount;
  final double averageSalary;
  final List<_BranchPayroll> branches;

  factory _PayrollInsights.from(List<Employee> employees) {
    final activeEmployees = employees.where((employee) => employee.isActive).toList();
    final totalSalary = activeEmployees.fold<double>(0, (sum, employee) => sum + employee.monthlySalary);
    final headcount = activeEmployees.length;
    final averageSalary = headcount == 0 ? 0.0 : totalSalary / headcount;

    final Map<String, _BranchPayroll> branchMap = {};
    for (final employee in activeEmployees) {
      final branchName = employee.branch.isNotEmpty ? employee.branch : 'فرع غير محدد';
      final existing = branchMap[branchName];
      if (existing == null) {
        branchMap[branchName] = _BranchPayroll(
          branchName: branchName,
          headcount: 1,
          totalSalary: employee.monthlySalary,
        );
      } else {
        branchMap[branchName] = existing.copyWith(
          headcount: existing.headcount + 1,
          totalSalary: existing.totalSalary + employee.monthlySalary,
        );
      }
    }

    final branches = branchMap.values.toList()
      ..sort((a, b) => b.totalSalary.compareTo(a.totalSalary));

    return _PayrollInsights(
    totalActiveSalary: totalSalary,
    activeHeadcount: headcount,
    averageSalary: averageSalary,
      branches: branches,
    );
  }
}

class _BranchPayroll {
  const _BranchPayroll({
    required this.branchName,
    required this.headcount,
    required this.totalSalary,
  });

  final String branchName;
  final int headcount;
  final double totalSalary;

  _BranchPayroll copyWith({int? headcount, double? totalSalary}) {
    return _BranchPayroll(
      branchName: branchName,
      headcount: headcount ?? this.headcount,
      totalSalary: totalSalary ?? this.totalSalary,
    );
  }
}

class _PayrollSummaryCard extends StatelessWidget {
  const _PayrollSummaryCard({required this.insights});

  final _PayrollInsights insights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF202B40), Color(0xFF1F4666)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F4666).withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, color: Colors.white70),
              const SizedBox(width: 10),
              Text(
                'ملخص الرواتب',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (insights.branches.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        insights.branches.first.branchName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _PayrollMetricTile(
                label: 'إجمالي الرواتب الشهرية',
                value: '${_formatCurrency(insights.totalActiveSalary)} ج.م',
                icon: Icons.savings_outlined,
              ),
              _PayrollMetricTile(
                label: 'عدد الموظفين النشطين',
                value: insights.activeHeadcount.toString(),
                icon: Icons.groups_2_outlined,
              ),
              _PayrollMetricTile(
                label: 'متوسط الراتب الشهري',
                value: insights.activeHeadcount == 0
                    ? '—'
                    : '${_formatCurrency(insights.averageSalary)} ج.م',
                icon: Icons.equalizer_outlined,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.white.withOpacity(0.18)),
          const SizedBox(height: 16),
          Text(
            'التوزيع حسب الفروع',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (insights.branches.isEmpty)
            Text(
              'لا يوجد موظفون نشطون حالياً لعرض كشوف المرتبات.',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
            )
          else
            Column(
              children: [
                for (final branch in insights.branches)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.apartment, color: Colors.white70),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                branch.branchName,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'الموظفون: ${branch.headcount}',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${_formatCurrency(branch.totalSalary)} ج.م',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PayrollMetricTile extends StatelessWidget {
  const _PayrollMetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
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

class _EmployeeSnapshot {
  const _EmployeeSnapshot({
    required this.employeeId,
    required this.displayName,
    required this.status,
    required this.totalDuration,
    required this.pulses,
    required this.pendingOfflineCount,
    required this.lastPulseAt,
    required this.role,
    required this.permissions,
    required this.isActive,
    required this.totalLogged,
    required this.monthlyLogged,
    required this.branch,
    required this.monthlySalary,
  });

  final String employeeId;
  final String displayName;
  final EmployeeStatus status;
  final Duration totalDuration;
  final List<_PulseSnapshot> pulses;
  final int pendingOfflineCount;
  final DateTime? lastPulseAt;
  final EmployeeRole? role;
  final List<EmployeePermission> permissions;
  final bool isActive;
  final int totalLogged;
  final int monthlyLogged;
  final String branch;
  final double monthlySalary;
}

class _PulseSnapshot {
  const _PulseSnapshot({
    required this.timestampLabel,
    required this.latitude,
    required this.longitude,
    required this.isFake,
    required this.wasOnline,
  });

  final String timestampLabel;
  final double latitude;
  final double longitude;
  final bool isFake;
  final bool wasOnline;
}

enum EmployeeStatus { checkedIn, checkedOut, offline, inactive }

List<_EmployeeSnapshot> _buildEmployeeSnapshots(
  List<PulseLogEntry> historyEntries,
  List<Pulse> offlinePulses,
  Map<String, Employee> employeeDirectory,
) {
  final Map<String, List<PulseLogEntry>> groupedHistory = {};
  for (final entry in historyEntries) {
    groupedHistory.putIfAbsent(entry.pulse.employeeId, () => []).add(entry);
  }

  final Map<String, int> offlineCounts = {};
  for (final pulse in offlinePulses) {
    offlineCounts[pulse.employeeId] =
        (offlineCounts[pulse.employeeId] ?? 0) + 1;
  }

  final snapshots = <_EmployeeSnapshot>[];

  void addSnapshot(String employeeId, List<PulseLogEntry> entries) {
    entries.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final latest = entries.isNotEmpty ? entries.first : null;
    final totalLogged = entries.length;
    final monthlyLogged = entries.where((entry) {
      final local = entry.recordedAt.toLocal();
      final now = DateTime.now();
      return local.year == now.year && local.month == now.month;
    }).length;
    final dayEntries = latest == null
        ? <PulseLogEntry>[]
        : entries
              .where(
                (log) =>
                    _isSameDay(log.pulse.timestamp, latest.pulse.timestamp),
              )
              .toList();
    final duration = latest == null || dayEntries.length < 2
        ? Duration.zero
        : latest.pulse.timestamp
              .difference(dayEntries.last.pulse.timestamp)
              .abs();
    final pendingOffline = offlineCounts[employeeId] ?? 0;
    final employeeRecord = employeeDirectory[employeeId];
    final displayName = employeeRecord?.fullName ?? employeeId;
    final branchLabel = employeeRecord?.branch ?? 'فرع غير محدد';
    final salaryValue = employeeRecord?.monthlySalary ?? 0;
    final status = _deriveStatus(
      latest,
      pendingOffline,
      employeeRecord?.isActive ?? true,
    );

    final recentPulses = entries.take(5).map((log) {
      final ts = log.pulse.timestamp.toLocal();
      final label = _formatTimestamp(ts);
      return _PulseSnapshot(
        timestampLabel: label,
        latitude: log.pulse.latitude,
        longitude: log.pulse.longitude,
        isFake: log.pulse.isFake,
        wasOnline: log.deliveryStatus == PulseDeliveryStatus.sentOnline,
      );
    }).toList();

    snapshots.add(
      _EmployeeSnapshot(
        employeeId: employeeId,
        displayName: displayName,
        status: status,
        totalDuration: duration,
        pulses: recentPulses,
        pendingOfflineCount: pendingOffline,
        lastPulseAt: latest?.pulse.timestamp.toLocal(),
        role: employeeRecord?.role,
        permissions: employeeRecord?.permissions ?? const [],
        isActive: employeeRecord?.isActive ?? true,
        totalLogged: totalLogged,
        monthlyLogged: monthlyLogged,
        branch: branchLabel,
        monthlySalary: salaryValue,
      ),
    );
  }

  groupedHistory.forEach(addSnapshot);

  for (final entry in employeeDirectory.entries) {
    if (!groupedHistory.containsKey(entry.key)) {
      addSnapshot(entry.key, <PulseLogEntry>[]);
    }
  }

  snapshots.sort((a, b) {
    final left = a.lastPulseAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final right = b.lastPulseAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return right.compareTo(left);
  });

  return snapshots;
}

EmployeeStatus _deriveStatus(
  PulseLogEntry? latest,
  int pendingOfflineCount,
  bool isActive,
) {
  if (!isActive) {
    return EmployeeStatus.inactive;
  }
  if (pendingOfflineCount > 0 ||
      (latest?.deliveryStatus ?? PulseDeliveryStatus.failed) ==
          PulseDeliveryStatus.queuedOffline) {
    return EmployeeStatus.offline;
  }
  if (latest == null) {
    return EmployeeStatus.checkedOut;
  }
  final minutesSincePulse = DateTime.now()
      .difference(latest.pulse.timestamp)
      .inMinutes;
  if (minutesSincePulse <= 10) {
    return EmployeeStatus.checkedIn;
  }
  return EmployeeStatus.checkedOut;
}

bool _isSameDay(DateTime a, DateTime b) {
  final localA = a.toLocal();
  final localB = b.toLocal();
  return localA.year == localB.year &&
      localA.month == localB.month &&
      localA.day == localB.day;
}

String _formatTimestamp(DateTime timestamp, {bool short = false}) {
  final local = timestamp.toLocal();
  final now = DateTime.now();
  final dateLabel = _isSameDay(local, now)
      ? 'اليوم'
      : '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
  final timeLabel =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return short ? '$dateLabel · $timeLabel' : '$dateLabel في $timeLabel';
}

String _formatCurrency(double value) {
  final isNegative = value.isNegative;
  final absoluteValue = value.abs();
  final raw = absoluteValue == absoluteValue.truncateToDouble()
      ? absoluteValue.toStringAsFixed(0)
      : absoluteValue.toStringAsFixed(2);
  final parts = raw.split('.');
  final digits = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    buffer.write(digits[i]);
    final remaining = digits.length - i - 1;
    if (remaining > 0 && remaining % 3 == 0) {
      buffer.write(',');
    }
  }
  if (parts.length > 1 && parts[1] != '00') {
    buffer.write('.');
    buffer.write(parts[1]);
  }
  final formatted = buffer.toString();
  return isNegative ? '-$formatted' : formatted;
}

Color _statusAccent(EmployeeStatus status) {
  switch (status) {
    case EmployeeStatus.checkedIn:
      return AppColors.success;
    case EmployeeStatus.checkedOut:
      return Colors.blueGrey;
    case EmployeeStatus.offline:
      return Colors.orange.shade700;
    case EmployeeStatus.inactive:
      return Colors.grey;
  }
}

String _statusLabelFor(EmployeeStatus status) {
  switch (status) {
    case EmployeeStatus.checkedIn:
      return 'مسجل حضور';
    case EmployeeStatus.checkedOut:
      return 'موقع مغادرة';
    case EmployeeStatus.offline:
      return 'بدون اتصال';
    case EmployeeStatus.inactive:
      return 'غير نشط';
  }
}

String _formatShiftDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).abs();
  return '$hoursس ${minutes.toString().padLeft(2, '0')}د';
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    this.showManagementActions = false,
    this.onToggleActive,
    this.onEdit,
    this.onRecordAdjustment,
  });

  final _EmployeeSnapshot employee;
  final bool showManagementActions;
  final VoidCallback? onToggleActive;
  final VoidCallback? onEdit;
  final VoidCallback? onRecordAdjustment;

  @override
  Widget build(BuildContext context) {
    final fakePulseCount = employee.pulses
        .where((pulse) => pulse.isFake)
        .length;
  final statusColor = _statusAccent(employee.status);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primaryOrange,
                  child: Text(
                    employee.displayName.isNotEmpty
                        ? employee.displayName.substring(0, 1).toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.displayName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'المعرف: ${employee.employeeId}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (employee.role != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _roleLabel(employee.role!),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha((0.15 * 255).round()),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusLabelFor(employee.status),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(
                      'مدة المناوبة: ${_formatShiftDuration(employee.totalDuration)}',
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_city, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text('الفرع: ${employee.branch}'),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.payments_outlined, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(
                      'الراتب الشهري: ${_formatCurrency(employee.monthlySalary)} ج.م',
                    ),
                  ],
                ),
                if (employee.totalLogged > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.favorite_rounded,
                        color: Colors.black54,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text('${employee.totalLogged} إجمالي'),
                    ],
                  ),
                if (employee.monthlyLogged > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_month,
                        color: Colors.black54,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text('${employee.monthlyLogged} هذا الشهر'),
                    ],
                  ),
              ],
            ),
            if (employee.lastPulseAt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, color: Colors.black54),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'آخر نبضة ${_formatTimestamp(employee.lastPulseAt!)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'أحدث النبضات',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (employee.pulses.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.hourglass_empty, color: Colors.black45),
                    SizedBox(width: 12),
                    Expanded(child: Text('لا توجد نبضات مسجلة بعد.')),
                  ],
                ),
              )
            else
              ...employee.pulses.map((pulse) {
                final isFake = pulse.isFake;
                final deliveredOnline = pulse.wasOnline;
                final backgroundColor =
                    (isFake
                            ? AppColors.danger
                            : deliveredOnline
                            ? AppColors.success
                            : Colors.orange.shade700)
                        .withAlpha((0.08 * 255).round());
                final icon = isFake
                    ? const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.danger,
                      )
                    : deliveredOnline
                    ? const Icon(
                        Icons.check_circle_outline,
                        color: AppColors.success,
                      )
                    : const Icon(Icons.cloud_off, color: Colors.orangeAccent);
                final description = isFake
                    ? '${pulse.timestampLabel} — خارج نطاق المطعم.'
                    : deliveredOnline
                    ? '${pulse.timestampLabel} — تمت المزامنة عبر الإنترنت.'
                    : '${pulse.timestampLabel} — في انتظار المزامنة.';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      icon,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              description,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: isFake
                                        ? AppColors.danger
                                        : deliveredOnline
                                        ? Colors.black87
                                        : Colors.orange.shade800,
                                    fontWeight: isFake
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'خط العرض: ${pulse.latitude.toStringAsFixed(4)}  |  خط الطول: ${pulse.longitude.toStringAsFixed(4)}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            if (employee.pendingOfflineCount > 0)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha((0.12 * 255).round()),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_upload_outlined,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${employee.pendingOfflineCount} نبضة بانتظار الاتصال.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            if (fakePulseCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.shield, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$fakePulseCount نبضات تم رصدها خارج المطعم. يرجى المراجعة.',
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (showManagementActions) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onEdit != null)
                    OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('تعديل'),
                    ),
                  if (onToggleActive != null)
                    OutlinedButton.icon(
                      onPressed: onToggleActive,
                      icon: Icon(
                        employee.isActive
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        size: 18,
                      ),
                      label: Text(
                        employee.isActive ? 'إيقاف التفعيل' : 'تفعيل',
                      ),
                    ),
                  if (onRecordAdjustment != null)
                    ElevatedButton.icon(
                      onPressed: onRecordAdjustment,
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('تعديل موارد بشرية'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MonitorTimelineSheet extends StatelessWidget {
  const _MonitorTimelineSheet({required this.snapshot});

  final _EmployeeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusAccent(snapshot.status);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: statusColor.withOpacity(0.12),
                      child: Text(
                        snapshot.displayName.isNotEmpty
                            ? snapshot.displayName.substring(0, 1).toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            snapshot.displayName,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'المعرف: ${snapshot.employeeId}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.grey.shade600),
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
                        color: statusColor.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _statusLabelFor(snapshot.status),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MonitorDetailChip(
                      icon: Icons.apartment,
                      label: 'الفرع',
                      value: snapshot.branch,
                      accentColor: Colors.blueGrey,
                    ),
                    _MonitorDetailChip(
                      icon: Icons.payments_outlined,
                      label: 'الراتب الشهري',
                      value: '${_formatCurrency(snapshot.monthlySalary)} ج.م',
                      accentColor: AppColors.success,
                    ),
                    _MonitorDetailChip(
                      icon: Icons.timer_outlined,
                      label: 'مدة اليوم',
                      value: _formatShiftDuration(snapshot.totalDuration),
                      accentColor: AppColors.primaryOrange,
                    ),
                    _MonitorDetailChip(
                      icon: Icons.bar_chart_rounded,
                      label: 'إجمالي النبضات',
                      value: snapshot.totalLogged.toString(),
                      accentColor: Colors.indigo,
                    ),
                    _MonitorDetailChip(
                      icon: Icons.calendar_month_outlined,
                      label: 'نبضات الشهر',
                      value: snapshot.monthlyLogged.toString(),
                      accentColor: Colors.teal,
                    ),
                    if (snapshot.pendingOfflineCount > 0)
                      _MonitorDetailChip(
                        icon: Icons.cloud_upload_outlined,
                        label: 'قيد المزامنة',
                        value: snapshot.pendingOfflineCount.toString(),
                        accentColor: Colors.orange.shade700,
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  'آخر النبضات',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                if (snapshot.pulses.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.speed_outlined,
                          color: Colors.grey.shade400,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد نبضات حديثة بعد',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'عند تسجيل الموظف لحضوره ستظهر أحدث المواقع وحالة الاتصال هنا.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    children: [
                      for (final pulse in snapshot.pulses)
                        _PulseTimelineRow(pulse: pulse),
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

class _MonitorDetailChip extends StatelessWidget {
  const _MonitorDetailChip({
    required this.icon,
    required this.label,
    required this.value,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.primaryOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.black54, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PulseTimelineRow extends StatelessWidget {
  const _PulseTimelineRow({required this.pulse});

  final _PulseSnapshot pulse;

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    final IconData iconData;
    final String deliveryLabel;

    if (pulse.isFake) {
      iconColor = AppColors.danger;
      iconData = Icons.new_releases_outlined;
      deliveryLabel = 'نبضة اختبارية';
    } else if (pulse.wasOnline) {
      iconColor = AppColors.success;
      iconData = Icons.wifi_rounded;
      deliveryLabel = 'تمت المزامنة فورياً';
    } else {
      iconColor = Colors.orange.shade700;
      iconData = Icons.cloud_upload_outlined;
      deliveryLabel = 'بانتظار الاتصال بالإنترنت';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(iconData, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pulse.timestampLabel,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  deliveryLabel,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 6),
                Text(
                  'خط العرض: ${pulse.latitude.toStringAsFixed(4)}، خط الطول: ${pulse.longitude.toStringAsFixed(4)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeFormSheet extends StatefulWidget {
  const _EmployeeFormSheet({this.existing});

  final Employee? existing;

  @override
  State<_EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends State<_EmployeeFormSheet> {
  late final TextEditingController _idController;
  late final TextEditingController _nameController;
  late final TextEditingController _pinController;
  late final TextEditingController _branchController;
  late final TextEditingController _salaryController;
  late EmployeeRole _role;
  late Set<EmployeePermission> _selectedPermissions;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _idController = TextEditingController(text: existing?.id ?? '');
    _nameController = TextEditingController(text: existing?.fullName ?? '');
    _pinController = TextEditingController(text: existing?.pin ?? '');
    _branchController = TextEditingController(text: existing?.branch ?? '');
    _salaryController = TextEditingController(
      text: existing?.monthlySalary.toStringAsFixed(2) ?? '',
    );
    _role = existing?.role ?? EmployeeRole.staff;
    _selectedPermissions = existing == null
        ? <EmployeePermission>{}
        : existing.permissions.toSet();
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _pinController.dispose();
    _branchController.dispose();
    _salaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final existing = widget.existing;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    existing == null ? 'إضافة موظف' : 'تعديل موظف',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _idController,
                readOnly: existing != null,
                decoration: const InputDecoration(
                  labelText: 'معرّف الموظف',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _branchController,
                decoration: const InputDecoration(
                  labelText: 'الفرع',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _salaryController,
                decoration: const InputDecoration(
                  labelText: 'الراتب الشهري (جنيه)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pinController,
                decoration: const InputDecoration(
                  labelText: 'الرقم السري',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                obscureText: true,
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'الدور',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<EmployeeRole>(
                    value: _role,
                    isExpanded: true,
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _role = value);
                    },
                    items: EmployeeRole.values
                        .map(
                          (role) => DropdownMenuItem<EmployeeRole>(
                            value: role,
                            child: Text(_roleLabel(role)),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'الصلاحيات',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: EmployeePermission.values
                    .map(
                      (permission) => FilterChip(
                        label: Text(_permissionLabel(permission)),
                        selected: _selectedPermissions.contains(permission),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedPermissions.add(permission);
                            } else {
                              _selectedPermissions.remove(permission);
                            }
                          });
                        },
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    existing == null ? 'إنشاء الموظف' : 'حفظ التعديلات',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final id = _idController.text.trim();
    final name = _nameController.text.trim();
    final pin = _pinController.text.trim();
    final branch = _branchController.text.trim();
    final salaryInput = _salaryController.text.trim().replaceAll(',', '');
    final salary = double.tryParse(salaryInput);

    if (id.isEmpty || name.isEmpty || pin.isEmpty || branch.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى ملء جميع الحقول المطلوبة.')),
      );
      return;
    }

    if (salary == null || salary < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال راتب شهري صالح.')),
      );
      return;
    }

    Navigator.of(context).pop(
      _EmployeeFormResult(
        id: id,
        fullName: name,
        pin: pin,
        role: _role,
        permissions: _selectedPermissions.toList(growable: false),
        branch: branch,
        monthlySalary: salary,
      ),
    );
  }
}

class _EmployeeFormResult {
  const _EmployeeFormResult({
    required this.id,
    required this.fullName,
    required this.pin,
    required this.role,
    required this.permissions,
    required this.branch,
    required this.monthlySalary,
  });

  final String id;
  final String fullName;
  final String pin;
  final EmployeeRole role;
  final List<EmployeePermission> permissions;
  final String branch;
  final double monthlySalary;
}

class _AdjustmentFormSheet extends StatefulWidget {
  const _AdjustmentFormSheet({required this.employee});

  final _EmployeeSnapshot employee;

  @override
  State<_AdjustmentFormSheet> createState() => _AdjustmentFormSheetState();
}

class _AdjustmentFormSheetState extends State<_AdjustmentFormSheet> {
  late AdjustmentType _type;
  late final TextEditingController _reasonController;
  late final TextEditingController _amountController;
  late final TextEditingController _recordedByController;

  @override
  void initState() {
    super.initState();
    _type = AdjustmentType.deduction;
    _reasonController = TextEditingController();
    _amountController = TextEditingController();
    _recordedByController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _amountController.dispose();
    _recordedByController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final requiresAmount = _type != AdjustmentType.note;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'تسجيل تعديل الموارد البشرية',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'الموظف: ${widget.employee.displayName}',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'النوع',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AdjustmentType>(
                    value: _type,
                    isExpanded: true,
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _type = value);
                    },
                    items: AdjustmentType.values
                        .map(
                          (type) => DropdownMenuItem<AdjustmentType>(
                            value: type,
                            child: Text(_adjustmentLabel(type)),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'السبب / الملاحظات',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              if (requiresAmount)
                TextField(
                  controller: _amountController,
                  decoration: InputDecoration(
                    labelText: _type == AdjustmentType.deduction
                        ? 'قيمة الخصم (جنيه)'
                        : 'قيمة المكافأة (جنيه)',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              if (requiresAmount) const SizedBox(height: 16),
              TextField(
                controller: _recordedByController,
                decoration: const InputDecoration(
                  labelText: 'سجل بواسطة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ التعديل'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final reason = _reasonController.text.trim();
    final recordedBy = _recordedByController.text.trim();
    final requiresAmount = _type != AdjustmentType.note;
    double? amount;

    if (requiresAmount) {
      amount = double.tryParse(_amountController.text.trim());
    }

    if (reason.isEmpty ||
        recordedBy.isEmpty ||
        (requiresAmount && amount == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى ملء جميع الحقول المطلوبة.')),
      );
      return;
    }

    Navigator.of(context).pop(
      _AdjustmentFormResult(
        type: _type,
        reason: reason,
        recordedBy: recordedBy,
        amount: amount,
      ),
    );
  }
}

class _AdjustmentFormResult {
  const _AdjustmentFormResult({
    required this.type,
    required this.reason,
    required this.recordedBy,
    this.amount,
  });

  final AdjustmentType type;
  final String reason;
  final String recordedBy;
  final double? amount;
}

String _roleLabel(EmployeeRole role) {
  switch (role) {
    case EmployeeRole.staff:
      return 'عضو فريق';
    case EmployeeRole.monitor:
      return 'مراقب';
    case EmployeeRole.hr:
      return 'شؤون الموظفين';
    case EmployeeRole.admin:
      return 'مسؤول';
  }
}

String _permissionLabel(EmployeePermission permission) {
  switch (permission) {
    case EmployeePermission.monitorAccess:
      return 'متابعة الدخول';
    case EmployeePermission.manageScheduling:
      return 'إدارة الجداول';
    case EmployeePermission.viewPayroll:
      return 'عرض الرواتب';
    case EmployeePermission.applyDiscounts:
      return 'تطبيق الخصومات';
    case EmployeePermission.manageEmployees:
      return 'إدارة الموظفين';
  }
}

String _adjustmentLabel(AdjustmentType type) {
  switch (type) {
    case AdjustmentType.deduction:
      return 'خصم';
    case AdjustmentType.bonus:
      return 'مكافأة';
    case AdjustmentType.note:
      return 'ملاحظة فقط';
  }
}
