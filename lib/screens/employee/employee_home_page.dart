import 'dart:async';

import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../../constants/restaurant_config.dart';
import '../../models/attendance_request.dart';
import '../../services/attendance_api_service.dart';
import '../../services/branch_api_service.dart';
import '../../services/location_service.dart';
import '../../services/requests_api_service.dart';
import '../../services/sync_service.dart';
import '../../services/notification_service.dart';
import '../../services/auth_service.dart';
import '../../services/geofence_service.dart';
import '../../database/offline_database.dart';
import '../../theme/app_colors.dart';
import 'my_attendance_table_screen.dart';
import 'package:geolocator/geolocator.dart';

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

  @override
  void initState() {
    super.initState();
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
    final db = OfflineDatabase.instance;
    final count = await db.getPendingCount();
    if (mounted) {
      setState(() {
        _pendingCount = count;
      });
    }
  }

  Future<void> _checkCurrentStatus() async {
    // Use the correct API to get employee status
    try {
      final status = await AttendanceApiService.fetchEmployeeStatus(widget.employeeId);
      final branchId = status['employee']?['branchId'];
      
      setState(() {
        _isCheckedIn = status['attendance']?['status'] == 'active';
        _checkInTime = status['attendance']?['checkInTime'] != null
            ? DateTime.parse(status['attendance']['checkInTime'])
            : null;
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
      final locationService = LocationService();
      final position = await locationService.tryGetPosition();
      final networkInfo = NetworkInfo();
      final wifiBSSID = await networkInfo.getWifiBSSID();

      // Validate location using branch data
      if (RestaurantConfig.enforceLocation && _branchData != null) {
        if (position == null) {
          throw Exception('تعذر تحديد موقعك، يرجى تفعيل خدمة تحديد الموقع والمحاولة مرة أخرى.');
        }
        
        // Check accuracy - warn if too poor
        if (position.accuracy > 100) {
          throw Exception('دقة الموقع ضعيفة جداً (${position.accuracy.toStringAsFixed(0)}م). يرجى الانتقال إلى مكان مفتوح وإعادة المحاولة.');
        }
        
        // Use branch coordinates if available
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
          
          print('📍 Geofence check:');
          print('  Branch: ($branchLat, $branchLng)');
          print('  Current: (${position.latitude}, ${position.longitude})');
          print('  Accuracy: ${position.accuracy.toStringAsFixed(1)}m');
          print('  Distance: ${distance.toStringAsFixed(1)}m');
          print('  Allowed radius: ${branchRadius}m');
          print('  Within range: ${distance <= branchRadius}');
          
          // Add accuracy buffer - if accuracy is poor, we need extra margin
          final effectiveRadius = branchRadius + (position.accuracy > 30 ? position.accuracy * 0.5 : 0);
          
          if (distance > effectiveRadius) {
            throw Exception(
              'أنت خارج نطاق الموقع المسموح للمطعم.\n'
              'المسافة: ${distance.toStringAsFixed(0)}م من ${branchRadius}م\n'
              'دقة GPS: ${position.accuracy.toStringAsFixed(0)}م\n'
              'يرجى الاقتراب من المطعم وإعادة المحاولة.'
            );
          }
        }
      }

      final latitude = position?.latitude ?? RestaurantConfig.latitude;
      final longitude = position?.longitude ?? RestaurantConfig.longitude;

      // Check internet connection
      final syncService = SyncService.instance;
      final hasInternet = await syncService.hasInternet();

      if (hasInternet) {
        // Online mode: Send to API directly
        await AttendanceApiService.checkIn(
          employeeId: widget.employeeId,
          latitude: latitude,
          longitude: longitude,
          wifiBssid: wifiBSSID,
        );
        
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
        final db = OfflineDatabase.instance;
        await db.insertPendingCheckin(
          employeeId: widget.employeeId,
          timestamp: DateTime.now(),
          latitude: latitude,
          longitude: longitude,
          wifiBssid: wifiBSSID,
        );
        
        // Start sync service if not already running
        syncService.startPeriodicSync();
        
        // Show offline notification
        await NotificationService.instance.showOfflineModeNotification();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📴 تم حفظ الحضور محلياً - سيتم الرفع عند توفر الإنترنت'),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
      
      // Start geofence monitoring with old service
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
        // Show regular error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
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
    setState(() => _isLoading = true);

    try {
      final locationService = LocationService();
      final position = await locationService.tryGetPosition();
      final networkInfo = NetworkInfo();
      final wifiBSSID = await networkInfo.getWifiBSSID();

      // Validate location using branch data
      if (RestaurantConfig.enforceLocation && _branchData != null) {
        if (position == null) {
          throw Exception('تعذر تحديد موقعك، يرجى تفعيل خدمة تحديد الموقع والمحاولة مرة أخرى.');
        }

        // Check accuracy - warn if too poor
        if (position.accuracy > 100) {
          throw Exception('دقة الموقع ضعيفة جداً (${position.accuracy.toStringAsFixed(0)}م). يرجى الانتقال إلى مكان مفتوح وإعادة المحاولة.');
        }

        // Use branch coordinates if available
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

          print('📍 Geofence check (checkout):');
          print('  Branch: ($branchLat, $branchLng)');
          print('  Current: (${position.latitude}, ${position.longitude})');
          print('  Accuracy: ${position.accuracy.toStringAsFixed(1)}m');
          print('  Distance: ${distance.toStringAsFixed(1)}m');
          print('  Allowed radius: ${branchRadius}m');

          // Add accuracy buffer
          final effectiveRadius = branchRadius + (position.accuracy > 30 ? position.accuracy * 0.5 : 0);

          if (distance > effectiveRadius) {
            throw Exception(
              'أنت خارج نطاق الموقع المسموح للمطعم.\n'
              'المسافة: ${distance.toStringAsFixed(0)}م من ${branchRadius}م\n'
              'دقة GPS: ${position.accuracy.toStringAsFixed(0)}م\n'
              'يرجى الاقتراب من المطعم وإعادة المحاولة.'
            );
          }
        }
      }

      final latitude = position?.latitude ?? RestaurantConfig.latitude;
      final longitude = position?.longitude ?? RestaurantConfig.longitude;

      // Check internet connection
      final syncService = SyncService.instance;
      final hasInternet = await syncService.hasInternet();

      if (hasInternet) {
        // Online mode: Send to API directly
        await AttendanceApiService.checkOut(
          employeeId: widget.employeeId,
          latitude: latitude,
          longitude: longitude,
          wifiBssid: wifiBSSID,
        );

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

        // For checkout we need attendance_id, but in offline mode we might not have it
        // So we'll save with a placeholder and let the sync service handle it
        await db.insertPendingCheckout(
          employeeId: widget.employeeId,
          attendanceId: null, // Will be resolved during sync
          timestamp: DateTime.now(),
          latitude: latitude,
          longitude: longitude,
        );

        // Start sync service if not already running
        syncService.startPeriodicSync();

        // Show offline notification
        await NotificationService.instance.showOfflineModeNotification();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📴 تم حفظ الانصراف محلياً - سيتم الرفع عند توفر الإنترنت'),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }

      setState(() {
        _isCheckedIn = false;
        _checkInTime = null;
        _elapsedTime = '00:00:00';
        _isLoading = false;
      });

      _timer?.cancel();

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

  // Start geofence monitoring
  Future<void> _startGeofenceMonitoring() async {
    try {
      // Get employee info from SharedPreferences
      final loginData = await AuthService.getLoginData();
      final employeeName = loginData['fullName'] ?? 'الموظف';

      // Start monitoring with restaurant config
      await GeofenceService.instance.startMonitoring(
        employeeId: widget.employeeId,
        employeeName: employeeName,
        branchLatitude: RestaurantConfig.latitude,
        branchLongitude: RestaurantConfig.longitude,
        geofenceRadius: RestaurantConfig.allowedRadiusInMeters,
        requiredBssids: [RestaurantConfig.allowedWifiBssid ?? ''],
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
