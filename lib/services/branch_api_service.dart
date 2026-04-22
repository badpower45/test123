import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';
import '../constants/api_endpoints.dart';

class BranchApiService {
  static bool get _useLegacyApi => apiBaseUrl.trim().isNotEmpty;

  static bool _isUsableBssid(String value) {
    final normalized = value.toUpperCase().replaceAll('-', ':').trim();
    if (normalized.isEmpty) return false;
    if (normalized == '02:00:00:00:00:00' || normalized == '00:00:00:00:00:00') {
      return false;
    }
    final bssidRegex = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$');
    return bssidRegex.hasMatch(normalized);
  }

  static String _normalizeBssid(String value) {
    return value.toUpperCase().replaceAll('-', ':').trim();
  }

  static List<String> _extractAllowedBssids(Map<String, dynamic> branch) {
    final values = <String>{};

    final arrayValue = branch['wifi_bssids_array'];
    if (arrayValue is List) {
      for (final item in arrayValue) {
        final text = _normalizeBssid(item.toString());
        if (_isUsableBssid(text)) values.add(text);
      }
    }

    final wifiBssid = branch['wifi_bssid']?.toString() ?? '';
    if (wifiBssid.trim().isNotEmpty) {
      for (final token in wifiBssid.split(',')) {
        final text = _normalizeBssid(token);
        if (_isUsableBssid(text)) values.add(text);
      }
    }

    final wifiBssidsText = branch['wifi_bssids']?.toString() ?? '';
    if (wifiBssidsText.trim().isNotEmpty) {
      for (final token in wifiBssidsText
          .replaceAll('[', '')
          .replaceAll(']', '')
          .replaceAll('"', '')
          .split(',')) {
        final text = _normalizeBssid(token);
        if (_isUsableBssid(text)) values.add(text);
      }
    }

    return values.toList(growable: false);
  }

  static Map<String, dynamic> _branchEnvelope(Map<String, dynamic> branch) {
    final allowedBssids = _extractAllowedBssids(branch);
    return {
      ...branch,
      'branch': branch,
      'allowedBssids': allowedBssids,
      'wifi_bssids_array': allowedBssids,
    };
  }

  static Future<List<Map<String, dynamic>>> getBranches() async {
    if (!_useLegacyApi) {
      try {
        final response = await SupabaseConfig.client
            .from('branches')
            .select('*')
            .order('name');

        return (response as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false);
      } catch (error) {
        throw Exception('Failed to load branches: $error');
      }
    }

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
    if (!_useLegacyApi) {
      try {
        final data = await SupabaseConfig.client
            .from('branches')
            .select('*')
            .eq('id', branchId)
            .maybeSingle();

        if (data == null) {
          throw Exception('Branch not found');
        }

        final branch = Map<String, dynamic>.from(data as Map);
        return _branchEnvelope(branch);
      } catch (error) {
        throw Exception('Failed to load branch: $error');
      }
    }

    try {
      final response = await http.get(Uri.parse('$branchesEndpoint/$branchId'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data.containsKey('branch') && data.containsKey('allowedBssids')) {
          final branch = Map<String, dynamic>.from(data['branch'] as Map);
          return {
            ...branch,
            'branch': branch,
            'allowedBssids': data['allowedBssids'] ?? [],
            'wifi_bssids_array': data['allowedBssids'] ?? [],
          };
        } else {
          final branch = Map<String, dynamic>.from(data as Map);
          return _branchEnvelope(branch);
        }
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
    if (!_useLegacyApi) {
      try {
        final payload = {
          'name': name,
          if (wifiBssid != null) 'wifi_bssid': wifiBssid,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          if (geofenceRadius != null) 'geofence_radius': geofenceRadius,
        };

        final inserted = await SupabaseConfig.client
            .from('branches')
            .insert(payload)
            .select()
            .single();

        return {'success': true, 'branch': inserted};
      } catch (error) {
        throw Exception('Failed to create branch: $error');
      }
    }

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
    if (!_useLegacyApi) {
      try {
        final branch = await SupabaseConfig.client
            .from('branches')
            .select('id, name')
            .eq('id', branchId)
            .maybeSingle();

        if (branch == null) {
          throw Exception('Branch not found');
        }

        await SupabaseConfig.client
            .from('employees')
            .update({
              'branch_id': branchId,
              'branch': branch['name'],
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', employeeId);

        return {
          'success': true,
          'branch_id': branchId,
          'employee_id': employeeId,
        };
      } catch (error) {
        throw Exception('Failed to assign manager: $error');
      }
    }

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
    if (!_useLegacyApi) {
      try {
        final branch = await SupabaseConfig.client
            .from('branches')
            .select('id, name')
            .eq('id', branchId)
            .maybeSingle();

        if (branch == null) {
          return const [];
        }

        final byBranchId = await SupabaseConfig.client
            .from('employees')
            .select('*')
            .eq('branch_id', branchId)
            .order('full_name');

        final employeesById = (byBranchId as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false);
        if (employeesById.isNotEmpty) {
          return employeesById;
        }

        final byBranchName = await SupabaseConfig.client
            .from('employees')
            .select('*')
            .eq('branch', branch['name'])
            .order('full_name');

        return (byBranchName as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false);
      } catch (error) {
        throw Exception('Failed to load branch employees: $error');
      }
    }

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
    if (!_useLegacyApi) {
      try {
        final body = <String, dynamic>{};
        if (name != null) body['name'] = name;
        if (wifiBssid != null) body['wifi_bssid'] = wifiBssid;
        if (latitude != null) body['latitude'] = latitude;
        if (longitude != null) body['longitude'] = longitude;
        if (geofenceRadius != null) body['geofence_radius'] = geofenceRadius;

        final updated = await SupabaseConfig.client
            .from('branches')
            .update(body)
            .eq('id', branchId)
            .select()
            .single();

        return {'success': true, 'branch': updated};
      } catch (error) {
        throw Exception('Failed to update branch: $error');
      }
    }

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
    if (!_useLegacyApi) {
      try {
        await SupabaseConfig.client.from('branches').delete().eq('id', branchId);
        return {'success': true};
      } catch (error) {
        throw Exception('Failed to delete branch: $error');
      }
    }

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
