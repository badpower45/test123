import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:universal_io/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

import '../../constants/restaurant_config.dart';
import '../../models/employee.dart';
import '../../services/branch_api_service.dart';
import '../../services/requests_api_service.dart';
import '../../services/sync_service.dart';
import '../../services/notification_service.dart';
import '../../services/auth_service.dart';
import '../../services/geofence_service.dart';
import '../../services/supabase_attendance_service.dart';
import '../../services/absence_service.dart';
import '../../services/payroll_service.dart';
import '../../services/offline_data_service.dart';
import '../../services/supabase_function_client.dart';
import '../../services/pulse_tracking_service.dart';
import '../../services/workmanager_pulse_service.dart';
import '../../services/foreground_attendance_service.dart' hide TimeOfDay;
import '../../services/alarm_manager_pulse_service.dart';
import '../../services/session_validation_service.dart';
import '../../services/app_logger.dart';
import '../../services/device_compatibility_service.dart';
import '../../services/checkout_debug_service.dart';
import '../../services/aggressive_keep_alive_service.dart';
import '../../database/offline_database.dart';
import '../../services/wifi_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/battery_optimization_guide.dart';
import 'logs_viewer_page.dart';

class EmployeeHomePage extends StatefulWidget {
  final String employeeId;

  const EmployeeHomePage({super.key, required this.employeeId});

  @override
  State<EmployeeHomePage> createState() => _EmployeeHomePageState();
}

class _EmployeeHomePageState extends State<EmployeeHomePage> {
  bool _isCheckedIn = false;
  DateTime? _checkInTime;
  String _elapsedTime = '00:00:00';
  Timer? _timer;
  bool _isLoading = false;
  int _pendingCount = 0;
  Map<String, dynamic>? _branchData;
  List<String> _allowedBssids = [];
  bool _isDataDownloaded = false;
  bool _isSyncing = false;
  
  // Live earnings state (used internally)
  double _hourlyRate = 0.0;
  double _currentEarnings = 0.0;
  
  // ✅ NEW: Store attendance_id locally for check-out
  String? _currentAttendanceId;
  // ✅ NEW: Track if we started an optimistic local timer before server success
  bool _optimisticCheckInStarted = false;
  
  final _offlineService = OfflineDataService();
  final _pulseService = PulseTrackingService();
  Timer? _shiftEndTimer; // ⏰ NEW: Timer for auto checkout at shift end
  
  // 🚨 NEW: Subscription for auto-checkout events
  StreamSubscription<AutoCheckoutEvent>? _autoCheckoutSubscription;

  @override
  void initState() {
    super.initState();
    _checkOfflineDataStatus();
    _loadBranchData(); // Load branch data first
    _checkCurrentStatus();
    _loadPendingCount();
    
    // Refresh pending count every minute
    Timer.periodic(const Duration(minutes: 1), (_) => _loadPendingCount());
    
    // ⚠️ Listen to violation alerts
    _pulseService.addListener(_checkForViolations);
    
    // 🚨 NEW: Listen to auto-checkout events for immediate UI update
    _autoCheckoutSubscription = _pulseService.onAutoCheckout.listen(_handleAutoCheckout);
    
    // ⏰ NEW: Check for auto checkout every minute
    _shiftEndTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkAutoCheckout());
    
