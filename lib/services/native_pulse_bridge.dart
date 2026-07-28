import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_io/io.dart';

import 'native_pulse_service.dart';
import 'offline_data_service.dart';

class NativePulseBridge {
  static const int _intervalMinutes = 5;

  static Future<void> startForAttendance({
    required String employeeId,
    required String attendanceId,
    required String branchId,
    int? shiftEndTimeEpoch,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }

    final branchData = await OfflineDataService().getCachedBranchData(
      employeeId: employeeId,
    );

    if (branchData == null) {
      print('⚠️ Native pulse start skipped: branch data missing');
      return;
    }

    final centerLat = (branchData['latitude'] as num?)?.toDouble();
    final centerLng = (branchData['longitude'] as num?)?.toDouble();
    if (centerLat == null || centerLng == null) {
      print('⚠️ Native pulse start skipped: branch coordinates missing');
      return;
    }

    final baseRadius =
        (branchData['geofence_radius'] as num?)?.toDouble() ?? 100.0;
    final extraTolerance =
        ((branchData['distance_from_radius'] as num?)?.toDouble() ?? 0.0)
            .clamp(0.0, 500.0);
    final radius = baseRadius + extraTolerance;

    await NativePulseService.startPersistentService(
      employeeId: employeeId,
      attendanceId: attendanceId,
      branchId: branchId,
      intervalMinutes: _intervalMinutes,
      branchLatitude: centerLat,
      branchLongitude: centerLng,
      branchRadius: radius,
      shiftEndTimeEpoch: shiftEndTimeEpoch,
    );
  }

  static Future<void> stop() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }

    await NativePulseService.stopPersistentService();
  }
}
