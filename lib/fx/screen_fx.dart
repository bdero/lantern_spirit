import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Effects that reach across the whole screen, driven once per frame by the
/// park and read by wrappers around the app's widgets:
///
/// * impacts, a shockwave that shakes every wrapped widget on its own
///   damped spring, later and gentler the farther it is from the hit;
/// * a pulse, a ring of light that lights each card's outline as it passes;
/// * a warp, a ring that bends the whole picture (a ripple or a heat haze),
///   drawn by [WarpLayer] with a fragment shader.
class ScreenFx extends ChangeNotifier {
  double _clock = 0;
  final List<_Impact> _impacts = [];
  _Pulse? _pulse;
  _Warp? _warp;
  bool _wasActive = false;

  /// The shared clock, in seconds.
  double get clock => _clock;

  bool get active => _impacts.isNotEmpty || _pulse != null || _warp != null;

  /// Advances to [clock] (seconds) and repaints the wrappers while anything
  /// is playing.
  void tick(double clock) {
    _clock = clock;
    _impacts.removeWhere((i) => clock - i.time > 3.0);
    if (_pulse != null && clock - _pulse!.time > _pulse!.length) _pulse = null;
    if (_warp != null && clock - _warp!.time > _warp!.length) _warp = null;
    final now = active;
    if (now || _wasActive) notifyListeners();
    _wasActive = now;
  }

  // ------------------------------------------------------------- impacts
  /// A hit at [at] (global pixels), [strength] about 1 for a big one.
  void impact(Offset at, {double strength = 1}) {
    _impacts.add(_Impact(at, _clock, strength));
    notifyListeners();
  }

  /// How far, and how much tilted, a widget centered at [center] is shaken
  /// right now. [seed] varies the phase between neighbors so they move
  /// independently.
  (Offset, double) shakeAt(Offset center, {double seed = 0}) {
    var offset = Offset.zero;
    var tilt = 0.0;
    for (final i in _impacts) {
      final d = (center - i.at).distance;
      final tau = _clock - i.time - d / 950;
      if (tau <= 0) continue;
      final amp = i.strength * 22 / (1 + d / 260);
      final dir = d < 1 ? const Offset(0, 1) : (center - i.at) / d;
      final w = 24 + 5 * math.sin(seed * 12.9898);
      final decay = math.exp(-tau * 5.5);
      final s = math.sin(tau * w + seed);
      // Pushed away from the hit, bouncing back, with a little sideways
      // wobble and a tip.
      offset += dir * (amp * decay * s) + Offset(0, amp * 0.35 * decay * math.sin(tau * w * 1.3 + seed * 3));
      tilt += amp * 0.004 * decay * math.sin(tau * w * 0.9 + seed * 7) * (dir.dx >= 0 ? 1 : -1);
    }
    return (offset, tilt);
  }

  /// The squash of the widget a hit landed right on: 1 at rest, less while
  /// it gives under the impact.
  double squashAt(Rect rect) {
    var squash = 1.0;
    for (final i in _impacts) {
      if (!rect.inflate(30).contains(i.at)) continue;
      final tau = _clock - i.time;
      if (tau < 0) continue;
      squash -= i.strength * 0.08 * math.exp(-tau * 7) * math.cos(tau * 26);
    }
    return squash;
  }

  // ------------------------------------------------------------- pulse
  /// A ring of light spreading from [at] (global pixels).
  void pulse(Offset at, {Color color = const Color(0xFFFFC874), double speed = 820}) {
    _pulse = _Pulse(at, _clock, color, speed);
    notifyListeners();
  }

  /// How lit a widget at [rect] is by the passing pulse, 0 to 1, and how far
  /// round its border the glint has run (0 to 1).
  (double, double, Color) pulseAt(Rect rect) {
    final p = _pulse;
    if (p == null) return (0, 0, const Color(0x00000000));
    final reach = (_clock - p.time) * p.speed;
    // Lit from when the ring first touches the rect until it has passed it.
    final near = _distanceToRect(p.at, rect);
    final far = [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight].map((c) => (c - p.at).distance).reduce(math.max);
    final u = ((reach - near) / math.max(far - near + 260, 1)).clamp(0.0, 1.0);
    final on = reach < near ? 0.0 : math.sin(u * math.pi);
    return (on, u, p.color);
  }

