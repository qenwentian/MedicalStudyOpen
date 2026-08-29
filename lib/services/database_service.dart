import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/anatomy_entity.dart';

/// Manages the local SQLite database that acts as the anatomical
/// knowledge graph. Provides CRUD helpers for [AnatomyEntity] and
/// [BodySystem] lookups, keyed by the mesh node IDs embedded in the
/// .glb assets.
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  /// Returns the singleton database handle, creating it on first access.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'anatomy.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  /// Creates the schema on first launch and seeds it with starter data
  /// so the app can render useful information immediately.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE body_system (
        system_id TEXT PRIMARY KEY,
        name      TEXT NOT NULL,
        hex_color TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE anatomy_entity (
        id             TEXT PRIMARY KEY,
        ta_id          TEXT,
        latin_name     TEXT NOT NULL,
        english_name   TEXT NOT NULL,
        description    TEXT,
        system_id      TEXT NOT NULL,
        hierarchy_path TEXT,
        FOREIGN KEY (system_id) REFERENCES body_system(system_id)
      )
    ''');

    // ── Seed: Body Systems ──────────────────────────────────────────
    await db.insert('body_system', const BodySystem(
      systemId: 'SYS_SKELETAL',
      name: 'Skeletal System',
      hexColor: '#F5F5DC',
    ).toMap());

    await db.insert('body_system', const BodySystem(
      systemId: 'SYS_MUSCULAR',
      name: 'Muscular System',
      hexColor: '#CD5C5C',
    ).toMap());

    // ── Seed: Example Entities ──────────────────────────────────────
    // These will be replaced by the full Z-Anatomy dataset later.
    await db.insert('anatomy_entity', const AnatomyEntity(
      id: 'BONE_FEMUR_L',
      taId: 'A02.5.04.001',
      latinName: 'Femur',
      englishName: 'Thigh Bone (Left)',
      description: 'The longest and strongest bone in the human body, '
          'extending from the hip to the knee.',
      systemId: 'SYS_SKELETAL',
      hierarchyPath: 'SYS_SKELETAL/LOWER_LIMB/FEMUR_L',
    ).toMap());

    await db.insert('anatomy_entity', const AnatomyEntity(
      id: 'BONE_SKULL',
      taId: 'A02.1.00.001',
      latinName: 'Cranium',
      englishName: 'Skull',
      description: 'The bony structure that forms the head, '
          'protecting the brain and supporting the face.',
      systemId: 'SYS_SKELETAL',
      hierarchyPath: 'SYS_SKELETAL/SKULL',
    ).toMap());
  }

  // ── Query helpers ───────────────────────────────────────────────────

  /// Looks up an [AnatomyEntity] by its mesh node ID (the .glb name).
  /// Returns `null` if the entity is not in the database.
  Future<AnatomyEntity?> getEntityById(String id) async {
    final db = await database;
    final results = await db.query(
      'anatomy_entity',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (results.isEmpty) return null;
    return AnatomyEntity.fromMap(results.first);
  }

  /// Returns all entities belonging to a given [systemId].
  Future<List<AnatomyEntity>> getEntitiesBySystem(String systemId) async {
    final db = await database;
    final results = await db.query(
      'anatomy_entity',
      where: 'system_id = ?',
      whereArgs: [systemId],
    );
    return results.map(AnatomyEntity.fromMap).toList();
  }

  /// Returns all body systems.
  Future<List<BodySystem>> getAllSystems() async {
    final db = await database;
    final results = await db.query('body_system');
    return results.map(BodySystem.fromMap).toList();
  }
}
