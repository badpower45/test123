import 'app_logger.dart';

/// 🧠 Smart Pulse Reconciliation Helper
/// 
/// Automatically analyzes the employee's active attendance session.
/// If there are no negative (outside) pulses recorded during the session,
/// it ensures the money timer remains perfectly synchronized with the actual elapsed
/// time since check-in, preventing missing minutes due to background latency.
class PulseReconciliationHelper {
  
  /// Reconciles worked seconds with elapsed seconds
  /// [checkInTime]: The start of the shift
  /// [currentWorkedSeconds]: The raw accumulated seconds based on inside pulses
  /// [pulsesCount]: Total recorded pulses
  /// [outsidePulsesCount]: Number of outside pulses recorded
  /// [isCurrentlyInside]: Whether the employee is currently marked as inside
  static int reconcileWorkedSeconds({
    required DateTime checkInTime,
    required int currentWorkedSeconds,
    required int pulsesCount,
    required int outsidePulsesCount,
    required bool isCurrentlyInside,
    int pausedSeconds = 0,
  }) {
    final now = DateTime.now();
    final elapsedDuration = now.difference(checkInTime);
    final elapsedSeconds = elapsedDuration.inSeconds;
    
    // Safety check: if time is negative or check-in is in the future
    if (elapsedSeconds <= 0) {
      return 0;
    }
    
    // Case 1: Active session has ZERO recorded outside pulses
    // This means the user has stayed inside the branch the entire time.
    if (outsidePulsesCount == 0 && isCurrentlyInside) {
      // Worked seconds must match elapsed seconds perfectly (minus paused seconds)!
      final reconciled = elapsedSeconds - pausedSeconds;
      if (reconciled > currentWorkedSeconds) {
        AppLogger.instance.log(
          'Reconciliation active: zero outside pulses. Syncing worked seconds ($currentWorkedSeconds -> $reconciled, paused: $pausedSeconds).',
          tag: 'TimerReconciler',
        );
        return reconciled;
      }
    }
    
    return currentWorkedSeconds;
  }
}
