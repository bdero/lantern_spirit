import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_scene/kit.dart' show CameraShake;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../app/profile.dart';
import '../app/sfx.dart';
import '../lantern/character.dart';
import '../lantern/moods.dart';
import '../vfx/shadow.dart';
import '../vfx/vfx.dart';
import 'game_host.dart';
import 'shapes.dart';

/// Star Catch: slide along the shore of a mirror-still lake and catch falling
/// stars. Every star you catch flies up and takes its place in a
/// constellation; finish one and the sky answers with a meteor shower worth
/// double. Storm clouds throw lightning. The lake reflects all of it.
class StarCatch extends MiniGame {
  @override
  String get title => 'Star Catch';

  @override
  String get hint => 'Drag to move. Catch the stars.';

  @override
  double? get roundLength => 45;

  @override
  final Scene scene = Scene();

  @override
  final PerspectiveCamera camera = PerspectiveCamera(
    fovRadiansY: 44 * degrees2Radians,
    position: Vector3(0, 3.2, -15),
    target: Vector3(0, 4.6, 0),
  );

  late LanternCharacter _lumi;
  final _rng = math.Random(11);
  final _shake = CameraShake();
  final List<_Faller> _fallers = [];
  final List<_Flight> _flights = [];
  late final PreprocessedMaterial _gold;
  late final PreprocessedMaterial _trail;
  late final PreprocessedMaterial _faint;
  late final PreprocessedMaterial _line;
  late final PreprocessedMaterial _storm;
  late final PreprocessedMaterial _bolt;
  late final PreprocessedMaterial _water;
  late final PreprocessedMaterial _pad;
  late final PreprocessedSky _sky;
  late final Geometry _star;
  late final Geometry _ball;
  late final Geometry _rod;
  late final Node _padNode;
  late final Vfx _vfx;
  late final ContactShadow _shadow;

  /// Constellation lines drawing themselves in, and a light tracing a
  /// finished figure.
  final List<_Line> _drawing = [];
  double _trace = -1;
  List<Vector3> _tracePath = const [];
  double _punch = 0;
  double _aura = 0;
  int _lastCount = 99;

  double _x = 0, _vx = 0, _targetX = 0;

  /// How high to stand Lumi so its feet rest on the lily pad (Lumi itself
  /// hovers just over it).
  double _stand = 0.12;
  double _spawn = 0.8;
  double _cloudSpawn = 6;
  double _played = 0;
  double _dim = 0;
  int _score = 0;
  int _combo = 0;
  int _caught = 0;
  double _calloutTime = 0;
  String? _callout;
  double _shower = 0;
  double _flash = 0;
  final Vector3 _flashColor = Vector3.zero();

  // Constellations.
  int _shape = 0;
  int _filled = 0;
  int _completed = 0;
  Node? _sky0;
  final List<Node> _slots = [];
  final List<Vector3> _slotPos = [];
  double _celebrate = 0;

  static const _halfWidth = 1.3;
  static const _depth = 10.0;

