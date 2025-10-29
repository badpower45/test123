import 'employee_attendance_status.dart';

// Model for attendance summary data
class AttendanceSummary {
  final int present;
  final int absent;
  final int onLeave;
  final int checkedOut;

  AttendanceSummary({
    this.present = 0,
    this.absent = 0,
    this.onLeave = 0,
    this.checkedOut = 0,
  });

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    return AttendanceSummary(
      present: json['present'] ?? 0,
      absent: json['absent'] ?? 0,
      onLeave: json['on_leave'] ?? 0,
      checkedOut: json['checked_out'] ?? 0,
    );
  }

  int get total => present + absent + onLeave + checkedOut;

  Map<String, dynamic> toJson() {
    return {
      'present': present,
      'absent': absent,
      'on_leave': onLeave,
      'checked_out': checkedOut,
    };
  }

  @override
  String toString() {
    return 'AttendanceSummary(present: $present, absent: $absent, onLeave: $onLeave, checkedOut: $checkedOut)';
  }
}

// Model combining summary with employees list
class EmployeeStatusResult {
  final AttendanceSummary summary;
  final List<EmployeeAttendanceStatus> employees;

  EmployeeStatusResult({
    required this.summary,
    required this.employees,
  });

  factory EmployeeStatusResult.fromJson(Map<String, dynamic> json) {
    return EmployeeStatusResult(
      summary: AttendanceSummary.fromJson(json['summary'] ?? {}),
      employees: (json['employees'] as List<dynamic>?)
          ?.map((e) => EmployeeAttendanceStatus.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'summary': summary.toJson(),
      'employees': employees.map((e) => e.toJson()).toList(),
    };
  }

  @override
  String toString() {
    return 'EmployeeStatusResult(summary: $summary, employees: ${employees.length})';
  }
}