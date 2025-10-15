class AttendanceReport {
  AttendanceReport({
    required this.employeeId,
    required this.period,
    required this.attendance,
    required this.advances,
    required this.leaves,
    required this.deductions,
    required this.summary,
  });

  final String employeeId;
  final ReportPeriod period;
  final List<Map<String, dynamic>> attendance;
  final List<Map<String, dynamic>> advances;
  final List<Map<String, dynamic>> leaves;
  final List<Map<String, dynamic>> deductions;
  final AttendanceSummary summary;

  factory AttendanceReport.fromJson(Map<String, dynamic> json) {
    return AttendanceReport(
      employeeId: (json['employeeId'] ?? json['employee_id'] ?? '') as String,
      period: ReportPeriod.fromJson(json['period'] as Map<String, dynamic>),
      attendance: (json['attendance'] as List<dynamic>)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList(),
      advances: (json['advances'] as List<dynamic>)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList(),
      leaves: (json['leaves'] as List<dynamic>)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList(),
      deductions: (json['deductions'] as List<dynamic>)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList(),
      summary:
          AttendanceSummary.fromJson(json['summary'] as Map<String, dynamic>),
    );
  }
}

class ReportPeriod {
  ReportPeriod({
    required this.start,
    required this.end,
  });

  final DateTime start;
  final DateTime end;

  factory ReportPeriod.fromJson(Map<String, dynamic> json) {
    final startRaw = (json['start_date'] ?? json['start']) as String;
    final endRaw = (json['end_date'] ?? json['end']) as String;
    return ReportPeriod(
      start: DateTime.parse(startRaw),
      end: DateTime.parse(endRaw),
    );
  }
}

class AttendanceSummary {
  AttendanceSummary({
    required this.totalWorkHours,
    required this.totalAdvances,
    required this.totalDeductions,
    required this.totalLeaveAllowance,
  });

  final double totalWorkHours;
  final double totalAdvances;
  final double totalDeductions;
  final double totalLeaveAllowance;

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
  num _numValue(Object? value) => (value as num? ?? 0);
    return AttendanceSummary(
    totalWorkHours:
      _numValue(json['totalWorkHours'] ?? json['total_work_hours'])
        .toDouble(),
    totalAdvances:
      _numValue(json['totalAdvances'] ?? json['total_advances']).toDouble(),
    totalDeductions: _numValue(
        json['totalDeductions'] ?? json['total_deductions'])
      .toDouble(),
    totalLeaveAllowance: _numValue(
        json['totalLeaveAllowance'] ?? json['total_leave_allowance'])
      .toDouble(),
    );
  }
}
