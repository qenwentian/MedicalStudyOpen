import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';

import '../../models/anatomy_entity.dart';
import '../../services/database_service.dart';
import '../widgets/thermion_viewport.dart';
import '../widgets/system_layer_panel.dart';

/// The primary interactive screen of the anatomy atlas.
///
/// Implements:
/// - Single-call GPU UBO system alpha mutations (`setSystemAlpha(uboIndex, alpha)`).
/// - Instant O(1) in-memory resolution of picked mesh keys without SQLite query lag.
/// - Throttled 30Hz slider layer peeling panel.
class AtlasScreen extends StatefulWidget {
  const AtlasScreen({super.key});

  @override
  State<AtlasScreen> createState() => _AtlasScreenState();
}

class _AtlasScreenState extends State<AtlasScreen> {
  final DatabaseService _db = DatabaseService();
  final GlobalKey<ThermionViewportState> _viewportKey = GlobalKey<ThermionViewportState>();

  // ignore: unused_field
  ThermionViewer? _viewer;
  AnatomyEntity? _selectedEntity;
  List<BodySystem> _systems = [];
  final Map<String, double> _systemAlphas = {};
  bool _isLoading = true;
  bool _showLayerPanel = false;

  @override
  void initState() {
    super.initState();
    _loadSystems();
  }

  Future<void> _loadSystems() async {
    try {
      final systems = await _db.getAllSystems();
      if (mounted) {
        setState(() {
          _systems = systems;
          for (final s in systems) {
            _systemAlphas[s.systemId] = 1.0;
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to load systems: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onViewerReady(ThermionViewer viewer) {
    if (!mounted) return;
    setState(() {
      _viewer = viewer;
      _isLoading = false;
    });
  }

  /// Handles O(1) integer meshKey resolution from native BVH raycaster.
  void _onMeshKeyPicked(int meshKey) {
    final entity = _db.getEntityByMeshKey(meshKey);
    if (entity != null && mounted) {
      setState(() => _selectedEntity = entity);
    }
  }

  /// Handles throttled system transparency changes.
  /// Executes a single FFI call to update the GPU UBO buffer index.
  void _onSystemAlphaChanged(String systemId, double alpha) {
    final uboIndex = _db.getUboIndexForSystem(systemId);
    if (uboIndex == null || _viewer == null) return;

    _viewportKey.currentState?.setSystemAlpha(systemId, alpha);
    debugPrint('GPU UBO Call: SetSystemAlpha(uboIndex: $uboIndex, alpha: $alpha)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Stack(
        children: [
          // ── 1. 3D Viewport (Full Screen) ──────────────────────
          Positioned.fill(
            child: ThermionViewport(
              key: _viewportKey,
              assetPaths: const [
                'assets/3d/sys_skeletal_lod0.glb',
                'assets/3d/sys_nervous_lod0.glb',
                'assets/3d/sys_visceral_lod0.glb',
                'assets/3d/sys_vascular_lod0.glb',
                'assets/3d/sys_muscular_lod0.glb',
                'assets/3d/sys_integumentary_lod0.glb',
              ],
              onViewerReady: _onViewerReady,
              onMeshKeyPicked: _onMeshKeyPicked,
              onBackgroundTapped: () {
                if (mounted) setState(() => _selectedEntity = null);
              },
            ),
          ),

          // ── 2. Top Navigation Bar ─────────────────────────────
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

                    // Layer Peeling Toggle
                    IconButton(
                      icon: Icon(
                        Icons.layers,
                        color: _showLayerPanel ? const Color(0xFF00D2FF) : Colors.white70,
                      ),
                      tooltip: 'Anatomical Peeling (Layer Controls)',
                      onPressed: () {
                        setState(() {
                          _showLayerPanel = !_showLayerPanel;
                          if (_showLayerPanel) _selectedEntity = null;
                        });
                      },
                    ),

                    // Simulate Tap Demo
                    IconButton(
                      icon: const Icon(Icons.touch_app, color: Color(0xFF00D2FF)),
                      tooltip: 'Simulate bone tap (Demo)',
                      onPressed: () => _onMeshKeyPicked(1002), // Simulates Femur Left
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 3. Loading Indicator ──────────────────────────────
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF00D2FF)),
                  SizedBox(height: 16),
                  Text(
                    'Initializing Filament GPU Engine…',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
            ),

          // ── 4. Layer Peeling Panel (Bottom Overlay) ───────────
          if (_showLayerPanel && _systems.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SystemLayerPanel(
                systems: _systems,
                systemAlphas: _systemAlphas,
                onSystemAlphaChanged: _onSystemAlphaChanged,
                onClose: () => setState(() => _showLayerPanel = false),
              ),
            ),

          // ── 5. Entity Info Sheet (Bottom Overlay) ─────────────
          if (_selectedEntity != null && !_showLayerPanel)
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
        color: Color(0xF0121224),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0x3300D2FF), width: 1)),
        boxShadow: [
          BoxShadow(
            color: Color(0x4D000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            entity.englishName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),

          Text(
            entity.latinName,
            style: const TextStyle(
              color: Color(0xFF00D2FF),
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 4),

          if (entity.taId != null)
            Text(
              'Terminologia Anatomica: ${entity.taId} [Key: ${entity.meshKey}]',
              style: TextStyle(
                color: Colors.white.withAlpha(140),
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 12),

          if (entity.description != null)
            Text(
              entity.description!,
              style: TextStyle(
                color: Colors.white.withAlpha(210),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          const SizedBox(height: 12),

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
