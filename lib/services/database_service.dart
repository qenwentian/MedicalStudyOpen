import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/anatomy_entity.dart';

/// Manages the local SQLite database acting as the anatomical
/// knowledge graph. Provides O(1) in-memory lookups for integer `meshKey`
/// returned from native spatial BVH raycasting.
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  /// Fast in-memory cache: Integer MeshKey -> AnatomyEntity.
  /// Guarantees instant O(1) resolution upon raycast hit without database I/O.
  final Map<int, AnatomyEntity> _meshKeyCache = {};

  /// Fast in-memory cache: String ID -> AnatomyEntity.
  final Map<String, AnatomyEntity> _idCache = {};

  /// System ID -> UBO Index mapping.
  final Map<String, int> _systemUboMap = {};

  Future<Database>? _initDbFuture;

  Future<Database> get database {
    if (_database != null) return Future.value(_database!);
    _initDbFuture ??= _initDatabaseAndWarmup();
    return _initDbFuture!;
  }

  Future<Database> _initDatabaseAndWarmup() async {
    try {
      _database = await _initDatabase();
      await _warmupCache();
      return _database!;
    } catch (e) {
      _initDbFuture = null; // Purge the poisoned cache
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'anatomy.db');

    const int currentAppDbVersion = 1; 
    final exists = await databaseExists(path);
    bool shouldCopy = !exists;

    if (exists) {
      // Open temporarily just to check the version
      final tempDb = await openDatabase(path);
      final deviceVersion = await tempDb.getVersion();
      await tempDb.close();
      
      if (deviceVersion < currentAppDbVersion) {
        shouldCopy = true;
      }
    }

    if (shouldCopy) {
      // Copy from assets
      try {
        await Directory(dirname(path)).create(recursive: true);
      } catch (_) {}

      // ByteData from flutter/services.dart
      final data = await rootBundle.load('assets/db/anatomy.db');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      // Write the copied bytes to the device
      await File(path).writeAsBytes(bytes, flush: true);
    }

    // 2. Open the DB and stamp it with the current version
    return openDatabase(
      path, 
      version: currentAppDbVersion,
      onUpgrade: (db, oldVersion, newVersion) async {},
    );
  }

  Future<void> _warmupCache() async {
    _meshKeyCache.clear();
    _idCache.clear();
    _systemUboMap.clear();

    final db = _database!;
    final systemRows = await db.query('body_system');
    for (final row in systemRows) {
      _systemUboMap[row['system_id'] as String] = row['ubo_index'] as int;
    }

    final entityRows = await db.query('anatomy_entity');
    for (final row in entityRows) {
      final entity = AnatomyEntity.fromMap(row);
      _meshKeyCache[entity.meshKey] = entity;
      _idCache[entity.id] = entity;
    }
  }

  // ── O(1) In-Memory Lookup APIs ──────────────────────────────────────

  /// Instant O(1) resolution from integer mesh key returned by native BVH raycaster.
  AnatomyEntity? getEntityByMeshKey(int meshKey) => _meshKeyCache[meshKey];

  /// Instant O(1) resolution from string ID.
  AnatomyEntity? getEntityById(String id) => _idCache[id];

  /// Returns the global GPU UBO index for a given system ID.
  int? getUboIndexForSystem(String systemId) => _systemUboMap[systemId];

  /// Returns all body systems ordered by depth priority.
  Future<List<BodySystem>> getAllSystems() async {
    final db = await database;
    final results = await db.query('body_system', orderBy: 'depth_priority ASC');
    return results.map(BodySystem.fromMap).toList();
  }

  /// Batch inserts manifest entities and warms the O(1) in-memory indices.
  Future<void> batchInsertEntities(List<AnatomyEntity> entities) async {
    final db = await database;
    final batch = db.batch();
    for (final ent in entities) {
      batch.insert('anatomy_entity', ent.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    await _warmupCache();
  }
}
