import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'pulse_tracking_service.dart';
import 'pulse_reconciliation_helper.dart';

/// 🚀 PHASE 4: Attendance Timer Service (Refactored)
/// Manages two timers:
/// 1. Shift Countdown Timer: Counts down from the beginning to the end of the shift.
/// 2. Money/Earnings Timer: Pulse-gated worked time, credited in 5-minute increments
///    only when pulses are true, ticking up in real-time when inside.
class AttendanceTimerService {
  static final AttendanceTimerService instance = AttendanceTimerService._();
  AttendanceTimerService._();

  Timer? _timer;
  DateTime? _checkInTime;
  String? _shiftEndTimeStr;
  String _elapsedTime = '00:00:00';
  String _shiftCountdown = '00:00:00';
  double _currentEarnings = 0.0;
  double _hourlyRate = 0.0;
  int _maxWorkedSeconds = 0;
  SharedPreferences? _prefs;
  
  // Listeners for UI updates
  final List<Function(String elapsedTime, double earnings)> _listeners = [];

  /// Check if timer is currently paused due to being outside
  bool get isPausedDueToOutside => _prefs?.getBool('timer_paused_due_to_outside') ?? false;

  /// Get the reason for the pause
  String get pausedReason => _prefs?.getString('timer_paused_reason') ?? 'خارج النطاق';

  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Utility to pause timer locally (from background or foreground)
  static Future<void> pauseTimerLocally({required String reason}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isAlreadyPaused = prefs.getBool('timer_paused_due_to_outside') ?? false;
      if (!isAlreadyPaused) {
        await prefs.setBool('timer_paused_due_to_outside', true);
        await prefs.setString('timer_paused_at', DateTime.now().toIso8601String());
        await prefs.setString('timer_paused_reason', reason);
        print('⏸️ [AttendanceTimerService] Timer paused locally: $reason');
      }
    } catch (e) {
      print('⚠️ [AttendanceTimerService] Error pausing timer locally: $e');
    }
  }

  /// Utility to resume timer locally (from background or foreground)
  static Future<void> resumeTimerLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isPaused = prefs.getBool('timer_paused_due_to_outside') ?? false;
      if (isPaused) {
        final pausedAtStr = prefs.getString('timer_paused_at');
        int additionalPausedSeconds = 0;
        if (pausedAtStr != null) {
          try {
            final pausedAt = DateTime.parse(pausedAtStr);
            additionalPausedSeconds = DateTime.now().difference(pausedAt).inSeconds;
          } catch (_) {}
        }
        
        final currentTotal = prefs.getInt('timer_total_paused_seconds') ?? 0;
        await prefs.setInt('timer_total_paused_seconds', currentTotal + additionalPausedSeconds);
        await prefs.setBool('timer_paused_due_to_outside', false);
        await prefs.remove('timer_paused_at');
        await prefs.remove('timer_paused_reason');
        print('▶️ [AttendanceTimerService] Timer resumed locally. Added $additionalPausedSeconds paused seconds.');
      }
    } catch (e) {
      print('⚠️ [AttendanceTimerService] Error resuming timer locally: $e');
    }
  }

  /// Get current elapsed worked time (paid)
  String get elapsedTime => _elapsedTime;
  
  /// Get current shift remaining countdown
  String get shiftCountdown => _shiftCountdown;
  
  /// Get current earnings
  double get currentEarnings => _currentEarnings;
  
  /// Check if timer is running
  bool get isRunning => _timer != null && _timer!.isActive;
  
  /// Get check-in time
  DateTime? get checkInTime => _checkInTime;

  /// Add listener for timer updates
  void addListener(Function(String elapsedTime, double earnings) listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// Remove listener
  void removeListener(Function(String elapsedTime, double earnings) listener) {
    _listeners.remove(listener);
  }

  /// Notify all listeners of timer update
  void _notifyListeners() {
    for (var listener in List<Function(String elapsedTime, double earnings)>.from(_listeners)) {
      try {
        listener(_elapsedTime, _currentEarnings);
      } catch (e) {
        print('⚠️ Error notifying timer listener: $e');
      }
    }
  }

  /// Helper to calculate the shift end time today/tomorrow based on check-in
  static DateTime getShiftEndTime(DateTime checkIn, String? endTimeStr) {
    if (endTimeStr == null || endTimeStr.isEmpty) {
      return checkIn.add(const Duration(hours: 8)); // default 8h shift
    }
    try {
      final parts = endTimeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      
      // Use checkIn's date instead of current now time, so calculation remains
      // consistent across dates if active session spans across day boundary.
      var shiftEnd = DateTime(checkIn.year, checkIn.month, checkIn.day, hour, minute);
      
      if (shiftEnd.isBefore(checkIn)) {
        shiftEnd = shiftEnd.add(const Duration(days: 1));
      }
      return shiftEnd;
    } catch (e) {
      return checkIn.add(const Duration(hours: 8));
    }
  }

  /// Calculates the actual paid worked seconds
  int calculateWorkedSeconds() {
    if (_checkInTime == null) return 0;
    
    final pulseService = PulseTrackingService();
    final lastPulse = pulseService.lastPulseTime ?? _checkInTime!;
    
    final pulses = pulseService.pulsesCount;
    final outside = pulseService.outsidePulsesCount;
    final insidePulsesCount = (pulses - outside).clamp(0, pulses);
    
    int baseSeconds = insidePulsesCount * 300;
    
    final now = DateTime.now();
    final currentBlockSeconds = now.difference(lastPulse).inSeconds;
    
    final isPaused = isPausedDueToOutside;
    final isCurrentlyInside = !isPaused && pulseService.isCurrentlyInside;
    
    if (currentBlockSeconds > 0) {
      if (isCurrentlyInside) {
        baseSeconds += currentBlockSeconds.clamp(0, 300);
      }
    }
    
    final totalPausedSeconds = _prefs?.getInt('timer_total_paused_seconds') ?? 0;
    int currentPauseSeconds = 0;
    if (isPaused) {
      final pausedAtStr = _prefs?.getString('timer_paused_at');
      if (pausedAtStr != null) {
        try {
          final pausedAt = DateTime.parse(pausedAtStr);
          currentPauseSeconds = DateTime.now().difference(pausedAt).inSeconds;
        } catch (_) {}
      }
    }
    final effectivePausedSeconds = totalPausedSeconds + currentPauseSeconds;
    
    // Apply reconciliation helper
    final reconciledSeconds = PulseReconciliationHelper.reconcileWorkedSeconds(
      checkInTime: _checkInTime!,
      currentWorkedSeconds: baseSeconds,
      pulsesCount: pulses,
      outsidePulsesCount: outside,
      isCurrentlyInside: isCurrentlyInside,
      pausedSeconds: effectivePausedSeconds,
    );
    
    if (reconciledSeconds > _maxWorkedSeconds) {
      _maxWorkedSeconds = reconciledSeconds;
      _persistState();
    }
    
    return _maxWorkedSeconds;
  }

  /// Start timer
  void startTimer({
    required DateTime checkInTime,
    required double hourlyRate,
    String? shiftEndTimeStr,
  }) {
    _initPrefs().then((_) {
      forceTickUpdate();
    });

    final normalizedCheckIn = checkInTime.toLocal();
    final safeCheckInTime = normalizedCheckIn.isAfter(DateTime.now())
        ? DateTime.now()
        : normalizedCheckIn;

    // Avoid unnecessary timer restart when state is already identical.
    if (_timer?.isActive == true &&
        _checkInTime?.millisecondsSinceEpoch == safeCheckInTime.millisecondsSinceEpoch &&
        _hourlyRate == hourlyRate &&
        _shiftEndTimeStr == shiftEndTimeStr) {
      return;
    }

    print('🚀 PHASE 4: Starting attendance dual-timer');
    
    _checkInTime = safeCheckInTime;
    _hourlyRate = hourlyRate;
    _shiftEndTimeStr = shiftEndTimeStr;
    
    // Calculate initial values
    final workedSec = calculateWorkedSeconds();
    _elapsedTime = _formatDuration(Duration(seconds: workedSec));
    _currentEarnings = _computeEarnings(Duration(seconds: workedSec));
    
    // Initial shift countdown (acts as elapsed timer if shift end is not set)
    if (_shiftEndTimeStr == null || _shiftEndTimeStr!.isEmpty) {
      final elapsed = DateTime.now().difference(safeCheckInTime);
      _shiftCountdown = _formatDuration(elapsed.isNegative ? Duration.zero : elapsed);
    } else {
      final shiftEnd = getShiftEndTime(safeCheckInTime, _shiftEndTimeStr);
      final remaining = shiftEnd.difference(DateTime.now());
      _shiftCountdown = remaining.isNegative ? '00:00:00' : _formatDuration(remaining);
    }

    // Cancel existing timer if any
    _timer?.cancel();
    
    // Start new timer (updates every second)
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_checkInTime != null) {
        final currentWorkedSeconds = calculateWorkedSeconds();
        final currentWorkedDuration = Duration(seconds: currentWorkedSeconds);
        _elapsedTime = _formatDuration(currentWorkedDuration);
        _currentEarnings = _computeEarnings(currentWorkedDuration);
        
        if (_shiftEndTimeStr == null || _shiftEndTimeStr!.isEmpty) {
          final elapsed = DateTime.now().difference(_checkInTime!);
          _shiftCountdown = _formatDuration(elapsed.isNegative ? Duration.zero : elapsed);
        } else {
          final end = getShiftEndTime(_checkInTime!, _shiftEndTimeStr);
          final rem = end.difference(DateTime.now());
          _shiftCountdown = rem.isNegative ? '00:00:00' : _formatDuration(rem);
        }

        // Notify UI listeners
        _notifyListeners();
        
        // Persist state every minute
        final totalElapsedSeconds = DateTime.now().difference(_checkInTime!).inSeconds;
        if (totalElapsedSeconds % 60 == 0) {
          _persistState();
        }
      }
    });
    
    // Persist initial state
    _persistState();
    
    print('✅ Attendance dual-timer started successfully');
  }

  /// Force recalculation and UI update immediately
  void forceTickUpdate() {
    if (_checkInTime != null) {
      final currentWorkedSeconds = calculateWorkedSeconds();
      final currentWorkedDuration = Duration(seconds: currentWorkedSeconds);
      _elapsedTime = _formatDuration(currentWorkedDuration);
      _currentEarnings = _computeEarnings(currentWorkedDuration);
      
      if (_shiftEndTimeStr == null || _shiftEndTimeStr!.isEmpty) {
        final elapsed = DateTime.now().difference(_checkInTime!);
        _shiftCountdown = _formatDuration(elapsed.isNegative ? Duration.zero : elapsed);
      } else {
        final end = getShiftEndTime(_checkInTime!, _shiftEndTimeStr);
        final rem = end.difference(DateTime.now());
        _shiftCountdown = rem.isNegative ? '00:00:00' : _formatDuration(rem);
      }
      
      _notifyListeners();
    }
  }

  /// Stop timer
  void stopTimer() {
    print('🛑 Stopping attendance timer service');
    
    _timer?.cancel();
    _timer = null;
    _checkInTime = null;
    _shiftEndTimeStr = null;
    _elapsedTime = '00:00:00';
    _shiftCountdown = '00:00:00';
    _currentEarnings = 0.0;
    _hourlyRate = 0.0;
    _maxWorkedSeconds = 0;
    
    // Clear persisted state
    _clearPersistedState();
    
    // Notify listeners one last time
    _notifyListeners();
    
    print('✅ Attendance timer stopped');
  }

  /// Resume timer from persisted state (after app restart)
  Future<bool> resumeTimerIfNeeded(double hourlyRate) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      final checkInTimeStr = prefs.getString('timer_check_in_time');
      final shiftEndTimeStr = prefs.getString('timer_shift_end_time');
      _maxWorkedSeconds = prefs.getInt('timer_max_worked_seconds') ?? 0;
      
      if (checkInTimeStr != null) {
        final checkInTime = DateTime.parse(checkInTimeStr);
        print('📱 Resuming timer from persisted state: $checkInTime, max worked seconds: $_maxWorkedSeconds');
        
        startTimer(
          checkInTime: checkInTime,
          hourlyRate: hourlyRate,
          shiftEndTimeStr: shiftEndTimeStr,
        );
        
        return true;
      }
    } catch (e) {
      print('⚠️ Error resuming timer: $e');
    }
    
    return false;
  }

  /// Persist timer state to SharedPreferences
  Future<void> _persistState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_checkInTime != null) {
        await prefs.setString('timer_check_in_time', _checkInTime!.toIso8601String());
        await prefs.setDouble('timer_hourly_rate', _hourlyRate);
        await prefs.setInt('timer_max_worked_seconds', _maxWorkedSeconds);
        if (_shiftEndTimeStr != null) {
          await prefs.setString('timer_shift_end_time', _shiftEndTimeStr!);
        }
      }
    } catch (e) {
      print('⚠️ Error persisting timer state: $e');
    }
  }

  /// Clear persisted state
  Future<void> _clearPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('timer_check_in_time');
      await prefs.remove('timer_hourly_rate');
      await prefs.remove('timer_shift_end_time');
      await prefs.remove('timer_max_worked_seconds');
      await prefs.remove('timer_paused_due_to_outside');
      await prefs.remove('timer_paused_at');
      await prefs.remove('timer_paused_reason');
      await prefs.remove('timer_total_paused_seconds');
    } catch (e) {
      print('⚠️ Error clearing timer state: $e');
    }
  }

  /// Format duration as HH:MM:SS
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  /// Compute earnings based on duration and hourly rate
  double _computeEarnings(Duration duration) {
    final hours = duration.inSeconds / 3600.0;
    final earnings = _hourlyRate * hours;
    
    if (earnings.isNaN || earnings.isInfinite || earnings < 0) return 0.0;
    
    return earnings;
  }

  /// Dispose service (cleanup)
  void dispose() {
    _timer?.cancel();
    _listeners.clear();
  }
}
