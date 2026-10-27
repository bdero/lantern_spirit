import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show HSVColor;
import 'package:vector_math/vector_math.dart';

/// Three numbers: a size, an offset, or a linear color.
typedef V3 = (double, double, double);

/// One of the friends a guest can choose to live in their app.
///
/// Every friend shares Lumi's rig and its clips (the same `<Part>Ctrl` and
/// `<Part>Fx` nodes from `assets/lantern.glb`), so every mood, reaction,
/// game, and the fireworks show work for all of them. A friend only reshapes
/// the parts under those nodes, swaps the materials and the face sheet, and
/// adds a few pieces of its own. One rig contract, many looks.
class Friend {
  const Friend({
    required this.id,
    required this.name,
    required this.kind,
    required this.blurb,
    required this.palettes,
    this.atlas = 'assets/faces/lumi.png',
    this.faceTint = 0,
    this.head = const (0.62, 0.62, 0.62),
    this.headOffset = const (0.0, 0.0, 0.0),
    this.body,
    this.bodyOffset = const (0.0, 0.0, 0.0),
    this.hand = 0.1,
    this.handOffset = const (0.0, 0.0, 0.0),
    this.foot,
    this.footOffset = const (0.0, 0.0, 0.0),
    this.neckOffset = const (0.0, 0.0, 0.0),
    this.neckScale = 1,
    this.extras = FriendExtras.none,
    this.glow = 1,
    this.ambientSparks = false,
    this.scale = 1,
    this.lift = 0,
    this.hatFit = 1,
  });

  /// The whole friend's size against Lumi's, and how far it is raised, so
  /// every friend frames the same in the header, the show, and the games.
  final double scale;
  final double lift;

  /// Hats shrink by this much and stay on top of the head (for a big head).
  final double hatFit;

  final String id;
  final String name;

  /// What kind of friend it is, as the design sheet calls it.
  final String kind;
  final String blurb;

  /// Expression sheet, a 4x3 grid in Lumi's order.
  final String atlas;

  /// 1 for a white sprite tinted with the palette's face color and glowing,
  /// 0 for a sprite shown in its own colors.
  final double faceTint;

  /// Head radii (x across, y up, z depth) and where its center sits relative
  /// to Lumi's head center.
  final V3 head;
  final V3 headOffset;

  /// Body radii, or null for no separate body (Mochi is all head).
  final V3? body;
  final V3 bodyOffset;

  /// Hand radius and offset (x is outward, mirrored for the other hand).
  final double hand;
  final V3 handOffset;

  /// Foot radii, or null for Lumi's single floating wisp instead of feet.
  final V3? foot;

  /// Where the feet sit relative to the wisp (x is outward, mirrored).
  final V3 footOffset;

  /// Where the scarf sits relative to Lumi's neck, and how much it grows.
  final V3 neckOffset;
  final double neckScale;

  final FriendExtras extras;

  /// How much light the friend gives off onto the screen around it.
  final double glow;

  /// Whether motes of light drift around it (Lumi's sparks).
  final bool ambientSparks;

  /// One look per color slot in the header (Aurora, Ember, Ghost).
  final List<FriendPalette> palettes;

  bool get isLantern => id == 'lumi';

  String get thumbnail => 'assets/ui/friend_$id.jpg';

  /// The transform that maps Lumi's head (radius 0.62 at the head socket)
  /// onto this friend's head, for the face and hats.
  /// Where hats go: the head mount, shrunk by [hatFit] toward the crown.
  Matrix4 get hatMount => Matrix4.compose(
    Vector3(headOffset.$1, headOffset.$2 + head.$2 * (1 - hatFit), headOffset.$3),
    Quaternion.identity(),
    Vector3(head.$1 / 0.62, head.$2 / 0.62, head.$3 / 0.62) * hatFit,
  );

  Matrix4 get headMount => Matrix4.compose(
    Vector3(headOffset.$1, headOffset.$2, headOffset.$3),
    Quaternion.identity(),
    Vector3(head.$1 / 0.62, head.$2 / 0.62, head.$3 / 0.62),
  );
}

enum FriendExtras { none, sprout, orbit }

/// A friend's colors for one slot. Each part is one toy material setting.
class FriendPalette {
  const FriendPalette({required this.head, required this.body, required this.hands, this.accent, this.face = (1, 1, 1)});

  final ToyLook head;
  final ToyLook body;
  final ToyLook hands;

