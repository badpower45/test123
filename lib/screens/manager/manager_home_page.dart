import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:optimize_battery/optimize_battery.dart';

import '../../constants/restaurant_config.dart';
import '../../models/attendance_request.dart';
import '../../models/employee.dart';
import '../../services/attendance_api_service.dart';
import '../../services/branch_api_service.dart';
import '../../services/location_service.dart';
import '../../services/requests_api_service.dart';
import '../../services/supabase_attendance_service.dart';
import '../../services/supabase_employee_service.dart';
import '../../services/sync_service.dart';
import '../../services/wifi_service.dart';
import '../../services/offline_data_service.dart';
import '../../services/geofence_service.dart';
import '../../services/pulse_tracking_service.dart';
import '../../services/foreground_attendance_service.dart';
import '../../services/workmanager_pulse_service.dart';
import '../../services/alarm_manager_pulse_service.dart';
import '../../services/native_pulse_bridge.dart';
import '../../services/aggressive_keep_alive_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_logger.dart';
import '../../services/device_compatibility_service.dart';
import '../../services/checkout_debug_service.dart';
import '../../services/offline_transition_helper.dart';
import '../../services/attendance_timer_service.dart';
import '../../database/offline_database.dart';
import '../../config/supabase_config.dart';
import '../../theme/app_colors.dart';
import 'manager_send_requests_page.dart';
import 'manager_employees_page.dart';
import 'manager_add_employee_page.dart';
import 'session_validation_page.dart';
import 'manager_dashboard_simple.dart';
import '../branch_manager_screen.dart';
import '../../services/location_permission_service.dart';
import '../../services/attendance_timer_service.dart';
import '../../services/payroll_service.dart';
import '../../services/notification_service.dart';
import '../permissions_onboarding_page.dart';
import '../../widgets/location_verification_dialog.dart';

class ManagerHomePage extends StatefulWidget {
  final String managerId;

  const ManagerHomePage({super.key, required this.managerId});

  @override
  State<ManagerHomePage> createState() => _ManagerHomePageState();
}

class _ManagerHomePageState extends State<ManagerHomePage> with WidgetsBindingObserver {
  bool _isCheckedIn = false;
  DateTime? _checkInTime;
  String _elapsedTime = '00:00:00';
  Timer? _timer;
  bool _isLoading = false;
  bool _isCheckingStatus = false;
  bool _hasCompletedInitialStatusCheck = false;
  String? _branchId;
  Map<String, dynamic>? _branchData;
  List<String> _allowedBssids = [];
  String? _currentAttendanceId;
  double? _distanceFromBranch;
  int _distanceUpdateCounter = 0;
  bool _isSyncing = false;

  final _offlineService = OfflineDataService();
  final _pulseService = PulseTrackingService();
  final _timerService = AttendanceTimerService.instance;

