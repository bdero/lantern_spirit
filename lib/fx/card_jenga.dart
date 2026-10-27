import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Card Jenga: the list's cards as rigid boxes that tumble and pile up.
///
/// Each card is a snapshot image on a box with mass and spin. A small
/// impulse solver handles gravity, the floor and walls, and box against box
/// (each box's corners pushed out of the others), with friction, so cards
/// slide, tip, and come to rest stacked. Afterwards [home] flies each one
/// back to where it came from.
class JengaBody {
  JengaBody(this.image, this.home, this.radius) : pos = home.center, half = Size(home.width / 2, home.height / 2) {
    final m = home.width * home.height / 10000;
    invMass = 1 / m;
    invInertia = 1 / (m * (home.width * home.width + home.height * home.height) / 12);
  }

  final ui.Image image;

  /// Where it sits in the list, in screen pixels.
  final Rect home;
  final double radius;
  final Size half;
  Offset pos;
  double angle = 0;
  Offset vel = Offset.zero;
  double spin = 0;
  late double invMass;
  late double invInertia;

  /// Pinned bodies do not move (until released).
  bool pinned = true;

  // Flying home.
  Offset _fromPos = Offset.zero;
  double _fromAngle = 0;

  List<Offset> get corners {
    final c = math.cos(angle), s = math.sin(angle);
    Offset w(double x, double y) => pos + Offset(x * c - y * s, x * s + y * c);
    return [w(-half.width, -half.height), w(half.width, -half.height), w(half.width, half.height), w(-half.width, half.height)];
  }

  /// [p] in this body's own frame.
  Offset local(Offset p) {
    final d = p - pos;
    final c = math.cos(-angle), s = math.sin(-angle);
    return Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }

  Offset _rotate(Offset v, double a) => Offset(v.dx * math.cos(a) - v.dy * math.sin(a), v.dx * math.sin(a) + v.dy * math.cos(a));

  Offset velocityAt(Offset p) {
    final r = p - pos;
    return vel + Offset(-spin * r.dy, spin * r.dx);
  }

  void applyImpulse(Offset j, Offset at) {
    if (pinned) return;
    vel += j * invMass;
    final r = at - pos;
    spin += (r.dx * j.dy - r.dy * j.dx) * invInertia;
  }
}

class _Contact {
  _Contact(this.a, this.b, this.point, this.normal, this.depth);
  final JengaBody a;
  final JengaBody? b; // null for the floor or a wall
  final Offset point;
  final Offset normal; // from b toward a
  final double depth;
}

class JengaSim {
  JengaSim(this.bodies, {required this.floor, required this.left, required this.right});

  final List<JengaBody> bodies;
  final double floor, left, right;
  static const gravity = 2600.0;

  void step(double dt) {
    const sub = 4;
    final h = dt.clamp(0.0, 1 / 30) / sub;
    for (var s = 0; s < sub; s++) {
      for (final b in bodies) {
        if (b.pinned) continue;
        b.vel += Offset(0, gravity * h);
        b.vel *= math.exp(-0.15 * h);
        b.spin *= math.exp(-0.6 * h);
      }
      final contacts = _contacts();
      for (var it = 0; it < 10; it++) {
        for (final c in contacts) {
          _resolve(c, h);
        }
      }
      for (final b in bodies) {
        if (b.pinned) continue;
        b.pos += b.vel * h;
        b.angle += b.spin * h;
      }
      // Push apart what still overlaps, gently, so piles do not sink.
      for (final c in _contacts()) {
        final fix = math.max(c.depth - 0.5, 0.0) * 0.4;
        if (fix <= 0) continue;
        final ia = c.a.pinned ? 0.0 : c.a.invMass;
        final ib = (c.b == null || c.b!.pinned) ? 0.0 : c.b!.invMass;
        final sum = ia + ib;
        if (sum <= 0) continue;
        c.a.pos += c.normal * (fix * ia / sum);
        if (c.b != null) c.b!.pos -= c.normal * (fix * ib / sum);
      }
    }
  }