    // 🌐 Listen to connectivity changes for auto-sync
    _setupConnectivityListener();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showForcedCheckoutNoticeIfNeeded();
    });
  }
  
  /// Setup connectivity listener for auto-sync when internet is available
  void _setupConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((results) async {
      final hasConnection = results.any((result) => result != ConnectivityResult.none);
      
      if (hasConnection && !_isSyncing) {
        // Refresh pending count first
        await _loadPendingCount();
        
        if (_pendingCount > 0) {
          // Internet is back and we have pending data
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🌐 جاري تحميل البيانات...'),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.blue,
              ),
            );
          }
          
          // Auto-sync pending data
          await _autoSyncPendingData();
        }
      }
    });
  }
  
  /// Auto-sync pending data when internet is available
  Future<void> _autoSyncPendingData() async {
    if (_isSyncing) return;
    
    setState(() => _isSyncing = true);
    
    try {
      final syncService = SyncService.instance;
      final result = await syncService.syncPendingData();
      
      if (mounted) {
        if (result['success'] == true && result['synced'] > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ تم الرفع بالكامل - ${result['synced']} سجل'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 3),
            ),
          );
          _loadPendingCount(); // Refresh count
        }
      }
    } catch (e) {
      AppLogger.instance.log('Auto-sync error', level: AppLogger.error, tag: 'EmployeeHome', error: e);
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shiftEndTimer?.cancel(); // ⏰ Cancel shift timer
    _autoCheckoutSubscription?.cancel(); // 🚨 Cancel auto-checkout subscription
    _pulseService.removeListener(_checkForViolations);
    super.dispose();
  }

  /// 🚨 Handle auto-checkout event from PulseTrackingService
  /// This is called when 2 consecutive pulses are outside the zone
  void _handleAutoCheckout(AutoCheckoutEvent event) {
    if (!mounted) return;
    
    print('🚨 Auto-checkout event received in UI');
    print('   Reason: ${event.reason}');
    print('   Saved offline: ${event.savedOffline}');
    
    // ✅ IMMEDIATELY stop timer and update UI state
    _timer?.cancel();
    _timer = null;
    
    setState(() {
      _isCheckedIn = false;
      _checkInTime = null;
      _elapsedTime = '00:00:00';
      _currentEarnings = 0.0;
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
    
    // Refresh pending count
    _loadPendingCount();
  }

  /// Check for violation alerts and show dialog
  void _checkForViolations() {
    if (!mounted) return;
    
    // ✅ Check if tracking stopped (auto-checkout happened)
    if (!_pulseService.isTracking && _isCheckedIn) {
      print('🔄 Pulse tracking stopped - refreshing attendance status');
      // Refresh immediately
      _checkCurrentStatus().then((_) {
        if (mounted && !_isCheckedIn) {
          // Show confirmation that checkout was applied
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم تحديث الحالة - تم تسجيل الانصراف التلقائي بنجاح'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 3),
            ),
          );
        }
      });
    }
    
    // Pulse tracking status is now handled via notifications
    // No need for violation dialogs - system sends notifications automatically
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
      final needsRefresh = await db.needsCacheRefresh(widget.employeeId);
      final cached = await db.getCachedBranchData(widget.employeeId);
      
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
        print('✅ Using cached branch data: ${cached['branch_name']} (${_allowedBssids.length} WiFi networks)');
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
          AppLogger.instance.log('Using stale cache (no internet): ${cached['branch_name']}', level: AppLogger.warning, tag: 'EmployeeHome');
        } else {
          AppLogger.instance.log('No internet and no cached branch data', level: AppLogger.warning, tag: 'EmployeeHome');
        }
        return;
      }
      
      // Get employee data to find branch_id
      final employeeData = await SupabaseAttendanceService.getEmployeeStatus(widget.employeeId);
      final branchId = employeeData['employee']?['branch_id'];
      
      if (branchId == null) {
        print('⚠️ Employee has no branch assigned');
        return;
      }
      
      // Fetch branch data from Supabase
      final branchData = await BranchApiService.getBranchById(branchId);
      
      // Parse WiFi BSSIDs (can be comma-separated or array)
      List<String> wifiBssids = [];
      if (branchData['wifi_bssid'] != null && branchData['wifi_bssid'].toString().isNotEmpty) {
        // Support comma-separated BSSIDs: "AA:BB:CC:DD:EE:FF,11:22:33:44:55:66"
        wifiBssids = branchData['wifi_bssid']
            .toString()
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      
      // Cache it locally for future use
      // ✅ FIX: Safe DateTime parsing for updated_at
      int dataVersion = 1;
      if (branchData['updated_at'] != null) {
        try {
          dataVersion = DateTime.parse(branchData['updated_at'].toString()).millisecondsSinceEpoch ~/ 1000;
        } catch (e) {
          print('⚠️ Invalid updated_at format: ${branchData['updated_at']}');
        }
      }
      await db.cacheBranchData(
        employeeId: widget.employeeId,
        branchId: branchData['id'],
        branchName: branchData['name'],
        wifiBssids: wifiBssids,
        latitude: branchData['latitude'],
        longitude: branchData['longitude'],
        geofenceRadius: branchData['geofence_radius'],
        dataVersion: dataVersion,
      );
      
      setState(() {
        _branchData = branchData;
        _allowedBssids = wifiBssids;
      });
      
      AppLogger.instance.log('Fetched and cached branch data: ${branchData['name']} (${wifiBssids.length} WiFi networks)', tag: 'EmployeeHome');
    } catch (e) {
      AppLogger.instance.log('Error loading branch data', level: AppLogger.error, tag: 'EmployeeHome', error: e);
    }
  }

  Future<void> _loadPendingCount() async {
    final db = OfflineDatabase.instance;
    final count = await db.getPendingCount();
    if (mounted) {
      setState(() {
        _pendingCount = count;
      });
    }
  }

  Future<void> _showForcedCheckoutNoticeIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getBool('forced_auto_checkout_pending') ?? false;
      if (!pending || !mounted) {
        return;
      }

      final message = prefs.getString('forced_auto_checkout_message') ??
          'تم تسجيل انصراف تلقائي بسبب الابتعاد عن الفرع.';
      final requiresSync =
          prefs.getBool('forced_auto_checkout_requires_sync') ?? false;
      final timeIso = prefs.getString('forced_auto_checkout_time');
      DateTime? timestamp;
      if (timeIso != null) {
        timestamp = DateTime.tryParse(timeIso);
      }

      await prefs.setBool('forced_auto_checkout_pending', false);
      await prefs.remove('forced_auto_checkout_message');
      await prefs.remove('forced_auto_checkout_time');
      await prefs.remove('forced_auto_checkout_requires_sync');

      // ✅ Refresh status from server first
      await _checkCurrentStatus();

      if (!mounted) {
        return;
      }

      final timeText = timestamp != null
          ? ' (${TimeOfDay.fromDateTime(timestamp.toLocal()).format(context)})'
          : '';
        final syncSuffix = requiresSync
          ? '\nسيتم رفع الانصراف تلقائياً عند توفر الإنترنت.'
          : '';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$message$timeText$syncSuffix'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      AppLogger.instance.log('Failed to show forced checkout notice', level: AppLogger.warning, tag: 'EmployeeHome', error: e);
    }
  }

  Future<void> _checkCurrentStatus() async {
    // Use Supabase to get employee status
    try {
      print('🔄 Checking current attendance status for employee: ${widget.employeeId}');
      
      // ✅ STEP 1: Check SharedPreferences for offline attendance FIRST
      final prefs = await SharedPreferences.getInstance();
      final savedAttendanceId = prefs.getString('active_attendance_id');
      final isOfflineAttendance = prefs.getBool('is_offline_attendance') ?? false;
      final offlineCheckinTimeStr = prefs.getString('offline_checkin_time');
      
      if (savedAttendanceId != null && isOfflineAttendance && offlineCheckinTimeStr != null) {
        print('📱 Found offline attendance in SharedPreferences: $savedAttendanceId');
        
        // Restore offline attendance state
        setState(() {
          _isCheckedIn = true;
          _currentAttendanceId = savedAttendanceId;
          try {
            _checkInTime = DateTime.parse(offlineCheckinTimeStr).toLocal();
          } catch (e) {
            _checkInTime = DateTime.now();
          }
        });
        
        // Start timer
        if (_checkInTime != null) {
          _startTimer();
        }
        
        // Start pulse tracking if not running
        if (!_pulseService.isTracking) {
          await _pulseService.startTracking(widget.employeeId, attendanceId: savedAttendanceId);
          print('🎯 Resumed pulse tracking for offline attendance');
        }
        
        print('✅ Restored offline attendance state');
        return; // Don't query server for offline attendance
      }
      
      // ✅ STEP 2: Check server for online attendance
      final status = await SupabaseAttendanceService.getEmployeeStatus(widget.employeeId);
      
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
        // Load hourly rate for earnings computation
        _hourlyRate = (status['employee']?['hourly_rate'] as num?)?.toDouble() ?? 0.0;
        
        // ✅ Clear attendance ID if checked out
        if (!_isCheckedIn) {
          _currentAttendanceId = null;
          _timer?.cancel(); // Stop earnings timer
        }
      });
      
      print('✅ Status updated: isCheckedIn=$_isCheckedIn (was: $wasCheckedIn)');
      
      // ✅ Ensure live earnings timer if checked-in
      if (_isCheckedIn && _checkInTime != null) {
        // Initialize current earnings immediately
        final duration = DateTime.now().difference(_checkInTime!);
        _currentEarnings = _computeEarnings(duration);
        _startTimer();
      }

      // ✅ CRITICAL: If user is checked-in but pulse tracking isn't running, start it now
      if (_isCheckedIn && !_pulseService.isTracking) {
        try {
          final attendanceId = status['attendance']?['id'] as String?;
          await _pulseService.startTracking(widget.employeeId, attendanceId: attendanceId);
          AppLogger.instance.log('Resumed pulse tracking based on status check', tag: 'EmployeeHome');

          // Ensure foreground service is running on Android
          if (!kIsWeb && Platform.isAndroid) {
            final fg = ForegroundAttendanceService.instance;
            final login = await AuthService.getLoginData();
            final employeeName = login['fullName'] ?? 'الموظف';
            final healthy = await fg.isServiceHealthy();
            if (!healthy) {
              await fg.ensureServiceRunning(employeeId: widget.employeeId, employeeName: employeeName);
            }
          }
        } catch (e) {
          AppLogger.instance.log('Failed to resume pulse tracking from status', level: AppLogger.error, tag: 'EmployeeHome', error: e);
        }
      }
      // Always refresh today's total when status is fetched
      await _refreshTodayTotal();
    } catch (e) {
      print('❌ Error checking status: $e');
      
      // ✅ On network error, check SharedPreferences for offline attendance
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedAttendanceId = prefs.getString('active_attendance_id');
        final offlineCheckinTimeStr = prefs.getString('offline_checkin_time');
        
        if (savedAttendanceId != null && offlineCheckinTimeStr != null) {
          print('📱 Network error - restoring from SharedPreferences');
          setState(() {
            _isCheckedIn = true;
            _currentAttendanceId = savedAttendanceId;
            try {
              _checkInTime = DateTime.parse(offlineCheckinTimeStr).toLocal();
            } catch (e) {
              _checkInTime = DateTime.now();
            }
          });
          
          if (_checkInTime != null) {
            _startTimer();
          }
          
          if (!_pulseService.isTracking) {
            await _pulseService.startTracking(widget.employeeId, attendanceId: savedAttendanceId);
          }
        }
      } catch (prefsError) {
        print('⚠️ Could not restore from SharedPreferences: $prefsError');
      }
    }
  }
  
  /// ✅ Refresh today's total with silent failure handling
  Future<void> _refreshTodayTotal() async {
    try {
      // Persist today's earnings into daily_attendance_summary
      // ✅ Use short timeout and don't throw on error
      await SupabaseFunctionClient.post(
        'employee-today-earnings',
        {
          'employee_id': widget.employeeId,
          'persist': true,
        },
        timeout: const Duration(seconds: 3),
        throwOnError: false, // ✅ Don't crash app if this fails
      );
    } catch (e) {
      // ✅ Just log - don't show error to user
      AppLogger.instance.log('Failed to persist today total (ignored)', level: AppLogger.warning, tag: 'EmployeeHome', error: e);
      // Continue normal operation
    }
  }

  Future<void> reloadData() async {
    await _checkCurrentStatus();
  }

  /// Load branch data for Web platform (using Hive)
  Future<void> _loadBranchDataForWeb() async {
    try {
      // Check cached data from Hive (employee-specific)
      final cached = await _offlineService.getCachedBranchData(employeeId: widget.employeeId);
      
      if (cached != null) {
        setState(() {
          _branchData = cached;
          // Parse BSSIDs from cached data
          final wifiList = cached['wifi_bssids'];
          if (wifiList is List && wifiList.isNotEmpty) {
            _allowedBssids = wifiList.map((e) => e.toString()).toList();
          } else {
            final bssid = cached['bssid'];
            if (bssid != null && bssid.toString().isNotEmpty) {
              _allowedBssids = [bssid.toString()];
            }
          }
        });
        print('✅ Using cached branch data from Hive: ${cached['name']}');
        return;
      }
      
      // Need to fetch from Supabase
      final syncService = SyncService.instance;
      final hasInternet = await syncService.hasInternet();
      
      if (!hasInternet) {
        print('⚠️ No internet and no cached branch data on Web');
        return;
      }
      
      // Get employee data to find branch name
      final employeeData = await SupabaseAttendanceService.getEmployeeStatus(widget.employeeId);
      final branchName = employeeData['employee']?['branch'];
      
      if (branchName == null) {
        print('⚠️ Employee has no branch assigned');
        return;
      }
      
      // Download and cache branch data (with employee ID)
      final branchData = await _offlineService.downloadBranchData(
        branchName, 
        employeeId: widget.employeeId,
      );
      
      if (branchData != null) {
        setState(() {
          _branchData = branchData;
          final wifiList = branchData['wifi_bssids'];
          if (wifiList is List && wifiList.isNotEmpty) {
            _allowedBssids = wifiList.map((e) => e.toString()).toList();
          } else {
            final bssid = branchData['bssid'];
            if (bssid != null && bssid.toString().isNotEmpty) {
              _allowedBssids = [bssid.toString()];
            }
          }
        });
        print('✅ Downloaded branch data on Web: ${branchData['name']}');
      }
    } catch (e) {
      print('❌ Error loading branch data on Web: $e');
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_checkInTime != null) {
        final duration = DateTime.now().difference(_checkInTime!);
        setState(() {
          _elapsedTime = _formatDuration(duration);
          _currentEarnings = _computeEarnings(duration);
        });
      }
    });
  }
  
  /// ✅ V2: Show battery optimization guide for problematic devices
  Future<void> _showBatteryGuideIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasShownGuide = prefs.getBool('battery_guide_shown') ?? false;
      
      if (!hasShownGuide) {
        // Initialize keep-alive service to check device
        final keepAliveService = AggressiveKeepAliveService();
        await keepAliveService.initialize();
        
        // Only show for problematic devices
        if (keepAliveService.isAggressiveMode && mounted) {
          // Mark as shown
          await prefs.setBool('battery_guide_shown', true);
          
          // Show dialog after a short delay
          await Future.delayed(const Duration(seconds: 2));
          
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => BatteryOptimizationDialog(
                onSettings: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => BatteryOptimizationGuide(
                        employeeId: widget.employeeId,
                      ),
                    ),
                  );
                },
                onDismiss: () {},
              ),
            );
          }
        }
      }
    } catch (e) {
      AppLogger.instance.log('Error showing battery guide', level: AppLogger.warning, tag: 'BatteryGuide', error: e);
    }
  }

  double _computeEarnings(Duration duration) {
    // Pro-rated per second for smooth updates (equivalent to per-minute rounding when displayed)
    final hours = duration.inSeconds / 3600.0;
    final earnings = _hourlyRate * hours;
    // Avoid negative/NaN
    if (earnings.isNaN || earnings.isInfinite || earnings < 0) return 0.0;
    return earnings;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  /// ⏰ NEW: Check for automatic checkout at shift end
  Future<void> _checkAutoCheckout() async {
    if (!_isCheckedIn) return; // Not checked in
    
    try {
      // Get employee data with shift times
      final employeeData = await SupabaseAttendanceService.getEmployeeStatus(widget.employeeId);
      final emp = employeeData['employee'];
      
      if (emp == null || emp['shift_end_time'] == null) {
        // No shift time defined, no auto checkout
        return;
      }
      
      final shiftEndTime = emp['shift_end_time'] as String; // "17:00"
      final now = DateTime.now();
      final currentTime = TimeOfDay(hour: now.hour, minute: now.minute);
      
      // Parse shift end time
      final parts = shiftEndTime.split(':');
      if (parts.length != 2) return;
      
      final endHour = int.tryParse(parts[0]);
      final endMinute = int.tryParse(parts[1]);
      if (endHour == null || endMinute == null) return;
      
      final shiftEnd = TimeOfDay(hour: endHour, minute: endMinute);
      
      // Check if current time is past shift end time
      final currentMinutes = currentTime.hour * 60 + currentTime.minute;
      final endMinutes = shiftEnd.hour * 60 + shiftEnd.minute;
      
      if (currentMinutes >= endMinutes) {
        print('⏰ Auto checkout triggered: Current time past shift end');
        
        // Show notification
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⏰ تم تسجيل الانصراف تلقائياً - انتهى موعد الشيفت ($shiftEndTime)'),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        
        // Trigger automatic checkout
        await _handleCheckOut();
      }
    } catch (e) {
      print('❌ Error in auto checkout check: $e');
      // Don't show error to user, just log it
    }
  }

  /// ✅ Helper: Check if employee has active attendance (prevent double check-in)
  /// Priority: Offline-first approach
  /// 1. Check local storage (SharedPreferences, SQLite)
  /// 2. Check server with short timeout (3 seconds)
  /// 3. If all fail, allow check-in (fail-safe)
  Future<Map<String, dynamic>?> _checkForActiveAttendance() async {
    try {
      print('🔍 Checking for existing active attendance (offline-first)...');
      
      // ✅ STEP 1: Check SharedPreferences for active attendance ID
      try {
        final prefs = await SharedPreferences.getInstance();
        final activeAttendanceId = prefs.getString('active_attendance_id');
        
        if (activeAttendanceId != null && activeAttendanceId.isNotEmpty) {
          print('📱 Found local active attendance ID: $activeAttendanceId');
          
          // Try to get details from local storage
          if (!kIsWeb) {
            final db = OfflineDatabase.instance;
            // Check if there's a pending check-in
            final pendingCheckins = await db.getPendingCheckins();
            if (pendingCheckins.isNotEmpty) {
              final lastCheckin = pendingCheckins.last;
              print('📱 Found pending local check-in: ${lastCheckin['timestamp']}');
              return {
                'id': activeAttendanceId,
                'check_in_time': lastCheckin['timestamp'],
                'employee_id': widget.employeeId,
                'source': 'local',
              };
            }
          }
          
          // Return minimal info if we have ID
          return {
            'id': activeAttendanceId,
            'employee_id': widget.employeeId,
            'source': 'local_prefs',
          };
        }
      } catch (e) {
        print('⚠️ Error checking local storage: $e');
      }
      
      // ✅ STEP 2: Check SQLite for pending check-ins (mobile only)
      if (!kIsWeb) {
        try {
          final db = OfflineDatabase.instance;
          final pendingCheckins = await db.getPendingCheckins();
          
          if (pendingCheckins.isNotEmpty) {
            final lastCheckin = pendingCheckins.last;
            print('📱 Found pending local check-in: ${lastCheckin['timestamp']}');
            
            // Return local attendance info WITHOUT placeholder attendance_id
            // attendance_id will remain null until server check-in succeeds (backfill later)
            return {
              'id': null,
              'check_in_time': lastCheckin['timestamp'],
              'employee_id': widget.employeeId,
              'latitude': lastCheckin['latitude'],
              'longitude': lastCheckin['longitude'],
              'source': 'local_db_pending',
              'pending_local': true,
            };
          }
        } catch (e) {
          print('⚠️ Error checking SQLite: $e');
        }
      }
      
      // ✅ STEP 3: Check server with SHORT timeout (3 seconds)
      try {
        print('🌐 Checking server for active attendance (timeout: 3s)...');
        
        final activeAttendance = await SupabaseAttendanceService
            .getActiveAttendance(widget.employeeId)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () {
                print('⏱️ Server check timed out - allowing check-in');
                return null;
              },
            );
        
        if (activeAttendance != null) {
          print('⚠️ Found active attendance on server: ${activeAttendance['id']}');
          print('   Check-in time: ${activeAttendance['check_in_time']}');
          
          // Save to local storage for future offline checks
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('active_attendance_id', activeAttendance['id']);
          
          return activeAttendance;
        }
      } catch (e) {
        print('⚠️ Server check failed: $e');
        // Don't block user - continue with check-in
      }
      
      print('✅ No active attendance found - safe to check in');
      return null;
    } catch (e) {
      print('❌ Error in _checkForActiveAttendance: $e');
      // In case of error, allow check-in (fail-safe)
      return null;
    }
  }

  /// Get status of all tracking services
  Future<Map<String, dynamic>> _getServicesStatus() async {
    try {
      final foregroundHealthy = await ForegroundAttendanceService.instance.isServiceHealthy();
      
      // Check AlarmManager (basic check - if registered)
      final alarmService = AlarmManagerPulseService();
      final alarmActive = alarmService.isRegistered;
      
      // WorkManager is harder to check, assume active if checked in
      final workManagerActive = _isCheckedIn;
      
      return {
        'foreground': foregroundHealthy,
        'workmanager': workManagerActive,
        'alarmmanager': alarmActive,
      };
    } catch (e) {
      return {
        'foreground': false,
        'workmanager': false,
        'alarmmanager': false,
      };
    }
  }

  /// Show diagnostic dialog for troubleshooting
  Future<void> _showDiagnosticDialog() async {
    if (!mounted) return;
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('جاري التشخيص...'),
          ],
        ),
      ),
    );

    try {
      final report = await CheckoutDebugService.instance.runDiagnostic(
        employeeId: widget.employeeId,
        branchId: _branchData?['branch_id']?.toString(),
      );
      
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      
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
      Navigator.pop(context); // Close loading dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في التشخيص: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Show permissions explanation dialog
  Future<bool> _showPermissionsExplanationDialog() async {
    if (!mounted) return false;
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, color: AppColors.primaryOrange),
            SizedBox(width: 10),
            Text('أذونات ضرورية', style: TextStyle(fontSize: 20)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'لضمان عمل التطبيق بشكل صحيح في الخلفية، نحتاج للأذونات التالية:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 15),
              _PermissionItem(
                icon: Icons.notifications,
                title: 'الإشعارات',
                description: 'لعرض حالة التتبع وإبقاء التطبيق نشطاً',
              ),
              SizedBox(height: 10),
              _PermissionItem(
                icon: Icons.battery_charging_full,
                title: 'تحسين البطارية',
                description: 'لمنع النظام من إيقاف التطبيق لتوفير البطارية',
              ),
              SizedBox(height: 15),
              Text(
                '⚠️ بدون هذه الأذونات، قد يتوقف التتبع عند تصغير التطبيق',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }

  Future<void> _handleCheckIn() async {
    setState(() => _isLoading = true);

    try {
      AppLogger.instance.log('Starting check-in process for employee: ${widget.employeeId}', tag: 'CheckIn');
      
      // ✅ CRITICAL: Request Location Permission FIRST (Android/iOS)
      if (!kIsWeb) {
        final locationPermission = await Permission.location.status;
        
        if (!locationPermission.isGranted) {
          AppLogger.instance.log('Location permission not granted - requesting', tag: 'CheckIn');
          
          // Show explanation dialog
          if (mounted) {
            final shouldRequest = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.location_on, color: AppColors.primaryOrange),
                    SizedBox(width: 10),
                    Text('صلاحية الموقع مطلوبة', style: TextStyle(fontSize: 18)),
                  ],
                ),
                content: const SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'نحتاج إلى صلاحية الموقع للتأكد من تواجدك في الفرع أثناء تسجيل الحضور.',
                        style: TextStyle(fontSize: 16),
                      ),
                      SizedBox(height: 15),
                      Text(
                        '⚠️ بدون هذه الصلاحية، لن يمكنك تسجيل الحضور',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryOrange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('متابعة'),
                  ),
                ],
              ),
            );
            
            if (shouldRequest != true) {
              setState(() => _isLoading = false);
              return;
            }
          }
          
          // Request permission
          final result = await Permission.location.request();
          
          if (!result.isGranted) {
            setState(() => _isLoading = false);
            
            if (result.isPermanentlyDenied && mounted) {
              // Guide to settings
              await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('صلاحية مطلوبة'),
                  content: const Text(
                    'تم رفض صلاحية الموقع بشكل دائم.\n\nيرجى الذهاب إلى الإعدادات → التطبيقات → Oldies Workers → الأذونات وتفعيل "الموقع".',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        openAppSettings();
                      },
                      child: const Text('فتح الإعدادات'),
                    ),
                  ],
                ),
              );
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('❌ يجب تفعيل صلاحية الموقع لتسجيل الحضور'),
                  backgroundColor: AppColors.error,
                ),
              );
            }
            return;
          }
          
          AppLogger.instance.log('Location permission granted', tag: 'CheckIn');
        }
      }
      
      // ✅ Show permissions explanation on Android (first time or if needed)
      if (!kIsWeb && Platform.isAndroid) {
        final prefs = await SharedPreferences.getInstance();
        final hasSeenPermissionDialog = prefs.getBool('has_seen_permission_dialog') ?? false;
        
        if (!hasSeenPermissionDialog) {
          final userAccepted = await _showPermissionsExplanationDialog();
          if (!userAccepted) {
            setState(() => _isLoading = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('يجب الموافقة على الأذونات لتسجيل الحضور'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }
          // Mark as seen
          await prefs.setBool('has_seen_permission_dialog', true);
        }
      }
      
      // ✅ CRITICAL FIX: If attendance is already active, resume services instead of blocking
      final existingAttendance = await _checkForActiveAttendance();
      final bool isPendingLocal = existingAttendance != null && (
        existingAttendance['pending_local'] == true || existingAttendance['id'] == null
      );
      if (existingAttendance != null && !isPendingLocal) {
        final attendanceId = existingAttendance['id'] as String?;
        final rawCheckIn = existingAttendance['check_in_time'];
        
        // ✅ FIX: Safe DateTime parsing with null check
        DateTime? checkInTime;
        if (rawCheckIn is DateTime) {
          checkInTime = rawCheckIn;
        } else if (rawCheckIn != null && rawCheckIn.toString().isNotEmpty && rawCheckIn.toString() != 'null') {
          try {
            checkInTime = DateTime.parse(rawCheckIn.toString());
          } catch (e) {
            print('⚠️ Invalid check_in_time format: $rawCheckIn');
            checkInTime = DateTime.now(); // Fallback to now
          }
        } else {
          checkInTime = DateTime.now(); // Fallback if null
        }
        final timeAgo = DateTime.now().difference(checkInTime);

        String timeDisplay;
        if (timeAgo.inHours > 0) {
          timeDisplay = '${timeAgo.inHours} ساعة';
        } else if (timeAgo.inMinutes > 0) {
          timeDisplay = '${timeAgo.inMinutes} دقيقة';
        } else {
          timeDisplay = 'منذ لحظات';
        }

        AppLogger.instance.log('Found active attendance, resuming services (check-in $timeDisplay ago)', level: AppLogger.info, tag: 'EmployeeHome');

        // ✅ NEW: Check for session gap > 5.5 minutes
        if (timeAgo.inSeconds > 330 && _branchData != null) {
          try {
            final employeeData = await SupabaseAttendanceService.getEmployeeStatus(widget.employeeId);
            final branchId = employeeData['employee']?['branch_id'];
            final managerId = _branchData!['manager_id'] ?? employeeData['employee']?['branch']?['manager_id'];

            if (branchId != null && managerId != null && attendanceId != null) {
              AppLogger.instance.log('Checking for session gap (${timeAgo.inMinutes} minutes)', 
                level: AppLogger.warning, tag: 'EmployeeHome');
              
              final validationCreated = await SessionValidationService.instance.checkAndCreateSessionValidation(
                employeeId: widget.employeeId,
                attendanceId: attendanceId,
                branchId: branchId,
                managerId: managerId,
              );

              if (validationCreated && mounted) {
                // Notify user that validation request was created
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '⚠️ تم إرسال طلب للمدير لتأكيد تواجدك خلال الـ ${timeAgo.inMinutes} دقيقة الماضية',
                    ),
                    backgroundColor: AppColors.warning,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            }
          } catch (e) {
            AppLogger.instance.log('Error checking session validation', 
              level: AppLogger.warning, tag: 'EmployeeHome', error: e);
            // Continue anyway - don't block user
          }
        }

        // Store attendance id for later checkout
        _currentAttendanceId = attendanceId;

        // Start pulse tracking immediately
        await _pulseService.startTracking(widget.employeeId, attendanceId: attendanceId);

        // ✅ NEW: Restore UI timer & earnings when resuming existing attendance
        try {
          final statusData = await SupabaseAttendanceService.getEmployeeStatus(widget.employeeId);
          final hourly = (statusData['employee']?['hourly_rate'] as num?)?.toDouble();
          setState(() {
            _isCheckedIn = true;
            _checkInTime = checkInTime?.toLocal() ?? DateTime.now(); // ✅ FIX: Safe null check
            if (hourly != null) _hourlyRate = hourly;
            // Precompute current earnings instantly
            final duration = DateTime.now().difference(_checkInTime!);
            _currentEarnings = _computeEarnings(duration);
          });
          _startTimer();
        } catch (e) {
          AppLogger.instance.log('Failed to restore timer for existing attendance', level: AppLogger.warning, tag: 'EmployeeHome', error: e);
        }

        // Ensure foreground service is running (Android)
        if (!kIsWeb && Platform.isAndroid) {
          final foregroundService = ForegroundAttendanceService.instance;
          final employeeName = (await AuthService.getLoginData())['fullName'] ?? 'الموظف';
          final healthy = await foregroundService.isServiceHealthy();
          if (!healthy) {
            await foregroundService.ensureServiceRunning(employeeId: widget.employeeId, employeeName: employeeName);
          }
        }

        // Notify user gently that tracking has resumed
        final nameForNotif = (await AuthService.getLoginData())['fullName'] ?? 'الموظف';
        await NotificationService.instance.showGeofenceViolation(
          employeeName: nameForNotif,
          message: '✅ تم استئناف التتبع لحضورك النشط. سيتم احتساب النبضات تلقائياً.',
        );

        // Short-circuit the check-in flow since we resumed
        setState(() => _isLoading = false);
        return;
      }
      
      print('📦 Branch Data Available: ${_branchData != null}');
      
      if (_branchData != null) {
        print('📍 Branch: ${_branchData!['name']}');
        print('📍 Lat/Lng: ${_branchData!['latitude']}, ${_branchData!['longitude']}');
        print('🎯 Radius: ${_branchData!['geofence_radius']}m');
      }

      // Create a simple employee object for validation
      final authData = await AuthService.getLoginData();
      final employee = Employee(
        id: authData['employeeId'] ?? widget.employeeId,
        fullName: authData['fullName'] ?? 'الموظف',
        pin: '', // We don't need PIN for validation
        role: EmployeeRole.staff, // Default to staff for now
        branch: authData['branch'] ?? 'المركز الرئيسي',
      );

      print('👤 Employee: ${employee.fullName} (${employee.id})');
      print('🏢 Branch: ${employee.branch}');

      // Use the new validation method for check-in (WiFi OR Location)
      print('⏳ Starting validation...');
      final validation = await GeofenceService.validateForCheckIn(employee);

      print('📊 Validation Result: ${validation.isValid}');
      print('💬 Message: ${validation.message}');

      if (!validation.isValid) {
        print('❌ Validation failed!');
        throw Exception(validation.message);
      }

      AppLogger.instance.log('Validation passed: ${validation.message}', tag: 'CheckIn');
      AppLogger.instance.log('Position: ${validation.position?.latitude}, ${validation.position?.longitude}', tag: 'CheckIn');
      AppLogger.instance.log('WiFi BSSID: ${validation.bssid}', tag: 'CheckIn');

      // Use validated position and BSSID (may be null if only one was validated)
      final position = validation.position;
      var wifiBSSID = validation.bssid;
      
      // If BSSID is null but we're connected to WiFi, try to get it
      if (wifiBSSID == null && !kIsWeb) {
        try {
          // First check availability with detailed error info
          final availability = await WiFiService.checkBssidAvailability();
          if (availability['available'] == true) {
            wifiBSSID = await WiFiService.getCurrentWifiBssidValidated();
            print('📶 Got BSSID from WiFiService: $wifiBSSID');
          } else {
            // Log the specific issue for debugging
            final errorCode = availability['errorCode'] as String?;
            print('⚠️ BSSID not available: ${availability['message']} (code: $errorCode)');
            AppLogger.instance.log(
              'BSSID unavailable: ${availability['message']}',
              level: AppLogger.warning,
              tag: 'CheckIn',
            );
            
            // Show device-specific help if it's a known issue
            if (errorCode != null && mounted && (errorCode == 'BSSID_PLACEHOLDER' || errorCode == 'LOCATION_SERVICE_DISABLED')) {
              // Don't block check-in, but inform user for future reference
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  DeviceCompatibilityService.instance.checkAndShowBssidWarning(context, errorCode);
                }
              });
            }
          }
        } catch (e) {
          print('⚠️ Could not get BSSID: $e');
        }
      }

      final latitude = position?.latitude ?? 0.0;
      final longitude = position?.longitude ?? 0.0;

      // ✅ Start optimistic local timer immediately (don't wait for server)
      if (!_isCheckedIn && _checkInTime == null) {
        setState(() {
          _isCheckedIn = true;
          _checkInTime = DateTime.now();
          _currentEarnings = 0.0;
        });
        _optimisticCheckInStarted = true;
        _startTimer();
        AppLogger.instance.log('Started optimistic local check-in timer', tag: 'CheckIn');
      }

      // Try online mode first, fallback to offline if it fails
      final syncService = SyncService.instance;
      bool checkInSuccess = false;
      String? attendanceId;
      
      // Try online mode first
      try {
        print('🌐 Attempting online check-in with WiFi: $wifiBSSID');
        final response = await SupabaseAttendanceService.checkIn(
          employeeId: widget.employeeId,
          latitude: latitude,
          longitude: longitude,
          wifiBssid: wifiBSSID,
          branchId: validation.branchId,
          distance: validation.distance,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⏱️ Check-in request timed out');
            throw TimeoutException('Request timeout');
          },
        );
        
        if (response != null && response['id'] != null) {
          checkInSuccess = true;
          attendanceId = response['id'] as String;
          AppLogger.instance.log('Online check-in successful: ${response['id']}', tag: 'CheckIn');
          
          // Check shift absence (if employee has shift times)
          if (_branchData != null) {
            try {
              final employeeData = await SupabaseAttendanceService.getEmployeeStatus(widget.employeeId);
              final emp = employeeData['employee'];
              
              if (emp != null && emp['shift_start_time'] != null) {
                await AbsenceService.checkShiftAbsence(
                  employeeId: widget.employeeId,
                  branchId: _branchData!['branch_id'],
                  managerId: emp['branch']?['manager_id'] ?? '',
                  shiftStartTime: emp['shift_start_time'],
                  shiftEndTime: emp['shift_end_time'] ?? '17:00',
                  checkInTime: DateTime.now(),
                );
                
                // Sync daily attendance for payroll
                final hourlyRate = (emp['hourly_rate'] as num?)?.toDouble() ?? 0.0;
                // Update hourly rate for live earnings
                _hourlyRate = hourlyRate;
                final checkInTimeStr = TimeOfDay.now().format(context);
                
                await PayrollService().syncDailyAttendance(
                  employeeId: widget.employeeId,
                  date: DateTime.now(),
                  checkInTime: checkInTimeStr,
                  checkOutTime: null,
                  hourlyRate: hourlyRate,
                );
              }
            } catch (e) {
              print('⚠️ Error in post-check-in tasks: $e');
              // Continue anyway - check-in was successful
            }
          }
          
          // ✅ Store attendance_id for check-out
          _currentAttendanceId = attendanceId;
          
          // Check-in successful (online)
          if (_optimisticCheckInStarted) {
            // Keep original optimistic start time, just clear loading
            setState(() {
              _isLoading = false;
            });
          } else {
            setState(() {
              _isCheckedIn = true;
              _checkInTime = DateTime.now();
              _isLoading = false;
              _currentEarnings = 0.0;
            });
            _startTimer();
          }
          await _refreshTodayTotal();
          
          // ✅ Start pulse tracking when check-in succeeds
          if (_branchData != null) {
            await _pulseService.startTracking(
              widget.employeeId, 
              attendanceId: attendanceId,
            );
            print('🎯 Started pulse tracking after check-in');
            
            // ✅ Start FOREGROUND service to keep app alive in background
            if (!kIsWeb && Platform.isAndroid) {
              try {
                final ForegroundAttendanceService foregroundService = ForegroundAttendanceService.instance;
                final authData = await AuthService.getLoginData();
                final employeeName = authData['fullName'] ?? 'الموظف';
                
                // ✅ VALIDATE: Check if service actually started
                final foregroundStarted = await foregroundService.startTracking(
                  employeeId: widget.employeeId,
                  employeeName: employeeName,
                );
                
                if (foregroundStarted) {
                  AppLogger.instance.log('Foreground service started - app will stay alive', tag: 'CheckIn');
                } else {
                  AppLogger.instance.log('Failed to start foreground service', level: AppLogger.error, tag: 'CheckIn');
                  // Show warning to user
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('⚠️ تحذير: خدمة التتبع في الخلفية قد لا تعمل بشكل صحيح'),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 5),
                      ),
                    );
                  }
                }
                
                // Also start background pulse service (WorkManager) as backup
                await WorkManagerPulseService.instance.startPeriodicPulses(
                  employeeId: widget.employeeId,
                  attendanceId: attendanceId,
                  branchId: _branchData!['id'] as String,
                );
                AppLogger.instance.log('Background pulse service started (WorkManager)', tag: 'CheckIn');
                
                // ✅ Start AlarmManager as additional backup layer
                final alarmService = AlarmManagerPulseService();
                final alarmInitialized = await alarmService.initialize();
                if (alarmInitialized) {
                  // ✅ Request SCHEDULE_EXACT_ALARM permission (Android 12+)
                  final hasAlarmPermission = await alarmService.requestExactAlarmPermission();
                  if (hasAlarmPermission) {
                    await alarmService.startPeriodicAlarms(widget.employeeId);
                    AppLogger.instance.log('AlarmManager backup started', tag: 'CheckIn');
                  } else {
                    AppLogger.instance.log('AlarmManager permission denied - skipping', level: AppLogger.warning, tag: 'CheckIn');
                    // Show warning but don't block check-in
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('⚠️ تحذير: لم يتم تفعيل نظام التنبيهات الاحتياطي'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                }
              } catch (e) {
                print('⚠️ Could not start foreground/background services: $e');
                // Show detailed error with guidance
                if (mounted) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange, size: 28),
                          SizedBox(width: 10),
                          Text('تحذير: خدمة التتبع'),
                        ],
                      ),
                      content: const SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'لم نتمكن من بدء خدمة التتبع في الخلفية بشكل صحيح.',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 15),
                            Text(
                              'هذا قد يعني:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 8),
                            Text('• التتبع قد يتوقف عند تصغير التطبيق'),
                            Text('• قد لا يتم تسجيل الحضور بدقة'),
                            SizedBox(height: 15),
                            Text(
                              'للحل:',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                            ),
                            SizedBox(height: 8),
                            Text('1. افتح الإعدادات → التطبيقات'),
                            Text('2. ابحث عن "Oldies Workers"'),
                            Text('3. اضغط على "البطارية"'),
                            Text('4. اختر "غير محدود" أو "غير محسّن"'),
                            Text('5. فعّل "السماح بنشاط الخلفية"'),
                            SizedBox(height: 15),
                            Text(
                              '⚠️ يُفضل إعادة تسجيل الحضور بعد تغيير الإعدادات',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('فهمت', style: TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                  );
                }
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
            
            // ✅ V2: Show battery optimization guide for problematic devices (first time only)
            if (!kIsWeb && Platform.isAndroid) {
              _showBatteryGuideIfNeeded();
            }
          }
        }
      } catch (e) {
        print('⚠️ Online check-in failed: $e');
        print('📴 Falling back to offline mode...');
      }
      
      // If online failed, save offline
      if (!checkInSuccess) {
        if (kIsWeb) {
          // Web requires internet
          throw Exception(
            'فشل تسجيل الحضور.\n'
            'يرجى التحقق من اتصالك بالإنترنت والمحاولة مرة أخرى.'
          );
        }
        
        // Mobile: Save offline
        print('📴 Saving check-in offline with WiFi: $wifiBSSID');
        final db = OfflineDatabase.instance;
        
        // Check if we have cached branch data
        final hasCachedData = await db.hasCachedBranchData(widget.employeeId);
        
        // ✅ Generate a local offline attendance ID
        final offlineAttendanceId = 'offline_${widget.employeeId}_${DateTime.now().millisecondsSinceEpoch}';
        print('📴 Generated offline attendance ID: $offlineAttendanceId');
        
        await db.insertPendingCheckin(
          employeeId: widget.employeeId,
          timestamp: DateTime.now(),
          latitude: latitude,
          longitude: longitude,
          wifiBssid: wifiBSSID,
        );
        
        // ✅ Save offline attendance ID to SharedPreferences for checkout
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('active_attendance_id', offlineAttendanceId);
        await prefs.setBool('is_offline_attendance', true);
        await prefs.setString('offline_checkin_time', DateTime.now().toIso8601String());
        print('📴 Saved offline attendance state to SharedPreferences');
        
        // Start sync service if not already running
        syncService.startPeriodicSync();
        
        // Show offline notification
        if (hasCachedData) {
          await NotificationService.instance.showOfflineModeNotification();
        }
        
        // تحديث الحالة فوراً
        if (_optimisticCheckInStarted) {
          // Timer already running; just clear loading state
            setState(() {
              _isLoading = false;
              _currentAttendanceId = offlineAttendanceId; // ✅ Store offline ID
            });
        } else {
          setState(() {
            _isCheckedIn = true;
            _checkInTime = DateTime.now();
            _isLoading = false;
            _currentAttendanceId = offlineAttendanceId; // ✅ Store offline ID
          });
          _startTimer();
        }
        await _refreshTodayTotal();
        
        // ✅ Start pulse tracking when check-in succeeds (offline mode, with offline attendance_id)
        if (_branchData != null) {
          await _pulseService.startTracking(widget.employeeId);
          print('🎯 Started pulse tracking after offline check-in');
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                hasCachedData 
                  ? '📴 تم حفظ الحضور محلياً - سيتم الرفع عند توفر الإنترنت'
                  : '✓ تم تسجيل الحضور محلياً',
              ),
              backgroundColor: hasCachedData ? AppColors.warning : AppColors.success,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
      
      // Start geofence monitoring
      if (_branchData != null) {
        await _startGeofenceMonitoring();
      }
    } catch (e) {
      setState(() => _isLoading = false);

      // Parse error message
      String errorMessage = e.toString().replaceAll('Exception: ', '');

      // Check if it's a shift time error
      if (errorMessage.contains('وقت الشيفت')) {
        // Show detailed shift time error
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('خارج وقت الشيفت', textAlign: TextAlign.right),
              content: Text(
                errorMessage,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 16),
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
      } else {
        // Show general error with helpful details
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('فشل تسجيل الحضور', textAlign: TextAlign.right),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      errorMessage,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'تأكد من:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 8),
                    const Text('• تنزيل بيانات الفرع أولاً', textAlign: TextAlign.right),
                    const Text('• التواجد في موقع الفرع', textAlign: TextAlign.right),
                    const Text('• أو الاتصال بشبكة WiFi الخاصة بالفرع', textAlign: TextAlign.right),
                  ],
                ),
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
      print('🚪 Starting check-out process...');

      // ✅ STEP 1: Check for active attendance (local first, then server)
      String? attendanceId = _currentAttendanceId;
      Map<String, dynamic>? activeAttendanceRecord;
      bool isOfflineAttendance = false;

      if (attendanceId == null) {
        print('🔍 No local attendance_id in memory, checking SharedPreferences...');
        
        // ✅ Check SharedPreferences for offline attendance
        final prefs = await SharedPreferences.getInstance();
        final savedAttendanceId = prefs.getString('active_attendance_id');
        isOfflineAttendance = prefs.getBool('is_offline_attendance') ?? false;
        
        if (savedAttendanceId != null && savedAttendanceId.isNotEmpty) {
          attendanceId = savedAttendanceId;
          print('📱 Found saved attendance_id: $attendanceId (offline: $isOfflineAttendance)');
        } else {
          // Try server as last resort
          print('🌐 Checking server for active attendance...');
          try {
            activeAttendanceRecord = await SupabaseAttendanceService.getActiveAttendance(widget.employeeId);
            if (activeAttendanceRecord != null) {
              attendanceId = activeAttendanceRecord['id'] as String;
              print('✅ Found active attendance on server: $attendanceId');
            }
          } catch (e) {
            print('⚠️ Server check failed: $e');
          }
        }
        
        if (attendanceId == null) {
          throw Exception('لا يوجد سجل حضور نشط\nيرجى تسجيل الحضور أولاً');
        }
      } else {
        // Check if current attendance is offline
        final prefs = await SharedPreferences.getInstance();
        isOfflineAttendance = prefs.getBool('is_offline_attendance') ?? attendanceId.startsWith('offline_');
      }
      
      print('📋 Using attendance_id: $attendanceId (offline: $isOfflineAttendance)');

      // ✅ STEP 2: Now validate geofence (after confirming attendance exists)
      final authData = await AuthService.getLoginData();
      final employee = Employee(
        id: authData['employeeId'] ?? widget.employeeId,
        fullName: authData['fullName'] ?? 'الموظف',
        pin: '', // We don't need PIN for validation
        role: EmployeeRole.staff, // Default to staff for now
        branch: authData['branch'] ?? 'المركز الرئيسي',
      );

      // Use the new validation method for check-out (WiFi OR GPS)
      final validation = await GeofenceService.validateForCheckOut(employee);

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
        if (_branchData != null) {
          latitude = _branchData!['latitude']?.toDouble() ?? 0.0;
          longitude = _branchData!['longitude']?.toDouble() ?? 0.0;
          print('📍 Using branch location: $latitude, $longitude');
        }
      }

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
          latitude: latitude,
          longitude: longitude,
          wifiBssid: wifiBSSID,
        );

        if (success) {
          checkOutSuccess = true;
          print('✅ Online check-out successful');
          
          // Update daily attendance with check-out time
          try {
            final employeeData = await SupabaseAttendanceService.getEmployeeStatus(widget.employeeId);
            final emp = employeeData['employee'];
            
            if (activeAttendanceRecord == null) {
              activeAttendanceRecord = await SupabaseAttendanceService.getActiveAttendance(widget.employeeId);
            }
            
            if (emp != null && emp['hourly_rate'] != null && activeAttendanceRecord != null) {
              final hourlyRate = (emp['hourly_rate'] as num?)?.toDouble() ?? 0.0;
              final checkOutTimeStr = TimeOfDay.now().format(context);
              
              // Get check-in time from active attendance (with safe parsing)
              DateTime? checkInDateTime;
              try {
                checkInDateTime = DateTime.parse(activeAttendanceRecord['check_in_time'].toString());
              } catch (e) {
                checkInDateTime = null;
              }
              final checkInTimeStr = checkInDateTime != null 
                  ? TimeOfDay.fromDateTime(checkInDateTime).format(context) 
                  : TimeOfDay.now().format(context);
              
              await PayrollService().syncDailyAttendance(
                employeeId: widget.employeeId,
                date: DateTime.now(),
                checkInTime: checkInTimeStr,
                checkOutTime: checkOutTimeStr,
                hourlyRate: hourlyRate,
              );
            }
          } catch (e) {
            print('⚠️ Error in post-check-out tasks: $e');
            // Continue anyway - check-out was successful
          }
        }
      } catch (e) {
        print('⚠️ Online check-out failed: $e');
        print('📴 Falling back to offline mode...');
      }
      
      // If online failed, save offline
      if (!checkOutSuccess) {
        if (kIsWeb) {
          // Web requires internet
          throw Exception(
            'فشل تسجيل الانصراف.\n'
            'يرجى التحقق من اتصالك بالإنترنت والمحاولة مرة أخرى.'
          );
        }
        
        // Mobile: Save offline
        print('📴 Saving check-out offline');
        final db = OfflineDatabase.instance;

        // Check if we have cached branch data
        final hasCachedData = await db.hasCachedBranchData(widget.employeeId);

        // For checkout we need attendance_id, but in offline mode we might not have it
        // So we'll save with a placeholder and let the sync service handle it
        await db.insertPendingCheckout(
          employeeId: widget.employeeId,
          attendanceId: _currentAttendanceId, // Use current if available
          timestamp: DateTime.now(),
          latitude: latitude,
          longitude: longitude,
        );

        // Start sync service if not already running
        final syncService = SyncService.instance;
        syncService.startPeriodicSync();

        // Show offline notification
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
              backgroundColor: hasCachedData ? AppColors.warning : AppColors.success,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        // Online check-out successful
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ تم تسجيل الانصراف بنجاح'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      setState(() {
        _isCheckedIn = false;
        _checkInTime = null;
        _elapsedTime = '00:00:00';
        _isLoading = false;
        _currentAttendanceId = null; // ✅ Clear attendance_id
        _currentEarnings = 0.0;
      });

      // ✅ Clear attendance state from SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_attendance_id');
        await prefs.remove('is_offline_attendance');
        await prefs.remove('offline_checkin_time');
        print('✅ Cleared attendance state from SharedPreferences');
      } catch (e) {
        print('⚠️ Error clearing SharedPreferences: $e');
      }

      _timer?.cancel();

      // ✅ Stop pulse tracking when check-out
      _pulseService.stopTracking();
      print('🛑 Stopped pulse tracking after check-out');
      
      // ✅ Stop foreground service
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final stopped = await ForegroundAttendanceService.instance.stopTracking();
          if (stopped) {
            AppLogger.instance.log('Foreground attendance service stopped', tag: 'CheckOut');
          }
        } catch (e) {
          AppLogger.instance.log('Could not stop foreground service', level: AppLogger.warning, tag: 'CheckOut', error: e);
        }
      }
      
      // ✅ Stop background pulse service (WorkManager)
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await WorkManagerPulseService.instance.stopPeriodicPulses();
          AppLogger.instance.log('Background pulse service stopped (WorkManager)', tag: 'CheckOut');
        } catch (e) {
          AppLogger.instance.log('Could not stop background pulse service', level: AppLogger.warning, tag: 'CheckOut', error: e);
        }
        
        // ✅ Stop AlarmManager backup
        try {
          await AlarmManagerPulseService().stopPeriodicAlarms();
          AppLogger.instance.log('AlarmManager backup stopped', tag: 'CheckOut');
        } catch (e) {
          AppLogger.instance.log('Could not stop AlarmManager', level: AppLogger.warning, tag: 'CheckOut', error: e);
        }
      }

      // Stop geofence monitoring on checkout
      GeofenceService.instance.stopMonitoring();

      // Refresh today's totals after checkout
      await _refreshTodayTotal();

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
      print('🔍 Submitting break request for employee: ${widget.employeeId}, duration: $duration minutes');
      await RequestsApiService.submitBreakRequest(
        employeeId: widget.employeeId,
        durationMinutes: duration,
      );
      print('✅ Break request submitted successfully');

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
      print('❌ Break request error: $e');
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

  // Start geofence monitoring
  Future<void> _startGeofenceMonitoring() async {
    try {
      // Get employee info from SharedPreferences
      final loginData = await AuthService.getLoginData();
      final employeeName = loginData['fullName'] ?? 'الموظف';

      // Use branch data if available, otherwise fall back to RestaurantConfig
      double branchLat = RestaurantConfig.latitude;
      double branchLng = RestaurantConfig.longitude;
      double radius = RestaurantConfig.allowedRadiusInMeters;
      List<String> bssids = [RestaurantConfig.allowedWifiBssid ?? ''];

      if (_branchData != null) {
        // Get latitude and longitude from branch data
        if (_branchData!['latitude'] != null) {
          branchLat = double.tryParse(_branchData!['latitude'].toString()) ?? branchLat;
        }
        if (_branchData!['longitude'] != null) {
          branchLng = double.tryParse(_branchData!['longitude'].toString()) ?? branchLng;
        }
        if (_branchData!['geofence_radius'] != null || _branchData!['geofenceRadius'] != null) {
          radius = double.tryParse((_branchData!['geofence_radius'] ?? _branchData!['geofenceRadius']).toString()) ?? radius;
        }
        
        // Use the allowed BSSIDs we fetched earlier
        if (_allowedBssids.isNotEmpty) {
          bssids = _allowedBssids;
        }
        
        print('[EmployeeHomePage] Using branch geofence: Lat=$branchLat, Lng=$branchLng, Radius=$radius, BSSIDs=${bssids.length}');
      }

      // Start monitoring with branch config
      await GeofenceService.instance.startMonitoring(
        employeeId: widget.employeeId,
        employeeName: employeeName,
        branchLatitude: branchLat,
        branchLongitude: branchLng,
        geofenceRadius: radius,
        requiredBssids: bssids,
      );

      print('[EmployeeHomePage] Geofence monitoring started');
    } catch (e) {
      print('[EmployeeHomePage] Failed to start geofence monitoring: $e');
    }
  }

  void _showAttendanceRequestDialog() async {
    // Skip check for existing requests - directly show dialog
    final today = DateTime.now();
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
                        employeeId: widget.employeeId,
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

  /// Check if offline data is downloaded
  Future<void> _checkOfflineDataStatus() async {
    final isDownloaded = await _offlineService.isBranchDataDownloaded(employeeId: widget.employeeId);
    setState(() {
      _isDataDownloaded = isDownloaded;
    });
    
    if (isDownloaded) {
      print('✅ Branch data found for employee: ${widget.employeeId}');
    } else {
      print('📥 No branch data - showing download button for employee: ${widget.employeeId}');
    }
  }

  /// Download branch data for offline use
  Future<void> _downloadBranchData() async {
    setState(() => _isSyncing = true);
    
    try {
      final authData = await AuthService.getLoginData();
      final employeeBranch = authData['branch'] ?? 'المركز الرئيسي';
      
      // Download with employee ID
      final branchData = await _offlineService.downloadBranchData(
        employeeBranch, 
        employeeId: widget.employeeId,
      );
      
      if (branchData != null) {
        setState(() {
          _isDataDownloaded = true;
          _branchData = branchData; // ✅ حفظ البيانات في المتغير
          
          // ✅ Parse BSSIDs for validation
          final bssid = branchData['bssid'];
          if (bssid != null && bssid.toString().isNotEmpty) {
            _allowedBssids = [bssid.toString()];
          }
        });
        
        // ✅ Reload branch data to ensure SQLite is updated on mobile
        if (!kIsWeb) {
          await _loadBranchData();
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم تنزيل بيانات الفرع'),
              backgroundColor: AppColors.success,
            ),
          );
        }
        
        // ❌ Don't start pulse tracking here - only start on check-in!
        // The download button just prepares the data for offline use
      } else {
        throw Exception('فشل في تحميل بيانات الفرع');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  /// Sync local data to Supabase
  Future<void> _syncToServer() async {
    setState(() => _isSyncing = true);
    
    try {
  await _offlineService.syncToSupabase();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم مزامنة البيانات ورفعها بالكامل'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في المزامنة: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('الصفحة الرئيسية'),
        backgroundColor: AppColors.primaryOrange,
        actions: [
          // Debug/Diagnostic button
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () => _showDiagnosticDialog(),
            tooltip: 'تشخيص المشاكل',
          ),
          // Help button for device-specific settings
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => DeviceCompatibilityService.instance.showPermissionGuideDialog(context),
            tooltip: 'دليل الإعدادات',
          ),
          // Download/Sync Button
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else if (!_isDataDownloaded)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _downloadBranchData,
              tooltip: 'تحميل بيانات الفرع',
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _syncToServer,
              tooltip: 'مزامنة البيانات',
            ),
        ],
      ),
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
              
              const SizedBox(height: 16),
              
              // ✅ Enhanced Service Status Indicator (only show when checked in)
              if (_isCheckedIn && !kIsWeb && Platform.isAndroid)
                FutureBuilder<Map<String, dynamic>>(
                  future: _getServicesStatus(),
                  builder: (context, snapshot) {
                    final status = snapshot.data ?? {};
                    final foregroundActive = status['foreground'] ?? false;
                    final workManagerActive = status['workmanager'] ?? false;
                    final alarmManagerActive = status['alarmmanager'] ?? false;
                    final activeCount = [foregroundActive, workManagerActive, alarmManagerActive].where((x) => x).length;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: activeCount >= 2
                              ? [Colors.green.withOpacity(0.1), Colors.green.withOpacity(0.05)]
                              : [Colors.orange.withOpacity(0.1), Colors.orange.withOpacity(0.05)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: activeCount >= 2 ? Colors.green : Colors.orange,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                activeCount >= 2 ? Icons.shield_outlined : Icons.warning_amber,
                                color: activeCount >= 2 ? Colors.green : Colors.orange,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      activeCount >= 2 ? 'التتبع نشط' : 'تحذير',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: activeCount >= 2 ? Colors.green[900] : Colors.orange[900],
                                      ),
                                    ),
                                    Text(
                                      '$activeCount من 3 آليات تعمل',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: (activeCount >= 2 ? Colors.green : Colors.orange)[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          _ServiceStatusRow(
                            icon: Icons.notifications_active,
                            label: 'خدمة المقدمة',
                            isActive: foregroundActive,
                          ),
                          const SizedBox(height: 8),
                          _ServiceStatusRow(
                            icon: Icons.work_outline,
                            label: 'مدير المهام',
                            isActive: workManagerActive,
                          ),
                          const SizedBox(height: 8),
                          _ServiceStatusRow(
                            icon: Icons.alarm,
                            label: 'المنبهات',
                            isActive: alarmManagerActive,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              
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
              
              // Break Button (only show when checked in)
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
              
              const SizedBox(height: 16),
              
              // Pending Data Indicator
              if (_pendingCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_upload,
                        color: AppColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$_pendingCount سجل في انتظار الرفع',
                          style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _isSyncing ? null : () async {
                          // Manual sync
                          setState(() => _isSyncing = true);
                          
                          try {
                            final syncService = SyncService.instance;
                            final hasInternet = await syncService.hasInternet();
                            
                            if (!hasInternet) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('❌ لا يوجد اتصال بالإنترنت'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                              return;
                            }
                            
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('🌐 جاري تحميل البيانات...'),
                                  duration: Duration(seconds: 1),
                                  backgroundColor: Colors.blue,
                                ),
                              );
                            }
                            
                            final result = await syncService.syncPendingData();
                            
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    result['success'] == true && result['synced'] > 0
                                        ? '✅ تم الرفع بالكامل - ${result['synced']} سجل'
                                        : (result['message'] ?? 'تم'),
                                  ),
                                  backgroundColor: result['success'] 
                                      ? AppColors.success 
                                      : AppColors.error,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                              _loadPendingCount();
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('❌ خطأ في الرفع: $e'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _isSyncing = false);
                            }
                          }
                        },
                        child: _isSyncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.warning),
                                ),
                              )
                            : const Text(
                                'رفع الآن',
                                style: TextStyle(
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              
              if (_pendingCount > 0) const SizedBox(height: 16),
              
              // Secondary Action - Attendance Request
              OutlinedButton(
                onPressed: _showAttendanceRequestDialog,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryOrange,
                  side: const BorderSide(color: AppColors.primaryOrange),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.event_note, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'طلب تسجيل حضور',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 12),
              
              
              const SizedBox(height: 32),
              
            ],
          ),
        ),
      ),
    );
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

/// Helper widget for permission explanation items
class _PermissionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primaryOrange, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Service status row widget
class _ServiceStatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;

  const _ServiceStatusRow({
    required this.icon,
    required this.label,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: isActive ? Colors.green : Colors.grey,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isActive ? Colors.green[900] : Colors.grey[600],
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? Colors.green : Colors.grey[300],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            isActive ? 'نشط' : 'متوقف',
            style: TextStyle(
              fontSize: 11,
              color: isActive ? Colors.white : Colors.grey[700],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
