import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';

class HRAttendanceScreen extends StatefulWidget {
  final String hrId;

  const HRAttendanceScreen({super.key, required this.hrId});

  @override
  State<HRAttendanceScreen> createState() => _HRAttendanceScreenState();
}

class _HRAttendanceScreenState extends State<HRAttendanceScreen> {
  bool _loading = true;
  String? _error;

  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _attendanceRecords = [];
  List<Map<String, dynamic>> _branches = [];
  String _selectedBranch = 'الكل';
  String _searchQuery = '';

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _loadData();
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

  String _dateForApi(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _dateLabel(DateTime date) {
    return DateFormat('EEEE - d MMMM yyyy', 'ar').format(date);
  }

  /// Formats raw time string (e.g. "09:15:00", "2026-07-27T09:15:00.000Z") to clean Arabic 12-hour AM/PM format
  String _formatTime12h(String? rawTime) {
    if (rawTime == null || rawTime.isEmpty || rawTime == '-' || rawTime == 'null') {
      return '-';
    }

    try {
      String timePart = rawTime;
      if (rawTime.contains('T')) {
        final parsedIso = DateTime.parse(rawTime).toLocal();
        return DateFormat('hh:mm a', 'ar').format(parsedIso);
      }

      final cleanTime = timePart.split('.').first;
      final parts = cleanTime.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        final dt = DateTime(2026, 1, 1, hour, minute);
        return DateFormat('hh:mm a', 'ar').format(dt);
      }
    } catch (e) {
      debugPrint('Time format error ($rawTime): $e');
    }

    return rawTime;
  }

