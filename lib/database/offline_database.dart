import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class OfflineDatabase {
  static final OfflineDatabase instance = OfflineDatabase._init();
  static Database? _database;

  OfflineDatabase._init();

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  bool _sameDouble(
    dynamic oldValue,
    double? newValue, {
    double epsilon = 0.000001,
  }) {
    final oldAsDouble = _toDouble(oldValue);
    if (oldAsDouble == null || newValue == null) {
      return oldAsDouble == newValue;
    }
    return (oldAsDouble - newValue).abs() < epsilon;
  }

  Future<Database> get database async {
    // For Web platform, throw error with helpful message
    if (kIsWeb) {
      throw UnsupportedError(
        'SQLite database is not supported on Web platform. '
        'Use Hive or other web-compatible storage instead.',
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
      version: 8, // Version 8: Add validation_method for pulses
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
        await db.execute(
          'ALTER TABLE branch_cache ADD COLUMN wifi_bssids TEXT',
        );
        await db.execute(
          'ALTER TABLE branch_cache ADD COLUMN data_version INTEGER DEFAULT 1',
        );

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
        await db.execute(
          'ALTER TABLE branch_cache ADD COLUMN shift_start_time TEXT',
        );
      } catch (e) {
        print('ℹ️ shift_start_time column may already exist: $e');
      }
      try {
        await db.execute(
          'ALTER TABLE branch_cache ADD COLUMN shift_end_time TEXT',
        );
      } catch (e) {
        print('ℹ️ shift_end_time column may already exist: $e');
      }
      try {
        await db.execute(
          'ALTER TABLE branch_cache ADD COLUMN hourly_rate REAL',
        );
      } catch (e) {
        print('ℹ️ hourly_rate column may already exist: $e');
      }
    }

    if (oldVersion < 5) {
      // Add new columns to pending_pulses table
      try {
        await db.execute(
          'ALTER TABLE pending_pulses ADD COLUMN attendance_id TEXT',
        );
      } catch (e) {
        print('ℹ️ attendance_id column may already exist: $e');
      }
      try {
        await db.execute('ALTER TABLE pending_pulses ADD COLUMN latitude REAL');
      } catch (e) {
        print('ℹ️ latitude column may already exist: $e');
      }
      try {
        await db.execute(
          'ALTER TABLE pending_pulses ADD COLUMN longitude REAL',
        );
      } catch (e) {
        print('ℹ️ longitude column may already exist: $e');
      }
      try {
        await db.execute(
          'ALTER TABLE pending_pulses ADD COLUMN inside_geofence INTEGER DEFAULT 0',
        );
      } catch (e) {
        print('ℹ️ inside_geofence column may already exist: $e');
      }
      try {
        await db.execute(
          'ALTER TABLE pending_pulses ADD COLUMN distance_from_center REAL',
        );
      } catch (e) {
        print('ℹ️ distance_from_center column may already exist: $e');
      }
      try {
        await db.execute(
          'ALTER TABLE pending_pulses ADD COLUMN wifi_bssid TEXT',
        );
      } catch (e) {
        print('ℹ️ wifi_bssid column may already exist: $e');
      }
      try {
        await db.execute(
          'ALTER TABLE pending_pulses ADD COLUMN validated_by_wifi INTEGER DEFAULT 0',
        );
      } catch (e) {
        print('ℹ️ validated_by_wifi column may already exist: $e');
      }
      try {
        await db.execute(
          'ALTER TABLE pending_pulses ADD COLUMN validated_by_location INTEGER DEFAULT 0',
        );
      } catch (e) {
        print('ℹ️ validated_by_location column may already exist: $e');
      }
      print('✅ Added pulse fields to pending_pulses table');
    }

    if (oldVersion < 6) {
      // Add notes column to pending_checkouts table
      try {
        await db.execute('ALTER TABLE pending_checkouts ADD COLUMN notes TEXT');
        print('✅ Added notes column to pending_checkouts table');
      } catch (e) {
        print('ℹ️ notes column may already exist: $e');
      }
    }

    if (oldVersion < 7) {
      try {
        await db.execute(
          'ALTER TABLE pending_pulses ADD COLUMN branch_id TEXT',
        );
        print('✅ Added branch_id column to pending_pulses table');
      } catch (e) {
        print('ℹ️ branch_id column may already exist: $e');
      }
    }

    if (oldVersion < 8) {
      try {
        await db.execute(
          'ALTER TABLE pending_pulses ADD COLUMN validation_method TEXT',
        );
        print('✅ Added validation_method column to pending_pulses table');
      } catch (e) {
        print('ℹ️ validation_method column may already exist: $e');
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
        notes $textTypeNull,
        created_at $textType,
        synced $integerType DEFAULT 0
      )
    ''');

    // Pending pulses (نبضات معلقة)
    await db.execute('''
      CREATE TABLE pending_pulses (
        id $idType,
        employee_id $textType,
        attendance_id $textTypeNull,
        branch_id $textTypeNull,
        timestamp $textType,
        latitude $realType,
        longitude $realType,
        inside_geofence $integerType DEFAULT 0,
        distance_from_center $realType,
        wifi_bssid $textTypeNull,
        validation_method $textTypeNull,
        validated_by_wifi $integerType DEFAULT 0,
        validated_by_location $integerType DEFAULT 0,
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
    final id =
        '${employeeId}_${timestamp.millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch}';

    await db.insert('pending_checkins', {
      'id': id,
      'employee_id': employeeId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'wifi_bssid': wifiBssid,
      'created_at': DateTime.now().toUtc().toIso8601String(),
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
    await db.delete('pending_checkins', where: 'synced = ?', whereArgs: [1]);
  }

  // ============ Pending Check-outs ============

  Future<String> insertPendingCheckout({
    required String employeeId,
    String? attendanceId,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
    String? notes,
  }) async {
    final db = await instance.database;
    final id = '${employeeId}_${timestamp.millisecondsSinceEpoch}';

    await db.insert('pending_checkouts', {
      'id': id,
      'employee_id': employeeId,
      'attendance_id': attendanceId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'notes': notes,
      'created_at': DateTime.now().toUtc().toIso8601String(),
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
    await db.delete('pending_checkouts', where: 'synced = ?', whereArgs: [1]);
  }

  // ============ Pending Pulses ============

  Future<String> insertPendingPulse({
    required String employeeId,
    required DateTime timestamp,
    String? attendanceId,
    String? branchId,
    double? latitude,
    double? longitude,
    bool insideGeofence = false,
    double? distanceFromCenter,
    String? wifiBssid,
    String? validationMethod,
    bool validatedByWifi = false,
    bool validatedByLocation = false,
    bool synced = false,
  }) async {
    final db = await instance.database;
    final id = '${employeeId}_${timestamp.millisecondsSinceEpoch}';

    await db.insert('pending_pulses', {
      'id': id,
      'employee_id': employeeId,
      'attendance_id': attendanceId,
      'branch_id': branchId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'inside_geofence': insideGeofence ? 1 : 0,
      'distance_from_center': distanceFromCenter,
      'wifi_bssid': wifiBssid,
      'validation_method': validationMethod,
      'validated_by_wifi': validatedByWifi ? 1 : 0,
      'validated_by_location': validatedByLocation ? 1 : 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'synced': synced ? 1 : 0,
    });

    return id;
  }

  Future<bool> hasRecentPulse({
    required String employeeId,
    required DateTime timestamp,
    int withinSeconds = 90,
  }) async {
    final db = await instance.database;
    final from = timestamp
        .toUtc()
        .subtract(Duration(seconds: withinSeconds))
        .toIso8601String();
    final to = timestamp
        .toUtc()
        .add(Duration(seconds: withinSeconds))
        .toIso8601String();

    final result = Sqflite.firstIntValue(
      await db.rawQuery(
        '''
        SELECT COUNT(*)
        FROM pending_pulses
        WHERE employee_id = ?
          AND timestamp >= ?
          AND timestamp <= ?
        ''',
        [employeeId, from, to],
      ),
    );

    return (result ?? 0) > 0;
  }

  Future<List<Map<String, dynamic>>> getPendingPulses() async {
    final db = await instance.database;
    return await db.query(
      'pending_pulses',
      where: 'synced = ?',
      whereArgs: [0],
    );
  }

  /// Backfill attendance_id for pulses that were captured before server attendance was created
  Future<int> backfillAttendanceIdForPulses({
    required String employeeId,
    required String attendanceId,
  }) async {
    final db = await instance.database;
    // Update pulses with NULL or placeholder attendance_id
    final result = await db.update(
      'pending_pulses',
      {'attendance_id': attendanceId},
      where:
          'employee_id = ? AND (attendance_id IS NULL OR attendance_id = "" OR attendance_id LIKE ?)',
      whereArgs: [employeeId, '%pending%'],
    );
    return result; // number of rows affected
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
      'timestamp': timestamp.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'created_at': DateTime.now().toUtc().toIso8601String(),
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
    final checkins =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM pending_checkins WHERE synced = 0',
          ),
        ) ??
        0;
    final checkouts =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM pending_checkouts WHERE synced = 0',
          ),
        ) ??
        0;
    final pulses =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM pending_pulses WHERE synced = 0',
          ),
        ) ??
        0;

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
      final normalizedBssids =
          wifiBssids
              .map((bssid) => bssid.toUpperCase().trim())
              .where((bssid) => bssid.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      bssidsJson = jsonEncode(normalizedBssids);
    }

    final existing = await db.query(
      'branch_cache',
      columns: [
        'branch_id',
        'branch_name',
        'wifi_bssids',
        'latitude',
        'longitude',
        'geofence_radius',
        'shift_start_time',
        'shift_end_time',
        'hourly_rate',
        'data_version',
      ],
      where: 'employee_id = ?',
      whereArgs: [employeeId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final current = existing.first;
      final targetGeofenceRadius = geofenceRadius ?? 50;
      final currentGeofenceRadius = current['geofence_radius'] is num
          ? (current['geofence_radius'] as num).toInt()
          : int.tryParse(current['geofence_radius']?.toString() ?? '');

      final currentDataVersion = current['data_version'] is num
          ? (current['data_version'] as num).toInt()
          : int.tryParse(current['data_version']?.toString() ?? '');

      final unchanged =
          current['branch_id']?.toString() == branchId &&
          current['branch_name']?.toString() == branchName &&
          current['wifi_bssids']?.toString() == bssidsJson &&
          _sameDouble(current['latitude'], latitude) &&
          _sameDouble(current['longitude'], longitude) &&
          currentGeofenceRadius == targetGeofenceRadius &&
          current['shift_start_time']?.toString() == shiftStartTime &&
          current['shift_end_time']?.toString() == shiftEndTime &&
          _sameDouble(current['hourly_rate'], hourlyRate) &&
          currentDataVersion == (dataVersion ?? 1);

      if (unchanged) {
        print(
          'ℹ️ Branch cache unchanged for employee $employeeId (skip rewrite)',
        );
        return;
      }
    }

    await db.insert('branch_cache', {
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
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    print(
      '✅ Cached branch data for employee $employeeId: $branchName (${wifiBssids?.length ?? 0} WiFi networks)',
    );
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

    // ✅ Add aliases for common field names (for backward compatibility)
    data['name'] = data['branch_name'];
    data['id'] = data['branch_id'];

    // Parse JSON array of BSSIDs
    if (data['wifi_bssids'] != null &&
        data['wifi_bssids'].toString().isNotEmpty) {
      try {
        data['wifi_bssids_array'] =
            jsonDecode(data['wifi_bssids']) as List<dynamic>;
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

      final checkins =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM pending_checkins WHERE synced = 0',
            ),
          ) ??
          0;

      final checkouts =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM pending_checkouts WHERE synced = 0',
            ),
          ) ??
          0;

      final pulses =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM pending_pulses WHERE synced = 0',
            ),
          ) ??
          0;

      final branches =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM branch_cache'),
          ) ??
          0;

      print(
        '📊 Database Stats: Checkins=$checkins, Checkouts=$checkouts, Pulses=$pulses, Branches=$branches',
      );

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
