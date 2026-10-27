import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/animation.dart';

/// Lumi's trip out of the header to fetch the reward key.
///
/// Everything here is in global screen pixels, re-evaluated every frame from
/// the card's live position, so the list can scroll while Lumi is out and
/// Lumi stays with the card. The park screen turns each [ErrandFrame] into a
/// place in the 3D overlay.
///
/// The beats: wind up in the header, hop out and dive behind the reward
/// card, wait out of sight, peek over its top edge and look around, hop up
/// onto the card, press Collect, catch the key, and carry it home.
/// A trip out of the header into the full-screen layer over the app.
abstract class Outing {
  Outing({required this.home, required this.headPx, required this.footPx, required this.outScale});

  /// Where the friend's head sits in the header, and where it comes back to.
  final Offset home;

  /// Head radius and the head-to-feet distance at full size, in pixels.
  final double headPx;
  final double footPx;

  /// How small the friend gets out in the app.
  final double outScale;

  double time = 0;

  bool get done;

  /// Whether the friend is in the overlay rather than the header.
  bool get out;

  /// Whether it is in the air (for trails).
  bool get flying;

  /// Advances the outing. [card] is the widget it is visiting, [button] a
  /// control on it; [atEnd] and [moving] describe the list for a ride.
  ErrandFrame update(double dt, {required Rect card, required Rect button, bool atEnd = false, bool moving = false});

  static Offset bezier(Offset a, Offset c, Offset b, double t) {
    final ab = Offset.lerp(a, c, t)!;
    final cb = Offset.lerp(c, b, t)!;
    return Offset.lerp(ab, cb, t)!;
  }
}

class FetchErrand extends Outing {
  FetchErrand({required super.home, required super.headPx, required super.footPx, super.outScale = 0.5});

  // Beat times, in seconds.
  static const handOff = 0.45;
  static const _diveEnd = 1.5;
  static const _peekStart = 1.9;
  static const _peekEnd = 2.4;
  static const _lookSwap = 3.0;
  static const _hopStart = 3.6;
  static const _hopEnd = 4.3;
  static const _reachStart = 4.6;
  static const pressAt = 5.0;
  static const keyAt = 5.3;
  static const _reachEnd = 5.35;
  static const _keyCaught = 5.6;
  static const _homeStart = 5.7;
  static const length = 6.9;

  @override
  bool get done => time >= length;

  /// Whether Lumi is in the air: diving, hopping onto the card, or flying home.
  @override
  bool get flying => (time >= handOff && time < _diveEnd) || (time >= _hopStart && time < _hopEnd) || time >= _homeStart;

  /// Whether Lumi is in the overlay rather than the header.
  @override
  bool get out => time >= handOff && !done;

