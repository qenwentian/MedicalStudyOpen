library thermion_flutter;

import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

enum ManipulatorType { ORBIT }

class ThermionViewer {
  Future<String?> pick(int x, int y) async {
    final completer = Completer<String?>();
    
    // Simulate FFI call using NativeCallable safely
    final callable = NativeCallable<Void Function(Pointer<Utf8>)>.listener((namePtr) {
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
  final Function(ThermionViewer)? onViewerReady;
  final ManipulatorType? manipulator;
  const ViewerWidget({Key? key, this.onViewerReady, this.manipulator}) : super(key: key);

  @override
  State<ViewerWidget> createState() => _ViewerWidgetState();
}

class _ViewerWidgetState extends State<ViewerWidget> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => widget.onViewerReady?.call(ThermionViewer()));
  }
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
