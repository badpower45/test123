import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// BLV API Client
/// التواصل مع الـ Backend للحصول على Baselines والإعدادات
class BLVApiClient {
  static final BLVApiClient _instance = BLVApiClient._internal();
  factory BLVApiClient() => _instance;
  BLVApiClient._internal();

  String _baseUrl = ''; // Disabled - using Supabase only
  String? _authToken;
  
  /// Initialize with base URL and auth token
  void initialize({required String baseUrl, String? authToken}) {
    _baseUrl = baseUrl.endsWith('/api') ? baseUrl : '$baseUrl/api';
    _authToken = authToken;
    debugPrint('[BLV API] Initialized with base URL: $_baseUrl');
  }
  
  /// Set authentication token
  void setAuthToken(String token) {
    _authToken = token;
  }
  
  /// Get headers for API requests
  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
    };
    
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    
    return headers;
  }
  
  /// Fetch branch baseline data
  Future<Map<String, dynamic>?> fetchBranchBaseline(String branchId) async {
    // Disabled - using Supabase only
    debugPrint('[BLV API] Baseline fetching disabled - using Supabase');
    return null;
  }
  
  /// Request manual baseline calculation
  Future<bool> requestBaselineCalculation(String branchId, {int daysBack = 14}) async {
    // Disabled - using Supabase only
    debugPrint('[BLV API] Baseline calculation disabled - using Supabase');
    return false;
  }
  
  /// Fetch employee flags
  Future<List<Map<String, dynamic>>> fetchEmployeeFlags(String employeeId, {bool includeResolved = false}) async {
    // Disabled - using Supabase only
    debugPrint('[BLV API] Employee flags fetching disabled - using Supabase');
    return [];
  }
  
  /// Fetch all flags (for managers)
  Future<List<Map<String, dynamic>>> fetchAllFlags({
    String? branchId,
    String? severity,
  }) async {
    // Disabled - using Supabase only
    debugPrint('[BLV API] All flags fetching disabled - using Supabase');
    return [];
    
    /* DISABLED OLD CODE
    try {
      var url = '$_baseUrl/flags?';
      if (branchId != null) url += 'branchId=$branchId&';
      if (severity != null) url += 'severity=$severity&';
      
      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true && data['flags'] != null) {
          return List<Map<String, dynamic>>.from(data['flags']);
        }
      }
      
      return [];
    } catch (e) {
      debugPrint('[BLV API] Error fetching all flags: $e');
      return [];
    }
    */
  }
  
  /// Resolve a flag
  Future<bool> resolveFlag(String flagId, String managerId, {String? resolution}) async {
    // Disabled - using Supabase only
    debugPrint('[BLV API] Flag resolution disabled - using Supabase');
    return false;
  }
  
  /// Create manual override
  Future<bool> createOverride({
    required String pulseId,
    required String employeeId,
    required String managerId,
    required String reason,
    String? newStatus,
    double? newPresenceScore,
  }) async {
    // Disabled - using Supabase only
    debugPrint('[BLV API] Override creation disabled - using Supabase');
    return false;
  }
}