  @override
  ErrandFrame update(double dt, {required Rect card, required Rect button, bool atEnd = false, bool moving = false}) {
    final before = time;
    time += dt;
    bool crossed(double at) => before < at && time >= at;

    final s = outScale;
    final r = headPx * s;
    final behind = Offset(card.left + card.width * 0.3, card.top + r * 1.8 + footPx * s * 0.2);
    final peek = Offset(behind.dx, card.top - r * 0.3);
    final perch = Offset(button.center.dx - r * 2.3, card.top - footPx * s);

    Offset head;
    var scale = s;
    var hidden = false;
    Offset? look;
    Offset? reach;
    var carrying = false;
    double? keyFlight;
    String? face;
    var jolt = 0.0;

    double span(double a, double b) => ((time - a) / (b - a)).clamp(0.0, 1.0);

    if (time < handOff) {
      head = home;
      scale = 1;
      look = card.center;
      if (crossed(0.1)) jolt = 0.6;
    } else if (time < _diveEnd) {
      // Out of the header in an arc that rises first, then swoops down
      // behind the card, shrinking on the way.
      final t = Curves.easeInOutCubic.transform(span(handOff, _diveEnd));
      final control = Offset(home.dx + (behind.dx - home.dx) * 0.35, home.dy - 70);
      head = _bezier(home, control, behind, t);
      scale = 1 + (s - 1) * Curves.easeInOut.transform(span(handOff, _diveEnd - 0.2));
      hidden = true;
      look = behind;
    } else if (time < _peekStart) {
      head = behind;
      hidden = true;
    } else if (time < _peekEnd) {
      head = Offset.lerp(behind, peek, Curves.easeOutBack.transform(span(_peekStart, _peekEnd)))!;
      hidden = true;
      if (crossed(_peekStart + 0.25)) face = 'curious';
    } else if (time < _hopStart) {
      head = peek + Offset(0, math.sin((time - _peekEnd) * 7) * 1.5);
      hidden = true;
      look = time < _lookSwap ? peek + const Offset(-160, -20) : peek + const Offset(160, 30);
    } else if (time < _hopEnd) {
      final t = span(_hopStart, _hopEnd);
      final e = Curves.easeInOut.transform(t);
      head = Offset.lerp(peek, perch, e)! - Offset(0, 4 * 70 * t * (1 - t));
      // Behind the card on the way up, in front of it once over the edge.
      hidden = t < 0.45;
      look = button.center;
      if (crossed(_hopStart)) jolt = 0.4;
    } else if (time < _homeStart) {
      head = perch;
      look = button.center;
      if (crossed(_hopEnd)) jolt = 0.7;
      if (time >= _reachStart && time < _reachEnd) reach = button.center;
      if (crossed(pressAt)) face = 'delighted';
      if (time >= keyAt) keyFlight = span(keyAt, _keyCaught);
      carrying = time >= _keyCaught;
    } else {
      // Home again with the key, growing back to full size.
      final t = Curves.easeInOutCubic.transform(span(_homeStart, length));
      final control = Offset(perch.dx + (home.dx - perch.dx) * 0.5, math.min(perch.dy, home.dy) - 90);
      head = _bezier(perch, control, home, t);
      scale = s + (1 - s) * Curves.easeInOut.transform(span(_homeStart + 0.2, length));
      carrying = true;
      if (crossed(_homeStart)) jolt = 0.4;
    }
    return ErrandFrame(
      head: head,
      scale: scale,
      hidden: hidden,
      look: look,
      reach: reach,
      pressing: time >= pressAt && time < keyAt + 0.05,
      pressNow: crossed(pressAt),
      keyFlight: keyFlight,
      carrying: carrying,
      face: face,
      jolt: jolt,
      handOffNow: crossed(handOff),
    );
  }

  static Offset _bezier(Offset a, Offset c, Offset b, double t) => Outing.bezier(a, c, b, t);
}

/// A surprise visit: the friend hides behind a card in the list, pops up
/// over its edge, waves, ducks back down, and flies home.
class PeekVisit extends Outing {
  PeekVisit({required super.home, required super.headPx, required super.footPx, super.outScale = 0.45});

  static const handOff = 0.4;
  static const _diveEnd = 1.35;
  static const _rise = 1.75;
  static const _waveEnd = 3.6;
  static const _duck = 3.95;
  static const length = 5.0;

  @override
  bool get done => time >= length;
  @override
  bool get out => time >= handOff && !done;
  @override
  bool get flying => (time >= handOff && time < _diveEnd) || time >= _duck;