  /// The sprout's leaves, or the ring and moon.
  final ToyLook? accent;

  /// The tint for a white face sprite.
  final V3 face;
}

/// Settings for `assets/toy.fmat`. Colors are linear.
class ToyLook {
  const ToyLook({
    required this.base,
    required this.shade,
    this.rim = (1, 1, 1),
    this.sss = 0.5,
    this.spec = 1,
    this.gloss = 120,
    this.rimAmount = 0.4,
    this.core = 0.2,
    this.film = 0,
    this.emissive = 0,
    this.coat = 0,
    this.sssColor = (1.0, 0.6, 0.45),
    this.sssEdge = 0,
    this.sparkle = 0,
    this.fuzz = 0,
  });

  final V3 base;
  final V3 shade;
  final V3 rim;
  final double sss;
  final double spec;
  final double gloss;
  final double rimAmount;
  final double core;
  final double film;
  final double emissive;

  /// Clear-coat reflection strength.
  final double coat;

  /// Glow out of thin edges, and its color.
  final V3 sssColor;
  final double sssEdge;

  /// Sugar glints (candy) and fuzz (felt).
  final double sparkle;
  final double fuzz;

  /// The same look with every hue turned [degrees] around the color wheel.
  ToyLook turned(double degrees) {
    if (degrees == 0) return this;
    return ToyLook(
      base: _turn(base, degrees),
      shade: _turn(shade, degrees),
      rim: _turn(rim, degrees),
      sss: sss,
      spec: spec,
      gloss: gloss,
      rimAmount: rimAmount,
      core: core,
      film: film,
      emissive: emissive,
      coat: coat,
      sssColor: _turn(sssColor, degrees),
      sssEdge: sssEdge,
      sparkle: sparkle,
      fuzz: fuzz,
    );
  }

  static V3 _turn(V3 c, double degrees) {
    // Turn in sRGB, where hue is perceptual, and come back to linear.
    double enc(double v) => v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
    double dec(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    final color = Color.from(alpha: 1, red: enc(c.$1.clamp(0, 1)), green: enc(c.$2.clamp(0, 1)), blue: enc(c.$3.clamp(0, 1)));
    final hsv = HSVColor.fromColor(color);
    final t = hsv.withHue((hsv.hue + degrees) % 360).toColor();
    return (dec(t.r), dec(t.g), dec(t.b));
  }
}

/// Everyone who can live in the app.
abstract final class Friends {
  /// Lumi keeps the lantern materials; its palettes are unused (the header
  /// themes drive it directly).
  static const lumi = Friend(
    id: 'lumi',
    name: 'Lumi',
    kind: 'Lantern Spirit',
    blurb: 'A glowing spirit with ember hands. Lights up the evening.',
    atlas: 'assets/face_atlas.png',
    faceTint: 1,
    ambientSparks: true,
    palettes: [],
  );

  static const _coral = ToyLook(
    base: (1.0, 0.36, 0.28),
    shade: (0.78, 0.17, 0.16),
    rim: (1.0, 0.8, 0.7),
    sss: 0.75,
    spec: 1.1,
    gloss: 320,
    rimAmount: 0.25,
    core: 0.45,
    coat: 1.0,
    sssColor: (1.0, 0.55, 0.42),
    sssEdge: 0.9,
    sparkle: 0.45,
  );
  static const _teal = ToyLook(
    base: (0.1, 0.85, 0.88),
    shade: (0.02, 0.42, 0.55),
    rim: (0.8, 1.0, 1.0),
    sss: 0.7,
    spec: 1.1,
    gloss: 320,
    rimAmount: 0.3,
    core: 0.5,
    coat: 1.0,
    sssColor: (0.5, 1.0, 0.95),
    sssEdge: 0.9,
    emissive: 0.12,
  );

