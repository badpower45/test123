import 'package:flutter/material.dart';
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
  List<Map<String, dynamic>> _allEmployees = [];

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _dateForApi(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _dateLabel(DateTime date) {
    return DateFormat('EEEE - dd/MM/yyyy', 'ar').format(date);
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
            .from('pulses')
            .select('id, employee_id, check_in, check_out, check_in_time, check_out_time')
            .gte('created_at', '${dateStr}T00:00:00.000Z')
            .lt('created_at', '${dateStr}T23:59:59.999Z'),
        _supabase
            .from('absences')
            .select('id, employee_id, status')
            .eq('absence_date', dateStr),
      ]);

      final employeesResp = List<Map<String, dynamic>>.from(results[0]);
      final pulsesResp = List<Map<String, dynamic>>.from(results[1]);
      final absencesResp = List<Map<String, dynamic>>.from(results[2]);

      final pulseMap = <String, Map<String, dynamic>>{};
      for (final p in pulsesResp) {
        final empId = p['employee_id']?.toString();
        if (empId != null) {
          pulseMap[empId] = Map<String, dynamic>.from(p);
        }
      }

      final absenceSet = <String>{};
      for (final a in absencesResp) {
        final empId = a['employee_id']?.toString();
        if (empId != null) {
          absenceSet.add(empId);
        }
      }

      final records = <Map<String, dynamic>>[];
      for (final emp in employeesResp) {
        final empId = emp['id']?.toString() ?? '';
        final pulse = pulseMap[empId];
        final isAbsent = absenceSet.contains(empId);

        final hasCheckIn = pulse != null && pulse['check_in'] != null;
        final hasCheckOut = pulse != null && pulse['check_out'] != null;

        String checkInTime = '-';
        String checkOutTime = '-';
        if (pulse != null) {
          if (pulse['check_in_time'] != null) {
            checkInTime = pulse['check_in_time'].toString();
          }
          if (pulse['check_out_time'] != null) {
            checkOutTime = pulse['check_out_time'].toString();
          }
        }

        records.add({
          ...emp,
          'check_in': hasCheckIn,
          'check_out': hasCheckOut,
          'check_in_time': checkInTime,
          'check_out_time': checkOutTime,
          'is_absent': isAbsent,
          'pulse': pulse,
        });
      }

      setState(() {
        _allEmployees = employeesResp;
        _attendanceRecords = records;
        _loading = false;
      });
    } catch (e) {
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
      setState(() {
        _selectedDate = picked;
      });
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _EditAttendanceSheet(
        employeeId: employeeId,
        employeeName: employeeName ?? '',
        date: _selectedDate,
        existingRecord: record,
        onSave: () => _loadData(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildDateSelector(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : _attendanceRecords.isEmpty
                        ? _buildEmpty()
                        : _buildAttendanceList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _selectedDate = _selectedDate.subtract(const Duration(days: 1));
              });
              _loadData();
            },
            icon: const Icon(Icons.chevron_right),
          ),
          Expanded(
            child: InkWell(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_today, color: AppColors.primaryOrange),
                    const SizedBox(width: 8),
                    Text(
                      _dateLabel(_selectedDate),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.edit_calendar, size: 18),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _selectedDate.isBefore(
                DateTime.now().subtract(const Duration(days: 1)))
                ? () {
                    setState(() {
                      _selectedDate = _selectedDate.add(const Duration(days: 1));
                    });
                    _loadData();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceList() {
    final checkedIn = _attendanceRecords.where((r) => r['check_in'] == true).length;
    final checkedOut =
        _attendanceRecords.where((r) => r['check_out'] == true).length;
    final absent = _attendanceRecords.where((r) => r['is_absent'] == true).length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatChip(
                label: 'حاضر',
                value: checkedIn.toString(),
                color: Colors.green,
              ),
              _StatChip(
                label: 'انصرف',
                value: checkedOut.toString(),
                color: Colors.blue,
              ),
              _StatChip(
                label: 'غائب',
                value: absent.toString(),
                color: Colors.red,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _attendanceRecords.length,
              itemBuilder: (context, index) {
                final record = _attendanceRecords[index];
                return _buildAttendanceCard(record);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceCard(Map<String, dynamic> record) {
    final fullName = record['full_name']?.toString() ?? '';
    final branch = record['branch']?.toString() ?? '';
    final role = record['role']?.toString() ?? 'staff';
    final hasCheckIn = record['check_in'] == true;
    final hasCheckOut = record['check_out'] == true;
    final isAbsent = record['is_absent'] == true;
    final checkInTime = record['check_in_time']?.toString() ?? '-';
    final checkOutTime = record['check_out_time']?.toString() ?? '-';

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isAbsent) {
      statusColor = Colors.red;
      statusText = 'غائب';
      statusIcon = Icons.close;
    } else if (hasCheckIn && hasCheckOut) {
      statusColor = Colors.green;
      statusText = 'مكتمل';
      statusIcon = Icons.check_circle;
    } else if (hasCheckIn) {
      statusColor = Colors.orange;
      statusText = 'متواجد';
      statusIcon = Icons.access_time;
    } else {
      statusColor = Colors.grey;
      statusText = 'لم يحضر';
      statusIcon = Icons.remove_circle_outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.2),
          child: Icon(statusIcon, color: statusColor),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                fullName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusText,
                style: TextStyle(fontSize: 12, color: statusColor),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$branch - ${_getRoleLabel(role)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              'حضور: $checkInTime | انصراف: $checkOutTime',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: !isAbsent
            ? IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _editAttendance(record),
              )
            : null,
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
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadData,
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
          Text('لا يوجد بيانات حضور', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
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
      final parts = time.split(':');
      if (parts.length >= 2) {
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1].split(' ')[0]),
        );
      }
    } catch (e) {}
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
        const SnackBar(content: Text('يرجى تحديد وقت الحضور أو الانصراف')),
      );
      return;
    }

    setState(() => _processing = true);

    try {
      final dateStr = _dateForApi(widget.date);
      final existingPulse = widget.existingRecord['pulse'] as Map<String, dynamic>?;

      if (existingPulse != null) {
        await _supabase.from('pulses').update({
          if (_hasCheckIn)
            'check_in_time':
                '${_checkInTime.hour.toString().padLeft(2, '0')}:${_checkInTime.minute.toString().padLeft(2, '0')}:00',
          if (_hasCheckOut)
            'check_out_time':
                '${_checkOutTime.hour.toString().padLeft(2, '0')}:${_checkOutTime.minute.toString().padLeft(2, '0')}:00',
        }).eq('id', existingPulse['id']);
      } else if (_hasCheckIn) {
        await _supabase.from('pulses').insert({
          'employee_id': widget.employeeId,
          'check_in': true,
          'check_in_time':
              '${_checkInTime.hour.toString().padLeft(2, '0')}:${_checkInTime.minute.toString().padLeft(2, '0')}:00',
          'created_at':
              '${dateStr}T${_checkInTime.hour.toString().padLeft(2, '0')}:${_checkInTime.minute.toString().padLeft(2, '0')}:00.000Z',
        });
      }

      widget.onSave();
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم حفظ التغييرات'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تعديل الحضور - ${widget.employeeName}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text('هل حضر؟'),
              value: _hasCheckIn,
              onChanged: (value) {
                setState(() {
                  _hasCheckIn = value;
                  if (value) _pickCheckInTime();
                });
              },
            ),
            if (_hasCheckIn)
              ListTile(
                title: const Text('وقت الحضور'),
                subtitle: Text(_checkInTime.format(context)),
                trailing: const Icon(Icons.access_time),
                onTap: _pickCheckInTime,
              ),
            SwitchListTile(
              title: const Text('هل انصرف؟'),
              value: _hasCheckOut,
              onChanged: (value) {
                setState(() {
                  _hasCheckOut = value;
                  if (value) _pickCheckOutTime();
                });
              },
            ),
            if (_hasCheckOut)
              ListTile(
                title: const Text('وقت الانصراف'),
                subtitle: Text(_checkOutTime.format(context)),
                trailing: const Icon(Icons.exit_to_app),
                onTap: _pickCheckOutTime,
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _processing ? null : _save,
                child: _processing
                    ? const CircularProgressIndicator()
                    : const Text('حفظ التغييرات'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}