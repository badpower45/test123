/// BLV Validation Event Model
/// Represents a validation event from either pulses or blv_validation_logs tables
class BLVValidationEvent {
  BLVValidationEvent({
    required this.id,
    required this.employeeId,
    required this.timestamp,
    required this.validationType,
    required this.status,
    this.totalScore,
    this.presenceScore,
    this.trustScore,
    this.isApproved,
    this.wifiScore,
    this.gpsScore,
    this.cellScore,
    this.soundScore,
    this.motionScore,
    this.bluetoothScore,
    this.lightScore,
    this.batteryScore,
    this.verificationMethod,
    this.branchId,
  });

  final String id;
  final String employeeId;
  final DateTime timestamp;
  final String validationType; // 'check-in', 'pulse', 'check-out'
  final String status; // 'IN', 'OUT', 'SUSPECT', 'REVIEW_REQUIRED'

  // BLV Scores
  final int? totalScore; // 0-100
  final double? presenceScore; // 0.0-1.0
  final double? trustScore; // 0.0-1.0
  final bool? isApproved;

  // Individual component scores
  final int? wifiScore;
  final int? gpsScore;
  final int? cellScore;
  final int? soundScore;
  final int? motionScore;
  final int? bluetoothScore;
  final int? lightScore;
  final int? batteryScore;

  final String? verificationMethod; // 'BLV', 'WiFi', 'Manual'
  final String? branchId;

  /// Create from pulses table data
  factory BLVValidationEvent.fromPulse(Map<String, dynamic> json) {
    return BLVValidationEvent(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      validationType: 'pulse',
      status: (json['status'] ?? 'IN') as String,
      presenceScore: json['presence_score'] != null
          ? (json['presence_score'] as num).toDouble()
          : null,
      trustScore: json['trust_score'] != null
          ? (json['trust_score'] as num).toDouble()
          : null,
      verificationMethod: json['verification_method'] as String?,
      branchId: json['branch_id'] as String?,
    );
  }

  /// Create from blv_validation_logs table data
  factory BLVValidationEvent.fromValidationLog(Map<String, dynamic> json) {
    return BLVValidationEvent(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      timestamp: DateTime.parse(json['created_at'] as String),
      validationType: (json['validation_type'] ?? 'check-in') as String,
      status: json['is_approved'] == true ? 'IN' : 'REJECTED',
      totalScore: json['total_score'] as int?,
      isApproved: json['is_approved'] as bool?,
      wifiScore: json['wifi_score'] as int?,
      gpsScore: json['gps_score'] as int?,
      cellScore: json['cell_score'] as int?,
      soundScore: json['sound_score'] as int?,
      motionScore: json['motion_score'] as int?,
      bluetoothScore: json['bluetooth_score'] as int?,
      lightScore: json['light_score'] as int?,
      batteryScore: json['battery_score'] as int?,
      branchId: json['branch_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employee_id': employeeId,
        'timestamp': timestamp.toIso8601String(),
        'validation_type': validationType,
        'status': status,
        'total_score': totalScore,
        'presence_score': presenceScore,
        'trust_score': trustScore,
        'is_approved': isApproved,
        'wifi_score': wifiScore,
        'gps_score': gpsScore,
        'cell_score': cellScore,
        'sound_score': soundScore,
        'motion_score': motionScore,
        'bluetooth_score': bluetoothScore,
        'light_score': lightScore,
        'battery_score': batteryScore,
        'verification_method': verificationMethod,
        'branch_id': branchId,
      };

  /// Get display-friendly validation type
  String get displayType {
    switch (validationType.toLowerCase()) {
      case 'check-in':
        return 'Check-in';
      case 'check-out':
        return 'Check-out';
      case 'pulse':
        return 'Pulse';
      default:
        return validationType;
    }
  }

  /// Get display-friendly status with icon
  String get displayStatus {
    switch (status.toUpperCase()) {
      case 'IN':
        return '✅ Verified';
      case 'OUT':
        return '🚫 Out of Range';
      case 'SUSPECT':
        return '⚠️ Suspicious';
      case 'REVIEW_REQUIRED':
        return '🔍 Review Required';
      case 'REJECTED':
        return '❌ Rejected';
      default:
        return status;
    }
  }

  /// Get score percentage (0-100)
  int? get scorePercentage {
    if (totalScore != null) return totalScore;
    if (presenceScore != null) return (presenceScore! * 100).round();
    if (trustScore != null) return (trustScore! * 100).round();
    return null;
  }

  /// Get status color
  String get statusColor {
    if (isApproved == false || status == 'REJECTED') return 'red';
    if (status == 'OUT' || status == 'SUSPECT') return 'orange';
    if (status == 'REVIEW_REQUIRED') return 'yellow';
    return 'green';
  }
}
