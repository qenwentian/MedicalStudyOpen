/// Data model representing a single anatomical entity.
///
/// The [id] is the string identifier (e.g. `BONE_FEMUR_L`).
/// The [meshKey] is an integer key baked into custom vertex attributes
/// during the Blender pipeline, allowing O(1) identification from spatial BVH raycasts.
class AnatomyEntity {
  /// Unique string ID (e.g., `BONE_FEMUR_L`).
  final String id;

  /// Unique integer mesh key baked into vertex data for O(1) raycast resolution.
  final int meshKey;

  /// Terminologia Anatomica ID (e.g., `A02.5.04.001`).
  final String? taId;

  /// Official Latin name (e.g., `Femur`).
  final String latinName;

  /// Common English name (e.g., `Thigh Bone (Left)`).
  final String englishName;

  /// Detailed anatomical description.
  final String? description;

  /// Foreign key linking to [BodySystem.systemId].
  final String systemId;

  /// Materialized hierarchy path (e.g., `SYS_SKELETAL/LOWER_LIMB/FEMUR_L`).
  final String? hierarchyPath;

  const AnatomyEntity({
    required this.id,
    required this.meshKey,
    this.taId,
    required this.latinName,
    required this.englishName,
    this.description,
    required this.systemId,
    this.hierarchyPath,
  });

  factory AnatomyEntity.fromMap(Map<String, dynamic> map) {
    return AnatomyEntity(
      id: map['id'] as String,
      meshKey: (map['mesh_key'] as num?)?.toInt() ?? 0,
      taId: map['ta_id'] as String?,
      latinName: map['latin_name'] as String,
      englishName: map['english_name'] as String,
      description: map['description'] as String?,
      systemId: map['system_id'] as String,
      hierarchyPath: map['hierarchy_path'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'mesh_key': meshKey,
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

  /// Integer index (0–15) used to index into the global GPU UBO `u_SystemAlpha[16]`.
  final int uboIndex;

  /// Human-readable name.
  final String name;

  /// Default UI highlight colour as a hex string.
  final String hexColor;

  /// Rigid depth priority for back-to-front rendering order.
  final int depthPriority;

  const BodySystem({
    required this.systemId,
    required this.uboIndex,
    required this.name,
    required this.hexColor,
    required this.depthPriority,
  });

  factory BodySystem.fromMap(Map<String, dynamic> map) {
    return BodySystem(
      systemId: map['system_id'] as String,
      uboIndex: (map['ubo_index'] as num?)?.toInt() ?? 0,
      name: map['name'] as String,
      hexColor: map['hex_color'] as String,
      depthPriority: (map['depth_priority'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'system_id': systemId,
      'ubo_index': uboIndex,
      'name': name,
      'hex_color': hexColor,
      'depth_priority': depthPriority,
    };
  }
}
