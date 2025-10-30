class AbsenceNotificationDetails {
  final String id;
  final String employeeId;
  final String employeeName;
  final String absenceDate;
  final String status;
  final DateTime notifiedAt;
  final bool deductionApplied;
  final double? deductionAmount;

  AbsenceNotificationDetails({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.absenceDate,
    required this.status,
    required this.notifiedAt,
    required this.deductionApplied,
    this.deductionAmount,
  });

  factory AbsenceNotificationDetails.fromJson(Map<String, dynamic> json) {
    return AbsenceNotificationDetails(
      id: json['id'] as String,
      employeeId: json['employeeId'] as String,
      employeeName: json['employeeName'] as String,
      absenceDate: json['absenceDate'] as String,
      status: json['status'] as String,
      notifiedAt: DateTime.parse(json['notifiedAt'] as String),
      deductionApplied: json['deductionApplied'] as bool,
      deductionAmount: json['deductionAmount'] != null
          ? double.tryParse(json['deductionAmount'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'absenceDate': absenceDate,
      'status': status,
      'notifiedAt': notifiedAt.toIso8601String(),
      'deductionApplied': deductionApplied,
      'deductionAmount': deductionAmount,
    };
  }

  @override
  String toString() {
    return 'AbsenceNotificationDetails(id: $id, employeeName: $employeeName, absenceDate: $absenceDate, status: $status)';
  }
}