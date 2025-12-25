import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

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
import '../../services/foreground_attendance_service.dart' hide TimeOfDay;
import '../../services/workmanager_pulse_service.dart';
import '../../services/alarm_manager_pulse_service.dart';
import '../../services/aggressive_keep_alive_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_logger.dart';
import '../../services/device_compatibility_service.dart';
import '../../services/checkout_debug_service.dart';
import '../../database/offline_database.dart';
import '../../theme/app_colors.dart';
import 'manager_send_requests_page.dart';
import 'manager_employees_page.dart';
import 'manager_add_employee_page.dart';
import 'session_validation_page.dart';
import '../branch_manager_screen.dart';

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
  String? _branchId;
  Map<String, dynamic>? _branchData;
  List<String> _allowedBssids = [];
  String? _currentAttendanceId;
  
  final _offlineService = OfflineDataService();
  final _pulseService = PulseTrackingService();
  
  // 🚨 NEW: Subscription for auto-checkout events
  StreamSubscription<AutoCheckoutEvent>? _autoCheckoutSubscription;

  @override
  void initState() {
    super.initState();
    try {
      _loadBranchData().catchError((e) {
        print('❌ Error loading branch data: $e');
      }); // Load branch data first
      _checkCurrentStatus().catchError((e) {
        print('❌ Error checking current status: $e');
      });
      
      // 🚨 NEW: Listen to auto-checkout events for immediate UI update
      _autoCheckoutSubscription = _pulseService.onAutoCheckout.listen(_handleAutoCheckout);
    } catch (e, stackTrace) {
      print('❌ Error in ManagerHomePage initState: $e');
      print('Stack trace: $stackTrace');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _autoCheckoutSubscription?.cancel(); // 🚨 Cancel auto-checkout subscription
    super.dispose();
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
            Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 28),
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
      
      // Get employee data to find branch
      final employeeData = await SupabaseAttendanceService.getEmployeeStatus(widget.managerId);
      
      // ✅ First try branch_id (more reliable), then fallback to branch name
      final branchIdFromEmployee = employeeData['employee']?['branch_id'];
      final branchName = employeeData['employee']?['branch'] ?? 
                        employeeData['employee']?['branch_name'];
      
      // Store branch_id if available
      if (branchIdFromEmployee != null && branchIdFromEmployee.toString().isNotEmpty) {
        _branchId = branchIdFromEmployee.toString();
        print('📍 [Manager] Branch ID from employee: $_branchId');
        
        // Fetch branch data by ID
        try {
          final branchData = await BranchApiService.getBranchById(branchIdFromEmployee.toString());
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
      
      print('✅ [Manager] Found branch: ${branchData['name']} (${branchData['id']})');
      
      await _processBranchData(branchData, db);
    } catch (e) {
      print('❌ [Manager] Error loading branch data: $e');
    }
  }

  /// Helper to process and cache branch data
  Future<void> _processBranchData(Map<String, dynamic> branchData, OfflineDatabase db) async {
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
    
    // Also check direct lat/lng
    latitude ??= (branchData['latitude'] as num?)?.toDouble();
    longitude ??= (branchData['longitude'] as num?)?.toDouble();
    
    final geofenceRadius = (branchData['geofence_radius'] ?? 
                           branchData['geofenceRadius'] ?? 
                           100.0).toDouble();
    
    // Cache it locally for future use
    int dataVersion = 1;
    if (branchData['updated_at'] != null) {
      try {
        dataVersion = DateTime.parse(branchData['updated_at'].toString()).millisecondsSinceEpoch ~/ 1000;
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
    
    print('✅ [Manager] Fetched and cached branch data: ${branchData['name']} (${wifiBssids.length} WiFi networks)');
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
                  hourlyRate: double.tryParse(hourlyRateController.text.trim()) ?? 0,
                  role: selectedRole,
                  email: emailController.text.trim().isEmpty ? null : emailController.text.trim(),
                  phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                );

                if (!mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم إضافة ${nameController.text.trim()} للفرع $branchName'),
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
                            child: const Icon(Icons.person_add_alt_1, color: AppColors.primaryOrange),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'إضافة موظف جديد',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'سيتم ربط الموظف أوتوماتيكياً بفرع $branchName',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
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
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.person_add_alt_1),
                          label: Text(isSubmitting ? 'جاري الإضافة...' : 'إضافة الموظف'),
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
    try {
      // ✅ Use Supabase directly like employee page (fixes "No host specified in URI" error)
      print('🔄 Checking current attendance status for manager: ${widget.managerId}');
      final status = await SupabaseAttendanceService.getEmployeeStatus(widget.managerId);
      
      final wasCheckedIn = _isCheckedIn;
      setState(() {
        _isCheckedIn = status['isCheckedIn'] as bool? ?? false;
        // Parse checkInTime and convert from UTC to local time (with safe parsing)
        if (status['attendance']?['check_in_time'] != null) {
          try {
            _checkInTime = DateTime.parse(status['attendance']['check_in_time'].toString()).toLocal();
          } catch (e) {
            _checkInTime = null;
          }
        } else {
          _checkInTime = null;
        }
        
        // ✅ Clear if checked out
        if (!_isCheckedIn) {
          _timer?.cancel();
        }
      });
      
      print('✅ Manager status updated: isCheckedIn=$_isCheckedIn (was: $wasCheckedIn)');
      
      // Load branch data if available
      if (_branchId != null && _branchId!.isNotEmpty) {
        try {
          final branchResponse = await BranchApiService.getBranchById(_branchId!);
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
      print('❌ Error checking manager status: $e');
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
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                DeviceCompatibilityService.instance.showPermissionGuideDialog(context);
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
    print('🚀 PHASE 2: Starting Unified Pulse System with 5-Layer Protection (MANAGER)');
    print('   Manager ID: $employeeId');
    print('   Attendance: $attendanceId');
    print('   Branch: $branchId');
    
    if (kIsWeb) {
      print('⚠️ Web platform - pulse tracking not available');
      return;
    }
    
    if (!Platform.isAndroid) {
      print('⚠️ Non-Android platform - pulse tracking limited');
      return;
    }
    
    try {
      // Get manager data for service initialization
      final authData = await AuthService.getLoginData();
      final managerName = authData['fullName'] ?? 'المدير';
      
      // ✅ LAYER 1: Start PulseTrackingService (Primary Foreground Service)
      print('📍 Layer 1: Starting PulseTrackingService...');
      // Note: PulseTrackingService is started via ForegroundAttendanceService
      
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
      
      // ✅ LAYER 4: Start WorkManager (15-Min Backup for Old Devices)
      print('🔄 Layer 4: Starting WorkManagerPulseService...');
      await WorkManagerPulseService.instance.startPeriodicPulses(
        employeeId: employeeId,
        attendanceId: attendanceId,
        branchId: branchId,
      );
      print('✅ WorkManagerPulseService started successfully');
      
      // ✅ LAYER 5: Start AggressiveKeepAlive (For Problematic Devices)
      print('💪 Layer 5: Starting AggressiveKeepAliveService...');
      await AggressiveKeepAliveService().startKeepAlive(employeeId);
      print('✅ AggressiveKeepAliveService started successfully');
      
      print('🎉 All 5 layers of pulse protection started successfully! (MANAGER)');
      
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
    
    if (!Platform.isAndroid) {
      print('⚠️ Non-Android platform - pulse tracking limited');
      return;
    }
    
    try {
      // ✅ LAYER 1: Stop PulseTrackingService
      print('🛑 Layer 1: Stopping PulseTrackingService...');
      _pulseService.stopTracking();
      print('✅ PulseTrackingService stopped');
      
      // ✅ LAYER 2: Stop ForegroundAttendanceService
      print('🛑 Layer 2: Stopping ForegroundAttendanceService...');
      try {
        final stopped = await ForegroundAttendanceService.instance.stopTracking();
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
      
      print('🎉 All 5 layers of pulse protection stopped successfully! (MANAGER)');
      
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
      final hasShownLocationGuide = prefs.getBool('location_permission_guide_shown_manager') ?? false;
      
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
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 15),
                    _buildPermissionStep('1', 'اختر "السماح طوال الوقت" (Always Allow)'),
                    const SizedBox(height: 10),
                    _buildPermissionStep('2', 'هذا يسمح بتتبع حضورك حتى عند إغلاق التطبيق'),
                    const SizedBox(height: 10),
                    _buildPermissionStep('3', 'سيتم إرسال النبضات تلقائياً في الخلفية'),
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
                          Icon(Icons.privacy_tip, color: Colors.blue[700], size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'نحن نحترم خصوصيتك - يُستخدم الموقع فقط لتتبع الحضور أثناء ساعات العمل',
                              style: TextStyle(fontSize: 12, color: Colors.black87),
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
      AppLogger.instance.log('Error showing location guide', level: AppLogger.warning, tag: 'LocationGuideManager', error: e);
    }
  }

  Widget _buildPermissionStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  /// 🚀 PHASE 5: Show battery optimization guide for managers
  Future<void> _showBatteryGuideIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasShownGuide = prefs.getBool('battery_guide_shown_manager') ?? false;
      
      // 🚀 PHASE 5: Show for all Android devices
      if (!hasShownGuide && mounted) {
        // Check if battery optimization is already disabled
        final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
        
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
                    Icon(Icons.battery_charging_full, color: Colors.orange[700], size: 28),
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
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 15),
                    _buildBatteryStep('1', 'تعطيل تحسين البطارية للتطبيق'),
                    const SizedBox(height: 10),
                    _buildBatteryStep('2', 'يضمن استمرار إرسال النبضات في الخلفية'),
                    const SizedBox(height: 10),
                    _buildBatteryStep('3', 'لن يستنزف البطارية - التطبيق مُحسّن'),
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
                          Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'مهم خاصة لأجهزة Samsung و Xiaomi و Realme',
                              style: TextStyle(fontSize: 12, color: Colors.black87),
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
                    child: const Text('لاحقاً', style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      // Request permission directly
                      final status = await Permission.ignoreBatteryOptimizations.request();
                      
                      if (status.isGranted && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ تم تعطيل تحسين البطارية - الأداء سيكون ممتاز!'),
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
      AppLogger.instance.log('Error showing battery guide', level: AppLogger.warning, tag: 'BatteryGuideManager', error: e);
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
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  Future<void> _handleCheckIn() async {
    setState(() => _isLoading = true);

    try {
      print('🚀 Manager check-in started...');
      
      // Create a simple employee object for validation
      final employee = Employee(
        id: widget.managerId,
        fullName: 'المدير', // Name not critical for validation
        pin: '',
        role: EmployeeRole.manager,
        branch: _branchData?['name'] ?? 'الفرع',
      );

      print('⏳ Starting validation for Manager...');
      final validation = await GeofenceService.validateForCheckIn(employee);

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

      setState(() {
        _isCheckedIn = true;
        _checkInTime = DateTime.now();
        _isLoading = false;
      });

      _startTimer();

      // ✅ Start pulse tracking when check-in succeeds
      if (_branchData != null) {
        await _pulseService.startTracking(
          widget.managerId, 
          attendanceId: attendanceId,
        );
        AppLogger.instance.log('Started pulse tracking after manager check-in', tag: 'ManagerCheckIn');
        
        // 🚀 PHASE 2: Start unified pulse system (all 5 layers)
        if (!kIsWeb && Platform.isAndroid && _branchData != null && attendanceId != null) {
          final branchIdForPulse = validation.branchId ?? _branchData!['id']?.toString() ?? _branchData!['branch_id']?.toString();
          if (branchIdForPulse != null) {
            await _startUnifiedPulseSystem(
              employeeId: widget.managerId,
              attendanceId: attendanceId,
              branchId: branchIdForPulse,
            );
            
            // 🚀 PHASE 6: Start sync service for offline pulses
            SyncService.instance.startPeriodicSync();
            print('✅ Started sync service for offline pulses (Manager)');
          }
        }
      }

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
            print('✅ Synced ${syncResult['synced']} pending records before check-out');
            
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
      
      // ✅ STEP 1: Get active attendance first (before validation)
      final activeAttendance = await SupabaseAttendanceService.getActiveAttendance(widget.managerId);
      
      if (activeAttendance == null) {
        throw Exception('لا يوجد سجل حضور نشط');
      }

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

      // ✅ FIXED: validateForCheckOut now always returns isValid=true
      // It's flexible and allows checkout even if location checks fail
      
      var wifiBSSID = validation.bssid;
      
      // Try to get BSSID if not already available
      if (wifiBSSID == null && !kIsWeb) {
        try {
          wifiBSSID = await WiFiService.getCurrentWifiBssidValidated();
          print('📶 Got WiFi BSSID: $wifiBSSID');
        } catch (e) {
          print('⚠️ Could not get BSSID: $e');
        }
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
        latitude = _branchData?['latitude']?.toDouble() ?? RestaurantConfig.latitude;
        longitude = _branchData?['longitude']?.toDouble() ?? RestaurantConfig.longitude;
        print('📍 Using branch location: $latitude, $longitude');
      }

      print('✅ Proceeding with checkout - lat: $latitude, lng: $longitude');

      final success = await SupabaseAttendanceService.checkOut(
        attendanceId: activeAttendance['id'],
        latitude: latitude,
        longitude: longitude,
        wifiBssid: wifiBSSID,
      );

      if (!success) {
        throw Exception('فشل تسجيل الانصراف');
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(validation.message.contains('⚠️') 
                ? '✓ تم تسجيل الانصراف (${validation.message})'
                : '✓ تم تسجيل الانصراف بنجاح'),
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

  // ignore: unused_element
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
    try {
      return Scaffold(
        backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
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
                          icon: const Icon(Icons.bug_report, color: Colors.white),
                          tooltip: 'تشخيص الموقع',
                          onPressed: _showDiagnosticDialog,
                        ),
                        IconButton(
                          icon: const Icon(Icons.help_outline, color: Colors.white),
                          tooltip: 'مساعدة الموقع',
                          onPressed: () {
                            DeviceCompatibilityService.instance.showPermissionGuideDialog(context);
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
                            color: AppColors.primaryOrange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person_add_alt_1, color: AppColors.primaryOrange, size: 26),
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
                                content: Text('خطأ: لا يوجد فرع مرتبط بحسابك'),
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
                          padding: const EdgeInsets.symmetric(vertical: 16),
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
                  const Icon(Icons.error_outline, size: 64, color: AppColors.error),
                  const SizedBox(height: 16),
                  const Text(
                    'حدث خطأ في تحميل الصفحة الرئيسية',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'الخطأ: ${e.toString()}',
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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