  /// The pulse's ring for an overlay to draw: center, radius, color, and
  /// strength; null when none is running.
  (Offset, double, Color, double)? get pulseRing {
    final p = _pulse;
    if (p == null) return null;
    final t = _clock - p.time;
    return (p.at, t * p.speed, p.color, (1 - t / p.length).clamp(0.0, 1.0));
  }

  static double _distanceToRect(Offset p, Rect r) {
    final dx = math.max(math.max(r.left - p.dx, 0.0), p.dx - r.right);
    final dy = math.max(math.max(r.top - p.dy, 0.0), p.dy - r.bottom);
    return math.sqrt(dx * dx + dy * dy);
  }

  // ------------------------------------------------------------- warp
  /// A water ripple across the screen from [at]: several crests rolling out.
  void ripple(Offset at, {double strength = 1}) {
    _warp = _Warp(at, _clock, speed: 900, width: 150, amp: 16 * strength, waves: 3, tint: 0.15, length: 1.6);
    notifyListeners();
  }

  /// A single soft crest of heat haze, riding a pulse.
  void haze(Offset at, {double speed = 820}) {
    _warp = _Warp(at, _clock, speed: speed, width: 70, amp: 7, waves: 1, tint: 0.35, length: 1.5);
    notifyListeners();
  }

  /// The warp's shader uniforms right now, or null.
  ({Offset center, double radius, double width, double amp, double waves, double tint})? get warp {
    final w = _warp;
    if (w == null) return null;
    final t = _clock - w.time;
    final fade = math.pow(1 - (t / w.length).clamp(0.0, 1.0), 1.5).toDouble();
    return (center: w.at, radius: t * w.speed, width: w.width + t * 60, amp: w.amp * fade, waves: w.waves, tint: w.tint * fade);
  }
}

class _Impact {
  _Impact(this.at, this.time, this.strength);
  final Offset at;
  final double time;
  final double strength;
}

class _Pulse {
  _Pulse(this.at, this.time, this.color, this.speed);
  final Offset at;
  final double time;
  final Color color;
  final double speed;
  double get length => 2.2;
}

class _Warp {
  _Warp(this.at, this.time, {required this.speed, required this.width, required this.amp, required this.waves, required this.tint, required this.length});
  final Offset at;
  final double time;
  final double speed, width, amp, waves, tint, length;
}

/// Shakes its child with every [ScreenFx] impact, on its own spring.
///
/// Reads where it is on screen while painting (where layout is always
/// settled), and repaints, without rebuilding, as the effects play.
class Wobble extends SingleChildRenderObjectWidget {
  const Wobble({super.key, required this.fx, required super.child, this.seed = 0, this.amount = 1});

  final ScreenFx fx;

  /// Varies the phase, so neighbors move independently.
  final double seed;

  /// Scales how much this one moves.
  final double amount;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWobble(fx, seed, amount);

  @override
  void updateRenderObject(BuildContext context, _RenderWobble renderObject) {
    renderObject
      ..fx = fx
      ..seed = seed
      ..amount = amount;
  }
}

/// Repaints a render object whenever a [ScreenFx] ticks.
mixin _Follows on RenderObject {
  ScreenFx? _fx;
  ScreenFx get fx => _fx!;
  set fx(ScreenFx value) {
    if (value == _fx) return;
    if (attached) _fx?.removeListener(markNeedsPaint);
    _fx = value;
    if (attached) value.addListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _fx?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _fx?.removeListener(markNeedsPaint);
    super.detach();
  }
}

class _RenderWobble extends RenderProxyBox with _Follows {
  _RenderWobble(ScreenFx fx, this.seed, this.amount) {
    this.fx = fx;
  }

  double seed;
  double amount;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (fx._impacts.isEmpty || child == null) {
      super.paint(context, offset);
      return;
    }
    final rect = localToGlobal(Offset.zero) & size;
    final (shake, tilt) = fx.shakeAt(rect.center, seed: seed);
    final squash = fx.squashAt(rect);
    final c = size.center(Offset.zero);
    final m = Matrix4.translationValues(c.dx + shake.dx * amount, c.dy + shake.dy * amount, 0)
      ..rotateZ(tilt * amount)
      ..scaleByDouble(2 - squash, squash, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
    context.pushTransform(needsCompositing, offset, m, super.paint);
  }
}

