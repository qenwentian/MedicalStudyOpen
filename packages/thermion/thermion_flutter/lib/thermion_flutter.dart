library thermion_flutter;

import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

enum ManipulatorType { ORBIT }

class ThermionViewer {
  Future<void> removeSkybox() async {}
  Future<void> loadGltf(String assetPath) async {}
  
  Future<void> setMaterialProperty(String materialName, String propertyName, List<double> values) async {
    // Mock FFI call to C++ to mutate material instance
    debugPrint('Mock FFI: setMaterialProperty($materialName, $propertyName, $values)');
  }

  Future<String?> pick(int x, int y) async {
    final completer = Completer<String?>();
    
    // Simulate FFI call using NativeCallable safely
    final callable = NativeCallable<Void Function(Pointer<Utf8>)>.listener((Pointer<Utf8> namePtr) {
      final name = namePtr.toDartString();
      if (name.isEmpty) {
        completer.complete(null);
      } else {
        completer.complete(name);
      }
    });

    // Mock invoking the C++ bridge
    Future.delayed(const Duration(milliseconds: 16), () {
      completer.complete("BONE_FEMUR_L");
      callable.close();
    });

    return completer.future;
  }
}

class ViewerWidget extends StatefulWidget {
  final bool? transformToUnitCube;
  final Vector3? initialCameraPosition;
  final Color? background;
  final ManipulatorType? manipulatorType;
  final Function(ThermionViewer)? onViewerAvailable;
  final Widget? initial;

  const ViewerWidget({
    Key? key,
    this.transformToUnitCube,
    this.initialCameraPosition,
    this.background,
    this.manipulatorType,
    this.onViewerAvailable,
    this.initial,
  }) : super(key: key);

  @override
  State<ViewerWidget> createState() => _ViewerWidgetState();
}

class _ViewerWidgetState extends State<ViewerWidget> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => widget.onViewerAvailable?.call(ThermionViewer()));
  }
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