  @override
  ErrandFrame update(double dt, {required Rect card, required Rect button, bool atEnd = false, bool moving = false}) {
    final before = time;
    time += dt;
    bool crossed(double at) => before < at && time >= at;
    double span(double a, double b) => ((time - a) / (b - a)).clamp(0.0, 1.0);
    final s = outScale;
    final r = headPx * s;
    final behind = Offset(card.left + card.width * 0.72, card.top + r * 2.2 + footPx * s * 0.25);
    final peek = Offset(behind.dx, card.top - r * 0.55);
    Offset head;
    var scale = s;
    var hidden = false;
    Offset? look;
    Offset? reach;
    String? face;
    var jolt = 0.0;
    if (time < handOff) {
      head = home;
      scale = 1;
      look = card.center;
      if (crossed(0.08)) jolt = 0.5;
    } else if (time < _diveEnd) {
      final t = Curves.easeInOutCubic.transform(span(handOff, _diveEnd));
      head = Outing.bezier(home, Offset(home.dx + (behind.dx - home.dx) * 0.4, home.dy - 60), behind, t);
      scale = 1 + (s - 1) * Curves.easeInOut.transform(span(handOff, _diveEnd - 0.2));
      hidden = true;
    } else if (time < _rise) {
      head = Offset.lerp(behind, peek, Curves.easeOutBack.transform(span(_diveEnd, _rise)))!;
      hidden = true;
      if (crossed(_diveEnd + 0.2)) face = 'delighted';
    } else if (time < _waveEnd) {
      // Hello! A wave from over the edge of the card.
      head = peek + Offset(0, math.sin((time - _rise) * 6) * 1.5);
      hidden = true;
      final w = math.sin((time - _rise) * 9);
      reach = head + Offset(r * (1.4 + 0.5 * w), -r * (0.9 + 0.3 * w.abs()));
      if (crossed(_rise + 0.05)) jolt = 0.4;
    } else if (time < _duck) {
      head = Offset.lerp(peek, behind, Curves.easeIn.transform(span(_waveEnd, _duck)))!;
      hidden = true;
    } else {
      // Up from behind the card and home.
      final t = Curves.easeInOutCubic.transform(span(_duck, length));
      head = Outing.bezier(behind, Offset(behind.dx, card.top - r * 4), home, t);
      scale = s + (1 - s) * Curves.easeInOut.transform(span(_duck + 0.25, length));
      // Stay clipped by the card until the feet have cleared its top edge,
      // or the lower half pops out in front of it.
      hidden = head.dy + (footPx + 16) * scale > card.top;
      if (crossed(_duck)) jolt = 0.4;
    }
    return ErrandFrame(
      head: head,
      scale: scale,
      hidden: hidden,
      look: look,
      reach: reach,
      pressing: false,
      pressNow: false,
      keyFlight: null,
      carrying: false,
      face: face,
      jolt: jolt,
      handOffNow: crossed(handOff),
    );
  }
}

/// A ride on the scrollbar: the friend hops onto the thumb and sits on it as
/// the list scrolls, gets dizzy if it reaches the bottom, and floats home when
/// the scrolling stops.
class ScrollRide extends Outing {
  ScrollRide({required super.home, required super.headPx, required super.footPx, super.outScale = 0.38});

  static const handOff = 0.35;
  static const _board = 1.0;
  double? _leaving;
  double _still = 0;
  double? _dizzyAt;
  Offset _seat = Offset.zero;

  double get _length => (_leaving ?? 1e9) + 0.9;

  @override
  bool get done => time >= _length;
  @override
  bool get out => time >= handOff && !done;
  @override
  bool get flying => (time >= handOff && time < _board) || (_leaving != null && time >= _leaving!);

  @override
  ErrandFrame update(double dt, {required Rect card, required Rect button, bool atEnd = false, bool moving = false}) {
    final before = time;
    time += dt;
    bool crossed(double at) => before < at && time >= at;
    double span(double a, double b) => ((time - a) / (b - a)).clamp(0.0, 1.0);
    final s = outScale;
    final r = headPx * s;
    // Sitting on the thumb: feet on its top, leaning on it from the left.
    final seat = Offset(card.left - r * 0.9, card.top - footPx * s * 0.85);
    String? face;
    var jolt = 0.0;
    Offset head;
    var scale = s;
    Offset? look;
    if (time < handOff) {
      head = home;
      scale = 1;
      look = card.center;
      if (crossed(0.08)) jolt = 0.5;
    } else if (time < _board) {
      final t = Curves.easeInOutCubic.transform(span(handOff, _board));
      head = Outing.bezier(home, Offset((home.dx + seat.dx) / 2, math.min(home.dy, seat.dy) - 80), seat, t);
      scale = 1 + (s - 1) * Curves.easeInOut.transform(span(handOff, _board));
      if (crossed(_board - 0.02)) jolt = 0.6;
    } else if (_leaving == null) {
      head = seat + Offset(0, math.sin(time * 5) * 1.2);
      _seat = seat;
      _still = moving ? 0 : _still + dt;
      if (atEnd && _dizzyAt == null) {
        _dizzyAt = time;
        face = 'dizzy';
        jolt = 1.0;
      }
      if (_dizzyAt != null && time - _dizzyAt! > 1.4 || _still > 1.3) _leaving = time;
      look = _dizzyAt == null ? Offset(seat.dx - 40, seat.dy + 120) : null;
    } else {
      final t = Curves.easeInOutCubic.transform(span(_leaving!, _length));
      head = Outing.bezier(_seat, Offset((_seat.dx + home.dx) / 2, math.min(_seat.dy, home.dy) - 90), home, t);
      scale = s + (1 - s) * Curves.easeInOut.transform(t);
      if (crossed(_leaving!)) jolt = 0.4;
    }
    return ErrandFrame(
      head: head,
      scale: scale,
      hidden: false,
      look: look,
      reach: null,
      pressing: false,
      pressNow: false,
      keyFlight: null,
      carrying: false,
      face: face,
      jolt: jolt,
      handOffNow: crossed(handOff),
    );
  }
}

