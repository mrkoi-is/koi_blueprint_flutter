import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:koi_ui/theme/koi_theme_tokens.dart';

class KoiResizableSplitView extends StatefulWidget {
  const KoiResizableSplitView({
    required this.primary,
    required this.secondary,
    this.width = 280,
    this.minWidth = 160,
    this.maxWidth = 480,
    this.minSecondaryWidth = 240,
    this.onWidthChanged,
    this.primaryOnTrailing = false,
    this.resizeLabel = '调整侧栏宽度',
    super.key,
  }) : assert(minWidth >= 0),
       assert(maxWidth >= minWidth),
       assert(minSecondaryWidth >= 0);

  final Widget primary;
  final Widget secondary;
  final double width;
  final double minWidth;
  final double maxWidth;
  final double minSecondaryWidth;
  final ValueChanged<double>? onWidthChanged;
  final bool primaryOnTrailing;
  final String resizeLabel;

  @override
  State<KoiResizableSplitView> createState() => _KoiResizableSplitViewState();
}

class _KoiResizableSplitViewState extends State<KoiResizableSplitView> {
  late double _width = widget.width;
  bool _focused = false;
  bool _hovered = false;
  bool _dragging = false;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant KoiResizableSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width != widget.width) _width = widget.width;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final tokens = KoiThemeTokens.of(context);
      // Reserve the target in the row, so touch resizing never steals taps
      // from either pane. The visible grip stays narrow in both densities.
      final handleWidth = tokens.density == KoiDensity.comfortable
          ? 48.0
          : 12.0;
      final available = math.max(0.0, constraints.maxWidth - handleWidth);
      final max = math.min(
        widget.maxWidth,
        math.max(0.0, available - widget.minSecondaryWidth),
      );
      final min = math.min(widget.minWidth, max);
      final width = _width.clamp(min, max);
      void change(double value) {
        final next = value.clamp(min, max);
        if (next == width) return;
        setState(() => _width = next);
        widget.onWidthChanged?.call(next);
      }

      final isRtl = Directionality.of(context) == TextDirection.rtl;
      final primaryOnRight = widget.primaryOnTrailing != isRtl;
      final direction = primaryOnRight ? -1.0 : 1.0;
      // A pane may contain a Navigator whose route blocks earlier semantics.
      // Keep that boundary inside the pane instead of hiding sibling regions.
      final primary = SizedBox(
        width: width,
        child: Semantics(container: true, child: widget.primary),
      );
      final secondary = Expanded(
        child: Semantics(container: true, child: widget.secondary),
      );
      final handle = Semantics(
        container: true,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: FocusableActionDetector(
            focusNode: _focus,
            mouseCursor: SystemMouseCursors.resizeLeftRight,
            onShowFocusHighlight: (value) => setState(() => _focused = value),
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.arrowLeft): _ResizeIntent(-10),
              SingleActivator(LogicalKeyboardKey.arrowRight): _ResizeIntent(10),
              SingleActivator(LogicalKeyboardKey.home): _ResizeIntent(
                -1e9,
                bound: true,
              ),
              SingleActivator(LogicalKeyboardKey.end): _ResizeIntent(
                1e9,
                bound: true,
              ),
            },
            actions: {
              _ResizeIntent: CallbackAction<_ResizeIntent>(
                onInvoke: (intent) {
                  change(width + intent.delta * (intent.bound ? 1 : direction));
                  return null;
                },
              ),
            },
            child: Semantics(
              label: widget.resizeLabel,
              value: '${width.round()}',
              increasedValue: '${(width + 10).clamp(min, max).round()}',
              decreasedValue: '${(width - 10).clamp(min, max).round()}',
              onIncrease: () => change(width + 10),
              onDecrease: () => change(width - 10),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onTap: _focus.requestFocus,
                onHorizontalDragStart: (_) {
                  _focus.requestFocus();
                  setState(() => _dragging = true);
                },
                onHorizontalDragUpdate: (event) =>
                    change(_width.clamp(min, max) + event.delta.dx * direction),
                onHorizontalDragEnd: (_) => setState(() => _dragging = false),
                onHorizontalDragCancel: () => setState(() => _dragging = false),
                child: SizedBox(
                  width: handleWidth,
                  child: Center(
                    child: AnimatedContainer(
                      key: const ValueKey('koi-split-grip'),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 120),
                      width: 2,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: _focused || _dragging
                            ? tokens.dropIndicator
                            : _hovered
                            ? Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: .2)
                            : Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widget.primaryOnTrailing
            ? [secondary, handle, primary]
            : [primary, handle, secondary],
      );
    },
  );
}

class _ResizeIntent extends Intent {
  const _ResizeIntent(this.delta, {this.bound = false});
  final double delta;
  final bool bound;
}
