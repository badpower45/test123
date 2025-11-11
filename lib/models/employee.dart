import 'package:hive/hive.dart';

const String employeesBox = 'employees';

enum EmployeeRole { staff, monitor, hr, admin, manager, owner }

enum EmployeePermission {
  monitorAccess,
  manageScheduling,
  viewPayroll,
  applyDiscounts,
  manageEmployees,
}

class Employee extends HiveObject {
  Employee({
    required this.id,
    required this.fullName,
    required this.pin,
    required this.role,
    List<EmployeePermission>? permissions,
    this.isActive = true,
    this.branch = 'المركز الرئيسي',
    this.hourlyRate = 0,
    this.shiftStartTime,
    this.shiftEndTime,
    this.address,
    this.birthDate,
    this.email,
    this.phone,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : permissions = permissions ?? <EmployeePermission>[],
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  String id;
  String fullName;
  String pin;
  EmployeeRole role;
  List<EmployeePermission> permissions;
  bool isActive;
  String branch;
  double hourlyRate; // سعر الساعة
  String? shiftStartTime; // وقت بداية الشيفت (e.g., "09:00")
  String? shiftEndTime; // وقت نهاية الشيفت (e.g., "17:00")
  String? address;
  DateTime? birthDate;
  String? email;
  String? phone;
  DateTime createdAt;
  DateTime updatedAt;

  void touch() {
    updatedAt = DateTime.now().toUtc();
  }

  // JSON Serialization for Supabase
  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      pin: json['pin'] as String,
      role: _roleFromString(json['role'] as String?),
      permissions: [], // Permissions not in Supabase yet
      isActive: json['is_active'] as bool? ?? true,
      branch: json['branch'] as String? ?? 'المركز الرئيسي',
      hourlyRate: (json['hourly_rate'] as num?)?.toDouble() ?? 0,
      shiftStartTime: json['shift_start_time'] as String?,
      shiftEndTime: json['shift_end_time'] as String?,
      address: json['address'] as String?,
      birthDate: json['birth_date'] != null 
          ? DateTime.tryParse(json['birth_date'] as String) 
          : null,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now().toUtc(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'pin': pin,
      'role': role.name,
      'is_active': isActive,
      'branch': branch,
      'hourly_rate': hourlyRate,
      'shift_start_time': shiftStartTime,
      'shift_end_time': shiftEndTime,
      'address': address,
      'birth_date': birthDate?.toIso8601String(),
      'email': email,
      'phone': phone,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static EmployeeRole _roleFromString(String? roleStr) {
    switch (roleStr?.toLowerCase()) {
      case 'owner':
        return EmployeeRole.owner;
      case 'manager':
        return EmployeeRole.manager;
      case 'admin':
        return EmployeeRole.admin;
      case 'hr':
        return EmployeeRole.hr;
      case 'monitor':
        return EmployeeRole.monitor;
      default:
        return EmployeeRole.staff;
    }
  }
}

class EmployeeAdapter extends TypeAdapter<Employee> {
  @override
  final int typeId = 3;

  @override
  Employee read(BinaryReader reader) {
    final fieldCount = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
    };
    final roleIndex = fields[3] as int? ?? 0;
    final permissionsRaw = (fields[4] as List?)?.cast<int>() ?? <int>[];
    final branch = fields[8] as String? ?? 'المركز الرئيسي';
    final hourlyRate = (fields[9] as num?)?.toDouble() ?? 0;
    final shiftStart = fields[15] as String?;
    final shiftEnd = fields[16] as String?;
    return Employee(
      id: fields[0] as String,
      fullName: fields[1] as String,
      pin: fields[2] as String,
      role: EmployeeRole.values[_safeEnumIndex(roleIndex, EmployeeRole.values)],
      permissions: permissionsRaw
          .where((index) => index >= 0 && index < EmployeePermission.values.length)
          .map((index) => EmployeePermission.values[index])
          .toList(),
      isActive: fields[5] as bool? ?? true,
      branch: branch,
      hourlyRate: hourlyRate,
      shiftStartTime: shiftStart,
      shiftEndTime: shiftEnd,
      address: fields[10] as String?,
      birthDate: fields[11] != null ? DateTime.tryParse(fields[11] as String) : null,
      email: fields[12] as String?,
      phone: fields[13] as String?,
      createdAt: DateTime.tryParse(fields[6] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: DateTime.tryParse(fields[7] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  @override
  void write(BinaryWriter writer, Employee obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.fullName)
      ..writeByte(2)
      ..write(obj.pin)
      ..writeByte(3)
      ..write(obj.role.index)
      ..writeByte(4)
      ..write(obj.permissions.map((permission) => permission.index).toList())
      ..writeByte(5)
      ..write(obj.isActive)
      ..writeByte(6)
      ..write(obj.createdAt.toUtc().toIso8601String())
      ..writeByte(7)
      ..write(obj.updatedAt.toUtc().toIso8601String())
      ..writeByte(8)
      ..write(obj.branch)
      ..writeByte(9)
      ..write(obj.hourlyRate)
      ..writeByte(10)
      ..write(obj.address)
      ..writeByte(11)
      ..write(obj.birthDate?.toUtc().toIso8601String())
      ..writeByte(12)
      ..write(obj.email)
      ..writeByte(13)
      ..write(obj.phone)
      ..writeByte(15)
      ..write(obj.shiftStartTime)
      ..writeByte(16)
      ..write(obj.shiftEndTime);
  }
}

int _safeEnumIndex<T>(int index, List<T> values) {
  if (index < 0 || index >= values.length) {
    return 0;
  }
  return index;
}

void registerEmployeeAdapter() {
  if (!Hive.isAdapterRegistered(3)) {
    Hive.registerAdapter(EmployeeAdapter());
  }
}