  /// The Gummy Toy: glossy candy vinyl, mitten hands, a big cartoon face.
  static const juju = Friend(
    id: 'juju',
    name: 'Juju',
    kind: 'Gummy Toy',
    blurb: 'Glossy candy vinyl with mitten hands. Bouncy and loud about it.',
    atlas: 'assets/faces/juju.png',
    head: (0.64, 0.64, 0.64),
    headOffset: (0, 0.06, 0),
    body: (0.46, 0.46, 0.46),
    bodyOffset: (0, -0.04, 0),
    hand: 0.17,
    handOffset: (0.0, -0.08, -0.08),
    foot: (0.2, 0.13, 0.26),
    footOffset: (0.25, -0.4, 0.02),
    neckOffset: (0, 0.02, 0),
    neckScale: 1.75,
    glow: 0.25,
    scale: 0.9,
    lift: 0.25,
    palettes: [
      FriendPalette(head: _coral, body: _coral, hands: _teal),
      FriendPalette(
        head: ToyLook(base: (0.42, 0.12, 0.85), shade: (0.12, 0.02, 0.3), rim: (0.9, 0.7, 1.0), sss: 0.55, spec: 1.5, gloss: 260, rimAmount: 0.45, core: 0.4),
        body: ToyLook(base: (0.42, 0.12, 0.85), shade: (0.12, 0.02, 0.3), rim: (0.9, 0.7, 1.0), sss: 0.55, spec: 1.5, gloss: 260, rimAmount: 0.45, core: 0.4),
        hands: ToyLook(base: (0.45, 0.85, 0.08), shade: (0.08, 0.25, 0.02), rim: (0.9, 1.0, 0.6), spec: 1.5, gloss: 260, core: 0.3),
      ),
      FriendPalette(
        head: ToyLook(base: (0.25, 0.85, 0.6), shade: (0.02, 0.28, 0.25), rim: (0.8, 1.0, 0.9), sss: 0.55, spec: 1.5, gloss: 260, rimAmount: 0.45, core: 0.4),
        body: ToyLook(base: (0.25, 0.85, 0.6), shade: (0.02, 0.28, 0.25), rim: (0.8, 1.0, 0.9), sss: 0.55, spec: 1.5, gloss: 260, rimAmount: 0.45, core: 0.4),
        hands: ToyLook(base: (1.0, 0.35, 0.55), shade: (0.4, 0.04, 0.15), rim: (1.0, 0.8, 0.85), spec: 1.5, gloss: 260, core: 0.3),
      ),
    ],
  );

  static const _cream = ToyLook(
    base: (1.0, 0.64, 0.44),
    shade: (0.84, 0.44, 0.33),
    rim: (1.0, 0.9, 0.78),
    sss: 0.95,
    spec: 0.08,
    gloss: 14,
    rimAmount: 0.35,
    core: 0.1,
    sssColor: (1.0, 0.62, 0.45),
    sssEdge: 0.35,
    fuzz: 0.8,
  );
  static const _leaf = ToyLook(
    base: (0.36, 0.8, 0.36),
    shade: (0.12, 0.42, 0.16),
    rim: (0.85, 1.0, 0.7),
    sss: 0.8,
    spec: 0.4,
    gloss: 40,
    core: 0.25,
    sssColor: (0.7, 1.0, 0.4),
    sssEdge: 0.8,
  );

  /// The Soft Pebble: one squishy matte body, nub hands, a sprout on top.
  static const mochi = Friend(
    id: 'mochi',
    name: 'Mochi',
    kind: 'Soft Pebble',
    blurb: 'One squishy pebble with a sprout on top. Cozy, a little shy.',
    atlas: 'assets/faces/mochi.png',
    head: (0.935, 0.73, 0.85),
    headOffset: (0, -0.66, 0),
    hand: 0.14,
    handOffset: (0.36, -0.14, -0.08),
    foot: (0.15, 0.083, 0.18),
    footOffset: (0.36, -0.2, 0.1),
    neckOffset: (0, -0.5, 0),
    neckScale: 2.5,
    extras: FriendExtras.sprout,
    glow: 0.18,
    lift: 0.05,
    palettes: [
      FriendPalette(head: _cream, body: _cream, hands: _cream, accent: _leaf),
      FriendPalette(
        head: ToyLook(base: (1.0, 0.36, 0.42), shade: (0.62, 0.12, 0.2), rim: (1.0, 0.85, 0.85), sss: 0.85, spec: 0.12, gloss: 16, rimAmount: 0.55, core: 0.12),
        body: ToyLook(base: (1.0, 0.36, 0.42), shade: (0.62, 0.12, 0.2), rim: (1.0, 0.85, 0.85), sss: 0.85, spec: 0.12, gloss: 16, rimAmount: 0.55, core: 0.12),
        hands: ToyLook(base: (1.0, 0.36, 0.42), shade: (0.62, 0.12, 0.2), rim: (1.0, 0.85, 0.85), sss: 0.85, spec: 0.12, gloss: 16, rimAmount: 0.55, core: 0.12),
        accent: _leaf,
      ),
      FriendPalette(
        head: ToyLook(base: (0.55, 0.78, 0.35), shade: (0.2, 0.38, 0.14), rim: (0.92, 1.0, 0.85), sss: 0.85, spec: 0.12, gloss: 16, rimAmount: 0.55, core: 0.12),
        body: ToyLook(base: (0.55, 0.78, 0.35), shade: (0.2, 0.38, 0.14), rim: (0.92, 1.0, 0.85), sss: 0.85, spec: 0.12, gloss: 16, rimAmount: 0.55, core: 0.12),
        hands: ToyLook(base: (0.55, 0.78, 0.35), shade: (0.2, 0.38, 0.14), rim: (0.92, 1.0, 0.85), sss: 0.85, spec: 0.12, gloss: 16, rimAmount: 0.55, core: 0.12),
        accent: ToyLook(base: (0.85, 0.42, 0.62), shade: (0.4, 0.12, 0.25), sss: 0.7, spec: 0.3, gloss: 30, core: 0.2),
      ),
    ],
  );

