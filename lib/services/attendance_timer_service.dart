import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

/// 🚀 PHASE 4: Attendance Timer Service
/// Manages attendance timer independently from UI
/// Timer continues even if UI page is closed or rebuilt
class AttendanceTimerService {
  static final AttendanceTimerService instance = AttendanceTimerService._();
  AttendanceTimerService._();

  Timer? _timer;
  DateTime? _checkInTime;
  String _elapsedTime = '00:00:00';
  double _currentEarnings = 0.0;
  double _hourlyRate = 0.0;
  
  // Listeners for UI updates
  final List<Function(String elapsedTime, double earnings)> _listeners = [];

  /// Get current elapsed time
  String get elapsedTime => _elapsedTime;
  
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
    for (var listener in _listeners) {
      try {
        listener(_elapsedTime, _currentEarnings);
      } catch (e) {
        print('⚠️ Error notifying timer listener: $e');
      }
    }
  }

  /// Start timer
  /// This continues running even if UI is closed
  void startTimer({
    required DateTime checkInTime,
    required double hourlyRate,
  }) {
    print('🚀 PHASE 4: Starting attendance timer service');
    print('   Check-in time: $checkInTime');
    print('   Hourly rate: $hourlyRate');
    
    _checkInTime = checkInTime;
    _hourlyRate = hourlyRate;
    
    // Calculate initial values
    final duration = DateTime.now().difference(_checkInTime!);
    _elapsedTime = _formatDuration(duration);
    _currentEarnings = _computeEarnings(duration);
    
    // Cancel existing timer if any
    _timer?.cancel();
    
    // Start new timer (updates every second)
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_checkInTime != null) {
        final duration = DateTime.now().difference(_checkInTime!);
        _elapsedTime = _formatDuration(duration);
        _currentEarnings = _computeEarnings(duration);
        
        // Notify UI listeners
        _notifyListeners();
        
        // Persist state every minute (for app restart recovery)
        if (duration.inSeconds % 60 == 0) {
          _persistState();
        }
      }
    });
    
    // Persist initial state
    _persistState();
    
    print('✅ Attendance timer started successfully');
  }

  /// Stop timer
  void stopTimer() {
    print('🛑 Stopping attendance timer service');
    
    _timer?.cancel();
    _timer = null;
    _checkInTime = null;
    _elapsedTime = '00:00:00';
    _currentEarnings = 0.0;
    _hourlyRate = 0.0;
    
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
      final checkInTimeStr = prefs.getString('timer_check_in_time');
      
      if (checkInTimeStr != null) {
        final checkInTime = DateTime.parse(checkInTimeStr);
        print('📱 Resuming timer from persisted state: $checkInTime');
        
        startTimer(
          checkInTime: checkInTime,
          hourlyRate: hourlyRate,
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
    // Pro-rated per second for smooth updates
    final hours = duration.inSeconds / 3600.0;
    final earnings = _hourlyRate * hours;
    
    // Avoid negative/NaN
    if (earnings.isNaN || earnings.isInfinite || earnings < 0) return 0.0;
    
    return earnings;
  }

  /// Dispose service (cleanup)
  void dispose() {
    _timer?.cancel();
    _listeners.clear();
  }
}
