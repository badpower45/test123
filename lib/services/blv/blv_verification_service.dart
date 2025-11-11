import 'package:flutter/foundation.dart';
import 'environmental_data_collector.dart';

/// BLV Verification Result
class BLVVerificationResult {
  final double presenceScore;
  final double trustScore;
  final bool isValid;
  final String verificationMethod;
  final String status;
  final List<String> flags;
  final Map<String, dynamic> details;

  BLVVerificationResult({
    required this.presenceScore,
    required this.trustScore,
    required this.isValid,
    required this.verificationMethod,
    required this.status,
    required this.flags,
    required this.details,
  });

  Map<String, dynamic> toJson() {
    return {
      'presence_score': presenceScore,
      'trust_score': trustScore,
      'is_valid': isValid,
      'verification_method': verificationMethod,
      'status': status,
      'flags': flags,
      'details': details,
    };
  }
}

/// Client-Side BLV Verification Service
/// التحقق المحلي من الوجود قبل إرسال الـ Pulse للسيرفر
class BLVVerificationService {
  static final BLVVerificationService _instance = BLVVerificationService._internal();
  factory BLVVerificationService() => _instance;
  BLVVerificationService._internal();

  // Thresholds (synced from server config)
  double _minPresenceScore = 0.7;
  double _minTrustScore = 0.6;
  
  // Feature weights (synced from server)
  double _wifiWeight = 0.4;
  double _motionWeight = 0.2;
  double _soundWeight = 0.2;
  double _batteryWeight = 0.2;
  
  // Cached baseline data from server
  Map<String, dynamic>? _branchBaseline;
  
  /// Update configuration from server
  void updateConfig({
    double? minPresenceScore,
    double? minTrustScore,
    double? wifiWeight,
    double? motionWeight,
    double? soundWeight,
    double? batteryWeight,
  }) {
    if (minPresenceScore != null) _minPresenceScore = minPresenceScore;
    if (minTrustScore != null) _minTrustScore = minTrustScore;
    if (wifiWeight != null) _wifiWeight = wifiWeight;
    if (motionWeight != null) _motionWeight = motionWeight;
    if (soundWeight != null) _soundWeight = soundWeight;
    if (batteryWeight != null) _batteryWeight = batteryWeight;
    
    debugPrint('[BLV] Config updated: presence=$_minPresenceScore, trust=$_minTrustScore');
  }
  
  /// Update branch baseline from server
  void updateBaseline(Map<String, dynamic> baseline) {
    _branchBaseline = baseline;
    debugPrint('[BLV] Baseline updated for time slot: ${baseline['time_slot']}');
  }
  
  /// Calculate WiFi score
  double _calculateWifiScore(EnvironmentalData data) {
    if (_branchBaseline == null) return 0.5; // Default if no baseline
    
    final avgWifiCount = _branchBaseline!['avg_wifi_count'] ?? 5.0;
    final wifiCountStdDev = _branchBaseline!['wifi_count_std_dev'] ?? 2.0;
    final avgSignalStrength = _branchBaseline!['avg_signal_strength'] ?? -60.0;
    
    // Count similarity (within 2 standard deviations = good)
    final countDiff = (data.wifiCount - avgWifiCount).abs();
    final countScore = 1.0 - (countDiff / (2 * wifiCountStdDev)).clamp(0.0, 1.0);
    
    // Signal strength similarity
    final signalDiff = (data.wifiSignalStrength - avgSignalStrength).abs();
    final signalScore = 1.0 - (signalDiff / 30.0).clamp(0.0, 1.0); // ±30 dBm range
    
    // Combined score (70% count, 30% signal)
    return (countScore * 0.7 + signalScore * 0.3);
  }
  
  /// Calculate Motion score
  double _calculateMotionScore(EnvironmentalData data) {
    if (_branchBaseline == null) return 0.5;
    
    final avgAccelVariance = _branchBaseline!['avg_accel_variance'] ?? 0.3;
    final accelVarianceStdDev = _branchBaseline!['accel_variance_std_dev'] ?? 0.15;
    
    final diff = (data.accelVariance - avgAccelVariance).abs();
    final score = 1.0 - (diff / (2 * accelVarianceStdDev)).clamp(0.0, 1.0);
    
    return score;
  }
  
  /// Calculate Sound score
  double _calculateSoundScore(EnvironmentalData data) {
    if (_branchBaseline == null) return 0.5;
    
    final avgSoundLevel = _branchBaseline!['avg_sound_level'] ?? 0.5;
    final soundLevelStdDev = _branchBaseline!['sound_level_std_dev'] ?? 0.2;
    
    final diff = (data.soundLevel - avgSoundLevel).abs();
    final score = 1.0 - (diff / (2 * soundLevelStdDev)).clamp(0.0, 1.0);
    
    return score;
  }
  
