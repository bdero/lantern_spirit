import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../lantern/moods.dart';
import 'fireworks.dart';

/// Linear colors for the stars.
abstract final class FwColor {
  static final gold = Vector3(1.0, 0.6, 0.2);
  static final warmWhite = Vector3(1.0, 0.86, 0.62);
  static final silver = Vector3(0.82, 0.88, 1.0);
  static final pink = Vector3(1.0, 0.32, 0.58);
  static final red = Vector3(1.0, 0.22, 0.16);
  static final blue = Vector3(0.3, 0.55, 1.0);
  static final violet = Vector3(0.62, 0.36, 1.0);
  static final green = Vector3(0.35, 1.0, 0.5);
  static final teal = Vector3(0.25, 1.0, 0.85);
}

/// A change in what Lumi is doing at a moment in the show.
class LumiBeat {
  const LumiBeat(this.time, this.mood, {this.rest});
  final double time;
  final LanternMood mood;

  /// The mood to settle into after this beat, when it is a one-shot.
  final LanternMood? rest;
}

/// The whole show as data: a one-minute program over the lagoon.
///
/// Times are seconds from the moment the card opens. The beat sheet:
///   0 to 1.2 dive through the card; 1.2 to 6 settle in, first shell climbs;
///   6 first break; 6 to 16 call and response; 16 to 24 close-up;
///   24 to 40 the build; 40 to 52 the finale; 52 to 60 afterglow;
///   60 to 64 back up into the card.
class ShowScript {
  ShowScript() {
    _program();
  }

  static const length = 64.0;
  static const firstBreak = 6.0;
  static const closeUp = 16.0;
  static const build = 24.0;
  static const finale = 40.0;
  static const afterglow = 52.0;
  static const returnAt = 60.0;

  /// Seconds per beat at 96 bpm.
  static const beat = 60 / 96;

  final List<Launch> launches = [];
  final List<LumiBeat> lumi = [];

  /// Adds a shell that breaks at [at] (show seconds).
  void _shell(
    double at,
    double x,
    double y,
    BurstKind kind,
    Vector3 color, {
    Vector3? pistil,
    double size = 1,
    double z = 160,
    double ascent = 2.1,
    double tilt = 0.3,
    bool main = false,
  }) {
    launches.add(
      Launch(
        time: at - ascent - Launch.hang,
        pad: Vector3(x * 0.85, 0, z - 8),
        breakAt: Vector3(x, y, z),
        kind: kind,
        color: color,
        pistil: pistil,
        size: size,
        ascent: ascent,
        ringTilt: tilt,
        main: main,
      ),
    );
  }

