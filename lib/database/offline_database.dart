import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class OfflineDatabase {
  static final OfflineDatabase instance = OfflineDatabase._init();
  static Database? _database;

  OfflineDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('offline_attendance.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT NOT NULL';
    const textTypeNull = 'TEXT';
    const integerType = 'INTEGER NOT NULL';
    const realType = 'REAL';

    // Pending check-ins (حضور معلق)
    await db.execute('''
      CREATE TABLE pending_checkins (
        id $idType,
        employee_id $textType,
        timestamp $textType,
        latitude $realType,
        longitude $realType,
        wifi_bssid $textTypeNull,
        created_at $textType,
        synced $integerType DEFAULT 0
      )
    ''');

    // Pending check-outs (انصراف معلق)
    await db.execute('''
      CREATE TABLE pending_checkouts (
        id $idType,
        employee_id $textType,
        attendance_id $textTypeNull,
        timestamp $textType,
        latitude $realType,
        longitude $realType,
        created_at $textType,
        synced $integerType DEFAULT 0
      )
    ''');

    // Pending pulses (نبضات معلقة)
    await db.execute('''
      CREATE TABLE pending_pulses (
        id $idType,
        employee_id $textType,
        timestamp $textType,
        created_at $textType,
        synced $integerType DEFAULT 0
      )
    ''');

    // Geofence violations (خروج من المكان)
    await db.execute('''
      CREATE TABLE geofence_violations (
        id $idType,
        employee_id $textType,
        timestamp $textType,
        latitude $realType,
        longitude $realType,
        created_at $textType,
        synced $integerType DEFAULT 0,
        notified_locally $integerType DEFAULT 0
      )
    ''');
  }

  // ============ Pending Check-ins ============

  Future<String> insertPendingCheckin({
    required String employeeId,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
    String? wifiBssid,
  }) async {
    final db = await instance.database;
    final id = '${employeeId}_${timestamp.millisecondsSinceEpoch}';
    
    await db.insert('pending_checkins', {
      'id': id,
      'employee_id': employeeId,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'wifi_bssid': wifiBssid,
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
    });

    return id;
  }

  Future<List<Map<String, dynamic>>> getPendingCheckins() async {
    final db = await instance.database;
    return await db.query(
      'pending_checkins',
      where: 'synced = ?',
      whereArgs: [0],
    );
  }

  Future<void> markCheckinSynced(String id) async {
    final db = await instance.database;
    await db.update(
      'pending_checkins',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteSyncedCheckins() async {
    final db = await instance.database;
    await db.delete(
      'pending_checkins',
      where: 'synced = ?',
      whereArgs: [1],
    );
  }

  // ============ Pending Check-outs ============

  Future<String> insertPendingCheckout({
    required String employeeId,
    String? attendanceId,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
  }) async {
    final db = await instance.database;
    final id = '${employeeId}_${timestamp.millisecondsSinceEpoch}';
    
    await db.insert('pending_checkouts', {
      'id': id,
      'employee_id': employeeId,
      'attendance_id': attendanceId,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
    });

    return id;
  }

  Future<List<Map<String, dynamic>>> getPendingCheckouts() async {
    final db = await instance.database;
    return await db.query(
      'pending_checkouts',
      where: 'synced = ?',
      whereArgs: [0],
    );
  }

  Future<void> markCheckoutSynced(String id) async {
    final db = await instance.database;
    await db.update(
      'pending_checkouts',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteSyncedCheckouts() async {
    final db = await instance.database;
    await db.delete(
      'pending_checkouts',
      where: 'synced = ?',
      whereArgs: [1],
    );
  }

  // ============ Pending Pulses ============

  Future<String> insertPendingPulse({
    required String employeeId,
    required DateTime timestamp,
  }) async {
    final db = await instance.database;
    final id = '${employeeId}_${timestamp.millisecondsSinceEpoch}';
    
    await db.insert('pending_pulses', {
      'id': id,
      'employee_id': employeeId,
      'timestamp': timestamp.toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
    });

    return id;
  }

  Future<List<Map<String, dynamic>>> getPendingPulses() async {
    final db = await instance.database;
    return await db.query(
      'pending_pulses',
      where: 'synced = ?',
      whereArgs: [0],
    );
  }

  Future<void> markPulseSynced(String id) async {
    final db = await instance.database;
    await db.update(
      'pending_pulses',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============ Geofence Violations ============

  Future<String> insertGeofenceViolation({
    required String employeeId,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
  }) async {
    final db = await instance.database;
    final id = '${employeeId}_${timestamp.millisecondsSinceEpoch}';
    
    await db.insert('geofence_violations', {
      'id': id,
      'employee_id': employeeId,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
      'notified_locally': 0,
    });

    return id;
  }

  Future<List<Map<String, dynamic>>> getUnnotifiedViolations() async {
    final db = await instance.database;
    return await db.query(
      'geofence_violations',
      where: 'notified_locally = ?',
      whereArgs: [0],
    );
  }

  Future<void> markViolationNotified(String id) async {
    final db = await instance.database;
    await db.update(
      'geofence_violations',
      {'notified_locally': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedViolations() async {
    final db = await instance.database;
    return await db.query(
      'geofence_violations',
      where: 'synced = ?',
      whereArgs: [0],
    );
  }

  Future<void> markViolationSynced(String id) async {
    final db = await instance.database;
    await db.update(
      'geofence_violations',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============ Utility Methods ============

  Future<int> getPendingCount() async {
    final db = await instance.database;
    final checkins = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM pending_checkins WHERE synced = 0'),
    ) ?? 0;
    final checkouts = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM pending_checkouts WHERE synced = 0'),
    ) ?? 0;
    final pulses = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM pending_pulses WHERE synced = 0'),
    ) ?? 0;
    
    return checkins + checkouts + pulses;
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