/// Where Lumi is and what it is doing on one frame of a [FetchErrand].
class ErrandFrame {
  const ErrandFrame({
    required this.head,
    required this.scale,
    required this.hidden,
    required this.look,
    required this.reach,
    required this.pressing,
    required this.pressNow,
    required this.keyFlight,
    required this.carrying,
    required this.face,
    required this.jolt,
    required this.handOffNow,
    this.roll = 0,
    this.impact = 0,
    this.tug = Offset.zero,
    this.spark,
    this.flail = 0,
  });

  /// Global position of the head's center (before any bob).
  final Offset head;
  final double scale;

  /// Whether Lumi is behind the card (the overlay is clipped below its top).
  final bool hidden;

  /// Global points Lumi looks at and reaches for.
  final Offset? look;
  final Offset? reach;

  /// Whether the Collect button is held down, and the frame it goes down.
  final bool pressing;
  final bool pressNow;

  /// Progress of the key's hop from the button into Lumi's hand, 0 to 1.
  final double? keyFlight;

  /// Whether the key is in Lumi's hand.
  final bool carrying;

  /// A face to flash, by name, on this frame.
  final String? face;

  /// A physical jolt to give Lumi on this frame.
  final double jolt;

  /// Whether Lumi leaves the header on this frame.
  final bool handOffNow;

  /// A tip about the head, in radians (positive is counterclockwise on
  /// screen): lying down after a fall, tumbling back after a yank.
  final double roll;

  /// A landing that shakes the whole screen, this frame, at about 1 for a
  /// big one.
  final double impact;

  /// How far the card being tugged is pulled out of place, in pixels.
  final Offset tug;

  /// A glowing spark to draw, in global coordinates (one the friend chases).
  final Offset? spark;

  /// How hard the free hand windmills for balance, 0 to 1.
  final double flail;
}

/// A pratfall: a spark drifts down past the friend and hangs just out of
/// reach below the header. The friend leans out after it, reaching, teeters
/// with the other arm windmilling, and when the spark darts down to a card it
/// lunges and topples after it, landing face-first with a thud that shakes
/// everything on screen. It lies there a moment, picks itself up dizzy, and
/// floats home.
class Pratfall extends Outing {
  Pratfall({required super.home, required super.headPx, required super.footPx, super.outScale = 0.62});

  static const handOff = 0.7, _dart = 1.95, _land = 2.7, _getUp = 3.45, _up = 4.0, length = 4.95;

  @override
  bool get done => time >= length;
  @override
  bool get out => time >= handOff && !done;
  @override
  bool get flying => (time >= _dart && time < _land) || time >= _up;

  // Where the fall starts from, caught on the frame the friend lets go.
  Offset? _letGo;
  double _letGoRoll = 0;