  /// Constellations, as points on a grid (x right, y up), with their names
  /// and which points the lines join, in drawing order.
  static const _shapes = [
    (
      'The Lantern',
      [(0.0, 1.0), (0.7, 0.7), (1.0, 0.0), (0.7, -0.7), (0.0, -1.0), (-0.7, -0.7), (-1.0, 0.0), (-0.7, 0.7), (0.0, -1.8)],
      [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7), (7, 0), (4, 8)],
    ),
    (
      'The Coaster',
      [(-2.0, -0.6), (-1.4, 0.6), (-0.8, -0.2), (-0.2, 0.9), (0.4, -0.5), (1.0, 0.4), (1.6, -0.3), (2.1, 0.5)],
      [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7)],
    ),
    (
      'The Castle',
      [(-1.4, -0.9), (-1.4, 0.3), (-0.7, 0.3), (-0.7, 0.9), (0.0, 1.5), (0.7, 0.9), (0.7, 0.3), (1.4, 0.3), (1.4, -0.9)],
      [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7), (7, 8), (8, 0)],
    ),
  ];

  @override
  Future<void> load(LanternCharacter lumi) async {
    _lumi = lumi;
    final results = await Future.wait([
      loadFmatMaterial('assets/ember.fmat'),
      loadFmatMaterial('assets/ember.fmat'),
      loadFmatMaterial('assets/ember.fmat'),
      loadFmatMaterial('assets/ember.fmat'),
      loadFmatMaterial('assets/games/cloud.fmat'),
      loadFmatMaterial('assets/ember.fmat'),
      loadFmatMaterial('assets/show/water.fmat'),
      loadFmatMaterial('assets/toy.fmat'),
      loadFmatSky('assets/show/lagoon_sky.fmat'),
    ]);
    _gold = results[0] as PreprocessedMaterial;
    _trail = results[1] as PreprocessedMaterial;
    _faint = results[2] as PreprocessedMaterial;
    _line = results[3] as PreprocessedMaterial;
    _storm = results[4] as PreprocessedMaterial;
    _bolt = results[5] as PreprocessedMaterial;
    _water = results[6] as PreprocessedMaterial;
    _pad = results[7] as PreprocessedMaterial;
    _sky = results[8] as PreprocessedSky;
    _gold.parameters
      ..setVec4('ember_color', Vector4(1.0, 0.76, 0.3, 1))
      ..setFloat('intensity', 3.4);
    // Golden stars burn hotter and whiter.
    _trail.parameters
      ..setVec4('ember_color', Vector4(1.0, 0.86, 0.55, 1))
      ..setFloat('intensity', 6.0);
    _faint.parameters
      ..setVec4('ember_color', Vector4(0.55, 0.65, 1.0, 1))
      ..setFloat('intensity', 0.7);
    _line.parameters
      ..setVec4('ember_color', Vector4(0.6, 0.75, 1.0, 1))
      ..setFloat('intensity', 1.4);
    _storm.parameters
      ..setVec4('lit_color', Vector4(0.36, 0.3, 0.56, 1))
      ..setVec4('shade_color', Vector4(0.07, 0.06, 0.15, 1))
      ..setVec4('sun_dir', Vector4(0.2, 1, -0.6, 0));
    _bolt.parameters
      ..setVec4('ember_color', Vector4(0.75, 0.85, 1.0, 1))
      ..setFloat('intensity', 6);
    _water.parameters
      ..setFloat('streak', 0.02)
      ..setFloat('wobble', 0.003)
      ..setFloat('reflectivity', 1.1);
    _pad.parameters
      ..setVec4('base_color', Vector4(0.12, 0.42, 0.22, 1))
      ..setVec4('shade_color', Vector4(0.02, 0.1, 0.06, 1))
      ..setVec4('rim_color', Vector4(0.5, 0.9, 0.6, 1))
      ..setFloat('spec', 0.6)
      ..setFloat('gloss', 60)
      ..setFloat('glow', 1);
    _sky.parameters
      ..setVec4('horizon_color', Vector4(0.12, 0.07, 0.28, 1))
      ..setVec4('zenith_color', Vector4(0.01, 0.015, 0.06, 1))
      ..setFloat('star_brightness', 1.2);
    scene
      ..skybox = Skybox(_sky)
      ..environmentIntensity = 0.15
      ..debugCheckCoplanarOverlaps = false;
    scene.postProcess.bloom
      ..enabled = true
      ..threshold = 0.95
      ..intensity = 0.45;
    _vfx = await Vfx.create(scene);
    _shadow = await ContactShadow.create(scene, opacity: 0.45);
    _star = starGeometry(radius: 0.32, depth: 0.12);
    _ball = SphereGeometry(radius: 1, segments: 16, rings: 8);
    _rod = CylinderGeometry(bottomRadius: 1, topRadius: 1, height: 1, radialSegments: 8, bottomCap: false, topCap: false);

    // A still lake that mirrors the sky.
    final lake = Node(name: 'Lake', mesh: Mesh(PlaneGeometry(width: 400, depth: 400), _water));
    lake.addComponent(PlanarReflectorComponent(resolutionScale: 0.5));
    scene.add(lake);
    // Rolling hills on the far shore.
    final hill = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(0.012, 0.014, 0.04, 1)
      ..roughnessFactor = 1;
    for (final (x, r, y) in const [(-14.0, 9.0, -6.0), (9.0, 10.0, -7.4), (0.0, 13.0, -11.0)]) {
      scene.add(
        Node(mesh: Mesh(SphereGeometry(radius: r, segments: 48, rings: 24), hill), localTransform: Matrix4.translation(Vector3(x, y, 40))),
      );
    }
    _padNode = Node(name: 'LilyPad', mesh: Mesh(CylinderGeometry(bottomRadius: 0.62, topRadius: 0.6, height: 0.05, radialSegments: 40), _pad));
    scene.add(_padNode);
    _layOut(0);
    lumi.place(Vector3.zero(), 0);
    if (lumi.footing case final f?) _stand = 0.05 - f;
    lumi.place(Vector3(0, _stand, 0), 0);
    lumi
      ..restMood = LanternMood.awake
      ..grounded = true;
  }

  // ---------------------------------------------------------------- shapes
  /// Puts up the faint outline of constellation [i], high in the sky.
  void _layOut(int i) {
    _sky0?.detach();
    final (_, points, _) = _shapes[i % _shapes.length];
    final group = Node(name: 'Constellation');
    _slots.clear();
    _slotPos.clear();
    final center = Vector3(0, 10.8, _depth);
    for (final (px, py) in points) {
      final p = center + Vector3(px * 1.25, py * 1.25, 0);
      final dot = Node(mesh: Mesh(_ball, _faint), localTransform: Matrix4.compose(p, Quaternion.identity(), Vector3.all(0.06)));
      group.add(dot);
      _slots.add(dot);
      _slotPos.add(p);
    }
    scene.add(group);
    _sky0 = group;
    _filled = 0;
  }

  /// A glowing rod between two points.
  Node _rodBetween(Vector3 a, Vector3 b, double radius, Material material) {
    final d = b - a;
    final len = d.length;
    final up = Vector3(0, 1, 0);
    final axis = up.cross(d.normalized());
    final angle = math.acos(up.dot(d.normalized()).clamp(-1.0, 1.0));
    final q = axis.length < 1e-6 ? Quaternion.identity() : Quaternion.axisAngle(axis.normalized(), angle);
    return Node(mesh: Mesh(_rod, material), localTransform: Matrix4.compose((a + b) * 0.5, q, Vector3(radius, len, radius)));
  }

  /// A caught star lands in its slot: it lights, and joins the lines.
  void _land(int slot) {
    final (name, points, lines) = _shapes[_shape % _shapes.length];
    final group = _sky0!;
    final p = _slotPos[slot];
    group.add(Node(mesh: Mesh(_star, _gold), localTransform: Matrix4.compose(p, Quaternion.identity(), Vector3.all(0.55))));
    _slots[slot].visible = false;
    _vfx
      ..flare(p, size: 1.0, color: Vector3(2.0, 1.8, 1.2), life: 0.35)
      ..ring(p, radius: 0.5, color: Vector3(1.2, 1.4, 2.0), life: 0.35);
    for (final (a, b) in lines) {
      if ((a == slot && b < slot) || (b == slot && a < slot)) {
        // The line draws itself from the earlier star to this one.
        final from = a == slot ? _slotPos[b] : _slotPos[a];
        final node = _rodBetween(from, p, 0.018, _line);
        group.add(node);
        _drawing.add(_Line(node, from, p));
      }
    }
    if (slot == points.length - 1) {
      // A light runs along the whole figure, line by line.
      _trace = 0;
      _tracePath = [for (final (a, b) in lines) ...[_slotPos[a], _slotPos[b]]];
      // Complete: the sky lights up and a meteor shower starts.
      _completed++;
      _score += 10;
      _celebrate = 1.6;
      _shower = 6;
      _flash = 1.2;
      _flashColor.setValues(0.5, 0.6, 1.4);
      banner(name, sub: 'Meteor shower · stars count double', color: const Color(0xFF9FC0FF));
      screenFlash(const Color(0xFFCFE0FF), 0.6);
      stop(0.15);
      for (final p in _slotPos) {
        _vfx
          ..flare(p, size: 1.4, color: Vector3(1.8, 1.9, 2.4), life: 0.9)
          ..ring(p, radius: 0.8, color: Vector3(1.0, 1.2, 2.0), life: 0.6);
      }
      final center = _slotPos.fold(Vector3.zero(), (a, b) => a + b) / _slotPos.length.toDouble();
      _vfx
        ..ring(center, radius: 5, color: Vector3(1.2, 1.4, 2.2), life: 1.0)
        ..burst(center, count: 70, speed: 7, color: Vector3(1.6, 1.7, 2.4), color2: Vector3(2.2, 1.6, 0.8), streaks: true, life: 1.0, gravity: 1.5);
      _lumi
        ..celebrate()
        ..react(LanternFace.wow, 1.0);
      _shake.addTrauma(0.3);
      Sfx.heavy();
    }
  }

  // ---------------------------------------------------------------- input
  @override
  void steer(double x) => _targetX = x * _halfWidth * 1.15;

  @override
  int get score => _score;

  @override
  String get leftPill => '★ $_score';

  @override
  String get rightPill => '0:${math.max(0, (45 - _played).ceil()).toString().padLeft(2, '0')}';

  /// How much of the current constellation is filled in.
  @override
  double? get meter => _filled / _shapes[_shape % _shapes.length].$2.length;

  @override
  String? get callout => _calloutTime > 0 ? _callout : null;

  @override
  String? get resultLine => _completed == 0
      ? '$_caught stars caught'
      : '$_completed ${_completed == 1 ? 'constellation' : 'constellations'} · $_caught stars';

  @override
  int starsFor(int score) => _caught ~/ 3 + _completed * 3;

  @override
  void record(Profile profile, int score) => profile.recordCatch(score);


  /// For autoplay: a steering target toward the lowest star and away from
  /// storm clouds overhead, in -1..1.
  double botSteer() {
    var x = _x;
    var low = double.infinity;
    for (final f in _fallers) {
      if (!f.cloud && f.y < low && f.y > 0.6) {
        low = f.y;
        x = f.x;
      }
    }
    for (final f in _fallers) {
      if (f.cloud && f.y < 6.5 && (f.x - x).abs() < 1.0) x = f.x > 0 ? f.x - 1.2 : f.x + 1.2;
    }
    return (x / (_halfWidth * 1.15)).clamp(-1.0, 1.0);
  }

  /// For tests: catch the next [n] stars wherever they are.
  void catchForTest(int n) {
    for (final f in _fallers.where((f) => !f.cloud).take(n).toList()) {
      _catch(f);
    }
  }

  // ---------------------------------------------------------------- frame
  @override
  void update(double dt, double time, {required bool playing}) {
    _sky.parameters.setFloat('time', time);
    _water.parameters.setFloat('time', time);
    // Lumi glides on a lily pad and leans into the motion.
    final a = (_targetX.clamp(-_halfWidth, _halfWidth) - _x) * 60 - _vx * 11;
    _vx += a * dt;
    _x += _vx * dt;
    _lumi.place(Vector3(_x, _stand + math.sin(time * 2.1) * 0.02, 0), (_vx * 0.05).clamp(-0.4, 0.4));
    _shadow.place(Vector3(_x, 0.055, 0), radius: 0.48, height: math.max(0, _lumi.restFeet + _stand - 0.05));
    _padNode.localTransform = Matrix4.compose(
      Vector3(_x, 0.02, 0),
      Quaternion.axisAngle(Vector3(0, 0, 1), (-_vx * 0.03).clamp(-0.12, 0.12)),
      Vector3.all(1),
    );
    _calloutTime -= dt;
    _dim = math.max(0, _dim - dt);
    _lumi.glowScale = 1 - 0.55 * math.min(1.0, _dim);
    _flash = math.max(0, _flash - dt * 2.5);
    _shower = math.max(0, _shower - dt);
    _celebrate = math.max(0, _celebrate - dt);
    _punch = math.max(0, _punch - dt * 4);

    if (playing) {
      _played += dt;
      final progress = (_played / 45).clamp(0.0, 1.0);
      _spawn -= dt;
      if (_spawn <= 0) {
        _spawn = _shower > 0 ? 0.16 + _rng.nextDouble() * 0.1 : 0.95 - 0.5 * progress + _rng.nextDouble() * 0.25;
        _drop(false, (_shower > 0 ? 4.2 : 3.0) + 3.0 * progress);
      }
      _cloudSpawn -= dt;
      if (_cloudSpawn <= 0 && _shower <= 0) {
        _cloudSpawn = 5 + _rng.nextDouble() * 3;
        _drop(true, 2.2 + 1.4 * progress);
      }
    }

    // Meteors streak across the far sky during a shower.
    if (_shower > 0 && _rng.nextDouble() < dt * 14) {
      final at = Vector3(-8 + _rng.nextDouble() * 16, 9 + _rng.nextDouble() * 7, 22);
      _vfx.streak(at, Vector3(-9 - _rng.nextDouble() * 5, -5, 0), color: Vector3(1.6, 1.4, 1.0), width: 0.05, length: 0.08, life: 0.8);
    }
    // The last ten seconds count down.
    final left = (45 - _played).ceil();
    if (playing && left <= 10 && left >= 1 && left < _lastCount) {
      _lastCount = left;
      popup(Vector3(0, 8.6, 0), '$left', color: left <= 3 ? const Color(0xFFFF8A8A) : const Color(0xFFFFFFFF), size: 44, life: 0.8);
    }
    // A hot streak wraps your friend in a ring of sparks.
    if (_combo >= 8) {
      _aura -= dt;
      if (_aura <= 0) {
        _aura = 0.08;
        final h = _lumi.headCenter;
        final a = _rng.nextDouble() * math.pi * 2;
        _vfx.burst(h + Vector3(math.cos(a) * 0.9, math.sin(a) * 1.1 - 0.4, -0.2), count: 1, speed: 0.4, color: Vector3(2.0, 1.6, 0.6), size: 0.08, life: 0.6, gravity: -1, shape: VfxShape.flare);
      }
    }

    // The sky: a faint glow during the shower, lightning flashes.
    final showerGlow = math.min(1.0, _shower) * 0.35;
    _sky.parameters
      ..setVec4('horizon_color', Vector4(0.12 + showerGlow * 0.4, 0.07 + showerGlow * 0.25, 0.28 + showerGlow * 0.2, 1))
      ..setVec4('flash_color', Vector4(_flashColor.x, _flashColor.y, _flashColor.z, 0) * _flash)
      ..setVec4('flash_dir', Vector4(0, 0.5, 1, 0));
    _lumi.ambientColor.setFrom(_flashColor * (_flash * 0.5));

    final head = _lumi.headCenter;
    Vector3? nearest;
    for (final f in _fallers.toList()) {
      f.y -= f.speed * dt;
      f.x += f.drift * dt;
      f.spin += dt * 2.2;
      f.node.localTransform = Matrix4.compose(
        Vector3(f.x, f.y, 0),
        Quaternion.axisAngle(Vector3(0, 0, 1), f.cloud ? math.sin(f.spin) * 0.08 : f.spin * 0.4),
        Vector3.all(1),
      );
      if (f.cloud && !f.struck && playing && (f.x - _x).abs() < 0.9 && f.y < 4.4) {
        _strike(f);
      }
      if (!f.cloud) {
        // Glitter falling off the star as it comes down.
        f.trail -= dt;
        if (f.trail <= 0) {
          f.trail = 0.025;
          final c = f.golden ? Vector3(1.0 + _rng.nextDouble(), 0.6 + _rng.nextDouble() * 0.8, 1.0 + _rng.nextDouble() * 0.6) * 1.4 : Vector3(2.0, 1.5, 0.6);
          _vfx
            ..streak(Vector3(f.x, f.y + 0.15, 0.05), Vector3(f.drift * -0.3, f.speed * 0.6, 0), color: c * 0.6, width: f.golden ? 0.07 : 0.045, length: 0.12, life: 0.35)
            ..burst(Vector3(f.x, f.y + 0.1, 0.05), count: 1, speed: 0.3, color: c, size: 0.05, life: 0.6, gravity: 1.2, shape: VfxShape.flare);
        }
      }
      final dx = f.x - head.x, dy = f.y - (head.y + 0.55);
      if (!f.cloud && dx.abs() < 0.85 && dy.abs() < 0.6) {
        _catch(f);
        continue;
      }
      if (f.y < 0.05 && !f.cloud) {
        // Into the lake: a splash and ripples.
        f.node.detach();
        _fallers.remove(f);
        if (_combo >= 5) popup(Vector3(f.x, 0.8, 0), 'Combo lost', color: const Color(0xFFAAB8FF), size: 16);
        _combo = 0;
        Sfx.sound('star_miss', volume: 0.6);
        final at = Vector3(f.x, 0.03, 0);
        _vfx
          ..ring(at, radius: 1.3, color: Vector3(0.7, 0.85, 1.4), life: 0.9, normal: Vector3(0, 1, 0))
          ..ring(at, radius: 0.7, color: Vector3(0.6, 0.75, 1.3), life: 0.6, normal: Vector3(0, 1, 0))
          ..burst(at, count: 12, speed: 2.2, color: Vector3(0.9, 1.1, 1.6), streaks: true, life: 0.5, gravity: 9, bias: Vector3(0, 2.2, 0));
        continue;
      }
      if (f.y < -0.6) {
        f.node.detach();
        _fallers.remove(f);
        continue;
      }
      if (!f.cloud && f.y < head.y + 3 && (nearest == null || f.y < nearest.y)) nearest = Vector3(f.x, f.y, 0);
    }
    _lumi.lookAtWorld(nearest);
    // Reach for a star that is about to arrive.
    _lumi.reachTarget = nearest != null && (nearest - head).length < 2.2 ? nearest + Vector3(0, 0, -0.3) : null;

    // Lines drawing in, with a spark riding the tip.
    for (final l in _drawing.toList()) {
      l.t = math.min(1, l.t + dt / 0.32);
      final e = Curves.easeOutCubic.transform(l.t);
      final tip = l.from + (l.to - l.from) * e;
      if (e < 0.01) {
        l.node.visible = false;
      } else {
        l.node.visible = true;
        final d = tip - l.from;
        final up = Vector3(0, 1, 0);
        final axis = up.cross(d.normalized());
        final angle = math.acos(up.dot(d.normalized()).clamp(-1.0, 1.0));
        final q = axis.length < 1e-6 ? Quaternion.identity() : Quaternion.axisAngle(axis.normalized(), angle);
        l.node.localTransform = Matrix4.compose((l.from + tip) * 0.5, q, Vector3(0.018, d.length, 0.018));
      }
      _vfx.burst(tip, count: 1, speed: 0.3, color: Vector3(1.6, 1.8, 2.4), size: 0.06, life: 0.35, gravity: 0, shape: VfxShape.flare);
      if (l.t >= 1) _drawing.remove(l);
    }
    // The trace around a finished constellation.
    if (_trace >= 0 && _tracePath.length >= 2) {
      _trace += dt;
      final segs = _tracePath.length ~/ 2;
      final u = (_trace / 1.2).clamp(0.0, 1.0) * segs;
      final i = math.min(segs - 1, u.floor());
      final k = u - i;
      final at = _tracePath[i * 2] + (_tracePath[i * 2 + 1] - _tracePath[i * 2]) * k;
      _vfx
        ..flare(at, size: 0.7, color: Vector3(2.2, 2.0, 1.6), life: 0.12)
        ..burst(at, count: 2, speed: 0.8, color: Vector3(1.4, 1.6, 2.4), size: 0.05, life: 0.5, gravity: 0.5, shape: VfxShape.flare);
      if (_trace > 1.2) _trace = -1;
    }

    // Caught stars flying up to their constellation.
    for (final fl in _flights.toList()) {
      fl.t += dt / 0.7;
      final t = fl.t.clamp(0.0, 1.0);
      final e = t * t * (3 - 2 * t);
      final p = fl.from + (fl.to - fl.from) * e + Vector3(0, math.sin(t * math.pi) * 1.5, 0);
      fl.node.localTransform = Matrix4.compose(p, Quaternion.axisAngle(Vector3(0, 0, 1), t * 6), Vector3.all(0.7 - 0.15 * t));
      if (fl.t >= 1) {
        fl.node.detach();
        _flights.remove(fl);
        if (fl.shape == _shape) _land(fl.slot);
      }
    }
    // A finished constellation flares, then the next one appears.
    if (_sky0 != null) {
      _line.parameters.setFloat('intensity', 1.4 + _celebrate * 2.5);
      final pts = _shapes[_shape % _shapes.length].$2.length;
      if (_filled >= pts && _celebrate <= 0 && _flights.isEmpty) {
        _shape++;
        _layOut(_shape);
      }
    }

    final jitter = _shake.update(dt).toMatrix4().getTranslation();
    camera
      ..position = Vector3(jitter.x, 3.2 + jitter.y, -15)
      ..target = Vector3(jitter.x * 4, 4.6 + jitter.y * 4, 0)
      ..fovRadiansY = (44 - 2.5 * _punch * _punch) * degrees2Radians;
    _vfx.update(dt, camera);
  }

  void _drop(bool cloud, double speed) {
    final node = Node(name: cloud ? 'Storm' : 'Star');
    if (cloud) {
      // A low row of puffs with a taller crown, like a small thunderhead.
      const puffs = [(-0.5, 0.0, 0.3), (-0.18, 0.12, 0.4), (0.2, 0.08, 0.38), (0.5, -0.02, 0.28), (0.02, 0.36, 0.34)];
      for (final (x, y, r) in puffs) {
        node.add(
          Node(
            mesh: Mesh(_ball, _storm),
            localTransform: Matrix4.compose(Vector3(x, y, _rng.nextDouble() * 0.1), Quaternion.identity(), Vector3.all(r * (0.9 + _rng.nextDouble() * 0.2))),
          ),
        );
      }
    }
    final golden = !cloud && _played > 6 && _shower <= 0 && _rng.nextDouble() < 0.045;
    if (!cloud) {
      node.add(Node(mesh: Mesh(_star, golden ? _trail : _gold), localTransform: Matrix4.diagonal3Values(golden ? 1.5 : 1, golden ? 1.5 : 1, 1)));
    }
    final drift = _shower > 0 ? -0.5 : 0.0;
    final f = _Faller(node, (_rng.nextDouble() * 2 - 1) * _halfWidth - drift, 10.5, golden ? speed * 0.8 : speed, cloud, drift)..golden = golden;
    scene.add(node);
    _fallers.add(f);
  }

  /// A storm cloud right overhead throws lightning down at Lumi.
  void _strike(_Faller f) {
    f.struck = true;
    final head = _lumi.headCenter;
    _vfx
      ..bolt(Vector3(f.x, f.y - 0.2, -0.3), head + Vector3(0, 0.5, -0.3))
      ..burst(head, count: 22, speed: 3, color: Vector3(1.4, 1.7, 2.6), streaks: true, life: 0.45, gravity: 0);
    _flash = 1.3;
    _flashColor.setValues(0.7, 0.8, 1.6);
    _shake.addTrauma(0.6);
    stop(0.1);
    screenFlash(const Color(0xFFC8D8FF), 0.75);
    if (_combo >= 5) popup(head + Vector3(0, 1.4, 0), 'Combo lost', color: const Color(0xFFAAB8FF), size: 16);
    _combo = 0;
    _dim = 2;
    popup(head + Vector3(0, 0.9, 0), 'ZAP!', color: const Color(0xFFB8D4FF), size: 34);
    _lumi
      ..react(LanternFace.dizzy, 1.0)
      ..jolt(1.0);
    Sfx.heavy();
    Sfx.sound('zap');
  }

  void _catch(_Faller f) {
    f.node.detach();
    _fallers.remove(f);
    _caught++;
    _combo++;
    final mult = math.min(5, 1 + _combo ~/ 5) * (_shower > 0 ? 2 : 1) * (f.golden ? 5 : 1);
    _score += mult;
    final at = Vector3(f.x, f.y, 0);
    final hot = _combo >= 5;
    _vfx
      ..flare(at, size: f.golden ? 2.6 : 1.4, color: f.golden ? Vector3(2.4, 2.0, 2.6) : null, life: 0.35)
      ..ring(at, radius: f.golden ? 2.4 : 1.1, color: hot ? Vector3(2.0, 1.2, 1.6) : Vector3(2.0, 1.7, 0.9), life: 0.35)
      ..burst(at, count: f.golden ? 60 : 18 + math.min(_combo, 20), speed: f.golden ? 7 : 4.5, color: Vector3(2.0, 1.6, 0.7), color2: hot ? Vector3(2.2, 1.0, 1.8) : null, streaks: true, life: 0.5, gravity: 3);
    _punch = f.golden ? 1 : 0.4;
    if (f.golden) {
      stop(0.12);
      screenFlash(const Color(0xFFFFF0C0), 0.5);
      banner('Golden star!', sub: '+$mult', color: const Color(0xFFFFE08A));
    } else if (const {5, 10, 20, 30, 50}.contains(_combo)) {
      stop(0.05);
      banner('×${math.min(5, 1 + _combo ~/ 5)} combo', sub: '$_combo in a row', color: const Color(0xFFFFA8E0), sound: 'combo');
    }
    final colors = [const Color(0xFFFFE08A), const Color(0xFFFFC08A), const Color(0xFFFFA8E0), const Color(0xFFC8A8FF), const Color(0xFF9FE8FF)];
    // Popups fan out so a fast streak never stacks them on one spot.
    final fan = Vector3((_caught % 3 - 1) * 0.45, 0.3 + (_caught % 2) * 0.25, 0);
    popup(at + fan, '+$mult', color: colors[math.min(_combo ~/ 5, colors.length - 1)], size: 20.0 + math.min(mult, 10) * 1.6, life: 0.7);
    _lumi
      ..react(LanternFace.delighted, 0.35)
      ..jolt(0.45);
    Sfx.light();
    // Each catch in a streak rings a step higher up the pentatonic scale.
    const steps = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24];
    Sfx.sound('star_catch', pitch: math.pow(2, steps[math.min(_combo - 1, steps.length - 1)] / 12).toDouble(), gap: const Duration(milliseconds: 30));
    // The star flies up into the next empty slot of the constellation.
    final points = _shapes[_shape % _shapes.length].$2.length;
    if (_filled < points) {
      final node = Node(mesh: Mesh(_star, _gold));
      scene.add(node);
      _flights.add(_Flight(node, Vector3(f.x, f.y, 0), _slotPos[_filled], _filled, _shape));
      _filled++;
    }
  }
}

class _Faller {
  _Faller(this.node, this.x, this.y, this.speed, this.cloud, this.drift);
  final Node node;
  double x, y;
  final double speed;
  final bool cloud;
  final double drift;
  double spin = 0;
  bool struck = false;
  bool golden = false;
  double trail = 0;
}

class _Flight {
  _Flight(this.node, this.from, this.to, this.slot, this.shape);
  final Node node;
  final Vector3 from, to;
  final int slot;
  final int shape;
  double t = 0;
}

class _Line {
  _Line(this.node, this.from, this.to);
  final Node node;
  final Vector3 from, to;
  double t = 0;
}
