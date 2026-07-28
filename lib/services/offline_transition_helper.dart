import '../database/offline_database.dart';
import 'attendance_timer_service.dart';
import 'sync_service.dart';

/// 🛡️ Offline Transition Helper
///
/// Protects the employee's checked-in state from being overridden
/// by the server check status (which might temporarily return checked-out
/// during network transitions or before local data is synced).
class OfflineTransitionHelper {
  /// Checks if the local check-in session is still active and should be protected
  /// from being overridden by the server's check-in status (e.g., during offline-online transitions).
  static Future<bool> shouldKeepLocalCheckIn({
    required bool localCheckedInFlag,
    required bool wasCheckedIn,
    required DateTime? checkInTime,
    required String? shiftEndTimeStr,
    required bool isOfflineAttendance,
    bool cachedAttendanceStillActive = true,
  }) async {
    // 1. If not checked in locally at all, no need to keep it
    if (!localCheckedInFlag && !wasCheckedIn) {
      return false;
    }

    // 2. If the server explicitly confirmed that the attendance is inactive/completed,
    // we do not protect the local check-in.
    if (!cachedAttendanceStillActive) {
      print('🛡️ [OfflineTransitionHelper] Server explicitly confirmed checkout. Not protecting check-in status.');
      return false;
    }

    // 3. Under the new policy, we always protect the active local session from being overridden 
    // by any server check-in status (since auto-checkout is completely disabled by policy).
    print('🛡️ [OfflineTransitionHelper] Local session is active. Protecting check-in status.');
    return true;
  }
}
