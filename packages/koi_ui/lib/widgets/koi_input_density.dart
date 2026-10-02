import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:koi_ui/theme/koi_theme_tokens.dart';

enum KoiDensityMode { automatic, comfortable, compact }

/// Input is ephemeral UI state. A non-null [density] always wins over it.
/// The initial automatic layout is touch-safe, including before the first event.
class KoiInputDensity extends StatefulWidget {
  const KoiInputDensity({required this.builder, this.density, super.key});

  final KoiDensity? density;
  final Widget Function(BuildContext context, KoiDensity density) builder;

  @override
  State<KoiInputDensity> createState() => _KoiInputDensityState();
}

class _KoiInputDensityState extends State<KoiInputDensity> {
  KoiDensity _inputDensity = KoiDensity.comfortable;

  void _observe(PointerEvent event) {
    final next = switch (event.kind) {
      PointerDeviceKind.mouse ||
      PointerDeviceKind.trackpad => KoiDensity.compact,
      PointerDeviceKind.touch ||
      PointerDeviceKind.stylus ||
      PointerDeviceKind.invertedStylus => KoiDensity.comfortable,
      PointerDeviceKind.unknown => _inputDensity,
    };
    if (next == _inputDensity) return;
    if (widget.density == null) {
      setState(() => _inputDensity = next);
    } else {
      // Keep the last physical input for a later switch to automatic, without
      // rebuilding or writing preferences while a manual choice is active.
      _inputDensity = next;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _observe,
    onPointerHover: _observe,
    onPointerPanZoomStart: _observe,
    child: widget.builder(context, widget.density ?? _inputDensity),
  );
}
