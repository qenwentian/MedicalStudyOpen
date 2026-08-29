/// Data model representing a single anatomical entity.
///
/// The [id] field is the primary key and corresponds directly to the
/// mesh node name inside the .glb file (e.g., `BONE_FEMUR_L`). This
/// one-to-one mapping is how a raycasted mesh hit resolves to a
/// database lookup.
class AnatomyEntity {
  /// Mesh node name from the .glb file — primary key.
  final String id;

  /// Terminologia Anatomica ID (e.g., `A02.1.00.001`).
  final String? taId;

  /// Official Latin name (e.g., `Cranium`).
  final String latinName;

  /// Common English name (e.g., `Skull`).
  final String englishName;

  /// Detailed text description of the structure.
  final String? description;

  /// Foreign key linking to [BodySystem.systemId].
  final String systemId;

  /// Materialized path for tree-based hierarchy traversal.
  /// Example: `SYS_SKELETAL/SKULL/CRANIUM`.
  final String? hierarchyPath;

  const AnatomyEntity({
    required this.id,
    this.taId,
    required this.latinName,
    required this.englishName,
    this.description,
    required this.systemId,
    this.hierarchyPath,
  });

  /// Deserializes a row from the SQLite `anatomy_entity` table.
  factory AnatomyEntity.fromMap(Map<String, dynamic> map) {
    return AnatomyEntity(
      id: map['id'] as String,
      taId: map['ta_id'] as String?,
      latinName: map['latin_name'] as String,
      englishName: map['english_name'] as String,
      description: map['description'] as String?,
      systemId: map['system_id'] as String,
      hierarchyPath: map['hierarchy_path'] as String?,
    );
  }

  /// Serializes this entity to a map suitable for SQLite insertion.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ta_id': taId,
      'latin_name': latinName,
      'english_name': englishName,
      'description': description,
      'system_id': systemId,
      'hierarchy_path': hierarchyPath,
    };
  }
}

/// Data model representing a body system (e.g., Skeletal, Muscular).
class BodySystem {
  /// Primary key (e.g., `SYS_SKELETAL`).
  final String systemId;

  /// Human-readable name (e.g., `Skeletal System`).
  final String name;

  /// Default UI highlight colour as a hex string (e.g., `#FFFFFF`).
  final String hexColor;

  const BodySystem({
    required this.systemId,
    required this.name,
    required this.hexColor,
  });

  factory BodySystem.fromMap(Map<String, dynamic> map) {
    return BodySystem(
      systemId: map['system_id'] as String,
      name: map['name'] as String,
      hexColor: map['hex_color'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'system_id': systemId,
      'name': name,
      'hex_color': hexColor,
    };
  }
}