  /// Calculate Battery score
  double _calculateBatteryScore(EnvironmentalData data) {
    if (_branchBaseline == null) return 0.5;
    
    final avgBatteryLevel = _branchBaseline!['avg_battery_level'] ?? 0.5;
    final chargingLikelihood = _branchBaseline!['charging_likelihood'] ?? 0.3;
    
    // Battery level similarity
    final levelDiff = (data.batteryLevel - avgBatteryLevel).abs();
    final levelScore = 1.0 - (levelDiff / 0.5).clamp(0.0, 1.0);
    
    // Charging status match
    final chargingScore = data.isCharging 
        ? chargingLikelihood 
        : (1.0 - chargingLikelihood);
    
    // Combined (60% level, 40% charging)
    return (levelScore * 0.6 + chargingScore * 0.4);
  }
  
  /// Calculate overall Presence Score
  double _calculatePresenceScore(EnvironmentalData data) {
    final wifiScore = _calculateWifiScore(data);
    final motionScore = _calculateMotionScore(data);
    final soundScore = _calculateSoundScore(data);
    final batteryScore = _calculateBatteryScore(data);
    
    final presenceScore = 
        wifiScore * _wifiWeight +
        motionScore * _motionWeight +
        soundScore * _soundWeight +
        batteryScore * _batteryWeight;
    
    debugPrint('[BLV] Scores - WiFi: ${wifiScore.toStringAsFixed(2)}, '
        'Motion: ${motionScore.toStringAsFixed(2)}, '
        'Sound: ${soundScore.toStringAsFixed(2)}, '
        'Battery: ${batteryScore.toStringAsFixed(2)} '
        '=> Presence: ${presenceScore.toStringAsFixed(2)}');
    
    return presenceScore;
  }
  
  /// Calculate Trust Score (fraud detection)
  Map<String, dynamic> _calculateTrustScore(EnvironmentalData data, double presenceScore) {
    final flags = <String>[];
    double trustScore = 1.0;
    
    // Flag 1: No Motion (accel variance too low)
    if (data.accelVariance < 0.05) {
      flags.add('NoMotion');
      trustScore -= 0.3;
    }
    
    // Flag 2: Passive Audio (sound level suspiciously constant)
    if (data.soundLevel < 0.1 || data.soundLevel > 0.9) {
      flags.add('PassiveAudio');
      trustScore -= 0.2;
    }
    
    // Flag 3: Anomalous WiFi (too different from baseline)
    if (_branchBaseline != null) {
      final avgWifiCount = _branchBaseline!['avg_wifi_count'] ?? 5.0;
      if ((data.wifiCount - avgWifiCount).abs() > 10) {
        flags.add('AnomalousWiFi');
        trustScore -= 0.25;
      }
    }
    
    // Flag 4: Battery Impossible (rapid changes)
    // TODO: Track battery history and detect impossible jumps
    
    // Flag 5: Low overall presence score
    if (presenceScore < _minPresenceScore - 0.2) {
      flags.add('LowPresenceScore');
      trustScore -= 0.2;
    }
    
    return {
      'score': trustScore.clamp(0.0, 1.0),
      'flags': flags,
    };
  }
  
  /// Verify presence using environmental data
  /// التحقق من الوجود باستخدام البيانات البيئية
  BLVVerificationResult verify(EnvironmentalData data) {
    try {
      // Calculate Presence Score
      final presenceScore = _calculatePresenceScore(data);
      
      // Calculate Trust Score
      final trustResult = _calculateTrustScore(data, presenceScore);
      final trustScore = trustResult['score'] as double;
      final flags = trustResult['flags'] as List<String>;
      
      // Determine if valid
      final isValid = presenceScore >= _minPresenceScore && 
                      trustScore >= _minTrustScore;
      
      // Determine status
      String status;
      if (isValid) {
        status = 'IN';
      } else if (presenceScore >= _minPresenceScore - 0.1) {
        status = 'SUSPICIOUS';
      } else {
        status = 'OUT';
      }
      
      return BLVVerificationResult(
        presenceScore: presenceScore,
        trustScore: trustScore,
        isValid: isValid,
        verificationMethod: 'BLV',
        status: status,
        flags: flags,
        details: {
          'wifi_score': _calculateWifiScore(data),
          'motion_score': _calculateMotionScore(data),
          'sound_score': _calculateSoundScore(data),
          'battery_score': _calculateBatteryScore(data),
          'has_baseline': _branchBaseline != null,
        },
      );
    } catch (e) {
      debugPrint('[BLV] Verification error: $e');
      
      // Return conservative result on error
      return BLVVerificationResult(
        presenceScore: 0.0,
        trustScore: 0.0,
        isValid: false,
        verificationMethod: 'BLV_Error',
        status: 'UNKNOWN',
        flags: ['VerificationError'],
        details: {'error': e.toString()},
      );
    }
  }
  
  /// Quick check if BLV is ready to use
  bool isReady() {
    return _branchBaseline != null;
  }
  
  /// Get current configuration
  Map<String, dynamic> getConfig() {
    return {
      'min_presence_score': _minPresenceScore,
      'min_trust_score': _minTrustScore,
      'wifi_weight': _wifiWeight,
      'motion_weight': _motionWeight,
      'sound_weight': _soundWeight,
      'battery_weight': _batteryWeight,
      'has_baseline': _branchBaseline != null,
    };
  }
}
