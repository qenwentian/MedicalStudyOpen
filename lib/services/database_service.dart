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

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    await _warmupCache();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'anatomy.db');

    return openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE body_system (
        system_id      TEXT PRIMARY KEY,
        ubo_index      INTEGER NOT NULL UNIQUE,
        name           TEXT NOT NULL,
        hex_color      TEXT NOT NULL,
        depth_priority INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE anatomy_entity (
        id             TEXT PRIMARY KEY,
        mesh_key       INTEGER NOT NULL UNIQUE,
        ta_id          TEXT,
        latin_name     TEXT NOT NULL,
        english_name   TEXT NOT NULL,
        description    TEXT,
        system_id      TEXT NOT NULL,
        hierarchy_path TEXT,
        FOREIGN KEY (system_id) REFERENCES body_system(system_id)
      )
    ''');

    // ── Seed: Systems with Global UBO Indices & Depth Priorities ──
    final systems = [
      const BodySystem(
        systemId: 'SYS_SKELETAL',
        uboIndex: 0,
        name: 'Skeletal System',
        hexColor: '#E8E4D9',
        depthPriority: 1, // Deepest core
      ),
      const BodySystem(
        systemId: 'SYS_NERVOUS',
        uboIndex: 1,
        name: 'Nervous System',
        hexColor: '#FFE066',
        depthPriority: 2,
      ),
      const BodySystem(
        systemId: 'SYS_VISCERAL',
        uboIndex: 2,
        name: 'Internal Organs & Viscera',
        hexColor: '#E06D53',
        depthPriority: 3,
      ),
      const BodySystem(
        systemId: 'SYS_VASCULAR',
        uboIndex: 3,
        name: 'Cardiovascular System',
        hexColor: '#D63031',
        depthPriority: 4,
      ),
      const BodySystem(
        systemId: 'SYS_MUSCULAR',
        uboIndex: 4,
        name: 'Muscular System',
        hexColor: '#C0392B',
        depthPriority: 5,
      ),
      const BodySystem(
        systemId: 'SYS_INTEGUMENTARY',
        uboIndex: 5,
        name: 'Integumentary System (Skin)',
        hexColor: '#EBBBA2',
        depthPriority: 6, // Outermost layer
      ),
    ];

    for (final sys in systems) {
      await db.insert('body_system', sys.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // ── Seed: Initial Core Entities with Integer MeshKeys ───────────
    final initialEntities = [
      const AnatomyEntity(
        id: 'BONE_SKULL',
        meshKey: 1001,
        taId: 'A02.1.00.001',
        latinName: 'Cranium',
        englishName: 'Skull',
        description: 'The bony framework of the head, protecting the brain and organs of special sense.',
        systemId: 'SYS_SKELETAL',
        hierarchyPath: 'SYS_SKELETAL/AXIAL/SKULL',
      ),
      const AnatomyEntity(
        id: 'BONE_FEMUR_L',
        meshKey: 1002,
        taId: 'A02.5.04.001',
        latinName: 'Femur',
        englishName: 'Thigh Bone (Left)',
        description: 'The longest and strongest bone in the human body, extending from the hip to the knee.',
        systemId: 'SYS_SKELETAL',
        hierarchyPath: 'SYS_SKELETAL/APPENDICULAR/LOWER_LIMB/FEMUR_L',
      ),
      const AnatomyEntity(
        id: 'BONE_FEMUR_R',
        meshKey: 1003,
        taId: 'A02.5.04.001',
        latinName: 'Femur',
        englishName: 'Thigh Bone (Right)',
        description: 'The longest and strongest bone in the human body, extending from the hip to the knee.',
        systemId: 'SYS_SKELETAL',
        hierarchyPath: 'SYS_SKELETAL/APPENDICULAR/LOWER_LIMB/FEMUR_R',
      ),
      const AnatomyEntity(
        id: 'MUSC_BICEPS_BRACHII_R',
        meshKey: 2001,
        taId: 'A04.6.02.005',
        latinName: 'Musculus biceps brachii',
        englishName: 'Biceps Brachii (Right)',
        description: 'A two-headed muscle lying on the upper arm between the shoulder and the elbow.',
        systemId: 'SYS_MUSCULAR',
        hierarchyPath: 'SYS_MUSCULAR/UPPER_LIMB/ARM/BICEPS_R',
      ),
      const AnatomyEntity(
        id: 'ORGAN_HEART',
        meshKey: 3001,
        taId: 'A12.1.00.001',
        latinName: 'Cor',
        englishName: 'Heart',
        description: 'A muscular organ in most animals, which pumps blood through the blood vessels of the circulatory system.',
        systemId: 'SYS_VISCERAL',
        hierarchyPath: 'SYS_VISCERAL/THORAX/HEART',
      ),
    ];

    for (final ent in initialEntities) {
      await db.insert('anatomy_entity', ent.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await db.execute('DROP TABLE IF EXISTS anatomy_entity');
      await db.execute('DROP TABLE IF EXISTS body_system');
      await _onCreate(db, newVersion);
    }
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
