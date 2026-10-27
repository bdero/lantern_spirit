import 'dart:math' as math;
import 'dart:ui';

/// Decides what Lumi looks at, moment to moment.
///
/// Anything on screen can be a target: cards, a coin in flight, the finger,
/// a button just tapped. Each frame the screen reports where its targets are
/// (in the header's coordinates), and new or fast-moving ones score high for
/// a moment. Lumi looks at the best one, sticks with it for a while, gets
/// bored after a couple of seconds, and drifts back to the person holding
/// the phone. Small jitters keep the eyes alive while it stares.
class Attention {
  final Map<Object, _Target> _targets = {};
  final _rng = math.Random(3);

  Object? _focus;
  double _focusTime = 0;
  Offset _jitter = Offset.zero;
  double _jitterTimer = 0;
  bool _shifted = false;

  /// How strongly Lumi wants to look back at the guest when nothing else is
  /// interesting.
  double viewerWeight = 0.55;

  /// The point Lumi should look at (header coordinates), or null to look at
  /// the guest.
  Offset? gaze;

  /// What it is looking at, for the creative panel.
  String get focusLabel => _focus?.toString() ?? 'you';

  /// Reports a target that persists on screen; call every frame it is visible.
  void report(Object id, Offset position, {double weight = 0.35}) {
    final t = _targets[id];
    if (t == null) {
      _targets[id] = _Target(position, weight);
      return;
    }
    t.velocity = Offset.lerp(t.velocity, (position - t.position) * 60, 0.3)!;
    t.position = position;
    t.weight = weight;
    t.seen = 0;
  }

  /// Something new just happened at [position]: it wins attention briefly.
  void ping(Object id, Offset position, {double weight = 1.4}) {
    _targets[id] = _Target(position, weight)..age = 0;
  }

  /// Whether the gaze jumped far this frame (a good moment to blink).
  bool takeShift() {
    final s = _shifted;
    _shifted = false;
    return s;
  }

  void update(double dt) {
    _targets.removeWhere((_, t) => (t.seen += dt) > 0.25 && t.age > 1.5);
    for (final t in _targets.values) {
      t.age += dt;
    }
    _focusTime += dt;

    Object? best;
    var bestScore = viewerWeight;
    _targets.forEach((id, t) {
      final novelty = 1.8 * math.exp(-t.age / 1.0);
      final motion = math.min(1.0, t.velocity.distance / 600) * 0.9;
      var score = t.weight * (0.25 + novelty) + motion;
      if (id == _focus) {
        // Stick with what it is looking at, until it gets boring.
        score *= _focusTime < 2.0 ? 1.25 : 0.3;
      }
      if (score > bestScore) {
        bestScore = score;
        best = id;
      }
    });
    if (best != _focus) {
      final before = gaze;
      _focus = best;
      _focusTime = 0;
      final after = best == null ? null : _targets[best]!.position;
      if (before == null || after == null || (before - after).distance > 120) _shifted = true;
    }

    // Small jitters while staring.
    _jitterTimer -= dt;
    if (_jitterTimer <= 0) {
      _jitterTimer = 0.3 + _rng.nextDouble() * 0.4;
      _jitter = Offset(_rng.nextDouble() * 12 - 6, _rng.nextDouble() * 8 - 4);
    }
    final f = _focus;
    gaze = f == null ? null : _targets[f]!.position + _jitter;
  }
}

class _Target {
  _Target(this.position, this.weight);
  Offset position;
  double weight;
  Offset velocity = Offset.zero;
  double age = 9;
  double seen = 0;
}
