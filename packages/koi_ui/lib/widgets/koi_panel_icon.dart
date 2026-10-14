import 'package:flutter/material.dart';

/// A panel outline, rather than an information or warning symbol.
class KoiPanelIcon extends StatelessWidget {
  const KoiPanelIcon({this.trailing = false, super.key});

  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final onRight =
        trailing != (Directionality.of(context) == TextDirection.rtl);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: theme.size ?? 20,
        child: CustomPaint(
          painter: _PanelPainter(
            color: (theme.color ?? Theme.of(context).colorScheme.onSurface)
                .withValues(alpha: theme.opacity ?? 1),
            onRight: onRight,
          ),
        ),
      ),
    );
  }
}

class _PanelPainter extends CustomPainter {
  const _PanelPainter({required this.color, required this.onRight});
  final Color color;
  final bool onRight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final rect = Rect.fromLTWH(
      size.width * .08,
      size.height * .14,
      size.width * .84,
      size.height * .72,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      paint,
    );
    final x = onRight
        ? rect.right - rect.width * .3
        : rect.left + rect.width * .3;
    canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
  }

  @override
  bool shouldRepaint(_PanelPainter oldDelegate) =>
      color != oldDelegate.color || onRight != oldDelegate.onRight;
}
