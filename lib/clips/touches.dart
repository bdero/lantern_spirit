import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/clock.dart';

/// Shows touches on screen for recordings: a soft dot that presses in,
/// follows the finger, and leaves a ripple when it lifts.
///
/// Real touches show while [showReal] is on; scripted clips drive a
/// finger of their own with [press], [move], and [lift], and the dot
/// glides between points with [glide].
class Touches extends ChangeNotifier {
  Touches._();
  static final instance = Touches._();

  bool showReal = false;

  /// A scripted finger hovering between taps, drawn faintly.
  Offset? hover;

  final Map<int, _Dot> _dots = {};
  final List<_Ripple> _ripples = [];
  static const _fake = -1;

  void press(Offset at) => _down(_fake, at);
  void move(Offset at) => _move(_fake, at);
  void lift() => _up(_fake);

  /// A tap: press, a short hold, and lift.
  Future<void> tap(Offset at) async {
    hover = null;
    press(at);
    await AppClock.delay(const Duration(milliseconds: 130));
    lift();
  }

  /// Moves the scripted finger from where it is to [to] over [ms], easing,
  /// calling [each] with every intermediate point.
  Future<void> glide(Offset to, {int ms = 600, void Function(Offset p)? each, Curve curve = Curves.easeInOutCubic}) async {
    final pressed = _dots.containsKey(_fake);
    final from = _dots[_fake]?.at ?? hover ?? to;
    final start = AppClock.now;
    while (true) {
      final t = (AppClock.now.difference(start).inMicroseconds / (ms * 1000)).clamp(0.0, 1.0);
      final p = Offset.lerp(from, to, curve.transform(t))!;
      if (pressed) {
        move(p);
      } else {
        hover = p;
        notifyListeners();
      }
      each?.call(p);
      if (t >= 1) break;
      await AppClock.delay(const Duration(milliseconds: 16));
    }
  }

  void _down(int id, Offset at) {
    if (id == _fake) hover = null;
    _dots[id] = _Dot(at);
    notifyListeners();
  }

  void _move(int id, Offset at) {
    final d = _dots[id];
    if (d == null) return;
    d.trail.insert(0, d.at);
    if (d.trail.length > 6) d.trail.removeLast();
    d.at = at;
    notifyListeners();
  }

  void _up(int id) {
    final d = _dots.remove(id);
    if (d != null) _ripples.add(_Ripple(d.at));
    if (id == _fake && d != null) hover = d.at;
    notifyListeners();
  }
}

class _Dot {
  _Dot(this.at);
  Offset at;
  final List<Offset> trail = [];
  final born = AppClock.now;
}

class _Ripple {
  _Ripple(this.at);
  final Offset at;
  final born = AppClock.now;
}

/// Draws [Touches] over the whole app, and feeds it real pointers.
class TouchOverlay extends StatefulWidget {
  const TouchOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<TouchOverlay> createState() => _TouchOverlayState();
}

class _TouchOverlayState extends State<TouchOverlay> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final t = Touches.instance;
      t._ripples.removeWhere((r) => AppClock.now.difference(r.born).inMilliseconds > 450);
      if (t._dots.isNotEmpty || t._ripples.isNotEmpty || t.hover != null || _shown) {
        _shown = t._dots.isNotEmpty || t._ripples.isNotEmpty || t.hover != null;
        setState(() {});
      }
    })..start();
  }

  bool _shown = false;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Touches.instance;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (t.showReal) t._down(e.pointer, e.position);
      },
      onPointerMove: (e) {
        if (t.showReal) t._move(e.pointer, e.position);
      },
      onPointerUp: (e) => t._up(e.pointer),
      onPointerCancel: (e) => t._up(e.pointer),
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _TouchPainter(t)))),
        ],
      ),
    );
  }
}

class _TouchPainter extends CustomPainter {
  _TouchPainter(this.t);
  final Touches t;

  @override
  void paint(Canvas canvas, Size size) {
    final now = AppClock.now;
    if (t.hover case final h?) {
      canvas.drawCircle(h, 16, Paint()..color = const Color(0x22000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(h, 14, Paint()..color = Colors.white.withValues(alpha: 0.22));
      canvas.drawCircle(
        h,
        14,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.55),
      );
    }
    for (final d in t._dots.values) {
      final age = now.difference(d.born).inMilliseconds / 1000;
      final pressIn = Curves.easeOutBack.transform((age / 0.18).clamp(0.0, 1.0));
      for (var i = 0; i < d.trail.length; i++) {
        final k = 1 - i / d.trail.length;
        canvas.drawCircle(d.trail[i], 15 * k, Paint()..color = Colors.white.withValues(alpha: 0.12 * k));
      }
      final r = 22 * (0.6 + 0.4 * pressIn);
      canvas.drawCircle(d.at, r + 6, Paint()..color = const Color(0x33000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawCircle(d.at, r, Paint()..color = Colors.white.withValues(alpha: 0.42));
      canvas.drawCircle(
        d.at,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.85),
      );
    }
    for (final rp in t._ripples) {
      final k = (now.difference(rp.born).inMilliseconds / 450).clamp(0.0, 1.0);
      final e = Curves.easeOutCubic.transform(k);
      canvas.drawCircle(
        rp.at,
        22 + 26 * e,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - e) + 0.5
          ..color = Colors.white.withValues(alpha: 0.7 * (1 - e)),
      );
    }
  }

  @override
  bool shouldRepaint(_TouchPainter old) => true;
}

/// Small helpers for scripted clips.
extension Wait on Duration {
  Future<void> get wait => AppClock.delay(this);
}

double easeOutBack(double t) => Curves.easeOutBack.transform(t.clamp(0.0, 1.0));
double sinWave(double t, double hz) => math.sin(t * math.pi * 2 * hz);
