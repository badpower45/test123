import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../constants/restaurant_config.dart';
import '../../models/attendance_request.dart';
import '../../models/employee.dart';
import '../../services/attendance_api_service.dart';
import '../../services/auth_service.dart';
import '../../services/branch_api_service.dart';
import '../../services/geofence_service.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../services/requests_api_service.dart';
import '../../services/supabase_attendance_service.dart';
import '../../services/sync_service.dart';
import '../../services/wifi_service.dart';
import '../../services/offline_data_service.dart';
import '../../database/offline_database.dart';
import '../../theme/app_colors.dart';
import 'manager_send_requests_page.dart';
import 'manager_employees_page.dart';

class ManagerHomePage extends StatefulWidget {
  final String managerId;

  const ManagerHomePage({super.key, required this.managerId});

  @override
  State<ManagerHomePage> createState() => _ManagerHomePageState();
}

class _ManagerHomePageState extends State<ManagerHomePage> {
  bool _isCheckedIn = false;
  DateTime? _checkInTime;
  String _elapsedTime = '00:00:00';
  Timer? _timer;
  bool _isLoading = false;
  int _pendingCount = 0;
  String? _branchId;
  Map<String, dynamic>? _branchData;
  List<String> _allowedBssids = [];
  
  final _offlineService = OfflineDataService();