  void _program() {
    // First break: one big gold chrysanthemum with a white heart.
    _shell(firstBreak, -4, 72, BurstKind.chrysanthemum, FwColor.gold, pistil: FwColor.warmWhite, size: 1.25, ascent: 2.3);

    // Call and response, left and right, about every two beats... then three.
    _shell(8.1, -30, 60, BurstKind.peony, FwColor.pink, pistil: FwColor.warmWhite);
    _shell(9.6, 28, 64, BurstKind.peony, FwColor.blue, pistil: FwColor.silver);
    _shell(11.2, 0, 70, BurstKind.ring, FwColor.violet, tilt: 0.45, size: 1.1);
    _shell(12.5, -22, 56, BurstKind.chrysanthemum, FwColor.green);
    _shell(13.9, 24, 62, BurstKind.crossette, FwColor.silver);
    _shell(15.3, -34, 58, BurstKind.peony, FwColor.red);
    _shell(15.3, 34, 58, BurstKind.peony, FwColor.teal);

    // The close-up: high breaks that fall into soft focus behind Lumi.
    _shell(16.9, -6, 88, BurstKind.chrysanthemum, FwColor.gold, size: 1.2);
    _shell(18.6, 20, 80, BurstKind.peony, FwColor.pink, pistil: FwColor.violet);
    _shell(20.3, -24, 74, BurstKind.palm, FwColor.gold);
    _shell(21.9, 10, 84, BurstKind.ring, FwColor.blue, tilt: 0.2);
    _shell(23.3, -14, 78, BurstKind.peony, FwColor.violet, pistil: FwColor.warmWhite);

    // The build: the pace tightens from three beats to one and a half.
    final rng = math.Random(96);
    const kinds = [
      BurstKind.chrysanthemum,
      BurstKind.peony,
      BurstKind.ring,
      BurstKind.palm,
      BurstKind.crossette,
      BurstKind.peony,
      BurstKind.chrysanthemum,
    ];
    final colors = [FwColor.blue, FwColor.pink, FwColor.green, FwColor.gold, FwColor.violet, FwColor.teal, FwColor.red, FwColor.silver];
    var t = build + 0.4;
    var i = 0;
    while (t < finale - 0.8) {
      final progress = (t - build) / (finale - build);
      final kind = kinds[i % kinds.length];
      final side = i.isEven ? -1 : 1;
      _shell(
        t,
        side * (8 + rng.nextDouble() * 34),
        52 + rng.nextDouble() * 34,
        kind,
        colors[(i * 3) % colors.length],
        pistil: kind == BurstKind.peony ? colors[(i * 5 + 2) % colors.length] : null,
        tilt: rng.nextDouble() * 0.7,
        z: 150 + rng.nextDouble() * 25,
      );
      if (progress > 0.55 && i % 3 == 0) {
        _shell(t + beat * 0.5, -side * (6 + rng.nextDouble() * 20), 46 + rng.nextDouble() * 20, BurstKind.crackle, FwColor.silver);
      }
      t += beat * (3.0 - 1.5 * progress);
      i++;
    }

    // The finale. Gold willows open it, mains land on downbeats, a crackle
    // wall, and one enormous last break.
    _shell(finale, -34, 64, BurstKind.willow, FwColor.gold, size: 1.15, main: true);
    _shell(finale + 0.3, 30, 66, BurstKind.willow, FwColor.gold, size: 1.15, main: true);
    _shell(finale + 1.0, -4, 88, BurstKind.peony, FwColor.blue, pistil: FwColor.silver, size: 1.3, main: true);
    _shell(finale + 1.6, 12, 60, BurstKind.ring, FwColor.pink, tilt: 1.2);
    _shell(finale + 2.2, -20, 46, BurstKind.palm, FwColor.green);
    _shell(finale + 2.9, 16, 96, BurstKind.crackle, FwColor.silver, size: 1.2);
    var f = finale + 3.6;
    var k = 0;
    while (f < finale + 8.4) {
      final onBeat = k % 4 == 0;
      _shell(
        f,
        (k.isEven ? -1 : 1) * (10 + (k * 7) % 30),
        54 + (k * 13) % 34,
        onBeat ? BurstKind.chrysanthemum : const [BurstKind.peony, BurstKind.ring, BurstKind.crossette][k % 3],
        colors[(k * 3 + 1) % colors.length],
        pistil: onBeat ? FwColor.warmWhite : null,
        size: onBeat ? 1.25 : 1.0,
        tilt: (k % 5) * 0.25,
        main: onBeat,
      );
      f += beat * 0.55;
      k++;
    }
    _shell(finale + 8.6, -30, 72, BurstKind.willow, FwColor.gold, size: 1.3, main: true);
    _shell(finale + 8.75, 0, 82, BurstKind.willow, FwColor.gold, size: 1.4, main: true);
    _shell(finale + 8.9, 30, 72, BurstKind.willow, FwColor.gold, size: 1.3, main: true);
    _shell(finale + 9.6, -18, 50, BurstKind.crackle, FwColor.silver);
    _shell(finale + 9.8, 2, 56, BurstKind.crackle, FwColor.silver);
    _shell(finale + 10.0, 20, 50, BurstKind.crackle, FwColor.silver);
    _shell(finale + 10.6, -2, 92, BurstKind.chrysanthemum, FwColor.silver, pistil: FwColor.gold, size: 1.6, main: true);
    _shell(finale + 10.7, -2, 92, BurstKind.crackle, FwColor.warmWhite, size: 1.5);

    // Afterglow: one soft willow to watch drift down into the water.
    _shell(afterglow + 2.0, -10, 54, BurstKind.willow, FwColor.gold, size: 1.0);

    launches.sort((a, b) => a.time.compareTo(b.time));

    // Lumi.
    lumi.addAll(const [
      LumiBeat(0, LanternMood.watch),
      LumiBeat(firstBreak + 0.02, LanternMood.flinch, rest: LanternMood.watch),
      LumiBeat(finale + 1.05, LanternMood.cheer, rest: LanternMood.watch),
      LumiBeat(finale + 8.8, LanternMood.cheer, rest: LanternMood.watch),
      LumiBeat(finale + 10.7, LanternMood.cheer, rest: LanternMood.lean),
      LumiBeat(afterglow + 1.0, LanternMood.lean),
    ]);
  }

  /// The resting mood Lumi should be in at [t], for jumping around the show.
  LanternMood restingMoodAt(double t) {
    var mood = LanternMood.watch;
    for (final b in lumi) {
      if (b.time > t) break;
      mood = b.rest ?? b.mood;
    }
    return mood;
  }
}
