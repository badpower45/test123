import 'package:hive/hive.dart';

import 'pulse.dart';

const String pulseHistoryBox = 'pulse_history';

enum PulseDeliveryStatus {
  sentOnline,
  queuedOffline,
  failed,
}

class PulseLogEntry extends HiveObject {
  PulseLogEntry({
    required this.pulse,
    required this.recordedAt,
    required this.wasOnline,
    required this.deliveryStatus,
  });

  final Pulse pulse;
  final DateTime recordedAt;
  final bool wasOnline;
  final PulseDeliveryStatus deliveryStatus;

  Map<String, dynamic> toJson() => {
        'pulse': pulse.toJson(),
        'recordedAt': recordedAt.toIso8601String(),
        'wasOnline': wasOnline,
        'deliveryStatus': deliveryStatus.index,
      };

  static PulseLogEntry fromJson(Map<String, dynamic> json) => PulseLogEntry(
        pulse: Pulse.fromJson(json['pulse'] as Map<String, dynamic>),
        recordedAt: DateTime.parse(json['recordedAt'] as String),
        wasOnline: json['wasOnline'] as bool,
        deliveryStatus:
            PulseDeliveryStatus.values[json['deliveryStatus'] as int],
      );
}

class PulseLogEntryAdapter extends TypeAdapter<PulseLogEntry> {
  @override
  int get typeId => 2;

  @override
  PulseLogEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    final rawIndex = fields[3] as int;
    final safeIndex = (rawIndex >= 0 && rawIndex < PulseDeliveryStatus.values.length)
        ? rawIndex
        : 0;
    return PulseLogEntry(
      pulse: Pulse.fromJson(Map<String, dynamic>.from(fields[0] as Map)),
      recordedAt: DateTime.parse(fields[1] as String),
      wasOnline: fields[2] as bool,
      deliveryStatus: PulseDeliveryStatus.values[safeIndex],
    );
  }

  @override
  void write(BinaryWriter writer, PulseLogEntry obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.pulse.toJson())
      ..writeByte(1)
      ..write(obj.recordedAt.toIso8601String())
      ..writeByte(2)
      ..write(obj.wasOnline)
      ..writeByte(3)
      ..write(obj.deliveryStatus.index);
  }
}

void registerPulseLogEntryAdapter() {
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(PulseLogEntryAdapter());
  }
}
