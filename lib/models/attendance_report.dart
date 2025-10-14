class AttendanceReport {
  AttendanceReport({
    required this.employeeId,
    required this.employeeName,
    required this.period,
    required this.records,
    required this.totalWorkHours,
    required this.totalAdvances,
    required this.totalDeductions,
    required this.leaveDays,
    required this.netPay,
  });

  final String employeeId;
  final String employeeName;
  final ReportPeriod period;
  final List<AttendanceRecord> records;
  final double totalWorkHours;
  final double totalAdvances;
  final double totalDeductions;
  final int leaveDays;
  final double netPay;

  factory AttendanceReport.fromJson(Map<String, dynamic> json) {
    return AttendanceReport(
      employeeId: json['employee_id'] as String,
      employeeName: json['employee_name'] as String,
      period: ReportPeriod.fromJson(json['period'] as Map<String, dynamic>),
      records: (json['records'] as List<dynamic>)
          .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalWorkHours: (json['total_work_hours'] as num).toDouble(),
      totalAdvances: (json['total_advances'] as num).toDouble(),
      totalDeductions: (json['total_deductions'] as num).toDouble(),
      leaveDays: json['leave_days'] as int,
      netPay: (json['net_pay'] as num).toDouble(),
    );
  }
}

class ReportPeriod {
  ReportPeriod({
    required this.type,
    required this.startDate,
    required this.endDate,
  });

  final String type;
  final DateTime startDate;
  final DateTime endDate;

  factory ReportPeriod.fromJson(Map<String, dynamic> json) {
    return ReportPeriod(
      type: json['type'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
    );
  }
}

class AttendanceRecord {
  AttendanceRecord({
    required this.date,
    this.checkInTime,
    this.checkOutTime,
    this.workHours,
    this.advances,
    this.deductions,
    this.notes,
  });

  final DateTime date;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final double? workHours;
  final double? advances;
  final double? deductions;
  final String? notes;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      date: DateTime.parse(json['date'] as String),
      checkInTime: json['check_in_time'] != null
          ? DateTime.parse(json['check_in_time'] as String)
          : null,
      checkOutTime: json['check_out_time'] != null
          ? DateTime.parse(json['check_out_time'] as String)
          : null,
      workHours: json['work_hours'] != null
          ? (json['work_hours'] as num).toDouble()
          : null,
      advances: json['advances'] != null
          ? (json['advances'] as num).toDouble()
          : null,
      deductions: json['deductions'] != null
          ? (json['deductions'] as num).toDouble()
          : null,
      notes: json['notes'] as String?,
    );
  }
}