  @override
  ErrandFrame update(double dt, {required Rect card, required Rect button, bool atEnd = false, bool moving = false}) {
    final before = time;
    time += dt;
    bool crossed(double at) => before < at && time >= at;
    double span(double a, double b) => ((time - a) / (b - a)).clamp(0.0, 1.0);
    final s = outScale;
    final r = headPx * s;
    // Lying on its side along the card's top edge.
    final lie = Offset(card.left + card.width * 0.42, card.top + math.min(card.height * 0.32, r * 1.1));
    const flat = -1.45;
    // Where the spark hangs: below and to the right, just past a reach.
    final dangle = home + Offset(headPx * 1.9, footPx + headPx * 1.2);
    Offset head = home;
    var scale = s;
    var roll = 0.0;
    var impact = 0.0;
    var jolt = 0.0;
    var flail = 0.0;
    String? face;
    Offset? look;
    Offset? reach;
    Offset? spark;

    // Tipped by [lean] about the feet (which stay put), so the head swings.
    Offset leanAt(double lean) => home + Offset(-footPx * math.sin(lean), footPx * (1 - math.cos(lean)));

    if (time < handOff) {
      // The spark drifts down past the face; the friend watches it go.
      final u = Curves.easeInOutSine.transform(span(0, handOff));
      spark = Outing.bezier(home + Offset(-headPx * 1.6, -headPx * 1.8), home + Offset(headPx * 2.6, -headPx * 0.2), dangle, u);
      scale = 1;
      look = spark;
      if (crossed(0.05)) face = 'curious';
    } else if (time < _dart) {
      // Leaning out after it, reaching; the lean grows into a teeter.
      final k = time - handOff;
      final grow = Curves.easeIn.transform(span(handOff, _dart));
      spark = dangle + Offset(math.sin(k * 3.1) * headPx * 0.35, math.cos(k * 2.3) * headPx * 0.25);
      final lean = -0.5 * Curves.easeInOut.transform(span(handOff, handOff + 0.55)) - math.sin(k * 10) * 0.16 * grow;
      head = leanAt(lean);
      roll = lean;
      scale = 1;
      look = spark;
      reach = spark;
      flail = Curves.easeOut.transform(span(handOff + 0.35, handOff + 0.7));
      if (crossed(_dart - 0.35)) face = 'surprised';
      _letGo = head;
      _letGoRoll = roll;
    } else if (time < _land) {
      // The spark darts down to the card and the friend lunges after it,
      // tumbling.
      final from = _letGo ?? home;
      final t = Curves.easeIn.transform(span(_dart, _land));
      head = Outing.bezier(from, Offset(from.dx + (lie.dx - from.dx) * 0.4, from.dy - 50), lie, t);
      scale = 1 + (s - 1) * Curves.easeOut.transform(span(_dart, _land - 0.3));
      roll = _letGoRoll + (flat - math.pi * 2 - _letGoRoll) * Curves.easeInOut.transform(span(_dart, _land));
      final d = Curves.easeOutCubic.transform(span(_dart, _dart + 0.3));
      spark = Offset.lerp(dangle, lie + Offset(r * 0.6, -r * 1.6), d);
      flail = 1 - span(_dart, _dart + 0.3);
      look = spark;
      if (crossed(_dart)) face = 'surprised';
    } else if (time < _getUp) {
      // Splat. A little bounce, then flat out; the spark gets away.
      final k = time - _land;
      head = lie + Offset(0, -math.max(0.0, math.sin(k * 14)) * 9 * math.exp(-k * 6));
      roll = flat + math.sin(k * 16) * 0.06 * math.exp(-k * 5);
      if (k < 0.45) spark = lie + Offset(r * 0.6 + k * r * 3, -r * 1.6 - k * r * 5);
      if (crossed(_land)) {
        impact = 1.1;
        jolt = 1.0;
        face = 'poked';
      }
      if (crossed(_land + 0.55)) face = 'dizzy';
    } else if (time < _up) {
      // Picking itself up, upright again, still woozy.
      final u = Curves.easeInOutBack.transform(span(_getUp, _up));
      head = lie + Offset(0, -r * 0.45 * u);
      roll = flat * (1 - u);
      if (crossed(_getUp + 0.1)) jolt = 0.4;
    } else {
      final t = Curves.easeInOutCubic.transform(span(_up, length));
      final from = lie + Offset(0, -r * 0.45);
      head = Outing.bezier(from, Offset(from.dx, from.dy - 160), home, t);
      scale = s + (1 - s) * Curves.easeInOut.transform(span(_up + 0.2, length));
      roll = math.sin(time * 9) * 0.08 * (1 - t);
    }
    return ErrandFrame(
      head: head,
      scale: scale,
      hidden: false,
      look: look,
      reach: reach,
      pressing: false,
      pressNow: false,
      keyFlight: null,
      carrying: false,
      face: face,
      jolt: jolt,
      handOffNow: crossed(handOff),
      roll: roll,
      impact: impact,
      spark: spark,
      flail: flail,
    );
  }
}