  // 🚨 NEW: Subscription for auto-checkout events
  StreamSubscription<AutoCheckoutEvent>? _autoCheckoutSubscription;
  Timer? _shiftEndTimer;
  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _loadLastKnownDistance();
    WidgetsBinding.instance.addObserver(this);
    _shiftEndTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkAutoCheckout().catchError((e, st) {
        print('⚠️ Error in manager periodic _checkAutoCheckout: $e\n$st');
      });
    });
    try {
      _loadBranchData().catchError((e) {
        print('❌ Error loading branch data: $e');
      }); // Load branch data first
      _checkCurrentStatus().catchError((e) {
        print('❌ Error checking current status: $e');
      });

      _timerService.addListener(_onTimerUpdate);

      // 🚨 NEW: Listen to auto-checkout events for immediate UI update
      _autoCheckoutSubscription = _pulseService.onAutoCheckout.listen(
        _handleAutoCheckout,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateDistanceFromBranch();
      });
    } catch (e, stackTrace) {
      print('❌ Error in ManagerHomePage initState: $e');
      print('Stack trace: $stackTrace');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _shiftEndTimer?.cancel();
    _timerService.removeListener(_onTimerUpdate);
    _autoCheckoutSubscription?.cancel(); // 🚨 Cancel auto-checkout subscription
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('📱 ManagerHomePage: App resumed - checking status and refreshing pulse counts');
      _checkCurrentStatus();
    }
  }

  void _onTimerUpdate(String elapsedTime, double earnings) {
    if (mounted) {
      setState(() {
        _elapsedTime = elapsedTime;
      });
      _checkAutoCheckoutInstant();
      
      _distanceUpdateCounter++;
      if (_distanceUpdateCounter >= 10) {
        _distanceUpdateCounter = 0;
        _updateDistanceFromBranch();
      }
    }
  }

  Future<void> _loadLastKnownDistance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastDistance = prefs.getDouble('last_known_distance_${widget.managerId}');
      if (lastDistance != null && mounted) {
        setState(() {
          _distanceFromBranch = lastDistance;
        });
        print('📱 [Manager] Restored last known distance from cache: ${lastDistance.toStringAsFixed(1)}m');
      }
    } catch (e) {
      print('⚠️ Error loading last known distance: $e');
    }
  }

  Future<void> _updateDistanceFromBranch() async {
    if (_branchData == null) return;
    final centerLat = (_branchData!['latitude'] as num?)?.toDouble();
    final centerLng = (_branchData!['longitude'] as num?)?.toDouble();
    if (centerLat == null || centerLng == null) return;
    
    try {
      final position = await Geolocator.getLastKnownPosition() ?? 
                       await Geolocator.getCurrentPosition(
                         desiredAccuracy: LocationAccuracy.high,
                         timeLimit: const Duration(seconds: 5),
                       );
      
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        centerLat,
        centerLng,
      );
      
      if (mounted) {
        setState(() {
          _distanceFromBranch = distance;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('last_known_distance_${widget.managerId}', distance);

        // ✅ Immediate foreground geofence pause check
        if (_isCheckedIn) {
          final isOnActiveBreak = prefs.getBool('is_break_active') ?? false;
          if (isOnActiveBreak) {
            await AttendanceTimerService.resumeTimerLocally();
          } else {
            final radius = (_branchData!['geofence_radius'] as num?)?.toDouble() ?? 100.0;
            if (distance > radius) {
              await AttendanceTimerService.pauseTimerLocally(reason: 'خارج نطاق الفرع');
            } else {
              await AttendanceTimerService.resumeTimerLocally();
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ Error updating distance: $e');
    }
  }

  void _checkAutoCheckoutInstant() {
    _checkAutoCheckout();
  }

  Future<void> _checkAutoCheckout() async {
    // Disabled by policy: shift-end auto-checkout is completely disabled.
    return;
    if (!_isCheckedIn || _checkInTime == null) return;

    final prefs = await SharedPreferences.getInstance();
    final personalShiftEnd = prefs.getString('employee_shift_end_time');
    
    // Prioritize personal shift end time. If not set, do not trigger auto-checkout.
    final shiftEndStr = personalShiftEnd;
    if (shiftEndStr == null || shiftEndStr.isEmpty) return;

    try {
      final shiftEndTime = AttendanceTimerService.getShiftEndTime(_checkInTime!, shiftEndStr);
      final now = DateTime.now();

      if (now.isAfter(shiftEndTime) || now.millisecondsSinceEpoch == shiftEndTime.millisecondsSinceEpoch) {
        print('⏰ [ShiftEndAutoCheckout] Manager shift end time reached ($shiftEndTime). Triggering auto checkout.');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⏰ انتهى وقت الشيفت! جاري تسجيل الانصراف التلقائي...'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }

        await _handleCheckOut();
      }
    } catch (e) {
      print('⚠️ Error in manager _checkAutoCheckout: $e');
    }
  }

  /// 🚨 Handle auto-checkout event from PulseTrackingService
  void _handleAutoCheckout(AutoCheckoutEvent event) {
    if (!mounted) return;

    print('🚨 Auto-checkout event received in Manager UI');
    print('   Reason: ${event.reason}');
    print('   Saved offline: ${event.savedOffline}');

    // ✅ IMMEDIATELY stop timer and update UI state
    _timer?.cancel();
    _timer = null;

    setState(() {
      _isCheckedIn = false;
      _checkInTime = null;
      _elapsedTime = '00:00:00';
      _currentAttendanceId = null;
      _isLoading = false;
    });

    // Show dialog to user
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange[700],
              size: 28,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '🚨 انصراف تلقائي',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              event.reason,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (event.savedOffline)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.cloud_off, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تم الحفظ محلياً - سيتم الرفع عند توفر الإنترنت',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 13, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'الوقت: ${event.timestamp.hour}:${event.timestamp.minute.toString().padLeft(2, '0')}',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  String? _getBranchName() {
    final candidates = [
      _branchData?['name'],
      _branchData?['branch_name'],
      _branchData?['branch'],
      _branchData?['branchName'],
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return null;
  }

  String? _getBranchId() {
    final direct = _branchId ?? _branchData?['id']?.toString();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    final nested = _branchData?['branch_id'] ?? _branchData?['branchId'];
    if (nested is String && nested.isNotEmpty) {
      return nested;
    }
    return null;
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
        _updateDistanceFromBranch();
        print(
          '✅ [Manager] Using cached branch data: ${cached['branch_name']} (${_allowedBssids.length} WiFi networks)',
        );
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
          _updateDistanceFromBranch();
          print(
            '⚠️ [Manager] Using stale cache (no internet): ${cached['branch_name']}',
          );
        } else {
          print('⚠️ [Manager] No internet and no cached branch data');
        }
        return;
      }

      // Get employee data to find branch
      final employeeData = await SupabaseAttendanceService.getEmployeeStatus(
        widget.managerId,
      );

      // ✅ First try branch_id (more reliable), then fallback to branch name
      final branchIdFromEmployee = employeeData['employee']?['branch_id'];
      final branchName =
          employeeData['employee']?['branch'] ??
          employeeData['employee']?['branch_name'];

      // Store branch_id if available
      if (branchIdFromEmployee != null &&
          branchIdFromEmployee.toString().isNotEmpty) {
        _branchId = branchIdFromEmployee.toString();
        print('📍 [Manager] Branch ID from employee: $_branchId');

        // Fetch branch data by ID
        try {
          final branchData = await BranchApiService.getBranchById(
            branchIdFromEmployee.toString(),
          );
          await _processBranchData(branchData, db);
          return;
        } catch (e) {
          print('⚠️ Failed to get branch by ID, trying by name: $e');
        }
      }

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

      print(
        '✅ [Manager] Found branch: ${branchData['name']} (${branchData['id']})',
      );

      await _processBranchData(branchData, db);
    } catch (e) {
      print('❌ [Manager] Error loading branch data: $e');
    }
  }

  /// Helper to process and cache branch data
  Future<void> _processBranchData(
    Map<String, dynamic> branchData,
    OfflineDatabase db,
  ) async {
    // Parse WiFi BSSIDs (can be comma-separated or array)
    List<String> wifiBssids = [];
    if (branchData['wifi_bssid'] != null &&
        branchData['wifi_bssid'].toString().isNotEmpty) {
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
          longitude =
              (location['longitude'] ?? location['lng'] ?? location['long'])
                  ?.toDouble();
        } else if (location is String) {
          final decoded = jsonDecode(location);
          latitude = (decoded['latitude'] ?? decoded['lat'])?.toDouble();
          longitude =
              (decoded['longitude'] ?? decoded['lng'] ?? decoded['long'])
                  ?.toDouble();
        }
      } catch (e) {
        print('⚠️ Error parsing location: $e');
      }
    }

    // Also check direct lat/lng
    latitude ??= (branchData['latitude'] as num?)?.toDouble();
    longitude ??= (branchData['longitude'] as num?)?.toDouble();

    final geofenceRadius =
        (branchData['geofence_radius'] ?? branchData['geofenceRadius'] ?? 100.0)
            .toDouble();

    // Cache it locally for future use
    int dataVersion = 1;
    if (branchData['updated_at'] != null) {
      try {
        dataVersion =
            DateTime.parse(
              branchData['updated_at'].toString(),
            ).millisecondsSinceEpoch ~/
            1000;
      } catch (e) {
        dataVersion = 1;
      }
    }

    await db.cacheBranchData(
      employeeId: widget.managerId,
      branchId: branchData['id'],
      branchName: branchData['name'],
      wifiBssids: wifiBssids,
      latitude: latitude,
      longitude: longitude,
      geofenceRadius: geofenceRadius,
      dataVersion: dataVersion,
    );

    setState(() {
      _branchData = branchData;
      _branchId = branchData['id'];
      _allowedBssids = wifiBssids;
    });

    _updateDistanceFromBranch();

    print(
      '✅ [Manager] Fetched and cached branch data: ${branchData['name']} (${wifiBssids.length} WiFi networks)',
    );
  }

  /// Load branch data for Web platform (using Hive)
  Future<void> _loadBranchDataForWeb() async {
    try {
      // Check cached data from Hive (employee-specific)
      final cached = await _offlineService.getCachedBranchData(
        employeeId: widget.managerId,
      );

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
        _updateDistanceFromBranch();
        print(
          '✅ [Manager] Using cached branch data from Hive: ${cached['name']}',
        );
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
      final managerData = await SupabaseAttendanceService.getEmployeeStatus(
        widget.managerId,
      );
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
        _updateDistanceFromBranch();
        print(
          '✅ [Manager] Downloaded branch data on Web: ${branchData['name']}',
        );
      }
    } catch (e) {
      print('❌ [Manager] Error loading branch data on Web: $e');
    }
  }

  void _showAddEmployeeSheet() {
    final branchName = _getBranchName();
    final branchId = _getBranchId();

    if (branchName == null || branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن إضافة موظف قبل تحميل بيانات الفرع'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final pinController = TextEditingController();
    final hourlyRateController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();

    final allowedRoles = <EmployeeRole>[
      EmployeeRole.staff,
      EmployeeRole.monitor,
      EmployeeRole.hr,
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        EmployeeRole selectedRole = EmployeeRole.staff;
        bool isSubmitting = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) {
                return;
              }

              setModalState(() => isSubmitting = true);
              try {
                await SupabaseEmployeeService.createEmployee(
                  fullName: nameController.text.trim(),
                  pin: pinController.text.trim(),
                  branchId: branchId,
                  branchName: branchName,
                  hourlyRate:
                      double.tryParse(hourlyRateController.text.trim()) ?? 0,
                  role: selectedRole,
                  email: emailController.text.trim().isEmpty
                      ? null
                      : emailController.text.trim(),
                  phone: phoneController.text.trim().isEmpty
                      ? null
                      : phoneController.text.trim(),
                );

                if (!mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'تم إضافة ${nameController.text.trim()} للفرع $branchName',
                    ),
                    backgroundColor: AppColors.success,
                  ),
                );
              } catch (error) {
                setModalState(() => isSubmitting = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('فشل إضافة الموظف: $error'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            }

            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.primaryOrange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: const Icon(
                              Icons.person_add_alt_1,
                              color: AppColors.primaryOrange,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'إضافة موظف جديد',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'سيتم ربط الموظف أوتوماتيكياً بفرع $branchName',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم الموظف',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'يرجى إدخال الاسم';
                          }
                          if (value.trim().length < 3) {
                            return 'الاسم يجب أن يكون أكثر من 3 أحرف';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: pinController,
                        decoration: const InputDecoration(
                          labelText: 'الرقم السري (PIN)',
                          border: OutlineInputBorder(),
                          hintText: 'أربعة أرقام على الأقل',
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'يرجى إدخال الرقم السري';
                          }
                          if (value.trim().length < 4) {
                            return 'الرقم السري يجب أن يكون 4 أرقام على الأقل';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<EmployeeRole>(
                        value: selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'دور الموظف',
                          border: OutlineInputBorder(),
                        ),
                        items: allowedRoles
                            .map(
                              (role) => DropdownMenuItem(
                                value: role,
                                child: Text(_roleLabel(role)),
                              ),
                            )
                            .toList(),
                        onChanged: (role) {
                          if (role != null) {
                            setModalState(() => selectedRole = role);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: hourlyRateController,
                        decoration: const InputDecoration(
                          labelText: 'سعر الساعة (اختياري)',
                          border: OutlineInputBorder(),
                          hintText: 'مثال: 100',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'البريد الإلكتروني (اختياري)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: phoneController,
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف (اختياري)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isSubmitting ? null : submit,
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.person_add_alt_1),
                          label: Text(
                            isSubmitting ? 'جاري الإضافة...' : 'إضافة الموظف',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryOrange,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      nameController.dispose();
      pinController.dispose();
      hourlyRateController.dispose();
      emailController.dispose();
      phoneController.dispose();
    });
  }

  static String _roleLabel(EmployeeRole role) {
    switch (role) {
      case EmployeeRole.manager:
        return 'مدير';
      case EmployeeRole.hr:
        return 'موارد بشرية';
      case EmployeeRole.monitor:
        return 'مراقب';
      case EmployeeRole.staff:
      default:
        return 'موظف';
    }
  }

  Future<void> _checkCurrentStatus() async {
    if (mounted) {
      setState(() {
        _isCheckingStatus = true;
      });
    }

    try {
      // ✅ Use Supabase directly like employee page (fixes "No host specified in URI" error)
      print(
        '🔄 Checking current attendance status for manager: ${widget.managerId}',
      );

      final prefs = await SharedPreferences.getInstance();
      var savedAttendanceId = prefs.getString('active_attendance_id');
      var activeEmployeeId = prefs.getString('active_employee_id');
      final hasForeignCache =
          activeEmployeeId != null && activeEmployeeId != widget.managerId;
      var isOfflineAttendance = prefs.getBool('is_offline_attendance') ?? false;
      var isCheckedInFlag = prefs.getBool('is_checked_in') ?? false;
      final pulseTrackingActive =
          prefs.getBool('pulse_tracking_active') ?? false;
      var offlineCheckinTimeStr = prefs.getString('offline_checkin_time');
      var cachedCheckinTimeStr = prefs.getString('cached_checkin_time');
      final persistedTimerCheckInTimeStr = prefs.getString(
        'timer_check_in_time',
      );
      var restoredTimeSource =
          offlineCheckinTimeStr ??
          cachedCheckinTimeStr ??
          persistedTimerCheckInTimeStr;

      final snapshot =
          await SupabaseAttendanceService.getCachedActiveAttendanceOnDevice(
            employeeId: widget.managerId,
          );
      if (snapshot != null &&
          ((savedAttendanceId == null || savedAttendanceId.isEmpty) ||
              hasForeignCache)) {
        savedAttendanceId = snapshot['attendance_id']?.toString();
        activeEmployeeId = snapshot['employee_id']?.toString();
        isOfflineAttendance = snapshot['is_offline_attendance'] == true;
        isCheckedInFlag = true;

        final snapshotCheckInTime = snapshot['check_in_time']?.toString();
        if (snapshotCheckInTime != null && snapshotCheckInTime.isNotEmpty) {
          cachedCheckinTimeStr = snapshotCheckInTime;
          restoredTimeSource = snapshotCheckInTime;
          await prefs.setString('cached_checkin_time', snapshotCheckInTime);
          if (isOfflineAttendance) {
            offlineCheckinTimeStr = snapshotCheckInTime;
            await prefs.setString('offline_checkin_time', snapshotCheckInTime);
          }
        }

        if (savedAttendanceId != null && savedAttendanceId.isNotEmpty) {
          await prefs.setString('active_attendance_id', savedAttendanceId);
        }

        if (activeEmployeeId != null && activeEmployeeId.isNotEmpty) {
          await prefs.setString('active_employee_id', activeEmployeeId);
        } else {
          activeEmployeeId = widget.managerId;
          await prefs.setString('active_employee_id', widget.managerId);
        }

        await prefs.setBool('is_checked_in', true);
        await prefs.setBool('is_offline_attendance', isOfflineAttendance);
        print(
          '📦 Restored manager active attendance from device snapshot: $savedAttendanceId',
        );
      }

      final cacheBelongsToManager =
          activeEmployeeId == null || activeEmployeeId == widget.managerId;
      String? resolvedCachedCheckinTimeStr = cachedCheckinTimeStr;
      bool cachedAttendanceStillActive = true;
      bool restoredFromCache = false;

      if (savedAttendanceId != null &&
          cacheBelongsToManager &&
          !isOfflineAttendance) {
        try {
          final cachedAttendanceRow = await SupabaseConfig.client
              .from('attendance')
              .select('id, check_in_time, check_out_time, status')
              .eq('id', savedAttendanceId)
              .maybeSingle()
              .timeout(const Duration(seconds: 3), onTimeout: () => null);

          if (cachedAttendanceRow != null) {
            final status = cachedAttendanceRow['status']
                ?.toString()
                .toLowerCase();
            final hasCheckout = cachedAttendanceRow['check_out_time'] != null;
            const inactiveStates = <String>{
              'completed',
              'checked_out',
              'inactive',
              'out',
            };
            final isActiveStatus =
                status == null ||
                status.isEmpty ||
                !inactiveStates.contains(status);

            if (hasCheckout || !isActiveStatus) {
              cachedAttendanceStillActive = false;
              await SupabaseAttendanceService.clearActiveAttendanceCache();
              savedAttendanceId = null;
              isOfflineAttendance = false;
              isCheckedInFlag = false;
              offlineCheckinTimeStr = null;
              cachedCheckinTimeStr = null;
              resolvedCachedCheckinTimeStr = null;
              print(
                '🧹 Cleared stale cached manager attendance state: $savedAttendanceId',
              );
            } else {
              final serverCheckInIso = cachedAttendanceRow['check_in_time']
                  ?.toString();
              if (serverCheckInIso != null && serverCheckInIso.isNotEmpty) {
                resolvedCachedCheckinTimeStr = serverCheckInIso;
                await prefs.setString('cached_checkin_time', serverCheckInIso);
              }
            }
          }
        } catch (verifyError) {
          print(
            '⚠️ Could not verify cached manager attendance against server: $verifyError',
          );
        }
      }

      // Early return if offline attendance is present
      if (savedAttendanceId != null &&
          cacheBelongsToManager &&
          isOfflineAttendance &&
          offlineCheckinTimeStr != null) {
        print(
          '📱 Found offline attendance in SharedPreferences for manager: $savedAttendanceId',
        );

        _safeSetState(() {
          _isCheckedIn = true;
          _currentAttendanceId = savedAttendanceId;
          try {
            _checkInTime = DateTime.parse(
              offlineCheckinTimeStr ?? DateTime.now().toIso8601String(),
            ).toLocal();
          } catch (e) {
            _checkInTime = DateTime.now();
          }
        });

        if (_checkInTime != null) {
          _startTimer();
        }

        await _ensurePulseTrackingActive(
          employeeId: widget.managerId,
          attendanceId: savedAttendanceId,
          checkInTime: _checkInTime,
        );

        print('✅ Restored offline manager attendance state');
        return;
      }

      // Restore quickly from local cache so reopening the app keeps active session UI.
      if (savedAttendanceId != null &&
          cachedAttendanceStillActive &&
          cacheBelongsToManager &&
          !isOfflineAttendance &&
          (resolvedCachedCheckinTimeStr != null ||
              persistedTimerCheckInTimeStr != null) &&
          (isCheckedInFlag || pulseTrackingActive)) {
        print(
          '📱 Restoring cached active manager attendance state: $savedAttendanceId',
        );

        DateTime restoredCheckIn;
        try {
          final sourceTime =
              resolvedCachedCheckinTimeStr ?? persistedTimerCheckInTimeStr;
          restoredCheckIn = DateTime.parse(sourceTime!).toLocal();
        } catch (_) {
          restoredCheckIn = DateTime.now();
        }

        _safeSetState(() {
          _isCheckedIn = true;
          _currentAttendanceId = savedAttendanceId;
          _checkInTime = restoredCheckIn;
        });

        _startTimer();

        await _ensurePulseTrackingActive(
          employeeId: widget.managerId,
          attendanceId: savedAttendanceId,
          checkInTime: restoredCheckIn,
        );

        print('✅ Restored cached manager online attendance state');
        restoredFromCache = true;
      }

      final status = await SupabaseAttendanceService.getEmployeeStatus(
        widget.managerId,
      );

      final wasCheckedIn = _isCheckedIn;

      // Cache personal shift start and end times
      final personalShiftStart = status['employee']?['shift_start_time']?.toString();
      final personalShiftEnd = status['employee']?['shift_end_time']?.toString();
      if (personalShiftStart != null && personalShiftStart.isNotEmpty) {
        await prefs.setString('employee_shift_start_time', personalShiftStart);
      } else {
        await prefs.remove('employee_shift_start_time');
      }
      if (personalShiftEnd != null && personalShiftEnd.isNotEmpty) {
        await prefs.setString('employee_shift_end_time', personalShiftEnd);
      } else {
        await prefs.remove('employee_shift_end_time');
      }

      // Sync & Pending Check-ins Guard:
      // Prevent automatic check-out if a sync is in progress or check-ins are pending
      final isCurrentlySyncing = SyncService.instance.isSyncing || _isSyncing;
      final pendingCheckins = await OfflineDatabase.instance.getPendingCheckins();
      
      // Determine check-in time to pass to helper if needed
      DateTime? resolvedCheckInTime = _checkInTime;
      if (resolvedCheckInTime == null) {
        final sourceTime = resolvedCachedCheckinTimeStr ??
            offlineCheckinTimeStr ??
            persistedTimerCheckInTimeStr;
        if (sourceTime != null) {
          try {
            resolvedCheckInTime = DateTime.parse(sourceTime).toLocal();
          } catch (_) {}
        }
      }

      final pendingCheckouts = await OfflineDatabase.instance.getPendingCheckouts();
      final hasPendingCheckout = pendingCheckouts.any((c) {
        final checkoutAttId = c['attendance_id']?.toString();
        final matchesId = checkoutAttId != null &&
            (checkoutAttId == _currentAttendanceId ||
             checkoutAttId == savedAttendanceId);
        
        bool isRecent = false;
        if (!matchesId && (checkoutAttId == null || checkoutAttId.isEmpty || checkoutAttId.contains('local') || checkoutAttId.contains('pending'))) {
          final checkoutTimeStr = c['timestamp']?.toString() ?? c['created_at']?.toString();
          if (checkoutTimeStr != null && resolvedCheckInTime != null) {
            try {
              final checkoutTime = DateTime.parse(checkoutTimeStr);
              if (checkoutTime.isAfter(resolvedCheckInTime)) {
                isRecent = true;
              }
            } catch (_) {}
          }
        }
        return matchesId || isRecent;
      });

      if (!hasPendingCheckout && (isCurrentlySyncing || pendingCheckins.isNotEmpty) && wasCheckedIn) {
        print('🛡️ [StatusCheck] Sync is in progress or pending check-ins exist. Protecting local manager check-in state.');
        _safeSetState(() {
          _isCheckedIn = true;
          _isCheckingStatus = false;
        });
        return;
      }

      final shiftEndTimeStr = prefs.getString('employee_shift_end_time');

      final keepLocalCheckedIn = await OfflineTransitionHelper.shouldKeepLocalCheckIn(
        localCheckedInFlag: isCheckedInFlag,
        wasCheckedIn: wasCheckedIn,
        checkInTime: resolvedCheckInTime,
        shiftEndTimeStr: shiftEndTimeStr,
        isOfflineAttendance: isOfflineAttendance,
        cachedAttendanceStillActive: cachedAttendanceStillActive,
      );

      final serverReportsCheckedIn = status['isCheckedIn'] as bool? ?? false;
      final targetCheckedIn = !hasPendingCheckout && (serverReportsCheckedIn || keepLocalCheckedIn);

      if (mounted) {
        setState(() {
          _isCheckedIn = targetCheckedIn;
          _currentAttendanceId =
              status['attendance']?['id']?.toString() ??
              (targetCheckedIn ? (savedAttendanceId ?? _currentAttendanceId ?? status['attendance']?['id']?.toString()) : null);
          // Parse checkInTime and convert from UTC to local time (with safe parsing)
          if (status['attendance']?['check_in_time'] != null) {
            try {
              _checkInTime = DateTime.parse(
                status['attendance']['check_in_time'].toString(),
              ).toLocal();
            } catch (e) {
              _checkInTime = resolvedCheckInTime;
            }
          } else {
            _checkInTime = resolvedCheckInTime;
          }

          // ✅ Clear if checked out
          if (!_isCheckedIn) {
            _timer?.cancel();
            _timerService.stopTimer();
            _elapsedTime = '00:00:00';
            _currentAttendanceId = null;
          }
        });
      }

      // ✅ Cache active attendance ID on device for safe offline retrieval
      if (_isCheckedIn && _currentAttendanceId != null && !isOfflineAttendance) {
        try {
          await SupabaseAttendanceService.cacheActiveAttendanceOnDevice(
            employeeId: widget.managerId,
            attendanceId: _currentAttendanceId!,
            checkInIso: _checkInTime?.toIso8601String(),
            isOfflineAttendance: false,
          );
        } catch (e) {
          print('⚠️ Failed to cache online manager attendance in status check: $e');
        }
      }

      print(
        '✅ Manager status updated: isCheckedIn=$_isCheckedIn (was: $wasCheckedIn)',
      );

      // Load branch data if available
      if (_branchId != null && _branchId!.isNotEmpty) {
        try {
          final branchResponse = await BranchApiService.getBranchById(
            _branchId!,
          );
          setState(() {
            _branchData = branchResponse['branch'];
            _allowedBssids =
                (branchResponse['allowedBssids'] as List<dynamic>?)
                    ?.map((e) => e.toString().toUpperCase())
                    .toList() ??
                [];
          });
        } catch (e) {
          print('Failed to load branch data: $e');
        }
      }

      if (_isCheckedIn && _checkInTime != null) {
        _startTimer();
        if (!_pulseService.isTracking) {
          try {
            await _ensurePulseTrackingActive(
              employeeId: widget.managerId,
              attendanceId: _currentAttendanceId,
              checkInTime: _checkInTime,
            );
            AppLogger.instance.log(
              'Resumed pulse tracking for manager based on status check',
              tag: 'ManagerHome',
            );
          } catch (e) {
            print('⚠️ Failed to resume pulse tracking: $e');
          }
        }
        if (_pulseService.isTracking) {
          await _pulseService.refreshPulseCounts(checkInTime: _checkInTime);
          _timerService.forceTickUpdate();
        }
      }
      _updateDistanceFromBranch();
    } catch (e) {
      print('❌ Error checking manager status: $e');

      // Fallback for transient network issues: keep active session from local cache.
      try {
        final prefs = await SharedPreferences.getInstance();
        var savedAttendanceId = prefs.getString('active_attendance_id');
        var activeEmployeeId = prefs.getString('active_employee_id');
        final hasForeignCache =
            activeEmployeeId != null && activeEmployeeId != widget.managerId;
        final offlineCheckinTimeStr = prefs.getString('offline_checkin_time');
        final cachedCheckinTimeStr = prefs.getString('cached_checkin_time');
        final persistedTimerCheckInTimeStr = prefs.getString(
          'timer_check_in_time',
        );
        var sourceTime =
            offlineCheckinTimeStr ??
            cachedCheckinTimeStr ??
            persistedTimerCheckInTimeStr;

        if ((savedAttendanceId == null || hasForeignCache) &&
            sourceTime == null) {
          final snapshot =
              await SupabaseAttendanceService.getCachedActiveAttendanceOnDevice(
                employeeId: widget.managerId,
              );
          if (snapshot != null) {
            savedAttendanceId = snapshot['attendance_id']?.toString();
            activeEmployeeId =
                snapshot['employee_id']?.toString() ?? widget.managerId;
            sourceTime = snapshot['check_in_time']?.toString();
          }
        }

        final cacheBelongsToManager =
            activeEmployeeId == null || activeEmployeeId == widget.managerId;

        if (savedAttendanceId != null &&
            cacheBelongsToManager &&
            sourceTime != null) {
          if (mounted) {
            setState(() {
              _isCheckedIn = true;
              _currentAttendanceId = savedAttendanceId;
              _checkInTime = DateTime.parse(sourceTime!).toLocal();
            });
          }

          _startTimer();

          if (!_pulseService.isTracking) {
            await _ensurePulseTrackingActive(
              employeeId: widget.managerId,
              attendanceId: savedAttendanceId,
              checkInTime: _checkInTime,
            );
          } else {
            // Already tracking - update the counts & timer UI
            await _pulseService.refreshPulseCounts(checkInTime: _checkInTime);
            _timerService.forceTickUpdate();
            _updateDistanceFromBranch();
          }

          print(
            '📱 Restored manager session after status error from local cache',
          );
        }
      } catch (restoreError) {
        print(
          '⚠️ Could not restore manager session after error: $restoreError',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingStatus = false;
          _hasCompletedInitialStatusCheck = true;
        });
      }
    }
  }

  Future<void> reloadData() async {
    await _checkCurrentStatus();
  }

  Future<void> _startTimer() async {
    _timer?.cancel();

    if (_checkInTime == null) {
      _elapsedTime = '00:00:00';
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final personalShiftEndTime = prefs.getString('employee_shift_end_time');

    _timerService.startTimer(
      checkInTime: _checkInTime!,
      hourlyRate: 0.0,
      shiftEndTimeStr: personalShiftEndTime,
    );
  }

  /// 🔒 Hard Permission Check - نظام الأمر الواقع للمدير
  /// يفحص جميع الصلاحيات الضرورية قبل السماح بتسجيل الحضور
  /// يمنع الحضور إذا لم تكن جميع الصلاحيات مفعلة
  Future<bool> checkHardPermissions() async {
    if (kIsWeb) return true; // Web doesn't need these checks

    try {
      bool notifOk = await Permission.notification.isGranted;
      final locationStatus = await Geolocator.checkPermission();
      bool locationAlwaysOk = locationStatus == LocationPermission.always;
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      
      bool exactAlarmOk = true;
      bool wifiEnabled = true;
      bool batteryOptOk = true;
      bool overlayOk = true;

      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        
        if (sdkInt >= 33) {
          notifOk = await Permission.notification.isGranted;
        } else {
          notifOk = true;
        }

        if (sdkInt >= 31) {
          exactAlarmOk = await Permission.scheduleExactAlarm.isGranted;
        }

        batteryOptOk = await Permission.ignoreBatteryOptimizations.isGranted;
        overlayOk = await Permission.systemAlertWindow.isGranted;

        try {
          final canStart = await WiFiScan.instance.canStartScan(askPermissions: false);
          wifiEnabled = canStart != CanStartScan.failed && canStart != CanStartScan.notSupported;
        } catch (_) {
          wifiEnabled = false;
        }
      }

      final hasAll = notifOk && locationAlwaysOk && serviceEnabled && exactAlarmOk && wifiEnabled && batteryOptOk && overlayOk;

      if (!hasAll) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('⚠️ صلاحيات مطلوبة', textAlign: TextAlign.right),
              content: const Text(
                'يجب تفعيل جميع صلاحيات الموقع طوال الوقت، الإشعارات، المنبه الدقيق، الواي فاي، تعطيل تحسين البطارية، والظهور فوق التطبيقات لتسجيل الحضور.',
                textAlign: TextAlign.right,
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final loginData = await AuthService.getLoginData();
                    final branchName = loginData['branch'] ?? _branchData?['name'] ?? '';
                    if (!mounted) return;
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => PermissionsOnboardingPage(
                          nextScreen: BranchManagerScreen(
                            managerId: widget.managerId,
                            branchName: branchName,
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('الانتقال للتفعيل'),
                ),
              ],
            ),
          );
        }
        return false;
      }

      return true;
    } catch (e) {
      AppLogger.instance.log(
        'Error checking hard permissions for manager: $e',
        level: AppLogger.error,
        tag: 'HardPermissionManager',
        error: e,
      );
      return false;
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  /// Show diagnostic dialog for location/checkout troubleshooting
  Future<void> _showDiagnosticDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جاري تشخيص المشكلة...'),
          ],
        ),
      ),
    );

    try {
      final report = await CheckoutDebugService.instance.runDiagnostic(
        employeeId: widget.managerId,
        branchId: _branchId,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      final summary = CheckoutDebugService.instance.getReadableSummary(report);

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                report['status'] == 'healthy'
                    ? Icons.check_circle
                    : report['status'] == 'critical'
                    ? Icons.error
                    : Icons.warning,
                color: report['status'] == 'healthy'
                    ? Colors.green
                    : report['status'] == 'critical'
                    ? Colors.red
                    : Colors.orange,
              ),
              const SizedBox(width: 10),
              const Text('تقرير التشخيص', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: SelectableText(
              summary,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                DeviceCompatibilityService.instance.showPermissionGuideDialog(
                  context,
                );
              },
              child: const Text('دليل الإعدادات'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                foregroundColor: Colors.white,
              ),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في التشخيص: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _ensurePulseTrackingActive({
    required String employeeId,
    required String? attendanceId,
    required DateTime? checkInTime,
  }) async {
    if (attendanceId == null || attendanceId.isEmpty) {
      print('⚠️ [ensurePulseTrackingActive] attendanceId is null or empty');
      return;
    }

    if (checkInTime != null) {
      _checkInTime = checkInTime;
    }

    if (_branchData == null) {
      try {
        _branchData = await OfflineDatabase.instance.getCachedBranchData(employeeId);
      } catch (e) {
        print('⚠️ Error loading branch data from cache in _ensurePulseTrackingActive: $e');
      }
    }

    if (_branchData != null) {
      final branchIdForPulse =
          _branchData!['id']?.toString() ??
          _branchData!['branch_id']?.toString() ??
          '';

      await _startUnifiedPulseSystem(
        employeeId: employeeId,
        attendanceId: attendanceId,
        branchId: branchIdForPulse,
      );

      if (!kIsWeb) {
        SyncService.instance.startPeriodicSync();
      }
      _updateDistanceFromBranch();
    } else {
      print('⚠️ _branchData is null in _ensurePulseTrackingActive, starting primary tracking only');
      if (!_pulseService.isTracking) {
        await _pulseService.startTracking(
          employeeId,
          attendanceId: attendanceId,
          checkInTime: checkInTime ?? _checkInTime,
        );
      }
    }
  }

  /// 🚀 PHASE 2: Unified Pulse System with 5-Layer Protection (MANAGER)
  /// Starts all pulse tracking services in the correct order with proper error handling
  /// Layers:
  /// 1. PulseTrackingService (primary foreground service)
  /// 2. ForegroundAttendanceService (persistent notification)
  /// 3. AlarmManager (guaranteed - works even if app killed)
  /// 4. WorkManager (15-min backup for old devices)
  /// 5. AggressiveKeepAlive (for Samsung/Xiaomi/Realme problematic devices)
  Future<void> _startUnifiedPulseSystem({
    required String employeeId,
    required String attendanceId,
    required String branchId,
  }) async {
    print(
      '🚀 PHASE 2: Starting Unified Pulse System with 5-Layer Protection (MANAGER)',
    );
    print('   Manager ID: $employeeId');
    print('   Attendance: $attendanceId');
    print('   Branch: $branchId');

    if (kIsWeb) {
      print('⚠️ Web platform - pulse tracking not available');
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      print('⚠️ Unsupported platform for unified pulse system');
      return;
    }

    try {
      if (Platform.isIOS) {
        print(
          '🍎 iOS unified pulse path (MANAGER): PulseTracking + WorkManager + Native Audio KeepAlive',
        );
        if (!_pulseService.isTracking) {
          await _pulseService.startTracking(
            employeeId,
            attendanceId: attendanceId,
            checkInTime: _checkInTime,
          );
        }

        // Start native iOS silent audio to keep app awake in background
        int? shiftEndTimeEpoch;
        if (_checkInTime != null) {
          final prefs = await SharedPreferences.getInstance();
          final personalShiftEnd = prefs.getString('employee_shift_end_time');
          final shiftEndStr = personalShiftEnd ?? 
                              _branchData?['shift_end_time']?.toString() ?? 
                              _branchData?['shift_end']?.toString();
          if (shiftEndStr != null && shiftEndStr.isNotEmpty) {
            final shiftEndDateTime = AttendanceTimerService.getShiftEndTime(_checkInTime!, shiftEndStr);
            shiftEndTimeEpoch = shiftEndDateTime.millisecondsSinceEpoch;
          }
        }
        await NativePulseBridge.startForAttendance(
          employeeId: employeeId,
          attendanceId: attendanceId,
          branchId: branchId,
          shiftEndTimeEpoch: shiftEndTimeEpoch,
        );

        await WorkManagerPulseService.instance.startPeriodicPulses(
          employeeId: employeeId,
          attendanceId: attendanceId,
          branchId: branchId,
        );

        AppLogger.instance.log(
          'Unified Pulse System started on iOS (MANAGER - Native Audio)',
          tag: 'UnifiedPulseManager',
        );
        return;
      }

      // Get manager data for service initialization
      final authData = await AuthService.getLoginData();
      final managerName = authData['fullName'] ?? 'المدير';

      // ✅ LAYER 1: Start PulseTrackingService (Primary Foreground Service)
      print('📍 Layer 1: Starting PulseTrackingService...');
      if (!_pulseService.isTracking) {
        await _pulseService.startTracking(
          employeeId,
          attendanceId: attendanceId,
          checkInTime: _checkInTime,
        );
      }

      // ✅ LAYER 1.5: Start Native Persistent Pulses (Android only)
      print('🛰️ Layer 1.5: Starting NativePulseService...');
      int? shiftEndTimeEpoch;
      if (_checkInTime != null) {
        final prefs = await SharedPreferences.getInstance();
        final personalShiftEnd = prefs.getString('employee_shift_end_time');
        final shiftEndStr = personalShiftEnd ?? 
                            _branchData?['shift_end_time']?.toString() ?? 
                            _branchData?['shift_end']?.toString();
        if (shiftEndStr != null && shiftEndStr.isNotEmpty) {
          final shiftEndDateTime = AttendanceTimerService.getShiftEndTime(_checkInTime!, shiftEndStr);
          shiftEndTimeEpoch = shiftEndDateTime.millisecondsSinceEpoch;
        }
      }
      await NativePulseBridge.startForAttendance(
        employeeId: employeeId,
        attendanceId: attendanceId,
        branchId: branchId,
        shiftEndTimeEpoch: shiftEndTimeEpoch,
      );

      // ✅ LAYER 2: Start ForegroundAttendanceService (Persistent Notification)
      print('🔔 Layer 2: Starting ForegroundAttendanceService...');
      final foregroundService = ForegroundAttendanceService.instance;
      await foregroundService.startTracking(
        employeeId: employeeId,
        employeeName: managerName,
      );
      print('✅ ForegroundAttendanceService started successfully');

      // ✅ LAYER 3: Start AlarmManager (Guaranteed - Even When App Killed)
      print('⏰ Layer 3: Starting AlarmManagerPulseService...');
      final alarmService = AlarmManagerPulseService();
      await alarmService.startPeriodicAlarms(employeeId);
      print('✅ AlarmManagerPulseService started successfully');

      // ✅ LAYER 4: WorkManager disabled here to avoid duplicate pulses.
      print(
        '⏭️ Layer 4: WorkManagerPulseService skipped to avoid duplicate pulses',
      );

      // ✅ LAYER 5: Start AggressiveKeepAlive (For Problematic Devices)
      print('💪 Layer 5: Starting AggressiveKeepAliveService...');
      await AggressiveKeepAliveService().startKeepAlive(employeeId);
      print('✅ AggressiveKeepAliveService started successfully');

      print(
        '🎉 All 5 layers of pulse protection started successfully! (MANAGER)',
      );

      // Log success
      AppLogger.instance.log(
        'Unified Pulse System started with 5-layer protection (MANAGER)',
        tag: 'UnifiedPulseManager',
      );
    } catch (e, stackTrace) {
      print('❌ Error starting unified pulse system (MANAGER): $e');
      print('Stack trace: $stackTrace');

      AppLogger.instance.log(
        'Failed to start unified pulse system (MANAGER)',
        level: AppLogger.error,
        tag: 'UnifiedPulseManager',
        error: e,
      );

      // Don't throw - pulse tracking is secondary to check-in success
      // Manager should still be checked in even if pulse tracking fails
    }
  }

  /// 🛑 PHASE 2: Stop Unified Pulse System (MANAGER)
  /// Stops all 5 layers of pulse tracking services
  Future<void> _stopUnifiedPulseSystem() async {
    print('🛑 PHASE 2: Stopping Unified Pulse System (5 layers) - MANAGER');

    if (kIsWeb) {
      print('⚠️ Web platform - pulse tracking not available');
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      print('⚠️ Unsupported platform for unified pulse system');
      return;
    }

    try {
      if (Platform.isIOS) {
        print('🍎 Stopping iOS unified pulse path (MANAGER)');
        _pulseService.stopTracking();
        await NativePulseBridge.stop();
        await WorkManagerPulseService.instance.stopPeriodicPulses();
        AppLogger.instance.log(
          'Unified Pulse System stopped on iOS (MANAGER)',
          tag: 'UnifiedPulseManager',
        );
        return;
      }

      // ✅ LAYER 1: Stop PulseTrackingService
      print('🛑 Layer 1: Stopping PulseTrackingService...');
      _pulseService.stopTracking();
      print('✅ PulseTrackingService stopped');

      // ✅ LAYER 1.5: Stop Native Persistent Pulses
      print('🛑 Layer 1.5: Stopping NativePulseService...');
      await NativePulseBridge.stop();

      // ✅ LAYER 2: Stop ForegroundAttendanceService
      print('🛑 Layer 2: Stopping ForegroundAttendanceService...');
      try {
        final stopped = await ForegroundAttendanceService.instance
            .stopTracking();
        if (stopped) {
          print('✅ ForegroundAttendanceService stopped successfully');
        } else {
          print('⚠️ ForegroundAttendanceService already stopped');
        }
      } catch (e) {
        print('⚠️ Error stopping ForegroundAttendanceService: $e');
      }

      // ✅ LAYER 3: Stop AlarmManagerPulseService
      print('🛑 Layer 3: Stopping AlarmManagerPulseService...');
      try {
        await AlarmManagerPulseService().stopPeriodicAlarms();
        print('✅ AlarmManagerPulseService stopped successfully');
      } catch (e) {
        print('⚠️ Error stopping AlarmManagerPulseService: $e');
      }

      // ✅ LAYER 4: Stop WorkManagerPulseService
      print('🛑 Layer 4: Stopping WorkManagerPulseService...');
      try {
        await WorkManagerPulseService.instance.stopPeriodicPulses();
        print('✅ WorkManagerPulseService stopped successfully');
      } catch (e) {
        print('⚠️ Error stopping WorkManagerPulseService: $e');
      }

      // ✅ LAYER 5: Stop AggressiveKeepAliveService
      print('🛑 Layer 5: Stopping AggressiveKeepAliveService...');
      try {
        await AggressiveKeepAliveService().stopKeepAlive();
        print('✅ AggressiveKeepAliveService stopped successfully');
      } catch (e) {
        print('⚠️ Error stopping AggressiveKeepAliveService: $e');
      }

      print(
        '🎉 All 5 layers of pulse protection stopped successfully! (MANAGER)',
      );

      // Log success
      AppLogger.instance.log(
        'Unified Pulse System stopped (all 5 layers) - MANAGER',
        tag: 'UnifiedPulseManager',
      );
    } catch (e, stackTrace) {
      print('❌ Error stopping unified pulse system (MANAGER): $e');
      print('Stack trace: $stackTrace');

      AppLogger.instance.log(
        'Failed to stop unified pulse system (MANAGER)',
        level: AppLogger.error,
        tag: 'UnifiedPulseManager',
        error: e,
      );

      // Don't throw - continue with checkout anyway
    }
  }

  /// 🚀 PHASE 3: Show location permission guide to educate user about "Always Allow" permission
  Future<void> _showLocationPermissionGuideIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasShownLocationGuide =
          prefs.getBool('location_permission_guide_shown_manager') ?? false;

      // Only show once per install
      if (!hasShownLocationGuide && mounted) {
        // Check current permission status
        final permission = await Geolocator.checkPermission();

        // Only show if we don't have "always" permission yet
        if (permission != LocationPermission.always) {
          // Mark as shown
          await prefs.setBool('location_permission_guide_shown_manager', true);

          // Show dialog after a short delay (let check-in success message show first)
          await Future.delayed(const Duration(seconds: 3));

          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: true,
              builder: (context) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.blue, size: 28),
                    SizedBox(width: 10),
                    Text('📍 تفعيل التتبع الدائم'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'للحصول على أفضل أداء لنظام تتبع الحضور:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 15),
                    _buildPermissionStep(
                      '1',
                      'اختر "السماح طوال الوقت" (Always Allow)',
                    ),
                    const SizedBox(height: 10),
                    _buildPermissionStep(
                      '2',
                      'هذا يسمح بتتبع حضورك حتى عند إغلاق التطبيق',
                    ),
                    const SizedBox(height: 10),
                    _buildPermissionStep(
                      '3',
                      'سيتم إرسال النبضات تلقائياً في الخلفية',
                    ),
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.privacy_tip,
                            color: Colors.blue[700],
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'نحن نحترم خصوصيتك - يُستخدم الموقع فقط لتتبع الحضور أثناء ساعات العمل',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('حسناً', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            );
          }
        }
      }
    } catch (e) {
      AppLogger.instance.log(
        'Error showing location guide',
        level: AppLogger.warning,
        tag: 'LocationGuideManager',
        error: e,
      );
    }
  }

  Widget _buildPermissionStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    );
  }

  /// 🚀 PHASE 5: Show battery optimization guide for managers
  Future<void> _showBatteryGuideIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasShownGuide =
          prefs.getBool('battery_guide_shown_manager') ?? false;

      // 🚀 PHASE 5: Show for all Android devices
      if (!hasShownGuide && mounted) {
        // Check if battery optimization is already disabled
        final batteryStatus =
            await Permission.ignoreBatteryOptimizations.status;

        // Only show if not already granted
        if (!batteryStatus.isGranted) {
          // Mark as shown
          await prefs.setBool('battery_guide_shown_manager', true);

          // Show dialog after location guide (5 seconds delay)
          await Future.delayed(const Duration(seconds: 5));

          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: true,
              builder: (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(
                      Icons.battery_charging_full,
                      color: Colors.orange[700],
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    const Text('🔋 تحسين أداء التطبيق'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'لضمان عمل تتبع الحضور بشكل مثالي:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 15),
                    _buildBatteryStep('1', 'تعطيل تحسين البطارية للتطبيق'),
                    const SizedBox(height: 10),
                    _buildBatteryStep(
                      '2',
                      'يضمن استمرار إرسال النبضات في الخلفية',
                    ),
                    const SizedBox(height: 10),
                    _buildBatteryStep(
                      '3',
                      'لن يستنزف البطارية - التطبيق مُحسّن',
                    ),
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange[700],
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'مهم خاصة لأجهزة Samsung و Xiaomi و Realme',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'لاحقاً',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      // Request permission directly
                      final status = await Permission.ignoreBatteryOptimizations
                          .request();

                      if (status.isGranted && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '✅ تم تعطيل تحسين البطارية - الأداء سيكون ممتاز!',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[700],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('تفعيل الآن'),
                  ),
                ],
              ),
            );
          }
        }
      }
    } catch (e) {
      AppLogger.instance.log(
        'Error showing battery guide',
        level: AppLogger.warning,
        tag: 'BatteryGuideManager',
        error: e,
      );
    }
  }

  Widget _buildBatteryStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.orange[700],
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    );
  }

  Future<void> _handleCheckIn() async {
    setState(() => _isLoading = true);

    try {
      // 🔒 Hard Permission Check - يجب أن تمر جميع الفحوصات
      if (!kIsWeb) {
        final hasAllPermissions = await checkHardPermissions();
        if (!hasAllPermissions) {
          setState(() => _isLoading = false);
          return; // توقف هنا
        }
      }

      print('🚀 Manager check-in started...');

      // Create a simple employee object for validation
      final employee = Employee(
        id: widget.managerId,
        fullName: 'المدير', // Name not critical for validation
        pin: '',
        role: EmployeeRole.manager,
        branch: _branchData?['name'] ?? 'الفرع',
      );

      print('⏳ Starting validation for Manager with dialog...');
      if (!mounted) return;
      final validation = await showDialog<GeofenceValidationResult?>(
        context: context,
        barrierDismissible: false,
        builder: (context) => LocationVerificationDialog(employee: employee),
      );

      if (validation == null) {
        print('❌ Validation canceled or failed for Manager!');
        throw Exception('تم إلغاء التحقق من الموقع أو فشل الجلب');
      }

      print('📊 Validation Result: ${validation.isValid}');
      print('💬 Message: ${validation.message}');

      if (!validation.isValid) {
        throw Exception(validation.message);
      }

      print('✅ Validation passed: ${validation.message}');

      // Use validated position and BSSID
      final position = validation.position;
      var wifiBSSID = validation.bssid;

      // If BSSID is null but we're connected to WiFi, try to get it (best effort)
      if (wifiBSSID == null && !kIsWeb) {
        try {
          wifiBSSID = await WiFiService.getCurrentWifiBssidValidated();
        } catch (e) {
          print('⚠️ Could not get BSSID: $e');
        }
      }

      final latitude = position?.latitude ?? 0.0;
      final longitude = position?.longitude ?? 0.0;

      final response = await SupabaseAttendanceService.checkIn(
        employeeId: widget.managerId,
        latitude: latitude,
        longitude: longitude,
        wifiBssid: wifiBSSID,
        branchId: validation.branchId,
        distance: validation.distance,
      );

      if (response == null) {
        throw Exception('فشل تسجيل الحضور');
      }

      final attendanceId = response['id'] as String?;
      _currentAttendanceId = attendanceId;

      // Cache active attendance ID on device for safe offline retrieval
      if (attendanceId != null && attendanceId.isNotEmpty) {
        await SupabaseAttendanceService.cacheActiveAttendanceOnDevice(
          employeeId: widget.managerId,
          attendanceId: attendanceId,
          checkInIso: response['check_in_time']?.toString() ?? DateTime.now().toIso8601String(),
          isOfflineAttendance: false,
        );
      }

      DateTime checkInTime;
      try {
        final serverCheckIn = response['check_in_time']?.toString();
        if (serverCheckIn != null && serverCheckIn.isNotEmpty) {
          checkInTime = DateTime.parse(serverCheckIn).toLocal();
        } else {
          checkInTime = DateTime.now();
        }
      } catch (_) {
        checkInTime = DateTime.now();
      }

      setState(() {
        _isCheckedIn = true;
        _checkInTime = checkInTime;
        _isLoading = false;
      });

      _startTimer();

      // ✅ Start pulse tracking when check-in succeeds
      if (attendanceId != null) {
        await _ensurePulseTrackingActive(
          employeeId: widget.managerId,
          attendanceId: attendanceId,
          checkInTime: checkInTime,
        );
        AppLogger.instance.log(
          'Started pulse tracking after manager check-in',
          tag: 'ManagerCheckIn',
        );
      }

      _updateDistanceFromBranch();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تم تسجيل الحضور بنجاح'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // 🚀 PHASE 3: Show location permission guide (educate about "Always Allow")
        // 🚀 PHASE 5: Show battery optimization guide
        if (!kIsWeb && Platform.isAndroid) {
          _showLocationPermissionGuideIfNeeded();
          _showBatteryGuideIfNeeded();
        }
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
    // ✅ Guard against double-tap
    if (_isLoading) {
      print('⚠️ Check-out already in progress, ignoring...');
      return;
    }

    setState(() => _isLoading = true);

    try {
      print('🚪 Manager check-out started...');

      // 🚀 PHASE 6: Try to sync pending pulses before check-out
      if (!kIsWeb) {
        try {
          print('🔄 Syncing pending pulses before check-out...');
          final syncResult = await SyncService.instance.forceSyncNow();
          if (syncResult['success'] == true && syncResult['synced'] > 0) {
            print(
              '✅ Synced ${syncResult['synced']} pending records before check-out',
            );

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ تم رفع ${syncResult['synced']} نبضة محلية'),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        } catch (e) {
          print('⚠️ Sync before check-out failed (will try again later): $e');
        }
      }

      // ✅ STEP 1: Get active attendance (local first, then server)
      String? attendanceId = _currentAttendanceId;
      Map<String, dynamic>? activeAttendanceRecord;
      bool isOfflineAttendance = false;

      if (attendanceId == null) {
        print(
          '🔍 No local attendance_id in memory, checking SharedPreferences...',
        );

        // ✅ Check SharedPreferences for offline attendance
        final prefs = await SharedPreferences.getInstance();
        final savedAttendanceId = prefs.getString('active_attendance_id');
        isOfflineAttendance = prefs.getBool('is_offline_attendance') ?? false;

        if (savedAttendanceId != null && savedAttendanceId.isNotEmpty) {
          attendanceId = savedAttendanceId;
          print(
            '📱 Found saved attendance_id: $attendanceId (offline: $isOfflineAttendance)',
          );
        } else {
          // Try server as last resort
          print('🌐 Checking server for active attendance...');
          try {
            activeAttendanceRecord =
                await SupabaseAttendanceService.getActiveAttendance(
              widget.managerId,
            );
            if (activeAttendanceRecord != null) {
              attendanceId = activeAttendanceRecord['id'] as String;
              print('✅ Found active attendance on server: $attendanceId');
            }
          } catch (e) {
            print('⚠️ Server check failed: $e');
          }
        }

        if (attendanceId == null) {
          if (_isCheckedIn) {
            print('⚠️ Failsafe: UI is checked-in but attendanceId is null. Allowing checkout.');
          } else {
            throw Exception('لا يوجد سجل حضور نشط\nيرجى تسجيل الحضور أولاً');
          }
        }
      } else {
        // Check if current attendance is offline
        final prefs = await SharedPreferences.getInstance();
        isOfflineAttendance =
            prefs.getBool('is_offline_attendance') ??
            attendanceId.startsWith('offline_');
      }

      print(
        '📋 Using attendance_id: $attendanceId (offline: $isOfflineAttendance)',
      );

      // ✅ STEP 2: Create employee object for validation
      final employee = Employee(
        id: widget.managerId,
        fullName: 'المدير',
        pin: '',
        role: EmployeeRole.manager,
        branch: _branchData?['name'] ?? 'الفرع',
      );

      // ✅ STEP 3: Use the same flexible validation as check-in
      print('⏳ Starting checkout validation for Manager...');
      final validation = await GeofenceService.validateForCheckOut(employee);

      print('📊 Checkout Validation Result: ${validation.isValid}');
      print('💬 Message: ${validation.message}');

      if (!validation.isValid) {
        throw Exception(validation.message);
      }

      // ✅ SIMPLIFIED: Get position from validation or use defaults
      double latitude = 0.0;
      double longitude = 0.0;

      if (validation.position != null) {
        latitude = validation.position!.latitude;
        longitude = validation.position!.longitude;
        print('📍 Using validated position: $latitude, $longitude');
      } else {
        // WiFi validation passed - use branch location (no need to wait for GPS)
        print('📍 WiFi validated - using branch location');
        latitude =
            _branchData?['latitude']?.toDouble() ?? RestaurantConfig.latitude;
        longitude =
            _branchData?['longitude']?.toDouble() ?? RestaurantConfig.longitude;
        print('📍 Using branch location: $latitude, $longitude');
      }

      final double calculatedWorkHours = _timerService.calculateWorkedSeconds() / 3600.0;
      print('⏱️ Calculated worked hours for manager checkout: $calculatedWorkHours');

      // Try online mode first, fallback to offline if it fails
      bool checkOutSuccess = false;

      // Try online mode first
      try {
        print('🌐 Attempting online check-out');

        // Get WiFi BSSID if available
        String? wifiBSSID = validation.bssid;
        if (wifiBSSID == null && !kIsWeb) {
          try {
            wifiBSSID = await WiFiService.getCurrentWifiBssidValidated();
            print('📶 Got WiFi BSSID for check-out: $wifiBSSID');
          } catch (e) {
            print('⚠️ Could not get WiFi BSSID: $e');
          }
        }

        final success = await SupabaseAttendanceService.checkOut(
          attendanceId: attendanceId,
          employeeId: widget.managerId,
          latitude: latitude,
          longitude: longitude,
          wifiBssid: wifiBSSID,
          workHours: calculatedWorkHours,
        );

        if (success) {
          checkOutSuccess = true;
          print('✅ Online check-out successful');

          // Update daily attendance with check-out time
          try {
            final employeeData =
                await SupabaseAttendanceService.getEmployeeStatus(
              widget.managerId,
            );
            final emp = employeeData['employee'];

            if (activeAttendanceRecord == null) {
              activeAttendanceRecord =
                  await SupabaseAttendanceService.getActiveAttendance(
                widget.managerId,
              );
            }

            if (emp != null &&
                emp['hourly_rate'] != null) {
              final hourlyRate =
                  (emp['hourly_rate'] as num?)?.toDouble() ?? 0.0;
              final checkOutTimeStr = TimeOfDay.now().format(context);

              // Get check-in time from active attendance (with safe parsing)
              DateTime? checkInDateTime = _checkInTime;
              if (activeAttendanceRecord != null && activeAttendanceRecord!['check_in_time'] != null) {
                try {
                  checkInDateTime = DateTime.parse(
                    activeAttendanceRecord!['check_in_time'].toString(),
                  );
                } catch (e) {
                  checkInDateTime = _checkInTime;
                }
              }
              final checkInTimeStr = checkInDateTime != null
                  ? TimeOfDay.fromDateTime(checkInDateTime).format(context)
                  : TimeOfDay.now().format(context);

              await PayrollService().syncDailyAttendance(
                employeeId: widget.managerId,
                date: DateTime.now(),
                checkInTime: checkInTimeStr,
                checkOutTime: checkOutTimeStr,
                hourlyRate: hourlyRate,
                workHoursOverride: calculatedWorkHours,
              );
            }
          } catch (e) {
            print('⚠️ Error in post-check-out tasks: $e');
          }
        }
      } catch (e) {
        print('⚠️ Online check-out failed: $e');
        print('📴 Falling back to offline mode...');
      }

      // If online failed, save offline
      if (!checkOutSuccess) {
        if (kIsWeb) {
          throw Exception(
            'فشل تسجيل الانصراف.\n'
            'يرجى التحقق من اتصالك بالإنترنت والمحاولة مرة أخرى.',
          );
        }

        // Mobile: Save offline
        print('📴 Saving check-out offline');
        final db = OfflineDatabase.instance;
        final hasCachedData = await db.hasCachedBranchData(widget.managerId);

        // Resolve attendance_id from memory or device cache before saving offline checkout
        String? targetAttendanceId = attendanceId;
        if (targetAttendanceId == null || targetAttendanceId.isEmpty) {
          final snapshot =
              await SupabaseAttendanceService.getCachedActiveAttendanceOnDevice(
                employeeId: widget.managerId,
              );
          targetAttendanceId = snapshot?['attendance_id']?.toString();
        }

        // Refuse to save an un-targeted offline checkout without a valid attendance_id
        if (targetAttendanceId == null || targetAttendanceId.isEmpty) {
          print('❌ Cannot queue offline checkout without a resolved attendance_id');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'لم نتمكن من تحديد جلسة الحضور الخاصة بك، يرجى المحاولة عند توفر الإنترنت.',
                ),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }

        await db.insertPendingCheckout(
          employeeId: widget.managerId,
          attendanceId: targetAttendanceId,
          timestamp: DateTime.now(),
          latitude: latitude,
          longitude: longitude,
          workHours: calculatedWorkHours,
        );

        // Start sync service if not already running
        final syncService = SyncService.instance;
        syncService.startPeriodicSync();

        if (hasCachedData) {
          await NotificationService.instance.showOfflineModeNotification();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                hasCachedData
                    ? '📴 تم حفظ الانصراف محلياً - سيتم الرفع عند توفر الإنترنت'
                    : '✓ تم تسجيل الانصراف محلياً',
              ),
              backgroundColor: hasCachedData
                  ? AppColors.warning
                  : AppColors.success,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        // Online check-out successful
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                validation.message.contains('⚠️')
                    ? '✓ تم تسجيل الانصراف (${validation.message})'
                    : '✓ تم تسجيل الانصراف بنجاح',
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      // 🚀 PHASE 2: Stop unified pulse system (all 5 layers)
      await _stopUnifiedPulseSystem();
      print('🛑 Stopped unified pulse system after manager check-out');

      setState(() {
        _isCheckedIn = false;
        _checkInTime = null;
        _elapsedTime = '00:00:00';
        _isLoading = false;
        _currentAttendanceId = null;
      });

      _timer?.cancel();
      _timerService.stopTimer();

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

  // ignore: unused_element
  void _showAttendanceRequestDialog() async {
    final today = DateTime.now();
    final requests = await RequestsApiService.fetchAttendanceRequests(
      widget.managerId,
    );
    final hasTodayRequest = requests.any(
      (r) =>
          r.requestedTime.year == today.year &&
          r.requestedTime.month == today.month &&
          r.requestedTime.day == today.day &&
          r.status == RequestStatus.pending,
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
                      borderSide: const BorderSide(
                        color: AppColors.primaryOrange,
                        width: 2,
                      ),
                    ),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'وقت الحضور:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
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
                              today.year,
                              today.month,
                              today.day,
                              picked.hour,
                              picked.minute,
                            );
                          });
                        }
                      },
                      child: Text(
                        selectedTime != null
                            ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                            : '--:--',
                      ),
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
    try {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
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
                              // Debug buttons
                              IconButton(
                                icon: const Icon(
                                  Icons.bug_report,
                                  color: Colors.white,
                                ),
                                tooltip: 'تشخيص الموقع',
                                onPressed: _showDiagnosticDialog,
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.help_outline,
                                  color: Colors.white,
                                ),
                                tooltip: 'مساعدة الموقع',
                                onPressed: () {
                                  DeviceCompatibilityService.instance
                                      .showPermissionGuideDialog(context);
                                },
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
                                branchName:
                                    _branchData?['branch_name'] ?? 'الفرع',
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

                    const SizedBox(height: 16),

                    // Branch Manager Dashboard Card
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          final branchName = _getBranchName();
                          if (branchName == null || branchName.isEmpty) {
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
                              builder: (_) => BranchManagerScreen(
                                branchName: branchName,
                                managerId: widget.managerId,
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
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.dashboard,
                                  color: Colors.blue,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'لوحة مدير الفرع',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'متابعة الطلبات والحضور والنبضات',
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

                    const SizedBox(height: 16),

                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          final branchName = _getBranchName();
                          if (branchName == null || branchName.isEmpty) {
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
                              builder: (_) => ManagerDashboardSimple(
                                managerId: widget.managerId,
                                branchName: branchName,
                                initialTabIndex: 3,
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
                                  color: AppColors.success.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.fact_check_outlined,
                                  color: AppColors.success,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'الجدول الحضوري اليومي',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'عرض وتعديل حضور كل موظفي الفرع بسرعة',
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

                    const SizedBox(height: 16),

                    // Session Validation Card
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SessionValidationPage(),
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
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.verified_user,
                                  color: Colors.orange,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'طلبات التحقق من الحضور',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'الموافقة أو الرفض على طلبات الموظفين',
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
                                  _isCheckedIn
                                      ? Icons.work
                                      : Icons.work_outline,
                                  color: _isCheckedIn
                                      ? AppColors.success
                                      : AppColors.textTertiary,
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
                                        color: _isCheckedIn
                                            ? AppColors.success
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      (_isCheckingStatus &&
                                              !_hasCompletedInitialStatusCheck)
                                          ? 'جاري التحقق من حالة الحضور...'
                                          : _isCheckedIn
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
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF4EA),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          children: [
                                            Text(
                                              'مدة العمل المحتسبة',
                                              style: GoogleFonts.tajawal(
                                                fontSize: 13,
                                                color: AppColors.textSecondary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              _timerService.elapsedTime,
                                              style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.primaryOrange,
                                                fontFeatures: [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        height: 40,
                                        width: 1,
                                        color: Colors.orange.withOpacity(0.2),
                                      ),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            Text(
                                              (_branchData?['shift_end_time'] == null || _branchData?['shift_end_time']?.toString().isEmpty == true)
                                                  ? 'الوقت المنقضي بالوردية'
                                                  : 'المتبقي على الشيفت',
                                              style: GoogleFonts.tajawal(
                                                fontSize: 13,
                                                color: AppColors.textSecondary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              _timerService.shiftCountdown,
                                              style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.blue.shade700,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _distanceFromBranch != null
                                        ? 'المسافة الحالية عن الفرع: ${_distanceFromBranch!.toStringAsFixed(0)} متر'
                                        : 'جاري تحديد المسافة عن الفرع...',
                                    style: GoogleFonts.tajawal(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (_isCheckedIn && (_timerService.isPausedDueToOutside || !_pulseService.isCurrentlyInside)) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                        horizontal: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.danger.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.pause_circle_filled_rounded,
                                            color: AppColors.danger,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _timerService.isPausedDueToOutside
                                                ? 'الوقت متوقف مؤقتاً (${_timerService.pausedReason})'
                                                : 'الوقت متوقف مؤقتاً (خارج النطاق)',
                                            style: GoogleFonts.tajawal(
                                              color: AppColors.danger,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
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
                        onPressed: (_isLoading || _isCheckingStatus)
                            ? null
                            : (_isCheckedIn ? _handleCheckOut : _handleCheckIn),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isCheckedIn
                              ? AppColors.error
                              : AppColors.primaryOrange,
                          disabledBackgroundColor: AppColors.textTertiary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: (_isLoading || _isCheckingStatus)
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
                                    _isCheckedIn
                                        ? 'تسجيل الانصراف'
                                        : 'تسجيل الحضور',
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
                              builder: (context) => ManagerSendRequestsPage(
                                managerId: widget.managerId,
                              ),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryOrange,
                          side: const BorderSide(
                            color: AppColors.primaryOrange,
                            width: 2,
                          ),
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
                            side: const BorderSide(
                              color: AppColors.primaryOrange,
                              width: 2,
                            ),
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

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
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
                                  color: AppColors.primaryOrange.withOpacity(
                                    0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.person_add_alt_1,
                                  color: AppColors.primaryOrange,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'إضافة موظف جديد',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _getBranchName() != null
                                          ? 'سيتم ربط الموظف بفرع ${_getBranchName()} تلقائياً'
                                          : 'يرجى التأكد من تحميل بيانات الفرع قبل إضافة موظف',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                final branchName = _getBranchName();
                                if (branchName == null || branchName.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'خطأ: لا يوجد فرع مرتبط بحسابك',
                                      ),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                  return;
                                }
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ManagerAddEmployeePage(
                                      managerId: widget.managerId,
                                      managerBranch: branchName,
                                    ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryOrange,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text(
                                'إضافة موظف للفرع',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ), // Column
              ), // SingleChildScrollView
            ), // ConstrainedBox
          ), // Center
        ), // SafeArea
      ); // Scaffold
    } catch (e, stackTrace) {
      print('❌ Error building ManagerHomePage: $e');
      print('Stack trace: $stackTrace');
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'حدث خطأ في تحميل الصفحة الرئيسية',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'الخطأ: ${e.toString()}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {});
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
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

  // ignore: unused_element
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
