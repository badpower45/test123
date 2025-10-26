import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_endpoints.dart';

class BranchApiService {
  static Future<List<Map<String, dynamic>>> getBranches() async {
    try {
      final response = await http.get(Uri.parse(branchesEndpoint));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['branches'] ?? []);
      } else {
        throw Exception('Failed to load branches: ${response.statusCode}');
      }
    } catch (error) {
      throw Exception('Failed to load branches: $error');
    }
  }

  static Future<Map<String, dynamic>> createBranch({
    required String name,
    String? wifiBssid,
    double? latitude,
    double? longitude,
    int? geofenceRadius,
  }) async {
    try {
      final body = {
        'name': name,
        if (wifiBssid != null) 'wifi_bssid': wifiBssid,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (geofenceRadius != null) 'geofence_radius': geofenceRadius,
      };

      final response = await http.post(
        Uri.parse(branchesEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to create branch');
      }
    } catch (error) {
      throw Exception('Failed to create branch: $error');
    }
  }

  static Future<Map<String, dynamic>> assignManager({
    required String branchId,
    required String employeeId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(branchAssignManagerEndpoint.replaceFirst(':branchId', branchId)),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'employee_id': employeeId}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to assign manager');
      }
    } catch (error) {
      throw Exception('Failed to assign manager: $error');
    }
  }

  static Future<List<Map<String, dynamic>>> getBranchEmployees(String branchId) async {
    try {
      final response = await http.get(
        Uri.parse(branchEmployeesEndpoint.replaceFirst(':branchId', branchId)),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['employees'] ?? []);
      } else {
        throw Exception('Failed to load branch employees: ${response.statusCode}');
      }
    } catch (error) {
      throw Exception('Failed to load branch employees: $error');
    }
  }
}