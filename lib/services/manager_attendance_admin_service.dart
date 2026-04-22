import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_function_client.dart';

enum ManagerPenaltyType { halfDay, day, twoDays, custom }

extension ManagerPenaltyTypeX on ManagerPenaltyType {
  String get apiValue {
    switch (this) {
      case ManagerPenaltyType.halfDay:
        return 'half_day';
      case ManagerPenaltyType.day:
        return 'day';
      case ManagerPenaltyType.twoDays:
        return 'two_days';
      case ManagerPenaltyType.custom:
        return 'custom';
    }
  }

  String get label {
    switch (this) {
      case ManagerPenaltyType.halfDay:
        return 'نصف يوم';
      case ManagerPenaltyType.day:
        return 'يوم';
      case ManagerPenaltyType.twoDays:
        return 'يومين';
      case ManagerPenaltyType.custom:
        return 'مبلغ مخصص';
    }
  }
}

class ManagerAttendanceAdminService {
  const ManagerAttendanceAdminService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static String monthKey(DateTime month) {
    final safeMonth = DateTime(month.year, month.month, 1);
    final monthText = safeMonth.month.toString().padLeft(2, '0');
    return '${safeMonth.year}-$monthText';
  }

  static Future<Map<String, dynamic>> _call(
    String action,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await SupabaseFunctionClient.post(
        'manager-attendance-admin',
        {'action': action, ...payload},
      );

      if (response == null) {
        throw Exception('تعذر الوصول لخدمة إدارة الحضور حالياً');
      }

      if (response['success'] == false) {
        throw Exception(
          response['error']?.toString() ??
              response['message']?.toString() ??
              'فشل تنفيذ الطلب',
        );
      }

      final data = response['data'];
      if (data is Map<String, dynamic>) {
        return data;
      }

      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }

