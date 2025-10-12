import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/restaurant_config.dart';
import '../services/background_pulse_service.dart';
import '../services/location_service.dart';
import '../services/pulse_history_repository.dart';
import '../services/pulse_sync_manager.dart';
import '../theme/app_colors.dart';

class PermissionRequest {
  PermissionRequest({
    required this.type,
    required this.note,
    required this.requestedAt,
    this.from,
    this.to,
  });

  final String type;
  final String note;
  final DateTime requestedAt;
  final TimeOfDay? from;
  final TimeOfDay? to;
}

const String _loginRouteName = '/login';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.employeeId});

  static const routeName = '/home';

  final String employeeId;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _checkedIn = false;
  bool _isProcessing = false;
  bool _isInsidePerimeter = true;
  bool _locationEnforced = RestaurantConfig.enforceLocation;
  bool _isOnline = true;
  bool _lastPulseQueuedOffline = false;
  bool _lastPulseDeliveredOnline = false;
  int _totalPulseCount = 0;
  int _monthlyPulseCount = 0;
  int _pulseCounter = 0;
  DateTime? _checkInTime;
  DateTime? _lastPulseTimestamp;
  DateTime? _lastSyncAt;
  DateTime? _lastOfflineReminderAt;
  DateTime? _lastFakePulseSnackAt;
  DateTime? _lastLocationWarningAt;
  Duration _elapsed = Duration.zero;
  bool _isSyncingOffline = false;
  int _syncInitialPending = 0;
  int? _syncBaselineTotal;
  DateTime? _offlineSince;
  Duration _offlineDuration = Duration.zero;
  double? _lastLatitude;
  double? _lastLongitude;
  double? _lastDistanceMeters;
  int _pendingOfflineCount = 0;
  Timer? _timer;
  Timer? _offlineTimer;
  StreamSubscription<Map<String, dynamic>?>? _statusSubscription;
  final List<PermissionRequest> _requests = <PermissionRequest>[];

  @override
  void initState() {
    super.initState();
    _statusSubscription = BackgroundPulseService.statusStream().listen((event) {
      if (!mounted || event == null) {
        return;
      }
    final previousOnline = _isOnline;
    final locationEnforcedValue = event['locationEnforced'];
      final effectiveLocationEnforced = locationEnforcedValue is bool
          ? locationEnforcedValue
          : _locationEnforced;
      final isFake = event['isFake'] == true && effectiveLocationEnforced;
      final timestampString = event['timestamp'] as String?;
      final latitude = (event['latitude'] as num?)?.toDouble();
      final longitude = (event['longitude'] as num?)?.toDouble();
      final distance = (event['distanceInMeters'] as num?)?.toDouble();
      final pendingOffline = (event['pendingOfflineCount'] as num?)?.toInt();
    final deliveredOnline = event['sentOnline'] == true;
    final queuedOffline = event['queuedOffline'] == true;
      final totalPulseCount = (event['totalPulseCount'] as num?)?.toInt();
      final monthlyPulseCount = (event['monthlyPulseCount'] as num?)?.toInt();
      final pulseCounter = (event['pulseCounter'] as num?)?.toInt();
      final locationUnavailable = event['locationUnavailable'] == true;
      final hasInsideKey = event.containsKey('isInsidePerimeter');
      final bool? insideValue = hasInsideKey
          ? (event['isInsidePerimeter'] != false)
          : null;
    final isOnlineNow = event['isOnline'] != false;

      setState(() {
        _lastPulseTimestamp = timestampString != null
            ? DateTime.tryParse(timestampString)?.toLocal()
            : _lastPulseTimestamp;
        _lastLatitude = latitude ?? _lastLatitude;
        _lastLongitude = longitude ?? _lastLongitude;
        _lastDistanceMeters = distance ?? _lastDistanceMeters;
        if (effectiveLocationEnforced) {
          if (locationUnavailable) {
            _isInsidePerimeter = false;
          } else if (insideValue != null) {
            _isInsidePerimeter = insideValue;
          }
        } else {
          _isInsidePerimeter = true;
        }
        _locationEnforced = effectiveLocationEnforced;
        _isOnline = isOnlineNow;
        _pendingOfflineCount = pendingOffline ?? _pendingOfflineCount;
        if (locationUnavailable) {
          _lastPulseDeliveredOnline = false;
          _lastPulseQueuedOffline = false;
        } else {
          _lastPulseDeliveredOnline = deliveredOnline;
          _lastPulseQueuedOffline = queuedOffline;
        }
        if (pulseCounter != null) {
          _pulseCounter = pulseCounter;
        }
        if (totalPulseCount != null) {
          _totalPulseCount = totalPulseCount;
        }
        if (monthlyPulseCount != null) {
          _monthlyPulseCount = monthlyPulseCount;
        }
        if (deliveredOnline && (_pendingOfflineCount == 0)) {
          _lastSyncAt = DateTime.now();
        }
      });

      if (!mounted) {
        return;
      }

      if (previousOnline && !isOnlineNow) {
        _handleWentOffline();
      } else if (!previousOnline && isOnlineNow) {
        _handleCameOnline();
      }

      if (!isOnlineNow) {
        final shouldNotify =
            _lastOfflineReminderAt == null ||
            DateTime.now().difference(_lastOfflineReminderAt!) >
                const Duration(minutes: 5);
        if (shouldNotify) {
          _lastOfflineReminderAt = DateTime.now();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.primaryOrange,
              content: const Text(
                'أنت داخل الشيفت لكن الاتصال بالإنترنت مقطوع، بنسجل النبضات أوفلاين لحد ما النت يرجع. شغّل الإنترنت بسرعة لتتفادى أي خصومات.',
                textDirection: TextDirection.rtl,
              ),
            ),
          );
        }
      }

      if (isFake) {
        final shouldShowWarning =
            _lastFakePulseSnackAt == null ||
            DateTime.now().difference(_lastFakePulseSnackAt!) >
                const Duration(seconds: 30);
        if (shouldShowWarning) {
          _lastFakePulseSnackAt = DateTime.now();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.danger,
              content: Text(
                'تم رصد نبضة غير حقيقية الساعة ${_formatTimeOfDay(_lastPulseTimestamp)}، تم إشعار الإدارة فوراً.',
                textDirection: TextDirection.rtl,
              ),
            ),
          );
        }
      }

      if (locationUnavailable && mounted) {
        final shouldWarn =
            _lastLocationWarningAt == null ||
            DateTime.now().difference(_lastLocationWarningAt!) >
                const Duration(minutes: 3);
        if (shouldWarn) {
          _lastLocationWarningAt = DateTime.now();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.danger,
              content: const Text(
                'لا يمكن تحديد موقعك حالياً. يرجى تفعيل خدمة تحديد الموقع ومنح الأذونات حتى يتم تسجيل النبضات.\u200f',
                textDirection: TextDirection.rtl,
              ),
            ),
          );
        }
      }
    });

    _loadPendingCount();
    _loadPulseHistoryStats();
  }

  Future<void> _loadPendingCount() async {
    final count = await PulseSyncManager.pendingPulseCount();
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingOfflineCount = count;
    });
  }

  Future<void> _loadPulseHistoryStats() async {
    final total = await PulseHistoryRepository.totalPulseCount();
    final monthly = await PulseHistoryRepository.monthlyPulseCount(
      DateTime.now(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _totalPulseCount = total;
      _monthlyPulseCount = monthly;
    });
  }

  Future<bool> _ensureNotificationPermission() async {
    if (kIsWeb || !Platform.isAndroid) {
      return true;
    }
    final status = await Permission.notification.status;
    if (status.isGranted || status.isLimited) {
      return true;
    }
    final result = await Permission.notification.request();
    return result.isGranted || result.isLimited;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statusSubscription?.cancel();
    if (_checkedIn) {
      BackgroundPulseService.stop();
    }
    _offlineTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleCheckIn() async {
    setState(() {
      _isProcessing = true;
    });

    if (RestaurantConfig.enforceLocation) {
      final locationService = LocationService();
      final isInside = await locationService.isWithinRestaurantArea(
        restaurantLat: RestaurantConfig.latitude,
        restaurantLon: RestaurantConfig.longitude,
        radiusInMeters: RestaurantConfig.allowedRadiusInMeters,
      );

      if (!mounted) {
        return;
      }

      if (!isInside) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أنت خارج نطاق الموقع المسموح للمطعم.')),
        );
        return;
      }
    } else if (!mounted) {
      return;
    }

    final notificationsAllowed = await _ensureNotificationPermission();
    if (!notificationsAllowed) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب منح إذن الإشعارات لمتابعة النبضات.')),
      );
      return;
    }

    await BackgroundPulseService.start(
      PulseConfig(
        employeeId: widget.employeeId,
        restaurantLat: RestaurantConfig.latitude,
        restaurantLon: RestaurantConfig.longitude,
        radiusInMeters: RestaurantConfig.allowedRadiusInMeters,
        enforceLocation: RestaurantConfig.enforceLocation,
      ),
    );

    final pending = await PulseSyncManager.syncPendingPulses();

    setState(() {
      _checkedIn = true;
      _checkInTime = DateTime.now();
      _elapsed = Duration.zero;
      _isProcessing = false;
      _pendingOfflineCount = pending;
      if (pending == 0) {
        _lastSyncAt = DateTime.now();
      }
      _locationEnforced = RestaurantConfig.enforceLocation;
    });
    _startTimer();
  }

  Future<void> _handleCheckOut() async {
    setState(() {
      _isProcessing = true;
    });
    await BackgroundPulseService.stop();
    _timer?.cancel();
    setState(() {
      _checkedIn = false;
      _elapsed = Duration.zero;
      _checkInTime = null;
      _isProcessing = false;
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _checkInTime == null) {
        return;
      }
      setState(() {
        _elapsed = DateTime.now().difference(_checkInTime!);
      });
    });
  }

  void _startOfflineTimer() {
    if (_offlineSince != null) {
      return;
    }
    final now = DateTime.now();
    setState(() {
      _offlineSince = now;
      _offlineDuration = Duration.zero;
    });
    _offlineTimer?.cancel();
    _offlineTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _offlineSince == null) {
        return;
      }
      setState(() {
        _offlineDuration = DateTime.now().difference(_offlineSince!);
      });
    });
  }

  void _stopOfflineTimer() {
    _offlineTimer?.cancel();
    _offlineTimer = null;
  }

  void _handleWentOffline() {
    _startOfflineTimer();
    if (_isSyncingOffline) {
      setState(() {
        _isSyncingOffline = false;
        _syncInitialPending = 0;
        _syncBaselineTotal = null;
      });
    }
  }

  void _handleCameOnline() {
    _stopOfflineTimer();
    _lastOfflineReminderAt = null;
    if (_pendingOfflineCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.primaryOrange,
          content: Text(
            'رجع الاتصال بالإنترنت، هنرفع دلوقتي $_pendingOfflineCount نبضات أوفلاين.',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
      _syncOfflinePulses();
    } else {
      setState(() {
        _offlineSince = null;
        _offlineDuration = Duration.zero;
      });
    }
  }

  Future<void> _syncOfflinePulses({bool triggeredByUser = false}) async {
    if (!_isOnline) {
      if (triggeredByUser) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'لا يمكن رفع النبضات الأوفلاين بدون اتصال بالإنترنت، شغّل النت وجرب تاني.',
              textDirection: TextDirection.rtl,
            ),
          ),
        );
      }
      return;
    }

    if (_isSyncingOffline || _pendingOfflineCount == 0) {
      if (triggeredByUser && _pendingOfflineCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'لا توجد نبضات أوفلاين للرفع حالياً.',
              textDirection: TextDirection.rtl,
            ),
          ),
        );
      }
      return;
    }

    final initialPending = _pendingOfflineCount;
    final baselineTotal = _totalPulseCount;
    setState(() {
      _isSyncingOffline = true;
      _syncInitialPending = initialPending;
      _syncBaselineTotal = baselineTotal;
    });

    try {
      final remaining = await PulseSyncManager.syncPendingPulses();
      if (!mounted) {
        return;
      }
      final uploaded = initialPending - remaining;
      setState(() {
        _pendingOfflineCount = remaining;
        _isSyncingOffline = false;
        _syncBaselineTotal = null;
        _syncInitialPending = 0;
        if (remaining == 0) {
          _lastSyncAt = DateTime.now();
          _offlineSince = null;
          _offlineDuration = Duration.zero;
        }
      });

      if (uploaded > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text(
              'تم رفع $uploaded نبضات أوفلاين إلى المنصة.',
              textDirection: TextDirection.rtl,
            ),
          ),
        );
      } else if (triggeredByUser) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ما زلنا في انتظار الشبكة لرفع النبضات الأوفلاين.',
              textDirection: TextDirection.rtl,
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSyncingOffline = false;
        _syncBaselineTotal = null;
        _syncInitialPending = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: const Text(
            'تعذر رفع النبضات المخزنة، سنعيد المحاولة تلقائيًا عند توفر الإنترنت.',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    }
  }

  Future<void> _manualSyncOfflinePulses() async {
    await _syncOfflinePulses(triggeredByUser: true);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatTimeOfDay(DateTime? timestamp) {
    if (timestamp == null) {
      return '--:--';
    }
    final hours = timestamp.hour.toString().padLeft(2, '0');
    final minutes = timestamp.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  String _formatDateTime(DateTime? timestamp) {
    if (timestamp == null) {
      return 'لا توجد بيانات بعد';
    }
    final day = timestamp.day.toString().padLeft(2, '0');
    final month = timestamp.month.toString().padLeft(2, '0');
    final year = timestamp.year.toString();
    final time = _formatTimeOfDay(timestamp);
    return '$day/$month/$year · $time';
  }

  void _showComingSoon(String featureName) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('ميزة $featureName قيد التحضير.')));
  }

  Future<void> _confirmLogout() async {
    if (_isProcessing) {
      return;
    }
    final shouldLogout =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تأكيد تسجيل الخروج'),
            content: const Text(
              'هل تريد بالتأكيد تسجيل الخروج والعودة إلى شاشة الدخول؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: AppColors.onPrimary,
                ),
                child: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLogout || !mounted) {
      return;
    }

    await _handleLogout();
  }

  Future<void> _handleLogout() async {
    setState(() {
      _isProcessing = true;
    });

    await BackgroundPulseService.stop();
    _timer?.cancel();

    if (!mounted) {
      return;
    }

    setState(() {
      _checkedIn = false;
      _elapsed = Duration.zero;
      _checkInTime = null;
      _lastPulseTimestamp = null;
      _pendingOfflineCount = 0;
      _isProcessing = false;
    });

    if (!mounted) {
      return;
    }

    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(_loginRouteName, (route) => false);
  }

  Future<void> _openPermissionSheet() async {
    final request = await showModalBottomSheet<PermissionRequest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _PermissionRequestSheet(employeeId: widget.employeeId);
      },
    );

    if (request == null || !mounted) {
      return;
    }

    setState(() {
      _requests.insert(0, request);
      if (_requests.length > 5) {
        _requests.removeLast();
      }
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('تم تسجيل طلب ${request.type}.')));
  }

  BoxDecoration _cardDecoration({Color? backgroundColor}) {
    return BoxDecoration(
      color: backgroundColor ?? Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFE3E8EF)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final int offlineUploadedCount =
        (_syncInitialPending - _pendingOfflineCount)
            .clamp(0, _syncInitialPending)
            .toInt();
    final statusChips = <Widget>[
      _buildStatusChip(
        icon: Icons.verified_user,
        label: _checkedIn ? 'مسجل حضور' : 'لم يتم تسجيل الحضور',
        background: _checkedIn
            ? AppColors.success.withValues(alpha: 0.14)
            : const Color(0xFFF0F2F7),
        foreground: _checkedIn ? AppColors.success : Colors.black87,
      ),
      _buildStatusChip(
        icon: !_locationEnforced
            ? Icons.place_outlined
            : _isInsidePerimeter
            ? Icons.place
            : Icons.error_outline,
        label: !_locationEnforced
            ? 'تم تجاوز التحقق من الموقع'
            : _isInsidePerimeter
            ? 'داخل النطاق'
            : 'خارج النطاق',
        background: !_locationEnforced
            ? const Color(0xFFE6ECFF)
            : _isInsidePerimeter
            ? const Color(0xFFE9F7EF)
            : const Color(0xFFFFE8E8),
        foreground: !_locationEnforced
            ? Colors.blueGrey
            : _isInsidePerimeter
            ? AppColors.success
            : AppColors.danger,
      ),
      _buildStatusChip(
        icon: _isOnline ? Icons.wifi : Icons.wifi_off,
        label: _isOnline
            ? 'متصل'
            : _offlineSince != null
                ? 'أوفلاين منذ ${_formatDuration(_offlineDuration)}'
                : 'وضع أوفلاين',
        background: _isOnline
            ? const Color(0xFFE8F4FF)
            : const Color(0xFFFFF1E6),
        foreground: _isOnline ? Colors.blue : Colors.deepOrange,
      ),
      if (_pendingOfflineCount > 0 || _isSyncingOffline)
        _buildStatusChip(
          icon: _isSyncingOffline
              ? Icons.sync_rounded
              : Icons.cloud_upload_outlined,
          label: _isSyncingOffline && _syncInitialPending > 0
              ? 'رفعنا $offlineUploadedCount من $_syncInitialPending نبضة أوفلاين'
              : '$_pendingOfflineCount نبضة أوفلاين بانتظار الرفع',
          background: const Color(0xFFFFF1E6),
          foreground: Colors.deepOrange,
        ),
      if (_pulseCounter > 0)
        _buildStatusChip(
          icon: Icons.numbers_rounded,
          label: 'آخر نبضة #$_pulseCounter',
          background: const Color(0xFFE6ECFF),
          foreground: Colors.blueGrey,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: AppColors.primaryOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.favorite_border,
                  color: AppColors.primaryOrange,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مرحباً، ${widget.employeeId}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'إليك آخر التحديثات حول الشيفت والنبضات.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(spacing: 10, runSpacing: 10, children: statusChips),
        ],
      ),
    );
  }

  Widget _buildShiftOverviewCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alarm, color: AppColors.primaryOrange),
              const SizedBox(width: 12),
              Text(
                'لمحة عن الشيفت',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _checkedIn
                      ? AppColors.success.withValues(alpha: 0.12)
                      : Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _checkedIn ? Icons.check_circle_outline : Icons.timelapse,
                      size: 16,
                      color: _checkedIn
                          ? AppColors.success
                          : Colors.orange.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _checkedIn ? 'شيفت نشط' : 'بانتظار البدء',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: _checkedIn
                            ? AppColors.success
                            : Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 560;
              final metrics = <Widget>[
                _ShiftMetric(
                  label: 'وقت تسجيل الحضور',
                  value: _checkInTime != null
                      ? _formatTimeOfDay(_checkInTime)
                      : '--:--',
                ),
                _ShiftMetric(
                  label: 'المدة المنقضية',
                  value: _formatDuration(_elapsed),
                ),
                _ShiftMetric(
                  label: 'نبضات بانتظار المزامنة',
                  value: _pendingOfflineCount.toString(),
                ),
              ];

              if (isCompact) {
                return Column(
                  children: [
                    for (var i = 0; i < metrics.length; i++) ...[
                      metrics[i],
                      if (i != metrics.length - 1) const SizedBox(height: 12),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  for (var i = 0; i < metrics.length; i++) ...[
                    Expanded(child: metrics[i]),
                    if (i != metrics.length - 1) const SizedBox(width: 12),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceControls(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'إدارة الحضور',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'سجّل حضورك، أنهِ الشيفت، أو زامن نبضات الأوفلاين عند الحاجة.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 520;

              final startButton = FilledButton.icon(
                onPressed: _isProcessing
                    ? null
                    : _checkedIn
                    ? _showAlreadyCheckedInMessage
                    : _handleCheckIn,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(_checkedIn ? 'مسجل حضور' : 'بدء الشيفت'),
              );

              final stopButton = OutlinedButton.icon(
                onPressed: _isProcessing || !_checkedIn
                    ? null
                    : _handleCheckOut,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('إنهاء الشيفت'),
              );

              if (isCompact) {
                return Column(
                  children: [
                    SizedBox(width: double.infinity, child: startButton),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: stopButton),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: startButton),
                  const SizedBox(width: 12),
                  Expanded(child: stopButton),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showComingSoon('وضع الراحة'),
                icon: const Icon(Icons.free_breakfast),
                label: const Text('التحويل إلى راحة'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showComingSoon('تبديل الشيفت'),
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('تبديل الشيفت'),
              ),
              TextButton.icon(
                onPressed: _manualSyncOfflinePulses,
                icon: const Icon(Icons.cloud_sync_outlined),
                label: const Text('مزامنة الآن'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  VoidCallback? _showAlreadyCheckedInMessage() {
    if (!_checkedIn) {
      return null;
    }
    return () {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أنت مسجل حضور بالفعل.')));
    };
  }

  Widget _buildPulseMonitor(ThemeData theme) {
    final int offlineUploadedCount =
        (_syncInitialPending - _pendingOfflineCount)
            .clamp(0, _syncInitialPending)
            .toInt();
    final double? syncProgress =
        _isSyncingOffline && _syncInitialPending > 0
            ? offlineUploadedCount / _syncInitialPending
            : null;
  final int expectedTotalPulseCount =
    (_syncBaselineTotal ?? _totalPulseCount) +
    (_isSyncingOffline && _syncInitialPending > 0
      ? _syncInitialPending
      : _pendingOfflineCount);
    final isLocationBypassed = !_locationEnforced;
    final distanceLabel = isLocationBypassed
        ? 'تم تجاوز التحقق من الموقع'
        : _lastDistanceMeters != null
        ? '${_lastDistanceMeters!.toStringAsFixed(1)} م'
        : 'لا يوجد موقع بعد';
    final coordinatesLabel = (_lastLatitude != null && _lastLongitude != null)
        ? '${_lastLatitude!.toStringAsFixed(5)}, ${_lastLongitude!.toStringAsFixed(5)}${isLocationBypassed ? ' (تجريبي)' : ''}'
        : isLocationBypassed
        ? 'إحداثيات تجريبية'
        : 'بانتظار تحديد الإحداثيات';
  final syncStatusLabel = _isSyncingOffline && _syncInitialPending > 0
    ? 'جاري رفع $offlineUploadedCount من $_syncInitialPending نبضة أوفلاين'
    : (!_isOnline && _pendingOfflineCount > 0)
      ? 'بانتظار الإنترنت لرفع $_pendingOfflineCount نبضة'
      : _pendingOfflineCount == 0
        ? (_lastSyncAt != null
            ? 'تمت المزامنة الساعة ${_formatTimeOfDay(_lastSyncAt)}'
            : 'المزامنة مستقرة')
        : 'بانتظار إعادة المحاولة';
  final offlineDurationLabel = _offlineSince != null
    ? _formatDuration(_offlineDuration)
    : 'لحظات قليلة';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_rounded, color: AppColors.danger),
              const SizedBox(width: 12),
              Text(
                'مراقبة النبضات',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_lastPulseDeliveredOnline)
                _buildMiniPill(
                  label: 'تم الإرسال فوراً',
                  color: AppColors.success,
                )
              else if (_lastPulseQueuedOffline)
                _buildMiniPill(
                  label: 'بانتظار الإرسال',
                  color: Colors.orange.shade600,
                )
              else
                _buildMiniPill(
                  label: 'بانتظار النبضة...',
                  color: Colors.grey.shade500,
                ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 620;
              final metricPairs = <List<Widget>>[
                [
                  _PulseMetricCard(
                    label: 'إجمالي النبضات الكلي',
                    value: expectedTotalPulseCount.toString(),
                    icon: Icons.monitor_heart,
                  ),
                  _PulseMetricCard(
                    label: 'نبضات مرفوعة أونلاين',
                    value: _totalPulseCount.toString(),
                    icon: Icons.cloud_done,
                  ),
                ],
                [
                  _PulseMetricCard(
                    label: 'نبضات مخزنة أوفلاين',
                    value: _pendingOfflineCount > 0
                        ? _pendingOfflineCount.toString()
                        : 'لا يوجد',
                    icon: Icons.cloud_off,
                  ),
                  _PulseMetricCard(
                    label: 'نبضات هذا الشهر',
                    value: _monthlyPulseCount.toString(),
                    icon: Icons.calendar_month,
                  ),
                ],
                [
                  _PulseMetricCard(
                    label: 'آخر نبضة',
                    value: _formatDateTime(_lastPulseTimestamp),
                    icon: Icons.schedule_rounded,
                  ),
                  _PulseMetricCard(
                    label: 'المسافة إلى الموقع',
                    value: distanceLabel,
                    icon: Icons.directions_walk,
                  ),
                ],
                [
                  _PulseMetricCard(
                    label: 'آخر إحداثيات',
                    value: coordinatesLabel,
                    icon: Icons.location_searching,
                  ),
                  _PulseMetricCard(
                    label: 'نافذة المزامنة القادمة',
                    value: syncStatusLabel,
                    icon: Icons.sync,
                  ),
                ],
              ];

              if (isCompact) {
                final flattened = metricPairs.expand((pair) => pair).toList();
                return Column(
                  children: [
                    for (var i = 0; i < flattened.length; i++) ...[
                      SizedBox(width: double.infinity, child: flattened[i]),
                      if (i != flattened.length - 1) const SizedBox(height: 12),
                    ],
                  ],
                );
              }

              return Column(
                children: [
                  for (var i = 0; i < metricPairs.length; i++) ...[
                    Row(
                      children: [
                        Expanded(child: metricPairs[i][0]),
                        const SizedBox(width: 12),
                        Expanded(child: metricPairs[i][1]),
                      ],
                    ),
                    if (i != metricPairs.length - 1) const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
          if (!_isOnline) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.wifi_off_rounded, color: Colors.deepOrange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الاتصال مقطوع منذ $offlineDurationLabel.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _pendingOfflineCount > 0
                              ? 'بنحسب النبضات أوفلاين (${_pendingOfflineCount} نبضة) وهيتضافوا تلقائي لما النت يرجع.'
                              : 'لسه ما سجلناش نبضات أوفلاين، أول ما يحصل أي نبضة هنخزنها وهنرفعها لما النت يرجع.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'الإجمالي المتوقع بعد المزامنة: $expectedTotalPulseCount نبضة.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_isSyncingOffline) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: syncProgress,
              backgroundColor: const Color(0xFFFFE8D9),
              color: AppColors.primaryOrange,
            ),
            const SizedBox(height: 8),
            Text(
              _syncInitialPending > 0
                  ? 'جاري رفع $offlineUploadedCount من $_syncInitialPending نبضة أوفلاين إلى السحابة.'
                  : 'جاري رفع النبضات الأوفلاين إلى السحابة.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'الإجمالي المتوقع بعد المزامنة: $expectedTotalPulseCount نبضة.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ] else if (_pendingOfflineCount > 0) ...[
            const SizedBox(height: 16),
            Text(
              'هناك $_pendingOfflineCount نبضة بانتظار الرفع، هنحاول تلقائيًا مع أول اتصال مستقر.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.article_outlined, color: AppColors.primaryOrange),
              const SizedBox(width: 12),
              Text(
                'الاستئذانات والطلبات',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'عايز تطلع بدري، تطوّل البريك، أو تروح مأمورية؟ ابعت الطلب وهيتوصل للمسؤول فوراً.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: _openPermissionSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('إرسال طلب استئذان'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRequests(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الطلبات الأخيرة',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          for (final request in _requests.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primaryOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.assignment_outlined,
                      color: AppColors.primaryOrange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.type,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (request.note.isNotEmpty)
                          Text(request.note, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(
                          _formatDateTime(request.requestedAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (request.from != null || request.to != null)
                          Text(
                            _formatRequestWindow(request.from, request.to),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatRequestWindow(TimeOfDay? from, TimeOfDay? to) {
    if (from == null && to == null) {
      return '';
    }
    final fromLabel = from != null
        ? '${from.hour.toString().padLeft(2, '0')}:${from.minute.toString().padLeft(2, '0')}'
        : '--:--';
    final toLabel = to != null
        ? '${to.hour.toString().padLeft(2, '0')}:${to.minute.toString().padLeft(2, '0')}'
        : '--:--';
    return 'الفترة · $fromLabel ← $toLabel';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.onPrimary,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text('أولديزز وركرز'),
        foregroundColor: AppColors.onPrimary,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        actions: [
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed: _isProcessing ? null : _confirmLogout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            height: 260,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryOrange, Color(0xFFF5A34A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                            const SizedBox(height: kToolbarHeight + 12),
                        _buildHeader(theme),
                        const SizedBox(height: 24),
                        _buildShiftOverviewCard(theme),
                        const SizedBox(height: 18),
                        _buildAttendanceControls(theme),
                        const SizedBox(height: 18),
                        _buildPulseMonitor(theme),
                        const SizedBox(height: 18),
                        _buildPermissionCard(theme),
                        if (_requests.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          _buildRecentRequests(theme),
                        ],
                        const SizedBox(height: 36),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniPill({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ShiftMetric extends StatelessWidget {
  const _ShiftMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseMetricCard extends StatelessWidget {
  const _PulseMetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryOrange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            softWrap: true,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRequestSheet extends StatefulWidget {
  const _PermissionRequestSheet({required this.employeeId});

  final String employeeId;

  @override
  State<_PermissionRequestSheet> createState() =>
      _PermissionRequestSheetState();
}

class _PermissionRequestSheetState extends State<_PermissionRequestSheet> {
  final TextEditingController _noteController = TextEditingController();
  final List<String> _types = <String>[
    'استئذان خروج مبكر',
    'تمديد البريك',
    'مأمورية عميل',
    'إجازة مرضية',
  ];
  String? _selectedType;
  TimeOfDay? _from;
  TimeOfDay? _to;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickFromTime() async {
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (result != null) {
      setState(() {
        _from = result;
      });
    }
  }

  Future<void> _pickToTime() async {
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (result != null) {
      setState(() {
        _to = result;
      });
    }
  }

  void _submit() {
    if (_selectedType == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى اختيار نوع الطلب.')));
      return;
    }

    Navigator.of(context).pop(
      PermissionRequest(
        type: _selectedType!,
        note: _noteController.text.trim(),
        requestedAt: DateTime.now(),
        from: _from,
        to: _to,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'إرسال طلب استئذان',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'نوع الطلب',
                  border: OutlineInputBorder(),
                ),
                value: _selectedType,
                items: _types
                    .map(
                      (type) => DropdownMenuItem<String>(
                        value: type,
                        child: Text(type),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedType = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات للمسؤول',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFromTime,
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        _from == null
                            ? 'من'
                            : '${_from!.hour.toString().padLeft(2, '0')}:${_from!.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickToTime,
                      icon: const Icon(Icons.schedule_outlined),
                      label: Text(
                        _to == null
                            ? 'إلى'
                            : '${_to!.hour.toString().padLeft(2, '0')}:${_to!.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('إرسال الطلب'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
