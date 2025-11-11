import 'package:hive/hive.dart';

const String offlinePulsesBox = 'offline_pulses';

class Pulse extends HiveObject {
  Pulse({
    required this.employeeId,
    this.branchId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.wifiBssid,
    this.status = 'IN',
    this.isWithinGeofence,
    this.isFake = false,
    this.isSynced = true,
    // BLV Environmental Data
    this.wifiCount,
    this.wifiSignalStrength,
    this.batteryLevel,
    this.isCharging,
    this.accelVariance,
    this.soundLevel,
    this.deviceOrientation,
    this.deviceModel,
    this.osVersion,
  });

  final String employeeId;
  final String? branchId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? wifiBssid;
  final String status;
  final bool? isWithinGeofence;
  final bool isFake;
  final bool isSynced;
  
  // BLV Environmental Data
  final int? wifiCount;
  final double? wifiSignalStrength;
  final double? batteryLevel;
  final bool? isCharging;
  final double? accelVariance;
  final double? soundLevel;
  final String? deviceOrientation;
  final String? deviceModel;
  final String? osVersion;

  Map<String, dynamic> toJson() => {
        'user_id': employeeId,
        'branch_id': branchId,
        'latitude': latitude,
        'longitude': longitude,
        'bssid_address': wifiBssid,
        'is_within_geofence': isWithinGeofence,
        'is_fake': isFake,
        'status': status,
        'created_at': timestamp.toIso8601String(),
        'is_synced': isSynced,
      }..removeWhere((key, value) => value == null);

  Map<String, dynamic> toApiPayload() => {
        'employee_id': employeeId,
        'latitude': latitude,
        'longitude': longitude,
        'wifi_bssid': wifiBssid,
        'is_within_geofence': isWithinGeofence,
        'is_fake': isFake,
        'timestamp': timestamp.toIso8601String(),
        // BLV Environmental Data
        'wifi_count': wifiCount,
        'wifi_signal_strength': wifiSignalStrength,
        'battery_level': batteryLevel,
        'is_charging': isCharging,
        'accel_variance': accelVariance,
        'sound_level': soundLevel,
        'device_orientation': deviceOrientation,
        'device_model': deviceModel,
        'os_version': osVersion,
      }..removeWhere((key, value) => value == null);

  static Pulse fromJson(Map<String, dynamic> json) => Pulse(
        employeeId: (json['user_id'] ?? json['employeeId']) as String,
        branchId: json['branch_id'] as String?,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        timestamp: DateTime.parse(
          (json['created_at'] ?? json['timestamp'] ?? json['createdAt']) as String,
        ),
        wifiBssid: (json['bssid_address'] ?? json['wifiBssid']) as String?,
        status: (json['status'] ?? 'IN') as String,
        isWithinGeofence:
            (json['is_within_geofence'] ?? json['isWithinGeofence']) as bool?,
        isFake: (json['is_fake'] ?? json['isFake'] ?? false) as bool,
        isSynced: (json['is_synced'] ?? json['isSynced'] ?? true) as bool,
      );
}

class PulseAdapter extends TypeAdapter<Pulse> {
  @override
  final int typeId = 1;

  @override
  Pulse read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return Pulse(
      employeeId: fields[0] as String,
      branchId: fields[1] as String?,
      latitude: fields[2] as double,
      longitude: fields[3] as double,
      timestamp: DateTime.parse(fields[4] as String),
      wifiBssid: fields[5] as String?,
      status: fields[6] as String? ?? 'IN',
      isWithinGeofence: fields[7] as bool?,
      isFake: fields[8] as bool? ?? false,
      isSynced: fields[9] as bool? ?? true,
    );
  }

  @override
  void write(BinaryWriter writer, Pulse obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.employeeId)
      ..writeByte(1)
      ..write(obj.branchId)
      ..writeByte(2)
      ..write(obj.latitude)
      ..writeByte(3)
      ..write(obj.longitude)
      ..writeByte(4)
      ..write(obj.timestamp.toIso8601String())
      ..writeByte(5)
      ..write(obj.wifiBssid)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.isWithinGeofence)
      ..writeByte(8)
      ..write(obj.isFake)
      ..writeByte(9)
      ..write(obj.isSynced);
  }
}

void registerPulseAdapter() {
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(PulseAdapter());
  }
}