/// The start of card Jenga: the friend flies to the side of a card, grabs
/// its edge, tugs it three times, and yanks it clean out of the list,
/// tumbling backward with the effort, then floats home.
class TugVisit extends Outing {
  TugVisit({required super.home, required super.headPx, required super.footPx, super.outScale = 0.5});

  static const handOff = 0.3, _arrive = 0.95, yank = 1.95, length = 3.2;

  @override
  bool get done => time >= length;
  @override
  bool get out => time >= handOff && !done;
  @override
  bool get flying => (time >= handOff && time < _arrive) || time >= yank;

  @override
  ErrandFrame update(double dt, {required Rect card, required Rect button, bool atEnd = false, bool moving = false}) {
    final before = time;
    time += dt;
    bool crossed(double at) => before < at && time >= at;
    double span(double a, double b) => ((time - a) / (b - a)).clamp(0.0, 1.0);
    final s = outScale;
    final r = headPx * s;
    // In front of the card's right end (the cards span the screen, so
    // there is no room beside it), a hand hooked over its edge.
    final at = Offset(card.right - r * 1.3, card.center.dy - r * 0.15);
    final grip = Offset(card.right - 8, card.center.dy + r * 0.2);
    Offset head;
    var scale = s;
    var roll = 0.0;
    var tug = Offset.zero;
    var jolt = 0.0;
    String? face;
    Offset? reach;
    Offset? look;
    if (time < handOff) {
      head = home;
      scale = 1;
      look = card.centerRight;
    } else if (time < _arrive) {
      final t = Curves.easeInOutCubic.transform(span(handOff, _arrive));
      head = Outing.bezier(home, Offset(at.dx + 40, home.dy + 40), at, t);
      scale = 1 + (s - 1) * Curves.easeInOut.transform(span(handOff, _arrive - 0.2));
      if (time > _arrive - 0.3) reach = grip;
    } else if (time < yank) {
      // Three tugs, each harder: lean back, the card follows a little, and
      // springs back.
      final k = time - _arrive;
      final pull = math.max(0.0, math.sin(k / (yank - _arrive) * math.pi * 3));
      final strength = 0.4 + 0.6 * span(_arrive, yank);
      tug = Offset(pull * 16 * strength, 0);
      head = at + Offset(pull * 14 * strength, 0);
      roll = -pull * 0.25 * strength;
      reach = grip + tug;
      look = grip;
      for (final f in const [0.15, 0.48, 0.81]) {
        final c = _arrive + (yank - _arrive) * f;
        if (crossed(c)) {
          jolt = 0.35;
          face = 'poked';
        }
      }
    } else {
      // Yanked out; the friend tumbles back, then floats home.
      final k = time - yank;
      final flip = Curves.easeOut.transform(span(yank, yank + 0.6));
      final back = at + Offset(-60 * flip, -50 * flip);
      final t = Curves.easeInOutCubic.transform(span(yank + 0.55, length));
      head = Outing.bezier(back, Offset(back.dx, home.dy), home, t);
      scale = s + (1 - s) * Curves.easeInOut.transform(span(yank + 0.8, length));
      roll = math.pi * 2 * flip;
      if (crossed(yank)) {
        jolt = 0.9;
        face = 'surprised';
      }
      if (k > 0.7) look = card.center;
    }
    return ErrandFrame(
      head: head,
      scale: scale,
      hidden: false,
      look: look,
      reach: reach,
      pressing: false,
      pressNow: false,
      keyFlight: null,
      carrying: false,
      face: face,
      jolt: jolt,
      handOffNow: crossed(handOff),
      roll: roll,
      tug: tug,
    );
  }
}
