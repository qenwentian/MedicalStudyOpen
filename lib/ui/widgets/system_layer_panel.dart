import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/anatomy_entity.dart';

/// A throttled layer peeling control panel for adjusting anatomical system transparency.
///
/// Implements **Vector 2 Mitigation (Event Thrashing)**:
/// Caps slider update emissions to ~30Hz (33ms window) to prevent FFI bottlenecking.
class SystemLayerPanel extends StatefulWidget {
  final List<BodySystem> systems;
  final Map<String, double> systemAlphas;
  final void Function(String systemId, double alpha) onSystemAlphaChanged;
  final VoidCallback onClose;

  const SystemLayerPanel({
    super.key,
    required this.systems,
    required this.systemAlphas,
    required this.onSystemAlphaChanged,
    required this.onClose,
  });

  @override
  State<SystemLayerPanel> createState() => _SystemLayerPanelState();
}

class _SystemLayerPanelState extends State<SystemLayerPanel> {
  // Throttler state
  Timer? _throttleTimer;
  String? _pendingSystemId;
  double? _pendingAlpha;
  int _lastEmitTimeMs = 0;

  static const int _throttleWindowMs = 33; // ~30 Hz emission rate

  void _onSliderDragged(String systemId, double value) {
    setState(() {
      widget.systemAlphas[systemId] = value;
    });

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastEmitTimeMs >= _throttleWindowMs) {
      _lastEmitTimeMs = now;
      widget.onSystemAlphaChanged(systemId, value);
    } else {
      _pendingSystemId = systemId;
      _pendingAlpha = value;
      _throttleTimer?.cancel();
      _throttleTimer = Timer(Duration(milliseconds: _throttleWindowMs - (now - _lastEmitTimeMs)), () {
        if (_pendingSystemId != null && _pendingAlpha != null) {
          _lastEmitTimeMs = DateTime.now().millisecondsSinceEpoch;
          widget.onSystemAlphaChanged(_pendingSystemId!, _pendingAlpha!);
          _pendingSystemId = null;
          _pendingAlpha = null;
        }
      });
    }
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    super.dispose();
  }

  Color _parseHexColor(String hex) {
    try {
      final buffer = StringBuffer();
      if (hex.length == 6 || hex.length == 7) buffer.write('ff');
      buffer.write(hex.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return const Color(0xFF00D2FF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 420),
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
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
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
          const SizedBox(height: 12),

          // Header
          Row(
            children: [
              const Icon(Icons.layers, color: Color(0xFF00D2FF), size: 22),
              const SizedBox(width: 8),
              const Text(
                'Anatomical Peeling (Layer Depth)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Adjust layer opacity. Deeper layers maintain strict render priority.',
            style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12),
          ),
          const SizedBox(height: 14),

          // Systems list
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.systems.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final system = widget.systems[index];
                final currentAlpha = widget.systemAlphas[system.systemId] ?? 1.0;
                final color = _parseHexColor(system.hexColor);

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withAlpha(15)),
                  ),
                  child: Row(
                    children: [
                      // Depth priority badge
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color.withAlpha(40),
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 1.5),
                        ),
                        child: Text(
                          '${system.depthPriority}',
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Name & Percentage
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              system.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Opacity: ${(currentAlpha * 100).toInt()}%',
                              style: TextStyle(
                                color: Colors.white.withAlpha(120),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Slider with 30Hz Throttling
                      SizedBox(
                        width: 140,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: color,
                            inactiveTrackColor: Colors.white12,
                            thumbColor: Colors.white,
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          ),
                          child: Slider(
                            value: currentAlpha,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (val) => _onSliderDragged(system.systemId, val),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
