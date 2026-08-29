import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';

/// A full-screen widget wrapping the Thermion/Filament 3D viewport.
///
/// Loads a `.glb` asset from the [assetPath] and renders it using
/// Google Filament's PBR pipeline via native FFI. Orbit manipulation
/// is enabled by default so the user can rotate/zoom the model.
///
/// When the viewer becomes available, the [onViewerReady] callback
/// fires, providing the [ThermionViewer] handle that the parent
/// screen uses for raycasting and material manipulation.
class ThermionViewport extends StatelessWidget {
  /// Relative path to the .glb asset (e.g., `assets/3d/skeleton_lod0.glb`).
  final String assetPath;

  /// Called once the native Filament engine is initialized and
  /// the viewer handle is ready for raycasting / entity queries.
  final void Function(ThermionViewer viewer)? onViewerReady;

  const ThermionViewport({
    super.key,
    required this.assetPath,
    this.onViewerReady,
  });

  @override
  Widget build(BuildContext context) {
    return ViewerWidget(
      assetPath: assetPath,
      transformToUnitCube: true,
      initialCameraPosition: Vector3(0, 1, 5),
      background: const Color(0xFF1A1A2E),
      manipulatorType: ManipulatorType.ORBIT,
      onViewerAvailable: (viewer) async {
        // Remove the default skybox for a clean dark background.
        await viewer.removeSkybox();
        onViewerReady?.call(viewer);
      },
      initial: const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF00D2FF),
        ),
      ),
    );
  }
}
