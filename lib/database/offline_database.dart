import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class OfflineDatabase {
  static final OfflineDatabase instance = OfflineDatabase._init();
  static Database? _database;

  OfflineDatabase._init();

  Future<Database> get database async {
    // For Web platform, throw error with helpful message
    if (kIsWeb) {
      throw UnsupportedError(
        'SQLite database is not supported on Web platform. '
        'Use Hive or other web-compatible storage instead.'
      );
    }
    
    if (_database != null) return _database!;
    _database = await _initDB('offline_attendance.db');
    return _database!;

  }

  Future<Database> _initDB(String filePath) async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite is not supported on Web');
    }
    
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    // Check if database exists
    final dbExists = await databaseExists(path);
    
    if (!dbExists) {
      print('� Database does not exist - creating new database');
    } else {
      print('✅ Database file found at: $path');
    }

    return await openDatabase(
      path,
      version: 4, // Version 4: Shift times & hourly rate in cache
      onCreate: (db, version) async {
        print('🆕 Creating new database (version $version)');
        await _createDB(db, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        print('🔄 Upgrading database from v$oldVersion to v$newVersion');
        await _onUpgrade(db, oldVersion, newVersion);
      },
      onOpen: (db) async {
        print('✅ Database opened successfully');
      },
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add branch_cache table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS branch_cache (
          employee_id TEXT PRIMARY KEY,
          branch_id TEXT NOT NULL,
          branch_name TEXT,
          wifi_bssids TEXT,
          latitude REAL,
          longitude REAL,
          geofence_radius INTEGER,
          last_updated TEXT NOT NULL,
          data_version INTEGER DEFAULT 1
        )
      ''');
    }
    
  if (oldVersion < 3) {
      // Migrate existing data: wifi_bssid → wifi_bssids (JSON array)
      // Add data_version column
      try {
        await db.execute('ALTER TABLE branch_cache ADD COLUMN wifi_bssids TEXT');
        await db.execute('ALTER TABLE branch_cache ADD COLUMN data_version INTEGER DEFAULT 1');
        
        // Migrate old wifi_bssid to wifi_bssids array
        final rows = await db.query('branch_cache');
        for (var row in rows) {
          final oldBssid = row['wifi_bssid'];
          if (oldBssid != null && oldBssid.toString().isNotEmpty) {
            final bssidsArray = '["${oldBssid}"]'; // Convert to JSON array
            await db.update(
              'branch_cache',
              {'wifi_bssids': bssidsArray},
              where: 'employee_id = ?',
              whereArgs: [row['employee_id']],
            );
          }
        }
        
        print('✅ Migrated wifi_bssid → wifi_bssids (JSON array)');
      } catch (e) {
        print('⚠️ Migration warning: $e');
      }
    }

    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE branch_cache ADD COLUMN shift_start_time TEXT');
      } catch (e) {
        print('ℹ️ shift_start_time column may already exist: $e');
      }
      try {
        await db.execute('ALTER TABLE branch_cache ADD COLUMN shift_end_time TEXT');
      } catch (e) {
        print('ℹ️ shift_end_time column may already exist: $e');
      }
      try {
        await db.execute('ALTER TABLE branch_cache ADD COLUMN hourly_rate REAL');
      } catch (e) {
        print('ℹ️ hourly_rate column may already exist: $e');
      }
    }
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

    // Branch cache (بيانات الفرع المحفوظة محليًا)
    await db.execute('''
      CREATE TABLE branch_cache (
        employee_id $idType,
        branch_id $textType,
        branch_name $textTypeNull,
        wifi_bssids $textTypeNull,
        latitude $realType,
        longitude $realType,
        geofence_radius $integerType,
        shift_start_time $textTypeNull,
        shift_end_time $textTypeNull,
        hourly_rate $realType,
        last_updated $textType,
        data_version $integerType DEFAULT 1
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
    // For Web, return 0 (use Hive boxes instead)
    if (kIsWeb) {
      return 0;
    }
    
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

  // ============ Branch Cache ============

  /// Save or update branch data for an employee
  Future<void> cacheBranchData({
    required String employeeId,
    required String branchId,
    String? branchName,
    List<String>? wifiBssids, // Changed from single to list
    double? latitude,
    double? longitude,
    int? geofenceRadius,
    String? shiftStartTime,
    String? shiftEndTime,
    double? hourlyRate,
    int? dataVersion,
  }) async {
    // For Web, skip SQLite (data is already in Hive via OfflineDataService)
    if (kIsWeb) {
      print('⚠️ Branch cache on Web uses Hive (skip SQLite)');
      return;
    }
    
    final db = await instance.database;
    
    // Convert list to JSON string
    String? bssidsJson;
    if (wifiBssids != null && wifiBssids.isNotEmpty) {
      bssidsJson = jsonEncode(wifiBssids);
    }
    
    await db.insert(
      'branch_cache',
      {
        'employee_id': employeeId,
        'branch_id': branchId,
        'branch_name': branchName,
        'wifi_bssids': bssidsJson,
        'latitude': latitude,
        'longitude': longitude,
        'geofence_radius': geofenceRadius ?? 50,
        'shift_start_time': shiftStartTime,
        'shift_end_time': shiftEndTime,
        'hourly_rate': hourlyRate,
        'last_updated': DateTime.now().toIso8601String(),
        'data_version': dataVersion ?? 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    print('✅ Cached branch data for employee $employeeId: $branchName (${wifiBssids?.length ?? 0} WiFi networks)');
  }

  /// Get cached branch data for an employee
  Future<Map<String, dynamic>?> getCachedBranchData(String employeeId) async {
    // For Web, return null (use Hive instead)
    if (kIsWeb) {
      return null;
    }
    
    final db = await instance.database;
    
    final result = await db.query(
      'branch_cache',
      where: 'employee_id = ?',
      whereArgs: [employeeId],
    );

    if (result.isEmpty) {
      print('❌ No cached branch data found for employee $employeeId');
      return null;
    }

    final data = Map<String, dynamic>.from(result.first);
    
    // Parse JSON array of BSSIDs
    if (data['wifi_bssids'] != null && data['wifi_bssids'].toString().isNotEmpty) {
      try {
        data['wifi_bssids_array'] = jsonDecode(data['wifi_bssids']) as List<dynamic>;
      } catch (e) {
        print('⚠️ Failed to parse wifi_bssids JSON: $e');
        data['wifi_bssids_array'] = [];
      }
    } else {
      data['wifi_bssids_array'] = [];
    }

    print('✅ Found cached branch data for employee $employeeId');
    return data;
  }

  /// Check if branch data is cached (for offline mode check)
  Future<bool> hasCachedBranchData(String employeeId) async {
    if (kIsWeb) return false;
    
    try {
      final data = await getCachedBranchData(employeeId);
      return data != null;
    } catch (e) {
      print('⚠️ Error checking cached branch data: $e');
      return false;
    }
  }
  
  /// Check if cache needs update (older than 24 hours)
  Future<bool> needsCacheRefresh(String employeeId) async {
    if (kIsWeb) return true;
    
    try {
      final data = await getCachedBranchData(employeeId);
      if (data == null) {
        print('📥 No cache found - needs download');
        return true;
      }
      
      final lastUpdated = DateTime.parse(data['last_updated']);
      final now = DateTime.now();
      final difference = now.difference(lastUpdated);
      
      final needsRefresh = difference.inHours >= 24;
      
      if (needsRefresh) {
        print('🔄 Cache is ${difference.inHours} hours old - needs refresh');
      } else {
        print('✅ Cache is fresh (${difference.inHours} hours old)');
      }
      
      return needsRefresh;
    } catch (e) {
      print('⚠️ Error checking cache age: $e');
      return true; // Refresh on error
    }
  }

  /// Get database statistics for debugging
  Future<Map<String, int>> getDatabaseStats() async {
    if (kIsWeb) {
      return {
        'pending_checkins': 0,
        'pending_checkouts': 0,
        'pending_pulses': 0,
        'cached_branches': 0,
      };
    }
    
    try {
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
      
      final branches = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM branch_cache'),
      ) ?? 0;
      
      print('📊 Database Stats: Checkins=$checkins, Checkouts=$checkouts, Pulses=$pulses, Branches=$branches');
      
      return {
        'pending_checkins': checkins,
        'pending_checkouts': checkouts,
        'pending_pulses': pulses,
        'cached_branches': branches,
      };
    } catch (e) {
      print('⚠️ Error getting database stats: $e');
      return {
        'pending_checkins': 0,
        'pending_checkouts': 0,
        'pending_pulses': 0,
        'cached_branches': 0,
      };
    }
  }

  Future<void> close() async {
    if (kIsWeb) return;
    final db = await instance.database;
    db.close();
  }
}
