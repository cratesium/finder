import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_palette.dart';

/// Full-bleed indigo gradient with soft diagonal light beams, painted in code
/// (no image assets).
class AuroraBackdrop extends StatelessWidget {
  const AuroraBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: c.backdropGradient),
      child: CustomPaint(
        painter: _BeamPainter(beam: c.beam, dark: Theme.of(context).brightness == Brightness.dark),
        child: child,
      ),
    );
  }
}

class _BeamPainter extends CustomPainter {
  _BeamPainter({required this.beam, required this.dark});
  final Color beam;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Violet bloom at the top-right, like stage light through glass.
    final bloom = Paint()
      ..shader = RadialGradient(
        colors: [
          beam.withValues(alpha: dark ? 0.35 : 0.55),
          beam.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: Offset(w * 0.85, -h * 0.05), radius: math.max(w, h) * 0.6));
    canvas.drawRect(Offset.zero & size, bloom);

    // A few slanted beams.
    const beams = [(0.18, 0.10, 0.20), (0.42, 0.05, 0.14), (0.62, 0.16, 0.10), (0.80, 0.07, 0.16)];
    canvas.save();
    canvas.translate(w * 0.5, 0);
    canvas.rotate(-0.42);
    canvas.translate(-w * 0.5, 0);
    for (final (x, width, alpha) in beams) {
      final rect = Rect.fromLTWH(w * x - w * 0.4, -h * 0.4, w * width, h * 1.2);
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            beam.withValues(alpha: 0),
            beam.withValues(alpha: alpha * (dark ? 1 : 1.6)),
            beam.withValues(alpha: 0),
          ],
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
      canvas.drawRect(rect, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BeamPainter old) => old.beam != beam || old.dark != dark;
}

/// Frosted-glass pill/circle used for controls placed on the backdrop.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 999,
    this.padding = EdgeInsets.zero,
    this.width,
    this.height,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0.04)]
              : [Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0.55)],
        ),
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.22) : c.border),
        boxShadow: [BoxShadow(color: c.shadow.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: child,
    );
  }
}
