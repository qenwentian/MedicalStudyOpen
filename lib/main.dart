import 'package:flutter/material.dart';

import 'ui/screens/atlas_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AnatomyAtlasApp());
}

/// Root widget for the Anatomy Atlas application.
///
/// Sets up a dark Material 3 theme and launches directly into the
/// [AtlasScreen] — the full-screen 3D viewport with Flutter overlay.
class AnatomyAtlasApp extends StatelessWidget {
  const AnatomyAtlasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anatomy Atlas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF00D2FF),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D0D1A),
      ),
      home: const AtlasScreen(),
    );
  }
}