      return <String, dynamic>{};
    } catch (error) {
      if (_shouldUseDirectFallback(error)) {
        return _callDirectFallback(action, payload);
      }
      rethrow;
    }
  }

  static bool _shouldUseDirectFallback(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('failed to fetch') ||
        message.contains('clientexception') ||
        message.contains('requested function was not found') ||
        message.contains('function not found') ||
        message.contains('not_found') ||
        message.contains('404');
  }

  static Future<Map<String, dynamic>> _callDirectFallback(
    String action,
    Map<String, dynamic> payload,
  ) async {
    switch (action) {
      case 'get_branch_employees':
        return _directGetBranchEmployees(payload);
      case 'get_monthly_attendance':
        return _directGetMonthlyAttendance(payload);
      case 'update_day_times':
        return _directUpdateDayTimes(payload);
      case 'delete_day':
        return _directDeleteDay(payload);
      default:
        throw Exception('الخدمة غير متاحة حاليًا لهذا الإجراء');
    }
  }

  static List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  static String _pad2(int value) => value.toString().padLeft(2, '0');

  static String _dateKey(DateTime value) {
    return '${value.year}-${_pad2(value.month)}-${_pad2(value.day)}';
  }

  static DateTime _parseMonthOrNow(String monthValue) {
    final monthRegex = RegExp(r'^\d{4}-\d{2}$');
    if (!monthRegex.hasMatch(monthValue)) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, 1);
    }

    final parts = monthValue.split('-');
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);

    if (year == null || month == null || month < 1 || month > 12) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, 1);
    }

    return DateTime(year, month, 1);
  }

  static String? _dateFromIso(dynamic isoValue) {
    final text = isoValue?.toString();
    if (text == null || text.trim().isEmpty) return null;

    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;

    return _dateKey(parsed.toLocal());
  }

  static String? _normalizeSummaryTime(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;

    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(text);
    if (match == null) return null;

    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return '${_pad2(hour)}:${_pad2(minute)}';
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().toLowerCase().trim();
    return text == 'true' || text == 't' || text == '1' || text == 'yes';
  }

  static DateTime _parseCairoToUtc(String date, String time) {
    final parsed = DateTime.tryParse('${date}T$time:00+02:00');
    if (parsed == null) {
      throw Exception('صيغة الوقت غير صحيحة');
    }
    return parsed.toUtc();
  }

  static Future<Map<String, dynamic>> _loadEmployeeInBranch(
    String employeeId,
    String branchName,
  ) async {
    final result = await _supabase
        .from('employees')
        .select('id, branch, branch_id, hourly_rate, full_name')
        .eq('id', employeeId)
        .maybeSingle();

    if (result == null) {
      throw Exception('لم يتم العثور على الموظف');
    }

    final employee = Map<String, dynamic>.from(result as Map);
    final employeeBranch = employee['branch']?.toString() ?? '';
    if (employeeBranch != branchName) {
      throw Exception('الموظف ليس ضمن هذا الفرع');
    }

    return employee;
  }

  static Future<Map<String, dynamic>> _directGetBranchEmployees(
    Map<String, dynamic> payload,
  ) async {
    final branchName = payload['branchName']?.toString().trim() ?? '';
    if (branchName.isEmpty) {
      throw Exception('branchName مطلوب');
    }

    final response = await _supabase
        .from('employees')
        .select(
          'id, full_name, role, branch, branch_id, hourly_rate, shift_start_time, shift_end_time, is_active',
        )
        .eq('branch', branchName)
        .eq('is_active', true)
        .neq('role', 'owner')
        .order('full_name', ascending: true);

    return {'employees': _asMapList(response)};
  }

  static Future<Map<String, dynamic>> _directGetMonthlyAttendance(
    Map<String, dynamic> payload,
  ) async {
    final employeeId = payload['employeeId']?.toString().trim() ?? '';
    final monthRaw = payload['month']?.toString().trim() ?? '';

    if (employeeId.isEmpty) {
      throw Exception('employeeId مطلوب');
    }

    final month = _parseMonthOrNow(monthRaw);
    final startDate = DateTime(month.year, month.month, 1);
    final endDate = DateTime(month.year, month.month + 1, 0);
    final startKey = _dateKey(startDate);
    final endKey = _dateKey(endDate);

    final summaryRowsRaw = await _supabase
        .from('daily_attendance_summary')
        .select(
          'attendance_date, check_in_time, check_out_time, total_hours, is_absent, is_on_leave',
        )
        .eq('employee_id', employeeId)
        .gte('attendance_date', startKey)
        .lte('attendance_date', endKey);

    List<Map<String, dynamic>> attendanceRows = const [];
    try {
      final attendanceRaw = await _supabase
          .from('attendance')
          .select(
            'date, check_in_time, check_out_time, total_hours, work_hours, status',
          )
          .eq('employee_id', employeeId)
          .gte('date', startKey)
          .lte('date', endKey)
          .order('date', ascending: true)
          .order('check_in_time', ascending: true);
      attendanceRows = _asMapList(attendanceRaw);
    } catch (_) {
      // Keep summary rows only when attendance query shape varies by schema.
    }

    final summaryRows = _asMapList(summaryRowsRaw);
    final dayMap = <String, Map<String, dynamic>>{};

    for (final row in summaryRows) {
      final date = row['attendance_date']?.toString().split('T').first ?? '';
      if (date.isEmpty) continue;

      final checkIn = _normalizeSummaryTime(row['check_in_time']);
      final checkOut = _normalizeSummaryTime(row['check_out_time']);
      final isOnLeave = _toBool(row['is_on_leave']);
      final isAbsent = _toBool(row['is_absent']);

      var status = 'none';
      if (isOnLeave) {
        status = 'on_leave';
      } else if (isAbsent) {
        status = 'absent';
      } else if ((checkIn ?? '').isNotEmpty && (checkOut ?? '').isEmpty) {
        status = 'active';
      } else if ((checkIn ?? '').isNotEmpty) {
        status = 'present';
      }

      dayMap[date] = {
        'date': date,
        'check_in_time': checkIn,
        'check_out_time': checkOut,
        'total_hours': _toDouble(row['total_hours']),
        'status': status,
        'is_absent': isAbsent,
        'is_on_leave': isOnLeave,
      };
    }

    for (final row in attendanceRows) {
      final date =
          row['date']?.toString().split('T').first ??
          _dateFromIso(row['check_in_time']) ??
          _dateFromIso(row['check_out_time']) ??
          '';
      if (date.isEmpty) continue;

      final existing =
          dayMap[date] ??
          {
            'date': date,
            'check_in_time': null,
            'check_out_time': null,
            'total_hours': 0.0,
            'status': 'none',
            'is_absent': false,
            'is_on_leave': false,
          };

      existing['check_in_time'] ??= row['check_in_time']?.toString();
      existing['check_out_time'] ??= row['check_out_time']?.toString();
      final hours = _toDouble(row['total_hours']) > 0
          ? _toDouble(row['total_hours'])
          : _toDouble(row['work_hours']);
      if (_toDouble(existing['total_hours']) <= 0 && hours > 0) {
        existing['total_hours'] = hours;
      }

      final status = row['status']?.toString() ?? '';
      if (status.isNotEmpty && status != 'none') {
        existing['status'] = status;
      } else if ((existing['check_in_time']?.toString().isNotEmpty ?? false)) {
        existing['status'] =
            (existing['check_out_time']?.toString().isNotEmpty ?? false)
            ? 'present'
            : 'active';
      }

      dayMap[date] = existing;
    }

    final days = dayMap.keys.toList()..sort();

    return {
      'month': monthKey(month),
      'start_date': startKey,
      'end_date': endKey,
      'days': days
          .map((day) => dayMap[day])
          .whereType<Map<String, dynamic>>()
          .toList(),
    };
  }

  static Future<Map<String, dynamic>> _directUpdateDayTimes(
    Map<String, dynamic> payload,
  ) async {
    final branchName = payload['branchName']?.toString().trim() ?? '';
    final employeeId = payload['employeeId']?.toString().trim() ?? '';
    final date = payload['date']?.toString().trim() ?? '';
    final checkInText = payload['checkInTime']?.toString().trim() ?? '';
    final checkOutText = payload['checkOutTime']?.toString().trim() ?? '';

    if (branchName.isEmpty || employeeId.isEmpty || date.isEmpty) {
      throw Exception('بيانات تعديل الحضور غير مكتملة');
    }

    final employee = await _loadEmployeeInBranch(employeeId, branchName);

    final checkInUtc = _parseCairoToUtc(date, checkInText);
    final checkOutUtc = _parseCairoToUtc(date, checkOutText);
    final totalHours =
        checkOutUtc.difference(checkInUtc).inMinutes.toDouble() / 60.0;

    if (totalHours <= 0) {
      throw Exception('وقت الانصراف لازم يكون بعد وقت الحضور');
    }

    final roundedHours = double.parse(totalHours.toStringAsFixed(2));
    final hourlyRate = _toDouble(employee['hourly_rate']);
    final dailySalary = double.parse(
      (roundedHours * hourlyRate).toStringAsFixed(2),
    );

    final existingRaw = await _supabase
        .from('attendance')
        .select('id')
        .eq('employee_id', employeeId)
        .eq('date', date)
        .order('check_in_time', ascending: true);

    final existing = _asMapList(existingRaw);

    final attendancePayload = {
      'date': date,
      'check_in_time': checkInUtc.toIso8601String(),
      'check_out_time': checkOutUtc.toIso8601String(),
      'status': 'completed',
      'work_hours': roundedHours,
      'total_hours': roundedHours,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (existing.isNotEmpty) {
      await _supabase
          .from('attendance')
          .update(attendancePayload)
          .eq('id', existing.first['id']);
    } else {
      await _supabase.from('attendance').insert({
        'employee_id': employeeId,
        'branch_id': employee['branch_id'],
        ...attendancePayload,
      });
    }

    await _supabase.from('daily_attendance_summary').upsert({
      'employee_id': employeeId,
      'attendance_date': date,
      'check_in_time': '$checkInText:00',
      'check_out_time': '$checkOutText:00',
      'total_hours': roundedHours,
      'hourly_rate': hourlyRate,
      'daily_salary': dailySalary,
      'is_absent': false,
      'is_on_leave': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'employee_id,attendance_date');

    return {
      'employee_id': employeeId,
      'date': date,
      'check_in_time': checkInText,
      'check_out_time': checkOutText,
      'total_hours': roundedHours,
      'daily_salary': dailySalary,
    };
  }

  static Future<Map<String, dynamic>> _directDeleteDay(
    Map<String, dynamic> payload,
  ) async {
    final branchName = payload['branchName']?.toString().trim() ?? '';
    final employeeId = payload['employeeId']?.toString().trim() ?? '';
    final date = payload['date']?.toString().trim() ?? '';

    if (branchName.isEmpty || employeeId.isEmpty || date.isEmpty) {
      throw Exception('بيانات حذف اليوم غير مكتملة');
    }

    await _loadEmployeeInBranch(employeeId, branchName);

    await _supabase
        .from('attendance')
        .delete()
        .eq('employee_id', employeeId)
        .eq('date', date);

    await _supabase
        .from('daily_attendance_summary')
        .delete()
        .eq('employee_id', employeeId)
        .eq('attendance_date', date);

    await _supabase
        .from('deductions')
        .delete()
        .eq('employee_id', employeeId)
        .eq('deduction_date', date);

    try {
      await _supabase
          .from('absences')
          .delete()
          .eq('employee_id', employeeId)
          .eq('absence_date', date);
    } catch (_) {
      // Optional cleanup only.
    }

    return {'employee_id': employeeId, 'date': date, 'deleted': true};
  }

  static Future<List<Map<String, dynamic>>> getBranchEmployees({
    required String managerId,
    required String branchName,
  }) async {
    final data = await _call('get_branch_employees', {
      'managerId': managerId,
      'branchName': branchName,
    });

    return _asMapList(data['employees']);
  }

  static Future<Map<String, dynamic>> getMonthlyAttendance({
    required String managerId,
    required String branchName,
    required String employeeId,
    required DateTime month,
  }) async {
    return _call('get_monthly_attendance', {
      'managerId': managerId,
      'branchName': branchName,
      'employeeId': employeeId,
      'month': monthKey(month),
    });
  }

  static Future<Map<String, dynamic>> updateDayTimes({
    required String managerId,
    required String branchName,
    required String employeeId,
    required String date,
    required String checkInTime,
    required String checkOutTime,
  }) async {
    return _call('update_day_times', {
      'managerId': managerId,
      'branchName': branchName,
      'employeeId': employeeId,
      'date': date,
      'checkInTime': checkInTime,
      'checkOutTime': checkOutTime,
    });
  }

  static Future<Map<String, dynamic>> deleteDay({
    required String managerId,
    required String branchName,
    required String employeeId,
    required String date,
  }) async {
    return _call('delete_day', {
      'managerId': managerId,
      'branchName': branchName,
      'employeeId': employeeId,
      'date': date,
    });
  }

  static Future<Map<String, dynamic>> applyPenalty({
    required String managerId,
    required String branchName,
    required String employeeId,
    required String date,
    required ManagerPenaltyType penaltyType,
    double? customAmount,
    String? reason,
  }) async {
    return _call('apply_penalty', {
      'managerId': managerId,
      'branchName': branchName,
      'employeeId': employeeId,
      'date': date,
      'penaltyType': penaltyType.apiValue,
      if (customAmount != null) 'customAmount': customAmount,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  static Future<Map<String, dynamic>> listPenalties({
    required String managerId,
    required String branchName,
    DateTime? month,
    String? employeeId,
  }) async {
    return _call('list_penalties', {
      'managerId': managerId,
      'branchName': branchName,
      'month': monthKey(month ?? DateTime.now()),
      if (employeeId != null && employeeId.isNotEmpty) 'employeeId': employeeId,
    });
  }
}
