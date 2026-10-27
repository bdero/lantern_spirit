import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lights out: the whole app goes dark and the friend is the only light.
///
/// Drawn over everything as one layer: darkness, with a warm pool of light
/// cut out around the friend, then every card's shadow cast away from the
/// light (soft, longer the farther the card is), then the cards' own faces
/// lit again by distance, and a rim of light on the edges that face the
/// friend.
class LightsOutPainter extends CustomPainter {
  LightsOutPainter({required this.light, required this.cards, required this.amount, required this.flicker, required this.warmth});

  /// Where the light is, in this painter's coordinates (the screen).
  final Offset light;

  /// The cards, as rounded rects, that catch the light and cast shadows.
  final List<RRect> cards;

  /// 0 (lights on, nothing drawn) to 1 (fully dark).
  final double amount;

  /// A slow breathing of the glow, around 1.
  final double flicker;

  /// The light's color.
  final Color warmth;

  @override
  void paint(Canvas canvas, Size size) {
    if (amount <= 0.001) return;
    final full = Offset.zero & size;
    final reach = size.longestSide * 0.48 * flicker;
    canvas.saveLayer(full, Paint());
    // Darkness everywhere.
    canvas.drawRect(full, Paint()..color = Color.fromRGBO(2, 3, 10, 0.94 * amount));
    // The pool of light, cut out of the dark with a soft falloff.
    canvas.drawRect(
      full,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..shader = RadialGradient(
          colors: const [Color(0xFFFFFFFF), Color(0xD8FFFFFF), Color(0x66FFFFFF), Color(0x1AFFFFFF), Color(0x00FFFFFF)],
          stops: const [0, 0.14, 0.42, 0.72, 1],
        ).createShader(Rect.fromCircle(center: light, radius: reach)),
    );
    // Shadows: each card blocks the light behind it. The shadow is the
    // card's outline swept away from the light, drawn back into the dark.
    final shade = Paint()
      ..color = Color.fromRGBO(2, 3, 10, 0.85 * amount)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    for (final c in cards) {
      final path = _shadow(c.outerRect, size.longestSide * 2);
      if (path != null) canvas.drawPath(path, shade);
    }
    // The cards' faces, lit by how near they are to the light (they sit in
    // front of their own shadows).
    for (final c in cards) {
      final d = _nearest(c.outerRect, light);
      final lit = math.pow((1 - d / reach).clamp(0.0, 1.0), 1.3).toDouble();
      canvas.drawRRect(
        c,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..color = Color.fromRGBO(255, 255, 255, 0.92 * lit),
      );
    }
    canvas.restore();
    // Warm light on the cards, and a rim on the edges facing the light.
    for (final c in cards) {
      final d = _nearest(c.outerRect, light);
      final lit = math.pow((1 - d / reach).clamp(0.0, 1.0), 1.3).toDouble() * amount;
      if (lit <= 0.01) continue;
      canvas.drawRRect(
        c,
        Paint()
          ..shader = RadialGradient(
            colors: [warmth.withValues(alpha: 0.16 * lit), warmth.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: light, radius: reach * 0.8)),
      );
      final toward = light - c.center;
      final rim = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = LinearGradient(
          begin: Alignment(toward.dx.sign * math.min(1, toward.dx.abs() / c.width * 2), toward.dy.sign * math.min(1, toward.dy.abs() / c.height * 2)),
          end: Alignment.center,
          colors: [warmth.withValues(alpha: 0.85 * lit), warmth.withValues(alpha: 0)],
        ).createShader(c.outerRect);
      canvas.drawRRect(c, rim);
    }
  }

  static double _nearest(Rect r, Offset p) {
    final dx = math.max(math.max(r.left - p.dx, 0.0), p.dx - r.right);
    final dy = math.max(math.max(r.top - p.dy, 0.0), p.dy - r.bottom);
    return math.sqrt(dx * dx + dy * dy);
  }

  /// The region a rect shadows from a point light: the hull of its corners
  /// and their projections far away from the light.
  Path? _shadow(Rect r, double far) {
    if (r.contains(light)) return null;
    final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
    final pts = <Offset>[
      for (final c in corners) c,
      for (final c in corners) c + (c - light) / math.max((c - light).distance, 1) * far,
    ];
    final hull = _convexHull(pts);
    return Path()..addPolygon(hull, true);
  }

  static List<Offset> _convexHull(List<Offset> pts) {
    final p = [...pts]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
    double cross(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final lower = <Offset>[];
    for (final q in p) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, q) <= 0) {
        lower.removeLast();
      }
      lower.add(q);
    }
    final upper = <Offset>[];
    for (final q in p.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, q) <= 0) {
        upper.removeLast();
      }
      upper.add(q);
    }
    return [...lower.sublist(0, lower.length - 1), ...upper.sublist(0, upper.length - 1)];
  }

  @override
  bool shouldRepaint(LightsOutPainter old) => true;
}