/// Lights a card's outline as a [ScreenFx] pulse passes over it: a warm
/// glow round the border, a glint running along it, and a small lift.
class PulseGlow extends SingleChildRenderObjectWidget {
  const PulseGlow({super.key, required this.fx, required super.child, this.radius = 18});

  final ScreenFx fx;
  final double radius;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPulseGlow(fx, radius);

  @override
  void updateRenderObject(BuildContext context, _RenderPulseGlow renderObject) {
    renderObject
      ..fx = fx
      ..radius = radius;
  }
}

class _RenderPulseGlow extends RenderProxyBox with _Follows {
  _RenderPulseGlow(ScreenFx fx, this.radius) {
    this.fx = fx;
  }

  double radius;

  @override
  void paint(PaintingContext context, Offset offset) {
    final pulse = fx._pulse;
    if (pulse == null || child == null) {
      super.paint(context, offset);
      return;
    }
    final rect = localToGlobal(Offset.zero) & size;
    final (on, run, color) = fx.pulseAt(rect);
    if (on <= 0.001) {
      super.paint(context, offset);
      return;
    }
    final from = pulse.at - rect.center;
    final lifted = offset + Offset(0, -3 * on);
    super.paint(context, lifted);
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(lifted.dx, lifted.dy);
    _GlowBorder(on, run, color, radius, math.atan2(from.dy, from.dx)).paint(canvas, size);
    canvas.restore();
  }
}

class _GlowBorder extends CustomPainter {
  _GlowBorder(this.on, this.run, this.color, this.radius, this.from);
  final double on, run, radius, from;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.drawRRect(rr, Paint()..color = color.withValues(alpha: 0.06 * on));
    canvas.drawRRect(
      rr.inflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = color.withValues(alpha: 0.28 * on)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    // Two glints, starting on the side the light came from and running
    // round the border in opposite directions.
    final start = from;
    final sweep = run * math.pi;
    final shader = SweepGradient(
      center: Alignment.center,
      startAngle: 0,
      endAngle: math.pi * 2,
      transform: GradientRotation(start),
      colors: [
        Colors.transparent,
        color.withValues(alpha: on),
        Colors.transparent,
        Colors.transparent,
        color.withValues(alpha: on),
        Colors.transparent,
      ],
      stops: [
        0,
        (sweep / (math.pi * 2)).clamp(0.0, 0.49),
        (sweep / (math.pi * 2) + 0.08).clamp(0.0, 0.5),
        (1 - sweep / (math.pi * 2) - 0.08).clamp(0.5, 1.0),
        (1 - sweep / (math.pi * 2)).clamp(0.51, 1.0),
        1,
      ],
    ).createShader(Offset.zero & size);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_GlowBorder old) => true;
}

/// Bends everything under it with the [ScreenFx] warp, through a fragment
/// shader; passes the child straight through when no warp is running.
class WarpLayer extends StatefulWidget {
  const WarpLayer({super.key, required this.fx, required this.child});

  final ScreenFx fx;
  final Widget child;

  @override
  State<WarpLayer> createState() => _WarpLayerState();
}

class _WarpLayerState extends State<WarpLayer> {
  static Future<ui.FragmentProgram>? _program;
  ui.FragmentShader? _shader;
  static final _identity = ui.ImageFilter.matrix(Matrix4.identity().storage);

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) {
      (_program ??= ui.FragmentProgram.fromAsset('shaders/screen_warp.frag')).then((p) {
        if (mounted) setState(() => _shader = p.fragmentShader());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.fx,
      child: widget.child,
      builder: (context, child) {
        final w = widget.fx.warp;
        final shader = _shader;
        ui.ImageFilter filter = _identity;
        if (w != null && shader != null) {
          // The first vec2 (the size) is filled in by the engine.
          shader
            ..setFloat(2, w.center.dx)
            ..setFloat(3, w.center.dy)
            ..setFloat(4, w.radius)
            ..setFloat(5, w.width)
            ..setFloat(6, w.amp)
            ..setFloat(7, w.waves)
            ..setFloat(8, w.tint);
          filter = ui.ImageFilter.shader(shader);
        }
        // The same widget either way, so the app beneath never remounts.
        return ImageFiltered(imageFilter: filter, enabled: w != null && shader != null, child: child);
      },
    );
  }
}
