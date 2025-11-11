import 'package:flutter/foundation.dart';
import 'environmental_data_collector.dart';
import 'blv_verification_service.dart';
import 'blv_api_client.dart';

/// BLV Manager - Main coordinator for BLV system
/// المدير الرئيسي لنظام BLV
class BLVManager {
  static final BLVManager _instance = BLVManager._internal();
  factory BLVManager() => _instance;
  BLVManager._internal();

  final _collector = EnvironmentalDataCollector();
  final _verificationService = BLVVerificationService();
  final _apiClient = BLVApiClient();
  
  bool _isInitialized = false;
  bool _isEnabled = true;
  String? _currentBranchId;
  
  /// Initialize BLV system
  Future<void> initialize({
    required String baseUrl,
    String? authToken,
    String? branchId,
  }) async {
    if (_isInitialized) {
      debugPrint('[BLV Manager] Already initialized');
      return;
    }
    
    try {
      debugPrint('[BLV Manager] Initializing BLV system...');
      
      // Initialize API client
      _apiClient.initialize(baseUrl: baseUrl, authToken: authToken);
      
      // Initialize environmental data collector
      await _collector.initialize();
      
      // Load baseline if branch ID provided
      if (branchId != null) {
        await loadBaseline(branchId);
      }
      
      _isInitialized = true;
      debugPrint('[BLV Manager] ✅ BLV system initialized successfully');
    } catch (e) {
      debugPrint('[BLV Manager] ❌ Error initializing BLV system: $e');
      _isInitialized = false;
    }
  }
  
  /// Load baseline for a specific branch
  Future<bool> loadBaseline(String branchId) async {
    try {
      debugPrint('[BLV Manager] Loading baseline for branch: $branchId');
      
      final baseline = await _apiClient.fetchBranchBaseline(branchId);
      
      if (baseline != null) {
        _verificationService.updateBaseline(baseline);
        _currentBranchId = branchId;
        
        debugPrint('[BLV Manager] ✅ Baseline loaded successfully');
        return true;
      } else {
        debugPrint('[BLV Manager] ⚠️ No baseline available for branch');
        return false;
      }
    } catch (e) {
      debugPrint('[BLV Manager] ❌ Error loading baseline: $e');
      return false;
    }
  }
  
  /// Request baseline calculation for current branch
  Future<bool> requestBaselineCalculation({int daysBack = 14}) async {
    if (_currentBranchId == null) {
      debugPrint('[BLV Manager] No branch ID set');
      return false;
    }
    
    return await _apiClient.requestBaselineCalculation(_currentBranchId!, daysBack: daysBack);
  }
  
  /// Update configuration from server
  void updateConfig({
    double? minPresenceScore,
    double? minTrustScore,
    double? wifiWeight,
    double? motionWeight,
    double? soundWeight,
    double? batteryWeight,
  }) {
    _verificationService.updateConfig(
      minPresenceScore: minPresenceScore,
      minTrustScore: minTrustScore,
      wifiWeight: wifiWeight,
      motionWeight: motionWeight,
      soundWeight: soundWeight,
      batteryWeight: batteryWeight,
    );
  }
  
  /// Collect environmental data and verify presence
  /// جمع البيانات والتحقق من الوجود
  Future<Map<String, dynamic>> verifyPresence() async {
    if (!_isInitialized) {
      throw Exception('BLV Manager not initialized. Call initialize() first.');
    }
    
    if (!_isEnabled) {
      return {
        'success': false,
        'error': 'BLV system is disabled',
      };
    }
    
    try {
      // Collect environmental data
      final environmentalData = await _collector.collectData();
      
      // Verify using local BLV service
      final verificationResult = _verificationService.verify(environmentalData);
      
      // Return combined data for server
      return {
        'success': true,
        'environmental_data': environmentalData.toJson(),
        'verification_result': verificationResult.toJson(),
        'is_valid': verificationResult.isValid,
        'presence_score': verificationResult.presenceScore,
        'trust_score': verificationResult.trustScore,
        'flags': verificationResult.flags,
      };
    } catch (e) {
      debugPrint('[BLV Manager] Error during verification: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
  
  /// Get environmental data only (without verification)
  Future<EnvironmentalData?> collectEnvironmentalData() async {
    if (!_isInitialized || !_isEnabled) return null;
    
    try {
      return await _collector.collectData();
    } catch (e) {
      debugPrint('[BLV Manager] Error collecting data: $e');
      return null;
    }
  }
  
  /// Get latest cached environmental data
  EnvironmentalData? getLatestData() {
    return _collector.getLatestData();
  }
  
  /// Check if BLV is ready to use
  bool isReady() {
    return _isInitialized && 
           _isEnabled && 
           _collector.isReady() && 
           _verificationService.isReady();
  }
  
  /// Enable/disable BLV system
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    debugPrint('[BLV Manager] BLV system ${enabled ? 'enabled' : 'disabled'}');
  }
  
  /// Check if BLV is enabled
  bool isEnabled() => _isEnabled;
  
  /// Get current status
  Map<String, dynamic> getStatus() {
    return {
      'initialized': _isInitialized,
      'enabled': _isEnabled,
      'collector_ready': _collector.isReady(),
      'verification_ready': _verificationService.isReady(),
      'overall_ready': isReady(),
      'current_branch_id': _currentBranchId,
      'config': _verificationService.getConfig(),
    };
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    await _collector.dispose();
    _isInitialized = false;
    debugPrint('[BLV Manager] Disposed');
  }
  
  // ============================================================================
  // Manager Dashboard API Methods
  // ============================================================================
  
  /// Fetch employee flags (for employee view)
  Future<List<Map<String, dynamic>>> fetchEmployeeFlags(String employeeId) async {
    return await _apiClient.fetchEmployeeFlags(employeeId);
  }
  
  /// Fetch all flags (for manager dashboard)
  Future<List<Map<String, dynamic>>> fetchAllFlags({
    String? branchId,
    String? severity,
  }) async {
    return await _apiClient.fetchAllFlags(branchId: branchId, severity: severity);
  }
  
  /// Resolve a flag (manager action)
  Future<bool> resolveFlag(String flagId, String managerId, {String? resolution}) async {
    return await _apiClient.resolveFlag(flagId, managerId, resolution: resolution);
  }
  
  /// Create manual override (manager action)
  Future<bool> createOverride({
    required String pulseId,
    required String employeeId,
    required String managerId,
    required String reason,
    String? newStatus,
    double? newPresenceScore,
  }) async {
    return await _apiClient.createOverride(
      pulseId: pulseId,
      employeeId: employeeId,
      managerId: managerId,
      reason: reason,
      newStatus: newStatus,
      newPresenceScore: newPresenceScore,
    );
  }
  
  /// Set auth token (after login)
  void setAuthToken(String token) {
    _apiClient.setAuthToken(token);
  }
}