  @override
  void initState() {
    super.initState();
    _loadBranchData(); // Load branch data first
    _checkCurrentStatus();
    _loadPendingCount();
    // Refresh pending count every minute
    Timer.periodic(const Duration(minutes: 1), (_) => _loadPendingCount());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadPendingCount() async {
    // Skip SQLite on Web (returns 0)
    final db = OfflineDatabase.instance;
    final count = await db.getPendingCount();
    if (mounted) {
      setState(() {
        _pendingCount = count;
      });
    }
  }

  /// Load branch data from cache or Supabase with auto-refresh
  Future<void> _loadBranchData() async {
    try {
      // On Web, use Hive-based OfflineDataService
      if (kIsWeb) {
        await _loadBranchDataForWeb();
        return;
      }
      
      // On Mobile/Desktop, use SQLite-based OfflineDatabase
      final db = OfflineDatabase.instance;
      
      // Check if we need to refresh (older than 24 hours)
      final needsRefresh = await db.needsCacheRefresh(widget.managerId);
      final cached = await db.getCachedBranchData(widget.managerId);
      
      // Use cached data immediately if available (for fast startup)
      if (cached != null && !needsRefresh) {
        setState(() {
          _branchData = cached;
          // Parse multiple BSSIDs
          final bssidsArray = cached['wifi_bssids_array'] as List<dynamic>?;
          if (bssidsArray != null && bssidsArray.isNotEmpty) {
            _allowedBssids = bssidsArray.map((e) => e.toString()).toList();
          }
        });
        print('✅ [Manager] Using cached branch data: ${cached['branch_name']} (${_allowedBssids.length} WiFi networks)');
        return;
      }
      
      // Need to fetch from Supabase (first time or refresh needed)
      final syncService = SyncService.instance;
      final hasInternet = await syncService.hasInternet();
      
      if (!hasInternet) {
        if (cached != null) {
          // Use stale cache if no internet
          setState(() {
            _branchData = cached;
            final bssidsArray = cached['wifi_bssids_array'] as List<dynamic>?;
            if (bssidsArray != null && bssidsArray.isNotEmpty) {
              _allowedBssids = bssidsArray.map((e) => e.toString()).toList();
            }
          });
          print('⚠️ [Manager] Using stale cache (no internet): ${cached['branch_name']}');
        } else {
          print('⚠️ [Manager] No internet and no cached branch data');
        }
        return;
      }
      
      // Get employee data to find branch name
      final employeeData = await SupabaseAttendanceService.getEmployeeStatus(widget.managerId);
      final branchName = employeeData['employee']?['branch'] ?? 
                        employeeData['employee']?['branch_name'];
      
      if (branchName == null || branchName.toString().isEmpty) {
        print('⚠️ [Manager] Manager has no branch assigned');
        print('⚠️ Employee data: $employeeData');
        return;
      }
      
      print('📍 [Manager] Branch name: $branchName');
      
      // Fetch branch data from Supabase by name
      final branchList = await BranchApiService.getBranches();
      final branchData = branchList.firstWhere(
        (b) => b['name'] == branchName,
        orElse: () => <String, dynamic>{},
      );
      
      if (branchData.isEmpty) {
        print('❌ [Manager] Branch not found: $branchName');
        return;
      }
      
      print('✅ [Manager] Found branch: ${branchData['name']} (${branchData['id']})');
      
      // Parse WiFi BSSIDs (can be comma-separated or array)
      List<String> wifiBssids = [];
      if (branchData['wifi_bssid'] != null && branchData['wifi_bssid'].toString().isNotEmpty) {
        wifiBssids = branchData['wifi_bssid']
            .toString()
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      
      // Parse location
      double? latitude;
      double? longitude;
      if (branchData['location'] != null) {
        try {
          final location = branchData['location'];
          if (location is Map) {
            latitude = (location['latitude'] ?? location['lat'])?.toDouble();
            longitude = (location['longitude'] ?? location['lng'] ?? location['long'])?.toDouble();
          } else if (location is String) {
            final decoded = jsonDecode(location);
            latitude = (decoded['latitude'] ?? decoded['lat'])?.toDouble();
            longitude = (decoded['longitude'] ?? decoded['lng'] ?? decoded['long'])?.toDouble();
          }
        } catch (e) {
          print('⚠️ Error parsing location: $e');
        }
      }
      
      final geofenceRadius = (branchData['geofence_radius'] ?? 
                             branchData['geofenceRadius'] ?? 
                             100.0).toDouble();
      
      // Cache it locally for future use
      await db.cacheBranchData(
        employeeId: widget.managerId,
        branchId: branchData['id'],
        branchName: branchData['name'],
        wifiBssids: wifiBssids,
        latitude: latitude,
        longitude: longitude,
        geofenceRadius: geofenceRadius,
        dataVersion: branchData['updated_at'] != null 
            ? DateTime.parse(branchData['updated_at']).millisecondsSinceEpoch ~/ 1000
            : 1,
      );
      
      setState(() {
        _branchData = branchData;
        _branchId = branchData['id'];
        _allowedBssids = wifiBssids;
      });
      
      print('✅ [Manager] Fetched and cached branch data: ${branchData['name']} (${wifiBssids.length} WiFi networks)');
    } catch (e) {
      print('❌ [Manager] Error loading branch data: $e');
    }
  }

  /// Load branch data for Web platform (using Hive)
  Future<void> _loadBranchDataForWeb() async {
    try {
      // Check cached data from Hive (employee-specific)
      final cached = await _offlineService.getCachedBranchData(employeeId: widget.managerId);
      
      if (cached != null) {
        setState(() {
          _branchData = cached;
          _branchId = cached['id'];
          // Parse BSSIDs from cached data
          final bssid = cached['bssid'];
          if (bssid != null && bssid.toString().isNotEmpty) {
            _allowedBssids = [bssid.toString()];
          }
        });
        print('✅ [Manager] Using cached branch data from Hive: ${cached['name']}');
        return;
      }
      
      // Need to fetch from Supabase
      final syncService = SyncService.instance;
      final hasInternet = await syncService.hasInternet();
      
      if (!hasInternet) {
        print('⚠️ [Manager] No internet and no cached branch data on Web');
        return;
      }
      
      // Get manager data to find branch name
      final managerData = await SupabaseAttendanceService.getEmployeeStatus(widget.managerId);
      final branchName = managerData['employee']?['branch'];
      
      if (branchName == null) {
        print('⚠️ [Manager] Employee has no branch assigned');
        return;
      }
      
      // Download and cache branch data (with manager ID)
      final branchData = await _offlineService.downloadBranchData(
        branchName,
        employeeId: widget.managerId,
      );
      
      if (branchData != null) {
        setState(() {
          _branchData = branchData;
          _branchId = branchData['id'];
          final bssid = branchData['bssid'];
          if (bssid != null && bssid.toString().isNotEmpty) {
            _allowedBssids = [bssid.toString()];
          }
        });
        print('✅ [Manager] Downloaded branch data on Web: ${branchData['name']}');
      }
    } catch (e) {
      print('❌ [Manager] Error loading branch data on Web: $e');
    }
  }

  Future<void> _checkCurrentStatus() async {
    try {
      final status = await AttendanceApiService.fetchEmployeeStatus(widget.managerId);
      final branchId = status['employee']?['branchId'];
      
      setState(() {
        _isCheckedIn = status['attendance']?['status'] == 'active';
        _checkInTime = status['attendance']?['checkInTime'] != null
            ? DateTime.parse(status['attendance']['checkInTime'])
            : null;
        _branchId = branchId;
      });
      
      // Fetch branch data if available
      if (branchId != null && branchId.toString().isNotEmpty) {
        try {
          final branchResponse = await BranchApiService.getBranchById(branchId.toString());
          setState(() {
            _branchData = branchResponse['branch'];
            _allowedBssids = (branchResponse['allowedBssids'] as List<dynamic>?)
                ?.map((e) => e.toString().toUpperCase())
                .toList() ?? [];
          });
        } catch (e) {
          print('Failed to load branch data: $e');
        }
      }
      
      if (_isCheckedIn && _checkInTime != null) {
        _startTimer();
      }
    } catch (e) {
      // handle error
    }
  }

  Future<void> reloadData() async {
    await _checkCurrentStatus();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_checkInTime != null) {
        final duration = DateTime.now().difference(_checkInTime!);
        setState(() {
          _elapsedTime = _formatDuration(duration);
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  Future<void> _handleCheckIn() async {
    setState(() => _isLoading = true);

    try {
      print('🚀 Manager check-in started...');
      
      // استخدام الخدمات المحسّنة مع التنفيذ المتوازي
      final locationService = LocationService();
      
      final position = await locationService.tryGetPosition();
      String? wifiBSSID;
      try {
        wifiBSSID = await WiFiService.getCurrentWifiBssidValidated();
      } catch (e) {
        print('⚠️ WiFi error: $e');
      }

      print('📍 Position: ${position?.latitude}, ${position?.longitude}');
      print('📶 WiFi BSSID: $wifiBSSID');

      // Validate: WiFi OR Location (at least one must be valid)
      bool isWifiValid = false;
      bool isLocationValid = false;

      // 1️⃣ Check WiFi
      if (_allowedBssids.isNotEmpty && wifiBSSID != null && wifiBSSID.isNotEmpty) {
        final normalizedCurrent = wifiBSSID.toUpperCase().trim();
        isWifiValid = _allowedBssids.any((allowed) {
          return allowed.toUpperCase().trim() == normalizedCurrent;
        });
        print('✅ WiFi check: ${isWifiValid ? "VALID" : "INVALID"} - $normalizedCurrent');
      } else {
        print('⚠️ WiFi check: SKIPPED (no WiFi or no allowed BSSIDs)');
      }

      // 2️⃣ Check Location
      if (RestaurantConfig.enforceLocation && _branchData != null && position != null) {
        final branchLat = _branchData!['latitude'] as double?;
        final branchLng = _branchData!['longitude'] as double?;
        final branchRadius = (_branchData!['geofence_radius'] as int?) ?? 200;
        
        if (branchLat != null && branchLng != null) {
          final distance = Geolocator.distanceBetween(
            branchLat,
            branchLng,
            position.latitude,
            position.longitude,
          );
          
          final accuracyMargin = position.accuracy > 100 ? position.accuracy * 1.5 : position.accuracy * 1.0;
          final effectiveRadius = branchRadius + accuracyMargin;
          
          isLocationValid = distance <= effectiveRadius;
          print('✅ Location check: ${isLocationValid ? "VALID" : "INVALID"} - ${distance.toStringAsFixed(0)}m from ${effectiveRadius.toStringAsFixed(0)}m');
        } else {
          print('⚠️ Location check: SKIPPED (no branch coordinates)');
        }
      } else {
        print('⚠️ Location check: SKIPPED (disabled or no position)');
      }

      // 3️⃣ Require at least ONE to be valid
      if (!isWifiValid && !isLocationValid) {
        throw Exception(
          'يجب أن تكون متصلاً بشبكة الواي فاي الخاصة بالفرع أو متواجداً في الموقع الصحيح.\n'
          'تأكد من الاتصال بالـ WiFi الصحيح أو التواجد داخل الفرع.'
        );
      }

      print('✅ Validation PASSED - WiFi: $isWifiValid, Location: $isLocationValid');

      final latitude = position?.latitude ?? 0.0;
      final longitude = position?.longitude ?? 0.0;

      final response = await SupabaseAttendanceService.checkIn(
        employeeId: widget.managerId,
        latitude: latitude,
        longitude: longitude,
      );

      if (response == null) {
        throw Exception('فشل تسجيل الحضور');
      }

      setState(() {
        _isCheckedIn = true;
        _checkInTime = DateTime.now();
        _isLoading = false;
      });

      _startTimer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تم تسجيل الحضور بنجاح'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: ${e.toString()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleCheckOut() async {
    setState(() => _isLoading = true);

    try {
      print('🚪 Manager check-out started...');
      
      // استخدام الخدمات المحسّنة مع التنفيذ المتوازي
      final locationService = LocationService();
      
      final position = await locationService.tryGetPosition();
      String? wifiBSSID;
      try {
        wifiBSSID = await WiFiService.getCurrentWifiBssidValidated();
      } catch (e) {
        print('⚠️ WiFi error: $e');
      }

      print('📍 Position: ${position?.latitude}, ${position?.longitude}');
      print('📶 WiFi BSSID: $wifiBSSID');

      // Validate: WiFi OR Location OR BLV (at least one must be valid)
      bool isWifiValid = false;
      bool isLocationValid = false;

      // 1️⃣ Check WiFi
      if (_allowedBssids.isNotEmpty && wifiBSSID != null && wifiBSSID.isNotEmpty) {
        final normalizedCurrent = wifiBSSID.toUpperCase().trim();
        isWifiValid = _allowedBssids.any((allowed) {
          return allowed.toUpperCase().trim() == normalizedCurrent;
        });
        print('✅ WiFi check: ${isWifiValid ? "VALID" : "INVALID"} - $normalizedCurrent');
      } else {
        print('⚠️ WiFi check: SKIPPED (no WiFi or no allowed BSSIDs)');
      }

      // 2️⃣ Check Location
      if (RestaurantConfig.enforceLocation && _branchData != null && position != null) {
        final branchLat = _branchData!['latitude'] as double?;
        final branchLng = _branchData!['longitude'] as double?;
        final branchRadius = (_branchData!['geofence_radius'] as int?) ?? 200;
        
        if (branchLat != null && branchLng != null) {
          final distance = Geolocator.distanceBetween(
            branchLat,
            branchLng,
            position.latitude,
            position.longitude,
          );
          
          final accuracyMargin = position.accuracy > 100 ? position.accuracy * 1.5 : position.accuracy * 1.0;
          final effectiveRadius = branchRadius + accuracyMargin;
          
          isLocationValid = distance <= effectiveRadius;
          print('✅ Location check: ${isLocationValid ? "VALID" : "INVALID"} - ${distance.toStringAsFixed(0)}m from ${effectiveRadius.toStringAsFixed(0)}m');
        } else {
          print('⚠️ Location check: SKIPPED (no branch coordinates)');
        }
      } else {
        print('⚠️ Location check: SKIPPED (disabled or no position)');
      }

      // 3️⃣ Require at least ONE to be valid (WiFi OR Location OR BLV will be checked by backend)
      if (!isWifiValid && !isLocationValid) {
        throw Exception(
          'يجب أن تكون متصلاً بشبكة الواي فاي الخاصة بالفرع أو متواجداً في الموقع الصحيح.\n'
          'تأكد من الاتصال بالـ WiFi الصحيح أو التواجد داخل الفرع.'
        );
      }

      print('✅ Validation PASSED - WiFi: $isWifiValid, Location: $isLocationValid');

      final latitude = position?.latitude ?? RestaurantConfig.latitude;
      final longitude = position?.longitude ?? RestaurantConfig.longitude;

      // Get active attendance first
      final activeAttendance = await SupabaseAttendanceService.getActiveAttendance(widget.managerId);
      
      if (activeAttendance == null) {
        throw Exception('لا يوجد سجل حضور نشط');
      }

      final success = await SupabaseAttendanceService.checkOut(
        attendanceId: activeAttendance['id'],
        latitude: latitude,
        longitude: longitude,
      );

      if (!success) {
        throw Exception('فشل تسجيل الانصراف');
      }

      setState(() {
        _isCheckedIn = false;
        _checkInTime = null;
        _elapsedTime = '00:00:00';
        _isLoading = false;
      });

      _timer?.cancel();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تم تسجيل الانصراف بنجاح'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: ${e.toString()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAttendanceRequestDialog() async {
    final today = DateTime.now();
    final requests = await RequestsApiService.fetchAttendanceRequests(widget.managerId);
    final hasTodayRequest = requests.any((r) =>
        r.requestedTime.year == today.year &&
        r.requestedTime.month == today.month &&
        r.requestedTime.day == today.day &&
        r.status == RequestStatus.pending
    );
    if (hasTodayRequest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكنك إرسال أكثر من طلب حضور في نفس اليوم'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final reasonController = TextEditingController();
    DateTime? selectedTime = DateTime.now();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryOrange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.calendar_today,
                        color: AppColors.primaryOrange,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'طلب تسجيل حضور',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'للموظفين الذين نسوا التسجيل',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: reasonController,
                  decoration: InputDecoration(
                    labelText: 'السبب',
                    hintText: 'اكتب سبب نسيان التسجيل...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primaryOrange, width: 2),
                    ),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('وقت الحضور:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(selectedTime!),
                        );
                        if (picked != null) {
                          setModalState(() {
                            selectedTime = DateTime(
                                today.year, today.month, today.day, picked.hour, picked.minute);
                          });
                        }
                      },
                      child: Text(selectedTime != null
                          ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                          : '--:--'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    final reason = reasonController.text.trim();
                    if (reason.isEmpty || selectedTime == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('يرجى إدخال السبب ووقت الحضور'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      return;
                    }
                    try {
                      await RequestsApiService.submitAttendanceRequest(
                        employeeId: widget.managerId,
                        requestedTime: selectedTime!,
                        reason: reason,
                      );
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✓ تم إرسال الطلب بنجاح'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ: ${e.toString()}'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'إرسال الطلب',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Greeting
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryOrange.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.wb_sunny_outlined,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'صباح الخير',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'أهلاً بك في عملك اليوم',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Quick Actions - Employees Management
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    if (_branchId == null || _branchId!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('خطأ: لا يوجد فرع مرتبط بحسابك'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ManagerEmployeesPage(
                          managerId: widget.managerId,
                          branchId: _branchId!,
                          branchName: _branchData?['branch_name'] ?? 'الفرع',
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.people,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'إدارة الموظفين',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'عرض وإضافة موظفي الفرع',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Status Card with Timer
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _isCheckedIn
                                ? AppColors.success.withOpacity(0.1)
                                : AppColors.textTertiary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _isCheckedIn ? Icons.work : Icons.work_outline,
                            color: _isCheckedIn ? AppColors.success : AppColors.textTertiary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isCheckedIn ? 'قيد العمل' : 'خارج العمل',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _isCheckedIn ? AppColors.success : AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isCheckedIn
                                    ? 'منذ ${_checkInTime != null ? "${_checkInTime!.hour}:${_checkInTime!.minute.toString().padLeft(2, '0')}" : ""}'
                                    : 'سجل حضورك لبدء العمل',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    if (_isCheckedIn) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'مدة العمل',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _elapsedTime,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryOrange,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Main Action Button
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : (_isCheckedIn ? _handleCheckOut : _handleCheckIn),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isCheckedIn ? AppColors.error : AppColors.primaryOrange,
                    disabledBackgroundColor: AppColors.textTertiary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isCheckedIn ? Icons.logout : Icons.login,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _isCheckedIn ? 'تسجيل الانصراف' : 'تسجيل الحضور',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Send Requests Button
              SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ManagerSendRequestsPage(managerId: widget.managerId),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryOrange,
                    side: const BorderSide(color: AppColors.primaryOrange, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.send, size: 24),
                      SizedBox(width: 12),
                      Text(
                        'إرسال طلبات',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Request Break Button
              if (_isCheckedIn)
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _requestBreak,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryOrange,
                      side: const BorderSide(color: AppColors.primaryOrange, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.coffee, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'طلب استراحة (بريك)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_isCheckedIn) const SizedBox(height: 16),

            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestBreak() async {
    // Show dialog to select break duration
    final duration = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('طلب استراحة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('اختر مدة الاستراحة:'),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('15 دقيقة'),
              onTap: () => Navigator.pop(context, 15),
            ),
            ListTile(
              title: const Text('30 دقيقة'),
              onTap: () => Navigator.pop(context, 30),
            ),
            ListTile(
              title: const Text('45 دقيقة'),
              onTap: () => Navigator.pop(context, 45),
            ),
            ListTile(
              title: const Text('60 دقيقة'),
              onTap: () => Navigator.pop(context, 60),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (duration == null) return;

    setState(() => _isLoading = true);

    try {
      await RequestsApiService.submitBreakRequest(
        employeeId: widget.managerId,
        durationMinutes: duration,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تم إرسال طلب الاستراحة للمراجعة'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: ${e.toString()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}