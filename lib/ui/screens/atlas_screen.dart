import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';

import '../../models/anatomy_entity.dart';
import '../../services/database_service.dart';
import '../widgets/thermion_viewport.dart';

/// The primary interactive screen of the anatomy atlas.
///
/// Architecture:
///   - Bottom layer: [ThermionViewport] rendering the .glb scene via Filament.
///   - Top layer: Transparent Flutter overlay containing the info panel.
///
/// When the user taps a mesh in the 3D viewport, the native Filament
/// raycaster returns the mesh node ID. This screen performs an SQLite
/// lookup via [DatabaseService] and displays the anatomical details
/// in a bottom sheet.
class AtlasScreen extends StatefulWidget {
  const AtlasScreen({super.key});

  @override
  State<AtlasScreen> createState() => _AtlasScreenState();
}

class _AtlasScreenState extends State<AtlasScreen> {
  final DatabaseService _db = DatabaseService();

  /// Handle to the native Filament viewer. Used for raycasting and
  /// material manipulation in later phases.
  // ignore: unused_field
  ThermionViewer? _viewer;
  AnatomyEntity? _selectedEntity;
  bool _isLoading = true;

  void _onViewerReady(ThermionViewer viewer) {
    setState(() {
      _viewer = viewer;
      _isLoading = false;
    });
  }

  /// Simulates a mesh selection.
  /// In production this will be driven by the native raycaster callback.
  /// For Phase 1 we demonstrate the data-flow by looking up a seed entity.
  Future<void> _onMeshTapped(String meshId) async {
    final entity = await _db.getEntityById(meshId);
    if (entity != null) {
      setState(() => _selectedEntity = entity);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Stack(
        children: [
          // ── 3D Viewport (full-screen background) ──────────────
          Positioned.fill(
            child: ThermionViewport(
              assetPath: 'assets/3d/skeleton_lod0.glb',
              onViewerReady: _onViewerReady,
            ),
          ),

          // ── Top bar overlay ───────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.biotech, color: Color(0xFF00D2FF), size: 28),
                    const SizedBox(width: 8),
                    Text(
                      'Anatomy Atlas',
                      style: TextStyle(
                        color: Colors.white.withAlpha(230),
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    // Phase 1 demo button: simulate selecting a bone.
                    IconButton(
                      icon: const Icon(Icons.touch_app, color: Color(0xFF00D2FF)),
                      tooltip: 'Simulate bone tap (Phase 1 demo)',
                      onPressed: () => _onMeshTapped('BONE_FEMUR_L'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Loading indicator ─────────────────────────────────
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF00D2FF)),
                  SizedBox(height: 16),
                  Text(
                    'Initializing Filament engine…',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
            ),

          // ── Bottom info panel overlay ──────────────────────────
          if (_selectedEntity != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildInfoPanel(_selectedEntity!),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(AnatomyEntity entity) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xE6141428),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x4000D2FF),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // English name
          Text(
            entity.englishName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),

          // Latin name
          Text(
            entity.latinName,
            style: const TextStyle(
              color: Color(0xFF00D2FF),
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 4),

          // TA ID
          if (entity.taId != null)
            Text(
              'TA: ${entity.taId}',
              style: TextStyle(
                color: Colors.white.withAlpha(127),
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 12),

          // Description
          if (entity.description != null)
            Text(
              entity.description!,
              style: TextStyle(
                color: Colors.white.withAlpha(204),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          const SizedBox(height: 12),

          // Dismiss button
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _selectedEntity = null),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Dismiss'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF00D2FF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
