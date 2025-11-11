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

  String _baseUrl = 'http://localhost:5000/api';
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
    try {
      final url = Uri.parse('$_baseUrl/baselines/$branchId');
      
      debugPrint('[BLV API] Fetching baseline for branch: $branchId');
      
      final response = await http.get(url, headers: _headers);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true && data['baselines'] != null) {
          final baselines = data['baselines'] as List;
          
          // Get current time slot
          final now = DateTime.now();
          final timeSlot = _getTimeSlot(now);
          
          // Find baseline for current time slot
          final baseline = baselines.firstWhere(
            (b) => b['time_slot'] == timeSlot,
            orElse: () => baselines.isNotEmpty ? baselines[0] : null,
          );
          
          if (baseline != null) {
            // Cache baseline locally
            await _cacheBaseline(branchId, baseline);
            
            debugPrint('[BLV API] Baseline fetched successfully for time slot: $timeSlot');
            return baseline;
          }
        }
      } else {
        debugPrint('[BLV API] Failed to fetch baseline: ${response.statusCode}');
      }
      
      // Try to load from cache
      return await _loadCachedBaseline(branchId);
    } catch (e) {
      debugPrint('[BLV API] Error fetching baseline: $e');
      
      // Fallback to cached data
      return await _loadCachedBaseline(branchId);
    }
  }
  
  /// Request manual baseline calculation
  Future<bool> requestBaselineCalculation(String branchId, {int daysBack = 14}) async {
    try {
      final url = Uri.parse('$_baseUrl/baselines/calculate');
      
      final body = json.encode({
        'branchId': branchId,
        'daysBack': daysBack,
      });
      
      debugPrint('[BLV API] Requesting baseline calculation for branch: $branchId');
      
      final response = await http.post(
        url,
        headers: _headers,
        body: body,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('[BLV API] Baseline calculation requested: ${data['message']}');
        return data['success'] == true;
      }
      
      return false;
    } catch (e) {
      debugPrint('[BLV API] Error requesting baseline calculation: $e');
      return false;
    }
  }
  
  /// Fetch employee flags
  Future<List<Map<String, dynamic>>> fetchEmployeeFlags(String employeeId, {bool includeResolved = false}) async {
    try {
      final url = Uri.parse('$_baseUrl/flags/employee/$employeeId?includeResolved=$includeResolved');
      
      final response = await http.get(url, headers: _headers);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true && data['flags'] != null) {
          return List<Map<String, dynamic>>.from(data['flags']);
        }
      }
      
      return [];
    } catch (e) {
      debugPrint('[BLV API] Error fetching employee flags: $e');
      return [];
    }
  }
  
  /// Fetch all flags (for managers)
  Future<List<Map<String, dynamic>>> fetchAllFlags({
    String? branchId,
    String? severity,
  }) async {
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
  }
  
  /// Resolve a flag
  Future<bool> resolveFlag(String flagId, String managerId, {String? resolution}) async {
    try {
      final url = Uri.parse('$_baseUrl/flags/$flagId/resolve');
      
      final body = json.encode({
        'resolvedBy': managerId,
        'resolution': resolution ?? 'Reviewed and approved',
      });
      
      final response = await http.post(
        url,
        headers: _headers,
        body: body,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true;
      }
      
      return false;
    } catch (e) {
      debugPrint('[BLV API] Error resolving flag: $e');
      return false;
    }
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
    try {
      final url = Uri.parse('$_baseUrl/overrides');
      
      final body = json.encode({
        'pulseId': pulseId,
        'employeeId': employeeId,
        'managerId': managerId,
        'reason': reason,
        'newStatus': newStatus ?? 'APPROVED',
        'newPresenceScore': newPresenceScore ?? 1.0,
      });
      
      final response = await http.post(
        url,
        headers: _headers,
        body: body,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('[BLV API] Override created: ${data['message']}');
        return data['success'] == true;
      }
      
      return false;
    } catch (e) {
      debugPrint('[BLV API] Error creating override: $e');
      return false;
    }
  }
  
  /// Get time slot for baseline matching
  String _getTimeSlot(DateTime time) {
    final hour = time.hour;
    
    if (hour >= 6 && hour < 12) {
      return 'morning';
    } else if (hour >= 12 && hour < 18) {
      return 'afternoon';
    } else if (hour >= 18 && hour < 22) {
      return 'evening';
    } else {
      return 'night';
    }
  }
  
  /// Cache baseline locally for offline use
  Future<void> _cacheBaseline(String branchId, Map<String, dynamic> baseline) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'blv_baseline_$branchId';
      await prefs.setString(key, json.encode(baseline));
      
      // Store timestamp
      await prefs.setInt('${key}_timestamp', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[BLV API] Error caching baseline: $e');
    }
  }
  
  /// Load cached baseline
  Future<Map<String, dynamic>?> _loadCachedBaseline(String branchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'blv_baseline_$branchId';
      final baselineStr = prefs.getString(key);
      final timestamp = prefs.getInt('${key}_timestamp');
      
      if (baselineStr != null && timestamp != null) {
        // Check if cache is not too old (24 hours)
        final age = DateTime.now().millisecondsSinceEpoch - timestamp;
        if (age < 24 * 60 * 60 * 1000) {
          debugPrint('[BLV API] Using cached baseline (age: ${(age / 3600000).toStringAsFixed(1)} hours)');
          return json.decode(baselineStr);
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('[BLV API] Error loading cached baseline: $e');
      return null;
    }
  }
}
