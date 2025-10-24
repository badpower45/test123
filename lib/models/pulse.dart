import 'package:hive/hive.dart';

const String offlinePulsesBox = 'offline_pulses';

class Pulse extends HiveObject {
  Pulse({
    required this.employeeId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.wifiBssid,
    bool isFake = false,
    this.isWithinGeofence,
  }) : isFake = isFake;

  final String employeeId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? wifiBssid;
  final bool isFake;
  final bool? isWithinGeofence;

  Map<String, dynamic> toJson() => {
        'employee_id': employeeId,
        'latitude': latitude,
        'longitude': longitude,
        'wifi_bssid': wifiBssid,
        'is_within_geofence': isWithinGeofence,
        'timestamp': timestamp.toIso8601String(),
        'is_fake': isFake,
      }..removeWhere((key, value) => value == null);

  Map<String, dynamic> toApiPayload() => {
        'employee_id': employeeId,
        'latitude': latitude,
        'longitude': longitude,
        'wifi_bssid': wifiBssid,
        'is_within_geofence': isWithinGeofence,
        'timestamp': timestamp.toIso8601String(),
      }..removeWhere((key, value) => value == null);

  static Pulse fromJson(Map<String, dynamic> json) => Pulse(
        employeeId: (json['employee_id'] ?? json['employeeId']) as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        timestamp: DateTime.parse(
          (json['timestamp'] ?? json['createdAt']) as String,
        ),
        isFake: (json['is_fake'] ?? json['isFake'] ?? false) as bool,
        wifiBssid: (json['wifi_bssid'] ?? json['wifiBssid']) as String?,
        isWithinGeofence:
            (json['is_within_geofence'] ?? json['isWithinGeofence']) as bool?,
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
      latitude: fields[1] as double,
      longitude: fields[2] as double,
      timestamp: DateTime.parse(fields[3] as String),
      isFake: fields[4] as bool? ?? false,
      wifiBssid: fields[5] as String?,
      isWithinGeofence: fields[6] as bool?,
    );
  }

  @override
  void write(BinaryWriter writer, Pulse obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.employeeId)
      ..writeByte(1)
      ..write(obj.latitude)
      ..writeByte(2)
      ..write(obj.longitude)
      ..writeByte(3)
      ..write(obj.timestamp.toIso8601String())
      ..writeByte(4)
      ..write(obj.isFake)
      ..writeByte(5)
      ..write(obj.wifiBssid)
      ..writeByte(6)
      ..write(obj.isWithinGeofence);
  }
}

void registerPulseAdapter() {
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(PulseAdapter());
  }
}
