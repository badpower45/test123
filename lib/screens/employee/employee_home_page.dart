import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../constants/restaurant_config.dart';
import '../../models/attendance_request.dart';
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
import '../../services/pulse_tracking_service.dart';
import '../../database/offline_database.dart';
import '../../theme/app_colors.dart';
import '../../widgets/violation_alert_dialog.dart';

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
  
  // ✅ NEW: Store attendance_id locally for check-out
  String? _currentAttendanceId;
  
  final _offlineService = OfflineDataService();
  final _pulseService = PulseTrackingService();
  Timer? _shiftEndTimer; // ⏰ NEW: Timer for auto checkout at shift end

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
    
    // ⏰ NEW: Check for auto checkout every minute
    _shiftEndTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkAutoCheckout());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shiftEndTimer?.cancel(); // ⏰ Cancel shift timer
    _pulseService.removeListener(_checkForViolations);
    super.dispose();
  }

  /// Check for violation alerts and show dialog
  void _checkForViolations() {
    if (!mounted) return;
    
    if (_pulseService.hasActiveViolation && 
        _pulseService.violationMessage != null &&
        _pulseService.violationSeverity != null) {
      
      // Show violation dialog
      showDialog(
        context: context,
        barrierDismissible: false, // Force user to acknowledge
        builder: (context) => ViolationAlertDialog(
          message: _pulseService.violationMessage!,
          severity: _pulseService.violationSeverity!,
          onAcknowledge: () {
            _pulseService.acknowledgeViolation();
          },
        ),
      );
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
          print('⚠️ Using stale cache (no internet): ${cached['branch_name']}');
        } else {
          print('⚠️ No internet and no cached branch data');
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
      await db.cacheBranchData(
        employeeId: widget.employeeId,
        branchId: branchData['id'],
        branchName: branchData['name'],
        wifiBssids: wifiBssids,
        latitude: branchData['latitude'],
        longitude: branchData['longitude'],
        geofenceRadius: branchData['geofence_radius'],
        dataVersion: branchData['updated_at'] != null 
            ? DateTime.parse(branchData['updated_at']).millisecondsSinceEpoch ~/ 1000
            : 1,
      );
      
      setState(() {
        _branchData = branchData;
        _allowedBssids = wifiBssids;
      });
      
      print('✅ Fetched and cached branch data: ${branchData['name']} (${wifiBssids.length} WiFi networks)');
    } catch (e) {
      print('❌ Error loading branch data: $e');
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

  Future<void> _checkCurrentStatus() async {
    // Use Supabase to get employee status
    try {
      final status = await SupabaseAttendanceService.getEmployeeStatus(widget.employeeId);
      
      setState(() {
        _isCheckedIn = status['isCheckedIn'] as bool? ?? false;
        // Parse checkInTime and convert from UTC to local time
        _checkInTime = status['attendance']?['check_in_time'] != null
            ? DateTime.parse(status['attendance']['check_in_time']).toLocal()
            : null;
      });
      
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

  Future<void> _handleCheckIn() async {
    setState(() => _isLoading = true);

    try {
      print('🚀 Starting check-in process...');
      print('📋 Employee ID: ${widget.employeeId}');
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

      print('✅ Validation passed: ${validation.message}');
      print('📍 Position: ${validation.position?.latitude}, ${validation.position?.longitude}');
      print('📶 WiFi BSSID: ${validation.bssid}');

      // Use validated position and BSSID (may be null if only one was validated)
      final position = validation.position;
      final wifiBSSID = validation.bssid;

      final latitude = position?.latitude ?? 0.0;
      final longitude = position?.longitude ?? 0.0;

      // Check internet connection
      final syncService = SyncService.instance;
      final hasInternet = await syncService.hasInternet();

      if (hasInternet) {
        // Online mode: Send to Supabase directly
        print('🌐 Online mode - sending to Supabase with WiFi: $wifiBSSID');
        final response = await SupabaseAttendanceService.checkIn(
          employeeId: widget.employeeId,
          latitude: latitude,
          longitude: longitude,
          wifiBssid: wifiBSSID, // ✅ إضافة WiFi BSSID
        );
        
        if (response == null) {
          throw Exception('فشل تسجيل الحضور');
        }
        
        print('✅ Check-in response: ${response['id']}');
        
        // Check shift absence (if employee has shift times)
        if (_branchData != null) {
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
            final checkInTimeStr = TimeOfDay.now().format(context);
            
            await PayrollService().syncDailyAttendance(
              employeeId: widget.employeeId,
              date: DateTime.now(),
              checkInTime: checkInTimeStr,
              checkOutTime: null,
              hourlyRate: hourlyRate,
            );
          }
        }
        
        // ✅ Store attendance_id for check-out
        _currentAttendanceId = response['id'];
        
        // New check-in successful
        setState(() {
          _isCheckedIn = true;
          _checkInTime = DateTime.now();
          _isLoading = false;
        });
        
        _startTimer();
        
        // ✅ Start pulse tracking when check-in succeeds
        if (_branchData != null) {
          await _pulseService.startTracking(widget.employeeId, attendanceId: response['id']);
          print('🎯 Started pulse tracking after check-in');
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ تم تسجيل الحضور بنجاح'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // Offline mode: Save locally
        print('📴 Offline mode - saving locally with WiFi: $wifiBSSID');
        
        if (kIsWeb) {
          // ❌ Web platform doesn't support full offline mode with SQLite
          // Show error message
          throw Exception(
            'الاتصال بالإنترنت مطلوب لتسجيل الحضور على المتصفح.\n'
            'يرجى التحقق من اتصالك والمحاولة مرة أخرى.'
          );
        }
        
        // Mobile: Use SQLite for offline storage
        final db = OfflineDatabase.instance;
        
        // Check if we have cached branch data (means we can work offline)
        final hasCachedData = await db.hasCachedBranchData(widget.employeeId);
        
        await db.insertPendingCheckin(
          employeeId: widget.employeeId,
          timestamp: DateTime.now(),
          latitude: latitude,
          longitude: longitude,
          wifiBssid: wifiBSSID,
        );
        
        // Start sync service if not already running
        syncService.startPeriodicSync();
        
        // Only show notification if we have cached data (true offline mode)
        if (hasCachedData) {
          await NotificationService.instance.showOfflineModeNotification();
        }
        
        // تحديث الحالة فوراً
        setState(() {
          _isCheckedIn = true;
          _checkInTime = DateTime.now();
          _isLoading = false;
          // ✅ No attendance_id in offline mode
          _currentAttendanceId = null;
        });
        
        _startTimer();
        
        // ✅ Start pulse tracking when check-in succeeds (offline mode, no attendance_id)
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
    setState(() => _isLoading = true);

    try {
      print('🚪 Starting check-out process...');

      // Create a simple employee object for validation
      final authData = await AuthService.getLoginData();
      final employee = Employee(
        id: authData['employeeId'] ?? widget.employeeId,
        fullName: authData['fullName'] ?? 'الموظف',
        pin: '', // We don't need PIN for validation
        role: EmployeeRole.staff, // Default to staff for now
        branch: authData['branch'] ?? 'المركز الرئيسي',
      );

      // Use the new validation method for check-out (GPS only)
      final validation = await GeofenceService.validateForCheckOut(employee);

      if (!validation.isValid) {
        throw Exception(validation.message);
      }

      // Ensure we have position for check-out
      if (validation.position == null) {
        throw Exception('خطأ في تحديد الموقع');
      }

      final position = validation.position!;

      // Check internet connection
      final syncService = SyncService.instance;
      final hasInternet = await syncService.hasInternet();

      if (hasInternet) {
        // Online mode: Send to Supabase directly
        // ✅ Use stored attendance_id if available, otherwise fetch
        String? attendanceId = _currentAttendanceId;
        Map<String, dynamic>? activeAttendanceRecord;
        
        if (attendanceId == null) {
          activeAttendanceRecord = await SupabaseAttendanceService.getActiveAttendance(widget.employeeId);
          
          if (activeAttendanceRecord == null) {
            throw Exception('لا يوجد سجل حضور نشط\nيرجى تسجيل الحضور أولاً');
          }
          
          attendanceId = activeAttendanceRecord['id'] as String;
        }
        
        final success = await SupabaseAttendanceService.checkOut(
          attendanceId: attendanceId,
          latitude: position.latitude,
          longitude: position.longitude,
        );

        if (!success) {
          throw Exception('فشل تسجيل الانصراف');
        }

        // Update daily attendance with check-out time
        final employeeData = await SupabaseAttendanceService.getEmployeeStatus(widget.employeeId);
        final emp = employeeData['employee'];
        
        if (emp != null && emp['hourly_rate'] != null && activeAttendanceRecord != null) {
          final hourlyRate = (emp['hourly_rate'] as num?)?.toDouble() ?? 0.0;
          final checkOutTimeStr = TimeOfDay.now().format(context);
          
          // Get check-in time from active attendance
          final checkInDateTime = DateTime.parse(activeAttendanceRecord['check_in_time']);
          final checkInTimeStr = TimeOfDay.fromDateTime(checkInDateTime).format(context);
          
          await PayrollService().syncDailyAttendance(
            employeeId: widget.employeeId,
            date: DateTime.now(),
            checkInTime: checkInTimeStr,
            checkOutTime: checkOutTimeStr,
            hourlyRate: hourlyRate,
          );
        }

        // New check-out successful
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ تم تسجيل الانصراف بنجاح'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // Offline mode: Save locally
        final db = OfflineDatabase.instance;

        // Check if we have cached branch data (means we can work offline)
        final hasCachedData = await db.hasCachedBranchData(widget.employeeId);

        // For checkout we need attendance_id, but in offline mode we might not have it
        // So we'll save with a placeholder and let the sync service handle it
        await db.insertPendingCheckout(
          employeeId: widget.employeeId,
          attendanceId: null, // Will be resolved during sync
          timestamp: DateTime.now(),
          latitude: position.latitude,
          longitude: position.longitude,
        );

        // Start sync service if not already running
        syncService.startPeriodicSync();

        // Only show notification if we have cached data (true offline mode)
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
      }

      setState(() {
        _isCheckedIn = false;
        _checkInTime = null;
        _elapsedTime = '00:00:00';
        _isLoading = false;
        _currentAttendanceId = null; // ✅ Clear attendance_id
      });

      _timer?.cancel();

      // ✅ Stop pulse tracking when check-out
      _pulseService.stopTracking();
      print('🛑 Stopped pulse tracking after check-out');

      // Stop geofence monitoring on checkout
      GeofenceService.instance.stopMonitoring();

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
      await RequestsApiService.submitBreakRequest(
        employeeId: widget.employeeId,
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
    // تحقق من وجود طلب حضور لنفس اليوم
    final today = DateTime.now();
    final requests = await RequestsApiService.fetchAttendanceRequests(widget.employeeId);
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
                        onPressed: () async {
                          // Manual sync
                          final syncService = SyncService.instance;
                          final result = await syncService.syncPendingData();
                          
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(result['message'] ?? 'تم'),
                                backgroundColor: result['success'] 
                                    ? AppColors.success 
                                    : AppColors.error,
                              ),
                            );
                            _loadPendingCount();
                          }
                        },
                        child: const Text(
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