  List<_Contact> _contacts() {
    final out = <_Contact>[];
    for (final a in bodies) {
      if (a.pinned) continue;
      for (final p in a.corners) {
        if (p.dy > floor) out.add(_Contact(a, null, p, const Offset(0, -1), p.dy - floor));
        if (p.dx < left) out.add(_Contact(a, null, p, const Offset(1, 0), left - p.dx));
        if (p.dx > right) out.add(_Contact(a, null, p, const Offset(-1, 0), p.dx - right));
      }
    }
    for (var i = 0; i < bodies.length; i++) {
      for (var j = 0; j < bodies.length; j++) {
        if (i == j) continue;
        final a = bodies[i], b = bodies[j];
        if (a.pinned && b.pinned) continue;
        if ((a.pos - b.pos).distance > a.half.longestSide + b.half.longestSide + 4) continue;
        // a's corners inside b: pushed out along b's nearest face.
        for (final p in a.corners) {
          final l = b.local(p);
          final dx = b.half.width - l.dx.abs();
          final dy = b.half.height - l.dy.abs();
          if (dx <= 0 || dy <= 0) continue;
          final Offset n;
          final double depth;
          if (dx < dy) {
            n = b._rotate(Offset(l.dx.sign, 0), b.angle);
            depth = dx;
          } else {
            n = b._rotate(Offset(0, l.dy.sign), b.angle);
            depth = dy;
          }
          out.add(_Contact(a, b, p, n, depth));
        }
      }
    }
    return out;
  }

  void _resolve(_Contact c, double h) {
    final a = c.a, b = c.b;
    final va = a.velocityAt(c.point);
    final vb = b?.velocityAt(c.point) ?? Offset.zero;
    final rel = va - vb;
    final vn = rel.dx * c.normal.dx + rel.dy * c.normal.dy;
    if (vn > 0) return;
    double inv(JengaBody? body, Offset n) {
      if (body == null || body.pinned) return 0;
      final r = c.point - body.pos;
      final rn = r.dx * n.dy - r.dy * n.dx;
      return body.invMass + rn * rn * body.invInertia;
    }

    final k = inv(a, c.normal) + inv(b, c.normal);
    if (k <= 0) return;
    final bounce = vn < -400 ? 0.18 : 0.0;
    final jn = -(1 + bounce) * vn / k;
    // Nothing to push (a resting touch, or a degenerate contact): no friction
    // either. This also keeps the friction clamp's bounds in order (a -0.0
    // impulse would flip them).
    if (!(jn > 0)) return;
    final impulse = c.normal * jn;
    a.applyImpulse(impulse, c.point);
    b?.applyImpulse(-impulse, c.point);
    // Friction along the surface.
    final t = Offset(-c.normal.dy, c.normal.dx);
    final vt = rel.dx * t.dx + rel.dy * t.dy;
    final kt = inv(a, t) + inv(b, t);
    if (kt <= 0) return;
    final jt = (-vt / kt).clamp(-0.55 * jn, 0.55 * jn);
    a.applyImpulse(t * jt, c.point);
    b?.applyImpulse(-(t * jt), c.point);
  }

  /// Starts every body flying home from wherever it lies now.
  void startHome() {
    for (final b in bodies) {
      b
        .._fromPos = b.pos
        .._fromAngle = b.angle
        ..pinned = true;
    }
  }

  /// Flies body [i] home, [u] from 0 (where it lay) to 1 (home), on an arc.
  void home(int i, double u) {
    final b = bodies[i];
    final e = Curves.easeInOutCubic.transform(u.clamp(0.0, 1.0));
    final lift = math.sin(e * math.pi) * 60;
    b
      ..pos = Offset.lerp(b._fromPos, b.home.center, e)! - Offset(0, lift)
      ..angle = b._fromAngle * (1 - e) + math.sin(e * math.pi) * 0.12 * (i.isEven ? 1 : -1);
  }
}

/// Draws the bodies: each card snapshot at its pose, with a soft shadow.
class JengaPainter extends CustomPainter {
  JengaPainter(this.bodies, this.repaint) : super(repaint: repaint);
  final List<JengaBody> bodies;
  final Listenable repaint;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bodies) {
      canvas.save();
      canvas.translate(b.pos.dx, b.pos.dy);
      canvas.rotate(b.angle);
      final r = Rect.fromCenter(center: Offset.zero, width: b.home.width, height: b.home.height);
      final rr = RRect.fromRectAndRadius(r, Radius.circular(b.radius));
      canvas.drawRRect(rr.shift(const Offset(0, 8)), Paint()..color = const Color(0x66000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
      canvas.save();
      canvas.clipRRect(rr);
      canvas.drawImageRect(b.image, Offset.zero & Size(b.image.width.toDouble(), b.image.height.toDouble()), r, Paint()..filterQuality = FilterQuality.medium);
      canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(JengaPainter old) => true;
}