  /// Calculates total daily working hours and minutes for an employee
  _HoursResult _calculateRecordHours(
    String? checkInStr,
    String? checkOutStr,
    Map<String, dynamic>? summary,
  ) {
    // 1. Try from summary total_hours if present
    if (summary != null && summary['total_hours'] != null) {
      final numVal = summary['total_hours'];
      if (numVal is num && numVal > 0) {
        final double hours = numVal.toDouble();
        final int h = hours.floor();
        final int m = ((hours - h) * 60).round();
        return _HoursResult(hours: hours, formatted: m > 0 ? '$h س $m د' : '$h ساعات');
      }
    }

    // 2. Parse from check_in and check_out
    if (checkInStr == null || checkInStr.isEmpty || checkInStr == '-') {
      return const _HoursResult(hours: 0, formatted: '0 س');
    }

    try {
      DateTime? inTime;
      DateTime? outTime;

      if (checkInStr.contains('T')) {
        inTime = DateTime.parse(checkInStr).toLocal();
      } else {
        final p = checkInStr.split(':');
        if (p.length >= 2) {
          inTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day,
              int.parse(p[0]), int.parse(p[1]));
        }
      }

      if (checkOutStr != null && checkOutStr.isNotEmpty && checkOutStr != '-') {
        if (checkOutStr.contains('T')) {
          outTime = DateTime.parse(checkOutStr).toLocal();
        } else {
          final p = checkOutStr.split(':');
          if (p.length >= 2) {
            outTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day,
                int.parse(p[0]), int.parse(p[1]));
          }
        }
      } else {
        // Currently present (In-progress work today)
        final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) ==
            DateFormat('yyyy-MM-dd').format(DateTime.now());
        if (isToday && inTime != null) {
          outTime = DateTime.now();
        }
      }

      if (inTime != null && outTime != null && outTime.isAfter(inTime)) {
        final diff = outTime.difference(inTime);
        final double hours = diff.inMinutes / 60.0;
        final int h = diff.inHours;
        final int m = diff.inMinutes.remainder(60);

        if (checkOutStr == null || checkOutStr.isEmpty || checkOutStr == '-') {
          return _HoursResult(
            hours: hours,
            formatted: '$h س $m د (مستمر)',
            isLive: true,
          );
        }

        return _HoursResult(hours: hours, formatted: m > 0 ? '$h س $m د' : '$h ساعات');
      }
    } catch (e) {
      debugPrint('Hours calculation error: $e');
    }

    return const _HoursResult(hours: 0, formatted: '0 س');
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dateStr = _dateForApi(_selectedDate);

      final results = await Future.wait([
        _supabase
            .from('employees')
            .select('id, full_name, role, branch')
            .neq('role', 'owner')
            .eq('is_active', true)
            .order('full_name'),
        _supabase
            .from('daily_attendance_summary')
            .select('id, employee_id, check_in_time, check_out_time, is_absent, is_on_leave, total_hours')
            .eq('attendance_date', dateStr),
        _supabase
            .from('attendance')
            .select('id, employee_id, check_in_time, check_out_time, status, total_hours')
            .eq('date', dateStr),
        _supabase
            .from('absences')
            .select('id, employee_id, status')
            .eq('absence_date', dateStr),
      ]);

      final employeesResp = List<Map<String, dynamic>>.from(results[0]);
      final summaryResp = List<Map<String, dynamic>>.from(results[1]);
      final attendanceResp = List<Map<String, dynamic>>.from(results[2]);
      final absencesResp = List<Map<String, dynamic>>.from(results[3]);

      final summaryMap = <String, Map<String, dynamic>>{};
      for (final s in summaryResp) {
        final empId = s['employee_id']?.toString();
        if (empId != null) summaryMap[empId] = Map<String, dynamic>.from(s);
      }

      final attendanceMap = <String, Map<String, dynamic>>{};
      for (final a in attendanceResp) {
        final empId = a['employee_id']?.toString();
        if (empId != null) attendanceMap[empId] = Map<String, dynamic>.from(a);
      }

      final absenceSet = <String>{};
      for (final a in absencesResp) {
        final empId = a['employee_id']?.toString();
        if (empId != null) absenceSet.add(empId);
      }

      final records = <Map<String, dynamic>>[];
      for (final emp in employeesResp) {
        final empId = emp['id']?.toString() ?? '';
        final summary = summaryMap[empId];
        final legacyAtt = attendanceMap[empId];
        final isAbsent = absenceSet.contains(empId) || (summary != null && summary['is_absent'] == true);

        String? checkInTimeStr = summary?['check_in_time']?.toString() ?? legacyAtt?['check_in_time']?.toString();
        String? checkOutTimeStr = summary?['check_out_time']?.toString() ?? legacyAtt?['check_out_time']?.toString();

        final hasCheckIn = checkInTimeStr != null && checkInTimeStr.isNotEmpty && checkInTimeStr != '-';
        final hasCheckOut = checkOutTimeStr != null && checkOutTimeStr.isNotEmpty && checkOutTimeStr != '-';

        final hoursRes = _calculateRecordHours(checkInTimeStr, checkOutTimeStr, summary);

        records.add({
          ...emp,
          'check_in': hasCheckIn,
          'check_out': hasCheckOut,
          'check_in_time': checkInTimeStr ?? '-',
          'check_out_time': checkOutTimeStr ?? '-',
          'check_in_formatted': _formatTime12h(checkInTimeStr),
          'check_out_formatted': _formatTime12h(checkOutTimeStr),
          'total_hours_num': hoursRes.hours,
          'total_hours_str': hoursRes.formatted,
          'is_live_work': hoursRes.isLive,
          'is_absent': isAbsent,
          'summary': summary,
          'attendance': legacyAtt,
        });
      }

      if (!mounted) return;
      setState(() {
        _attendanceRecords = records;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: _selectedDate,
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadData();
    }
  }

  Future<void> _editAttendance(Map<String, dynamic> record) async {
    final employeeId = record['id']?.toString();
    final employeeName = record['full_name']?.toString();
    if (employeeId == null) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditAttendanceSheet(
        employeeId: employeeId,
        employeeName: employeeName ?? '',
        date: _selectedDate,
        existingRecord: record,
        onSave: () => _loadData(),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredRecords {
    var filtered = _attendanceRecords;

    if (_selectedBranch != 'الكل') {
      filtered = filtered.where((r) => (r['branch'] ?? '') == _selectedBranch).toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered = filtered.where((r) {
        final name = (r['full_name'] ?? '').toString().toLowerCase();
        final branch = (r['branch'] ?? '').toString().toLowerCase();
        final id = (r['id'] ?? '').toString().toLowerCase();
        return name.contains(q) || branch.contains(q) || id.contains(q);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeaderControls(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : _filteredRecords.isEmpty
                        ? _buildEmpty()
                        : _buildAttendanceView(),
          ),
        ],
      ),
    );
  }

  /// Top Controls Bar (Date Selector, Branch Filter, Search)
  Widget _buildHeaderControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Date Navigation (Previous Day)
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                  });
                  _loadData();
                },
                icon: const Icon(Icons.chevron_right_rounded, size: 28),
                tooltip: 'اليوم السابق',
              ),

              // Date Picker Field
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryOrange.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primaryOrange.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 18, color: AppColors.primaryOrange),
                        const SizedBox(width: 8),
                        Text(
                          _dateLabel(_selectedDate),
                          style: GoogleFonts.tajawal(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_drop_down_rounded, color: AppColors.primaryOrange),
                      ],
                    ),
                  ),
                ),
              ),

              // Date Navigation (Next Day)
              IconButton(
                onPressed: _selectedDate.isBefore(DateTime.now())
                    ? () {
                        setState(() {
                          _selectedDate = _selectedDate.add(const Duration(days: 1));
                        });
                        _loadData();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 28),
                tooltip: 'اليوم التالي',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Search Input
              Expanded(
                flex: 2,
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'ابحث باسم الموظف أو الفرع...',
                    hintStyle: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Colors.grey),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Branch Filter Dropdown
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedBranch,
                      isExpanded: true,
                      icon: const Icon(Icons.filter_alt_rounded, size: 18, color: AppColors.primaryOrange),
                      style: GoogleFonts.tajawal(fontSize: 12, color: Colors.black87),
                      items: [
                        const DropdownMenuItem(value: 'الكل', child: Text('جميع الفروع')),
                        ..._branches.map((b) {
                          final name = b['name']?.toString() ?? '';
                          return DropdownMenuItem(value: name, child: Text(name));
                        }),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedBranch = val);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Main Attendance View (Summary Chips & Employee Cards)
  Widget _buildAttendanceView() {
    final records = _filteredRecords;

    final presentNow = records.where((r) => r['check_in'] == true && r['check_out'] != true).toList();
    final checkedOutCount = records.where((r) => r['check_out'] == true).length;
    final absentCount = records.where((r) => r['is_absent'] == true).length;

    final totalHoursSum = records.fold<double>(
      0.0,
      (sum, r) => sum + ((r['total_hours_num'] as num?)?.toDouble() ?? 0.0),
    );

    return Column(
      children: [
        // Summary Metrics Cards Header
        Container(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildStatCard(
                    title: 'الحاضرون الآن',
                    value: '${presentNow.length}',
                    icon: Icons.person_pin_circle_rounded,
                    color: Colors.green,
                    width: isWide ? (constraints.maxWidth - 30) / 4 : (constraints.maxWidth - 10) / 2,
                  ),
                  _buildStatCard(
                    title: 'تم الانصراف',
                    value: '$checkedOutCount',
                    icon: Icons.logout_rounded,
                    color: Colors.blue,
                    width: isWide ? (constraints.maxWidth - 30) / 4 : (constraints.maxWidth - 10) / 2,
                  ),
                  _buildStatCard(
                    title: 'الغائبين',
                    value: '$absentCount',
                    icon: Icons.cancel_rounded,
                    color: Colors.red,
                    width: isWide ? (constraints.maxWidth - 30) / 4 : (constraints.maxWidth - 10) / 2,
                  ),
                  _buildStatCard(
                    title: 'إجمالي الساعات اليوم',
                    value: '${totalHoursSum.toStringAsFixed(1)} س',
                    icon: Icons.timer_rounded,
                    color: AppColors.primaryOrange,
                    width: isWide ? (constraints.maxWidth - 30) / 4 : (constraints.maxWidth - 10) / 2,
                  ),
                ],
              );
            },
          ),
        ),

        // Live Active Present Employees Highlights (If any)
        if (presentNow.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.sensors_rounded, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  'الحاضرين حالياً (${presentNow.length}): ',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green.shade800),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: presentNow.map((r) {
                        return Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Text(
                            '${r['full_name']} • ${r['check_in_formatted']}',
                            style: GoogleFonts.tajawal(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade900),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Employee Attendance Cards List
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: records.length,
              itemBuilder: (context, index) {
                return _buildAttendanceCard(records[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Metric Card Widget for Summary
  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: GoogleFonts.tajawal(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  title,
                  style: GoogleFonts.tajawal(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Employee Attendance Card with Formatted 12h Times & Total Daily Hours
  Widget _buildAttendanceCard(Map<String, dynamic> record) {
    final fullName = record['full_name']?.toString() ?? '';
    final branch = record['branch']?.toString() ?? 'فرع غير محدد';
    final role = record['role']?.toString() ?? 'staff';
    final hasCheckIn = record['check_in'] == true;
    final hasCheckOut = record['check_out'] == true;
    final isAbsent = record['is_absent'] == true;
    final checkInFormatted = record['check_in_formatted']?.toString() ?? '-';
    final checkOutFormatted = record['check_out_formatted']?.toString() ?? '-';
    final totalHoursStr = record['total_hours_str']?.toString() ?? '0 س';

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isAbsent) {
      statusColor = AppColors.error;
      statusText = 'غائب';
      statusIcon = Icons.cancel_rounded;
    } else if (hasCheckIn && hasCheckOut) {
      statusColor = Colors.blue.shade700;
      statusText = 'مكتمل (انصرف)';
      statusIcon = Icons.task_alt_rounded;
    } else if (hasCheckIn) {
      statusColor = AppColors.success;
      statusText = 'حاضر الآن';
      statusIcon = Icons.check_circle_rounded;
    } else {
      statusColor = Colors.grey.shade600;
      statusText = 'لم يحضر';
      statusIcon = Icons.remove_circle_outline_rounded;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasCheckIn && !hasCheckOut
              ? AppColors.success.withOpacity(0.4)
              : Colors.grey.shade200,
          width: hasCheckIn && !hasCheckOut ? 1.5 : 1.0,
        ),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // Top Employee Info Header
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: statusColor.withOpacity(0.12),
                  child: Text(
                    fullName.isNotEmpty ? fullName[0] : 'E',
                    style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.storefront_rounded, size: 13, color: Colors.grey[600]),
                          const SizedBox(width: 3),
                          Text(
                            branch,
                            style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey[600]),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getRoleLabel(role),
                              style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey[700]),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Status Badge & Edit Icon
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 14, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: GoogleFonts.tajawal(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.edit_note_rounded, color: AppColors.primaryOrange, size: 22),
                      onPressed: () => _editAttendance(record),
                      tooltip: 'تعديل سجل الحضور',
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Time & Hours Badges Section (Check-in, Check-out, Total Hours)
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 500;
                return isWide
                    ? Row(
                        children: [
                          Expanded(child: _buildTimeBox(
                            title: 'وقت الحضور',
                            value: checkInFormatted,
                            icon: Icons.login_rounded,
                            color: Colors.green,
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _buildTimeBox(
                            title: 'وقت الانصراف',
                            value: checkOutFormatted,
                            icon: Icons.logout_rounded,
                            color: hasCheckOut ? Colors.blue : Colors.orange,
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _buildTimeBox(
                            title: 'إجمالي ساعات اليوم',
                            value: totalHoursStr,
                            icon: Icons.schedule_rounded,
                            color: AppColors.primaryOrange,
                            isHighlighted: true,
                          )),
                        ],
                      )
                    : Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildTimeBox(
                                title: 'وقت الحضور',
                                value: checkInFormatted,
                                icon: Icons.login_rounded,
                                color: Colors.green,
                              )),
                              const SizedBox(width: 8),
                              Expanded(child: _buildTimeBox(
                                title: 'وقت الانصراف',
                                value: checkOutFormatted,
                                icon: Icons.logout_rounded,
                                color: hasCheckOut ? Colors.blue : Colors.orange,
                              )),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _buildTimeBox(
                            title: 'إجمالي ساعات اليوم',
                            value: totalHoursStr,
                            icon: Icons.schedule_rounded,
                            color: AppColors.primaryOrange,
                            isHighlighted: true,
                          ),
                        ],
                      );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Individual Badge Box for Check-In / Check-Out / Total Hours
  Widget _buildTimeBox({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isHighlighted ? color.withOpacity(0.08) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHighlighted ? color.withOpacity(0.3) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.tajawal(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.tajawal(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isHighlighted ? color : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'manager':
        return 'مدير';
      case 'hr':
        return 'موارد بشرية';
      case 'admin':
        return 'إداري';
      case 'staff':
        return 'موظف';
      default:
        return role;
    }
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 54, color: AppColors.error),
          const SizedBox(height: 12),
          Text(_error!, style: GoogleFonts.tajawal(color: AppColors.error)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('إعادة المحاولة', style: GoogleFonts.tajawal()),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy_rounded, size: 54, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'لا يوجد بيانات حضور لهذا اليوم أو الفرع المحدد',
            style: GoogleFonts.tajawal(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _HoursResult {
  final double hours;
  final String formatted;
  final bool isLive;

  const _HoursResult({
    required this.hours,
    required this.formatted,
    this.isLive = false,
  });
}

class _EditAttendanceSheet extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final DateTime date;
  final Map<String, dynamic> existingRecord;
  final VoidCallback onSave;

  const _EditAttendanceSheet({
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.existingRecord,
    required this.onSave,
  });

  @override
  State<_EditAttendanceSheet> createState() => _EditAttendanceSheetState();
}

class _EditAttendanceSheetState extends State<_EditAttendanceSheet> {
  final _supabase = Supabase.instance.client;
  bool _processing = false;

  TimeOfDay _checkInTime = TimeOfDay.now();
  TimeOfDay _checkOutTime = TimeOfDay.now();
  bool _hasCheckIn = false;
  bool _hasCheckOut = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingRecord;
    _hasCheckIn = existing['check_in'] == true;
    _hasCheckOut = existing['check_out'] == true;

    if (existing['check_in_time'] != null && existing['check_in_time'] != '-') {
      _checkInTime = _parseTime(existing['check_in_time'].toString());
    }
    if (existing['check_out_time'] != null && existing['check_out_time'] != '-') {
      _checkOutTime = _parseTime(existing['check_out_time'].toString());
    }
  }

  TimeOfDay _parseTime(String time) {
    try {
      if (time.contains('T')) {
        final parsed = DateTime.parse(time).toLocal();
        return TimeOfDay(hour: parsed.hour, minute: parsed.minute);
      }
      final parts = time.split(':');
      if (parts.length >= 2) {
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1].split(' ')[0]),
        );
      }
    } catch (e) {
      debugPrint('Parse time error: $e');
    }
    return TimeOfDay.now();
  }

  String _dateForApi(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  Future<void> _pickCheckInTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _checkInTime,
    );
    if (picked != null) {
      setState(() {
        _checkInTime = picked;
        _hasCheckIn = true;
      });
    }
  }

  Future<void> _pickCheckOutTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _checkOutTime,
    );
    if (picked != null) {
      setState(() {
        _checkOutTime = picked;
        _hasCheckOut = true;
      });
    }
  }

  Future<void> _save() async {
    if (!_hasCheckIn && !_hasCheckOut) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('يرجى تحديد وقت الحضور أو الانصراف', style: GoogleFonts.tajawal()),
        ),
      );
      return;
    }

    setState(() => _processing = true);

    try {
      final dateStr = _dateForApi(widget.date);
      final checkInTimeFormatted = _hasCheckIn
          ? '${_checkInTime.hour.toString().padLeft(2, '0')}:${_checkInTime.minute.toString().padLeft(2, '0')}:00'
          : null;
      final checkOutTimeFormatted = _hasCheckOut
          ? '${_checkOutTime.hour.toString().padLeft(2, '0')}:${_checkOutTime.minute.toString().padLeft(2, '0')}:00'
          : null;

      double calculatedHours = 0.0;
      if (_hasCheckIn && _hasCheckOut) {
        final startMin = _checkInTime.hour * 60 + _checkInTime.minute;
        final endMin = _checkOutTime.hour * 60 + _checkOutTime.minute;
        if (endMin > startMin) {
          calculatedHours = (endMin - startMin) / 60.0;
        }
      }

      final summaryPayload = <String, dynamic>{
        'employee_id': widget.employeeId,
        'attendance_date': dateStr,
        'is_absent': false,
        'total_hours': calculatedHours > 0 ? calculatedHours : null,
      };
      if (checkInTimeFormatted != null) {
        summaryPayload['check_in_time'] = checkInTimeFormatted;
      }
      if (checkOutTimeFormatted != null) {
        summaryPayload['check_out_time'] = checkOutTimeFormatted;
      }

      await _supabase
          .from('daily_attendance_summary')
          .upsert(summaryPayload, onConflict: 'employee_id,attendance_date');

      final attendancePayload = <String, dynamic>{
        'employee_id': widget.employeeId,
        'date': dateStr,
        'status': checkOutTimeFormatted != null ? 'completed' : 'present',
        'total_hours': calculatedHours > 0 ? calculatedHours : null,
      };
      if (checkInTimeFormatted != null) {
        attendancePayload['check_in_time'] = '${dateStr}T$checkInTimeFormatted.000Z';
      }
      if (checkOutTimeFormatted != null) {
        attendancePayload['check_out_time'] = '${dateStr}T$checkOutTimeFormatted.000Z';
      }

      await _supabase.from('attendance').upsert(attendancePayload);

      widget.onSave();
      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ تم حفظ التغييرات وساعات العمل', style: GoogleFonts.tajawal()),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $e', style: GoogleFonts.tajawal()),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_calendar_rounded, color: AppColors.primaryOrange),
              const SizedBox(width: 8),
              Text(
                'تعديل الحضور - ${widget.employeeName}',
                style: GoogleFonts.tajawal(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          SwitchListTile(
            title: Text('سجل الحضور', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            value: _hasCheckIn,
            activeColor: AppColors.primaryOrange,
            onChanged: (value) {
              setState(() {
                _hasCheckIn = value;
                if (value) _pickCheckInTime();
              });
            },
          ),
          if (_hasCheckIn)
            ListTile(
              title: Text('وقت الحضور', style: GoogleFonts.tajawal()),
              subtitle: Text(
                _checkInTime.format(context),
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.green),
              ),
              trailing: const Icon(Icons.access_time_rounded, color: Colors.green),
              onTap: _pickCheckInTime,
            ),
          SwitchListTile(
            title: Text('سجل الانصراف', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            value: _hasCheckOut,
            activeColor: AppColors.primaryOrange,
            onChanged: (value) {
              setState(() {
                _hasCheckOut = value;
                if (value) _pickCheckOutTime();
              });
            },
          ),
          if (_hasCheckOut)
            ListTile(
              title: Text('وقت الانصراف', style: GoogleFonts.tajawal()),
              subtitle: Text(
                _checkOutTime.format(context),
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.blue),
              ),
              trailing: const Icon(Icons.logout_rounded, color: Colors.blue),
              onTap: _pickCheckOutTime,
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _processing ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _processing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text('حفظ التغييرات', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}