  static const _visor = ToyLook(
    base: (0.012, 0.012, 0.03),
    shade: (0.004, 0.004, 0.012),
    rim: (0.42, 0.34, 1.0),
    sss: 0.0,
    spec: 2.2,
    gloss: 360,
    rimAmount: 1.6,
    core: 0,
  );
  static const _pearl = ToyLook(
    base: (0.9, 0.9, 0.95),
    shade: (0.42, 0.42, 0.6),
    rim: (0.85, 0.8, 1.0),
    sss: 0.35,
    spec: 1.4,
    gloss: 180,
    rimAmount: 0.35,
    core: 0.1,
    film: 0.55,
  );

  /// The Orbit Guide: floating pearl parts, a glass visor with an LED face,
  /// a halo ring, and a little moon.
  static const nova = Friend(
    id: 'nova',
    name: 'Nova',
    kind: 'Orbit Guide',
    blurb: 'Pearl parts and a glass visor with an LED face. Knows every shortcut.',
    atlas: 'assets/faces/nova.png',
    faceTint: 1,
    head: (0.56, 0.56, 0.56),
    headOffset: (0, 0.22, 0),
    body: (0.42, 0.42, 0.42),
    bodyOffset: (0, -0.04, 0),
    hand: 0.16,
    handOffset: (0.08, -0.07, -0.08),
    foot: (0.17, 0.119, 0.2125),
    footOffset: (0.27, -0.4, 0.02),
    neckOffset: (0, 0.13, 0),
    neckScale: 1.5,
    extras: FriendExtras.orbit,
    glow: 0.7,
    scale: 0.86,
    lift: 0.25,
    ambientSparks: true,
    palettes: [
      FriendPalette(
        head: _visor,
        body: _pearl,
        hands: _pearl,
        accent: ToyLook(base: (0.6, 0.35, 1.0), shade: (0.6, 0.35, 1.0), spec: 0, emissive: 3.2),
        face: (0.47, 0.94, 1.0),
      ),
      FriendPalette(
        head: ToyLook(base: (0.03, 0.012, 0.01), shade: (0.01, 0.004, 0.004), rim: (1.0, 0.45, 0.2), spec: 2.2, gloss: 360, rimAmount: 1.6, sss: 0, core: 0),
        body: _pearl,
        hands: _pearl,
        accent: ToyLook(base: (1.0, 0.45, 0.12), shade: (1.0, 0.45, 0.12), spec: 0, emissive: 3.2),
        face: (1.0, 0.75, 0.3),
      ),
      FriendPalette(
        head: ToyLook(base: (0.008, 0.03, 0.025), shade: (0.003, 0.01, 0.01), rim: (0.25, 1.0, 0.7), spec: 2.2, gloss: 360, rimAmount: 1.6, sss: 0, core: 0),
        body: _pearl,
        hands: _pearl,
        accent: ToyLook(base: (0.2, 1.0, 0.65), shade: (0.2, 1.0, 0.65), spec: 0, emissive: 3.2),
        face: (0.55, 1.0, 0.8),
      ),
    ],
  );

  static const all = [lumi, juju, mochi, nova];

  static Friend byId(String? id) => all.firstWhere((f) => f.id == id, orElse: () => lumi);
}
