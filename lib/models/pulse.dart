import 'package:hive/hive.dart';

const String offlinePulsesBox = 'offline_pulses';

class Pulse extends HiveObject {
  Pulse({
    required this.employeeId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.isFake,
  });

  final String employeeId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool isFake;

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
        'isFake': isFake,
      };

  static Pulse fromJson(Map<String, dynamic> json) => Pulse(
        employeeId: json['employeeId'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        timestamp: DateTime.parse(json['timestamp'] as String),
        isFake: json['isFake'] as bool,
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
      isFake: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Pulse obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.employeeId)
      ..writeByte(1)
      ..write(obj.latitude)
      ..writeByte(2)
      ..write(obj.longitude)
      ..writeByte(3)
      ..write(obj.timestamp.toIso8601String())
      ..writeByte(4)
      ..write(obj.isFake);
  }
}

void registerPulseAdapter() {
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(PulseAdapter());
  }
}
