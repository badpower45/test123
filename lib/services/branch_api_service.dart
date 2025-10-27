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

  static Future<Map<String, dynamic>> getBranchById(String branchId) async {
    try {
      final response = await http.get(Uri.parse('$branchesEndpoint/$branchId'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['branch'] as Map<String, dynamic>;
      } else {
        throw Exception('Failed to load branch: ${response.statusCode}');
      }
    } catch (error) {
      throw Exception('Failed to load branch: $error');
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
        body: json.encode({'employee_id': employeeId}),  // Changed from employeeId to employee_id
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

  static Future<Map<String, dynamic>> updateBranch({
    required String branchId,
    String? name,
    String? wifiBssid,
    double? latitude,
    double? longitude,
    int? geofenceRadius,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (wifiBssid != null) body['wifi_bssid'] = wifiBssid;
      if (latitude != null) body['latitude'] = latitude;
      if (longitude != null) body['longitude'] = longitude;
      if (geofenceRadius != null) body['geofence_radius'] = geofenceRadius;

      final endpoint = branchesEndpoint.endsWith('/')
          ? '${branchesEndpoint}$branchId'
          : '$branchesEndpoint/$branchId';

      final response = await http.put(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to update branch');
      }
    } catch (error) {
      throw Exception('Failed to update branch: $error');
    }
  }

  static Future<Map<String, dynamic>> deleteBranch({
    required String branchId,
  }) async {
    try {
      final endpoint = branchesEndpoint.endsWith('/')
          ? '${branchesEndpoint}$branchId'
          : '$branchesEndpoint/$branchId';

      final response = await http.delete(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else if (response.statusCode == 404) {
        throw Exception('الفرع غير موجود');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to delete branch');
      }
    } catch (error) {
      throw Exception('Failed to delete branch: $error');
    }
  }
}
