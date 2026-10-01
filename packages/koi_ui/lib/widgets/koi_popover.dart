import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:koi_ui/theme/koi_theme_tokens.dart';

/// A bounded, modal popover. The trigger owns its focus and overlay lifetime.
class KoiPopover extends StatefulWidget {
  const KoiPopover({
    required this.builder,
    required this.child,
    this.label = '打开面板',
    super.key,
  });

  final Widget Function(BuildContext context, VoidCallback close) builder;
  final Widget child;
  final String label;

  @override
  State<KoiPopover> createState() => _KoiPopoverState();
}

class _KoiPopoverState extends State<KoiPopover> {
  final _controller = OverlayPortalController();
  final _anchor = GlobalKey();
  final _triggerFocus = FocusNode();
  final _scope = FocusScopeNode(
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );

  void _close() {
    if (!mounted || !_controller.isShowing) return;
    setState(_controller.hide);
    _triggerFocus.requestFocus();
  }

  void _toggle() {
    if (_controller.isShowing) {
      _close();
    } else {
      setState(_controller.show);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.isShowing) {
          _scope.requestFocus();
          _scope.nextFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _scope.dispose();
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !_controller.isShowing,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _close();
    },
    child: OverlayPortal(
      controller: _controller,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) return const SizedBox.shrink();
          final anchor = box.localToGlobal(Offset.zero) & box.size;
          final media = MediaQuery.of(context);
          // Root overlays do not inherit Scaffold's keyboard avoidance.
          final safeLeft =
              math.max(media.padding.left, media.viewInsets.left) + 16;
          final safeRight =
              constraints.maxWidth -
              math.max(media.padding.right, media.viewInsets.right) -
              16;
          final safeTop =
              math.max(media.padding.top, media.viewInsets.top) + 16;
          final safeBottom =
              constraints.maxHeight -
              math.max(media.padding.bottom, media.viewInsets.bottom) -
              16;
          final width = math.min(360.0, math.max(0.0, safeRight - safeLeft));
          final left = anchor.left.clamp(
            safeLeft,
            math.max(safeLeft, safeRight - width),
          );
          final belowTop = (anchor.bottom + 8).clamp(
            safeTop,
            math.max(safeTop, safeBottom),
          );
          final aboveBottom = (anchor.top - 8).clamp(
            safeTop,
            math.max(safeTop, safeBottom),
          );
          final below = math.max(0.0, safeBottom - belowTop);
          final above = math.max(0.0, aboveBottom - safeTop);
          final placeBelow = below >= 160 || below >= above;
          final available = placeBelow ? below : above;
          return Stack(
            children: [
              Positioned.fill(
                child: ModalBarrier(onDismiss: _close, semanticsLabel: '关闭面板'),
              ),
              Positioned(
                left: left.toDouble(),
                top: placeBelow ? belowTop.toDouble() : null,
                bottom: placeBelow ? null : constraints.maxHeight - aboveBottom,
                width: width,
                child: Semantics(
                  scopesRoute: true,
                  namesRoute: true,
                  explicitChildNodes: true,
                  label: widget.label,
                  child: FocusScope(
                    node: _scope,
                    autofocus: true,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        _close();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Material(
                      elevation: 3,
                      surfaceTintColor: Colors.transparent,
                      color: KoiThemeTokens.of(context).overlayBackground,
                      borderRadius: BorderRadius.circular(KoiRadius.medium),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: available),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(KoiSpace.md),
                          child: widget.builder(context, _close),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      child: TextButton(
        key: _anchor,
        focusNode: _triggerFocus,
        onPressed: _toggle,
        child: Semantics(
          expanded: _controller.isShowing,
          label: widget.label,
          excludeSemantics: true,
          child: widget.child,
        ),
      ),
    ),
  );
}
