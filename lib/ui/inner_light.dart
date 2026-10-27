import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A glowing part of Lumi on screen.
class GlowPoint {
  const GlowPoint(this.position, this.color, this.strength);

  /// Global screen position.
  final Offset position;

  /// Linear color of the light.
  final vm.Vector3 color;
  final double strength;
}

/// Light from inside: Lumi's hands and head glow onto the list below the
/// header, as soft colored pools that follow them around.
///
/// Painted over the Flutter UI (nothing here is 3D), so it works on any
/// screen. Only the part below [top] is painted; the header already shows
/// the real glow.
class InnerLight extends StatelessWidget {
  const InnerLight({super.key, required this.points, required this.top});

  final ValueListenable<List<GlowPoint>> points;
  final double top;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _InnerLightPainter(points, top)),
      ),
    );
  }
}

class _InnerLightPainter extends CustomPainter {
  _InnerLightPainter(this.points, this.top) : super(repaint: points);

  final ValueListenable<List<GlowPoint>> points;
  final double top;

  static double _srgb(double v) => v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;

  @override
  void paint(Canvas canvas, Size size) {
    // The overlay fills the screen from its origin, so global positions are
    // local ones here.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, top, size.width, size.height));
    for (final p in points.value) {
      final local = p.position;
      final c = Color.from(
        alpha: 1,
        red: _srgb(p.color.x.clamp(0.0, 1.0)),
        green: _srgb(p.color.y.clamp(0.0, 1.0)),
        blue: _srgb(p.color.z.clamp(0.0, 1.0)),
      );
      final s = p.strength.clamp(0.0, 1.8);
      // The pool reaches further the closer the light is to the edge.
      final reach = 150.0 + 40 * s;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [c.withValues(alpha: 0.22 * s), c.withValues(alpha: 0.08 * s), c.withValues(alpha: 0)],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: local, radius: reach));
      canvas.drawCircle(local, reach, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InnerLightPainter old) => false;
}
