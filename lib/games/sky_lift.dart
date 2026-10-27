import 'dart:math' as math;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_scene/kit.dart' show CameraShake;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../app/profile.dart';
import '../app/sfx.dart';
import '../lantern/character.dart';
import '../lantern/moods.dart';
import '../show/fireworks.dart';
import '../vfx/vfx.dart';
import 'game_host.dart';
import 'shapes.dart';

/// Sky Lift: hold anywhere to glow and float up, slide your finger to steer,
/// let go to drift. Ride from a sunset over the park, bounce off clouds,
/// burst through the cloud sea into the night, past the aurora, all the way
/// to the moon.
///
/// Glow is the fuel: holding spends it, drifting and sky lanterns refill
/// it. Soft clouds are trampolines when you come down on them; storm clouds
/// zap you. The round ends at the moon, after 90 seconds, or when you sink
/// out of view.
class SkyLift extends MiniGame {
  @override
  String get title => 'Sky Lift';

  @override
  String get hint => 'Hold to float up. Slide to steer.';

  @override
  double? get roundLength => 90;

  @override
  final Scene scene = Scene();

  @override
  final PerspectiveCamera camera = PerspectiveCamera(
    fovRadiansY: 46 * degrees2Radians,
    position: Vector3(0, 3.0, -15),
    target: Vector3(0, 3.6, 0),
  );

  late LanternCharacter _lumi;
  final _rng = math.Random(7);
  final _shake = CameraShake();
  late final PreprocessedMaterial _cloud;
  late final PreprocessedMaterial _farCloud;
  late final PreprocessedMaterial _storm;
  late final PreprocessedMaterial _gold;
  late final PreprocessedMaterial _lantern;
  late final PreprocessedMaterial _aurora;
  late final PreprocessedMaterial _moonMat;
  late final PreprocessedSky _sky;
  late final Geometry _star;
  late final Geometry _puff;
  late final Geometry _lanternGeo;

  // Lumi.
  double _x = 0, _vx = 0, _targetX = 0;
  double _y = 0, _vy = 0;
  double _glow = 1;
  bool _thrust = false;
  SfxLoop? _burner;
  bool _burnerStarting = false;
  bool _burnerWanted = false;

  @override
  void dispose() {
    _burnerWanted = false;
    _burner?.stop();
    _burner = null;
  }

  // Progress.
  double _best = 0;
  int _stars = 0;
  int _lanterns = 0;
  int _bounces = 0;
  bool _sunk = false;
  bool _moonReached = false;
  double _camY = 3.0;
  double _flash = 0;
  final Vector3 _flashColor = Vector3.zero();
  int _zone = 0;

  // The sky.
  double _nextLevel = 4;
  final List<_Cloud> _clouds = [];
  final List<_Pickup> _pickups = [];
  final List<Node> _far = [];
  double _nextFar = -4;
  late final Node _auroraNode;
  late final Node _moon;
  String? _callout;
  double _calloutTime = 0;

  // Juice.
  late final Vfx _vfx;
  late final FireworkRenderer _fireworks;
  final List<Launch> _launches = [];
  double _moonTime = -1;
  double _invuln = 0;
  double _punch = 0;
  double _speedLines = 0;
  int _streak = 0;
  double _streakTimer = 0;
  int _milestone = 0;

  static const _halfWidth = 1.45;
  static const _gravity = 5.2;
  static const _thrustAccel = 10.5;
  static const _cloudSea = 15.0;
  static const _moonY = 100.0;

  /// Altitude in meters, as the HUD shows it.
  double get meters => _best * 10;

  @override
  Future<void> load(LanternCharacter lumi) async {
    _lumi = lumi;
    final results = await Future.wait([
      loadFmatMaterial('assets/games/cloud.fmat'),
      loadFmatMaterial('assets/games/cloud.fmat'),
      loadFmatMaterial('assets/games/cloud.fmat'),
      loadFmatMaterial('assets/ember.fmat'),
      loadFmatMaterial('assets/ember.fmat'),
      loadFmatMaterial('assets/games/aurora.fmat'),
      loadFmatMaterial('assets/games/moon.fmat'),
      loadFmatSky('assets/show/lagoon_sky.fmat'),
    ]);
    _cloud = results[0] as PreprocessedMaterial;
    _farCloud = results[1] as PreprocessedMaterial;
    _storm = results[2] as PreprocessedMaterial;
    _gold = results[3] as PreprocessedMaterial;
    _lantern = results[4] as PreprocessedMaterial;
    _aurora = results[5] as PreprocessedMaterial;
    _moonMat = results[6] as PreprocessedMaterial;
    _sky = results[7] as PreprocessedSky;
    _gold.parameters
      ..setVec4('ember_color', Vector4(1.0, 0.78, 0.32, 1))
      ..setFloat('intensity', 3.2);
    _lantern.parameters
      ..setVec4('ember_color', Vector4(1.0, 0.5, 0.16, 1))
      ..setFloat('intensity', 2.6);
    _storm.parameters
      ..setVec4('lit_color', Vector4(0.34, 0.3, 0.5, 1))
      ..setVec4('shade_color', Vector4(0.06, 0.05, 0.13, 1))
      ..setVec4('sun_dir', Vector4(0.2, 1, -0.6, 0));
    _moonMat.parameters.setFloat('brightness', 1.15);
    scene
      ..skybox = Skybox(_sky)
      ..environmentIntensity = 0.3
      ..debugCheckCoplanarOverlaps = false;
    scene.postProcess.bloom
      ..enabled = true
      ..threshold = 0.95
      ..intensity = 0.4;
    // Lumi in focus; clouds that sweep past the lens blur.
    scene.depthOfField
      ..enabled = true
      ..focusDistance = 15
      ..fStop = 2.2;
    _vfx = await Vfx.create(scene);
    final fw = await Future.wait([loadFmatMaterial('assets/show/firework.fmat'), loadFmatMaterial('assets/show/smoke.fmat')]);
    _fireworks = FireworkRenderer(lightMaterial: fw[0], smokeMaterial: fw[1], trailSamples: 6);
    scene
      ..add(_fireworks.lightNode)
      ..add(_fireworks.smokeNode);
    _star = starGeometry(radius: 0.3, depth: 0.12);
    _puff = SphereGeometry(radius: 1, segments: 24, rings: 12);
    _lanternGeo = CapsuleGeometry(radius: 0.17, height: 0.16, radialSegments: 20, capRings: 6);

    // The aurora: two wide curtains far behind, high up.
    _auroraNode = Node(name: 'Aurora');
    for (final (x, z, w, yaw) in const [(-8.0, 46.0, 70.0, 0.25), (14.0, 60.0, 80.0, -0.3)]) {
      _auroraNode.add(
        Node(
          mesh: Mesh(PlaneGeometry(width: w, depth: 26), _aurora),
          localTransform: Matrix4.compose(
            Vector3(x, 82, z),
            Quaternion.axisAngle(Vector3(0, 1, 0), yaw) * Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2),
            Vector3.all(1),
          ),
        ),
      );
    }
    scene.add(_auroraNode);
    _moon = Node(
      name: 'Moon',
      mesh: Mesh(SphereGeometry(radius: 7, segments: 64, rings: 32), _moonMat),
      localTransform: Matrix4.translation(Vector3(4, _moonY + 8, 40)),
    );
    scene.add(_moon);

    // The cloud sea: a wide deck of puffs to burst through.
    for (var i = 0; i < 70; i++) {
      final x = (_rng.nextDouble() * 2 - 1) * 16;
      final z = -2 + _rng.nextDouble() * 40;
      final s = 1.2 + _rng.nextDouble() * 1.8;
      final n = Node(
        mesh: Mesh(_puff, z > 6 ? _farCloud : _cloud),
        localTransform: Matrix4.compose(Vector3(x, _cloudSea + _rng.nextDouble() * 0.8, z), Quaternion.identity(), Vector3(s, s * 0.55, s)),
      );
      scene.add(n);
    }
    while (_nextLevel < 30) {
      _addLevel();
    }
    _stockFar();
    lumi
      ..place(Vector3.zero(), 0)
      ..airborne = true
      ..restMood = LanternMood.awake;
    _applySky(0);
  }

  // ---------------------------------------------------------------- world
  void _addLevel() {
    final y = _nextLevel;
    // Skip the band of the cloud sea, then space out as the air thins.
    _nextLevel += y < 40 ? 3.3 : 3.9;
    if ((y - _cloudSea).abs() < 2.2 || y > _moonY - 6) return;
    final storms = y > 10 ? math.min(0.55, 0.15 + y / 200) : 0.0;
    final count = _rng.nextDouble() < 0.45 ? 2 : 1;
    final used = <double>[];
    for (var i = 0; i < count; i++) {
      var x = (_rng.nextDouble() * 2 - 1) * _halfWidth;
      if (used.any((u) => (u - x).abs() < 1.5)) x = x > 0 ? x - 1.6 : x + 1.6;
      used.add(x);
      _clouds.add(_makeCloud(Vector3(x, y, 0.6), 0.7 + _rng.nextDouble() * 0.35, false));
    }
    // A small storm cloud off to one side, between levels, always leaving a
    // clear lane on the other side.
    if (_rng.nextDouble() < storms) {
      final side = _rng.nextBool() ? 1.0 : -1.0;
      _clouds.add(_makeCloud(Vector3(side * (0.85 + _rng.nextDouble() * 0.45), y + 1.65, 0.6), 0.48 + _rng.nextDouble() * 0.12, true));
    }
    // Something to reach for in the gaps: lanterns low, stars higher.
    final gap = used.length == 1 ? (used.first > 0 ? -1.0 : 1.0) * (0.5 + _rng.nextDouble() * 0.7) : 0.0;
    final pos = Vector3(gap, y + 1.1, 0);
    if (_rng.nextDouble() < (y < 60 ? 0.6 : 0.4)) {
      final n = Node(name: 'SkyLantern', mesh: Mesh(_lanternGeo, _lantern));
      n.localTransform = Matrix4.translation(pos);
      scene.add(n);
      _pickups.add(_Pickup(n, pos, lantern: true, phase: _rng.nextDouble() * 6));
    } else {
      final n = Node(name: 'Star', mesh: Mesh(_star, _gold));
      n.localTransform = Matrix4.translation(pos);
      scene.add(n);
      _pickups.add(_Pickup(n, pos, lantern: false, phase: 0));
    }
  }

  _Cloud _makeCloud(Vector3 center, double size, bool storm) {
    final node = Node(name: storm ? 'Storm' : 'Cloud');
    final puffs = Node();
    for (var k = 0; k < 6; k++) {
      puffs.add(
        Node(
          mesh: Mesh(_puff, storm ? _storm : _cloud),
          localTransform: Matrix4.compose(
            Vector3((k - 2.5) * 0.36 * size, _rng.nextDouble() * 0.28 * size, _rng.nextDouble() * 0.3),
            Quaternion.identity(),
            Vector3.all(size * (0.38 + _rng.nextDouble() * 0.22)),
          ),
        ),
      );
    }
    node.add(puffs);
    node.localTransform = Matrix4.translation(center);
    scene.add(node);
    return _Cloud(node, puffs, center, size, storm);
  }

  /// Big dim cloud banks far behind, for depth as the sky slides past.
  void _stockFar() {
    while (_nextFar < _camY + 30) {
      final y = _nextFar;
      _nextFar += 5 + _rng.nextDouble() * 4;
      if (y > _moonY - 10) continue;
      final side = _rng.nextBool() ? 1.0 : -1.0;
      final bank = Node(localTransform: Matrix4.translation(Vector3(side * (6 + _rng.nextDouble() * 8), y, 22 + _rng.nextDouble() * 14)));
      for (var k = 0; k < 5; k++) {
        final s = 1.8 + _rng.nextDouble() * 1.8;
        bank.add(
          Node(
            mesh: Mesh(_puff, _farCloud),
            localTransform: Matrix4.compose(Vector3((k - 2) * 1.9, _rng.nextDouble() * 1.2, 0), Quaternion.identity(), Vector3(s, s * 0.7, s)),
          ),
        );
      }
      scene.add(bank);
      _far.add(bank);
    }
    _far.removeWhere((b) {
      if (b.localTransform.getTranslation().y < _camY - 24) {
        b.detach();
        return true;
      }
      return false;
    });
  }

  // ---------------------------------------------------------------- input
  @override
  void steer(double x) => _targetX = x * _halfWidth * 1.15;

  @override
  void press(double x) {
    steer(x);
    _thrust = true;
  }

  @override
  void release() => _thrust = false;

  /// For tests: hold or let go without a pointer.
  set thrustForTest(bool on) => _thrust = on;

  /// For the test bot: a steering target toward the nearest pickup above
  /// and away from storm clouds, in -1..1.
  double botSteer() {
    var x = 0.0;
    var best = double.infinity;
    for (final p in _pickups) {
      final dy = p.pos.y - _y;
      if (dy > 0 && dy < best) {
        best = dy;
        x = p.pos.x;
      }
    }
    for (final c in _clouds) {
      if (c.storm && (c.center.y - _y - 1.8).abs() < 2.5 && (c.center.x - x).abs() < 1.0) x = -c.center.x.sign * 1.0;
    }
    return (x / (_halfWidth * 1.15)).clamp(-1.0, 1.0);
  }

  /// For tests: jump straight to a height, in world units.
  void jumpForTest(double y) {
    _y = y;
    _best = math.max(_best, y);
    _vy = 0;
    _camY = y + 2.6;
  }

  // ---------------------------------------------------------------- HUD
  @override
  int get score => meters.floor() + _stars * 25 + _lanterns * 10 + _bonus + (_moonReached ? 250 : 0);

  int _bonus = 0;

  @override
  String get leftPill => '↑ ${meters.floor()} m';

  @override
  String get rightPill => '★ $_stars  ✦ $_lanterns';

  @override
  double get meter => _glow;

  @override
  String? get callout => _calloutTime > 0 ? _callout : null;

  @override
  bool get finished => _sunk || (_moonReached && _moonTime > 4.5);

  @override
  String? get resultLine => _moonReached ? 'Reached the moon!' : '${meters.floor()} m high · $_bounces cloud bounces';

  @override
  int starsFor(int score) => _stars + _lanterns ~/ 2 + (meters ~/ 120) + (_moonReached ? 5 : 0);

  @override
  void record(Profile profile, int score) => profile.recordLift(meters.floor());

  // ---------------------------------------------------------------- sky
  // Zones by height (world units; a unit is 10 m): sunset over the park,
  // above the clouds, nightfall, the aurora, and the moon.
  static const _zones = [
    (0.0, 'Sunset', (0.85, 0.38, 0.42), (0.14, 0.15, 0.44), 0.0),
    (_cloudSea + 1, 'Above the clouds', (0.95, 0.55, 0.38), (0.06, 0.1, 0.36), 0.1),
    (40.0, 'Night falls', (0.16, 0.08, 0.26), (0.008, 0.012, 0.05), 0.8),
    (62.0, 'The aurora', (0.04, 0.12, 0.14), (0.004, 0.008, 0.03), 1.4),
    (88.0, 'Reach for the moon', (0.05, 0.05, 0.12), (0.002, 0.003, 0.012), 2.0),
  ];

  void _applySky(double y) {
    var i = 0;
    while (i + 1 < _zones.length && y >= _zones[i + 1].$1) {
      i++;
    }
    final a = _zones[i];
    final b = _zones[math.min(i + 1, _zones.length - 1)];
    final k = identical(a, b) ? 0.0 : ((y - a.$1) / (b.$1 - a.$1)).clamp(0.0, 1.0);
    Vector4 mix((double, double, double) p, (double, double, double) q) =>
        Vector4(p.$1 + (q.$1 - p.$1) * k, p.$2 + (q.$2 - p.$2) * k, p.$3 + (q.$3 - p.$3) * k, 1);
    _sky.parameters
      ..setVec4('horizon_color', mix(a.$3, b.$3))
      ..setVec4('zenith_color', mix(a.$4, b.$4))
      ..setFloat('star_brightness', a.$5 + (b.$5 - a.$5) * k)
      ..setVec4('flash_color', Vector4(_flashColor.x, _flashColor.y, _flashColor.z, 0) * _flash)
      ..setVec4('flash_dir', Vector4(0, 0.3, 1, 0));
    // Clouds catch the sunset low and go moonlit blue high.
    final night = ((y - 30) / 25).clamp(0.0, 1.0);
    Vector4 lerp4(Vector4 p, Vector4 q, double t) => p + (q - p) * t;
    _cloud.parameters
      ..setVec4('lit_color', lerp4(Vector4(1.0, 0.8, 0.82, 1), Vector4(0.5, 0.56, 0.9, 1), night))
      ..setVec4('shade_color', lerp4(Vector4(0.62, 0.46, 0.74, 1), Vector4(0.08, 0.1, 0.25, 1), night));
    _farCloud.parameters
      ..setVec4('lit_color', lerp4(Vector4(0.95, 0.62, 0.62, 1), Vector4(0.2, 0.24, 0.48, 1), night))
      ..setVec4('shade_color', lerp4(Vector4(0.42, 0.3, 0.55, 1), Vector4(0.03, 0.04, 0.12, 1), night));
    final aurora = ((y - 50) / 14).clamp(0.0, 1.0);
    _aurora.parameters.setFloat('intensity', aurora * 1.6);
    _auroraNode.visible = aurora > 0;
    if (i > _zone) {
      _zone = i;
      banner(_zones[i].$2, sub: '${(y * 10).floor()} m', color: const [Color(0xFFFFB38A), Color(0xFFFFD6A0), Color(0xFFB9A8FF), Color(0xFF7DFFC4), Color(0xFFFFF1C4)][i]);
      screenFlash(const Color(0xFFFFF4E0), 0.35);
      final head = _lumi.headCenter;
      _vfx
        ..ring(head, radius: 3.2, color: Vector3(1.4, 1.2, 1.6), life: 0.8)
        ..burst(head, count: 40, speed: 4.5, color: Vector3(1.8, 1.5, 0.9), color2: Vector3(1.0, 1.4, 2.0), shape: VfxShape.flare, life: 1.0, gravity: 0.5);
      _lumi.react(LanternFace.wow, 0.9);
      Sfx.medium();
    }
  }

  // ---------------------------------------------------------------- frame
  @override
  void update(double dt, double time, {required bool playing}) {
    _sky.parameters.setFloat('time', time);
    _aurora.parameters.setFloat('time', time);
    _calloutTime -= dt;
    _flash = math.max(0, _flash - dt * 3);

    final thrusting = playing && _thrust && !_sunk && !_moonReached;
    if (playing && !_sunk && !_moonReached) {
      // Out of glow, holding only slows the fall: let go to recharge.
      final power = _glow > 0.02 ? 1.0 : 0.4;
      if (thrusting) {
        _vy += _thrustAccel * power * dt;
        _glow = math.max(0, _glow - 0.19 * dt);
      } else {
        _glow = math.min(1, _glow + 0.5 * dt);
      }
      _vy -= _gravity * dt;
      // Drag: rise briskly, fall gently, like something lighter than air.
      _vy = _vy.clamp(-2.8, 5.6);
      if (!thrusting && _vy < 0) _vy *= math.exp(-dt * 1.2);
    } else if (!playing) {
      _vy = 0;
    }
    final ax = (_targetX.clamp(-_halfWidth, _halfWidth) - _x) * 28 - _vx * 8;
    _vx += ax * dt;
    _x += _vx * dt;
    if (_x.abs() > _halfWidth) {
      _x = _x.clamp(-_halfWidth, _halfWidth);
      _vx *= -0.3;
    }
    _y = math.max(0, _y + _vy * dt);
    if (_y == 0 && _vy < 0) _vy = 0;

    // The burner roars while thrusting, softer out of glow.
    if (thrusting && _burner == null && !_burnerStarting) {
      _burnerStarting = true;
      Sfx.soundLoop('thrust_loop', volume: 0.55).then((v) {
        _burnerStarting = false;
        if (_burnerWanted) {
          _burner = v;
        } else {
          v?.stop();
        }
      });
    }
    _burnerWanted = thrusting;
    if (!thrusting && _burner != null) {
      _burner!.stop();
      _burner = null;
    }
    _burner?.volume = _glow > 0.02 ? 0.55 : 0.25;
    // Jet fire while thrusting: one plume per foot (or from the wisp),
    // angled a little against sideways travel, weaker when out of glow.
    if (thrusting) {
      final points = _lumi.jetPoints;
      final dir = Vector3((-_vx * 0.06).clamp(-0.4, 0.4), -1, 0)..normalize();
      final power = _glow > 0.02 ? 1.0 : 0.45;
      for (final p in points) {
        _vfx.jet(p, dir, dt, scale: points.length > 1 ? 1.3 : 1.8, power: power / points.length * 1.5, inherit: Vector3(_vx, _vy, 0));
      }
    }
    // Speed lines when climbing fast.
    _speedLines -= dt;
    if (_vy > 3.6 && _speedLines <= 0) {
      _speedLines = 0.02;
      final at = Vector3((_rng.nextDouble() * 2 - 1) * 3.4, _camY + 6, -3 + _rng.nextDouble() * 4);
      _vfx.streak(at, Vector3(0, -_vy * 4.5, 0), color: Vector3(0.7, 0.75, 0.9) * 0.35, width: 0.012, length: 0.05, life: 0.5);
    }
    _invuln = math.max(0, _invuln - dt);
    _punch = math.max(0, _punch - dt * 4);
    _streakTimer -= dt;
    if (_streakTimer <= 0) _streak = 0;

    final head = Vector3(_x, _y + 1.8, 0);
    final feet = Vector3(_x, _y + 0.4, 0);
    for (final c in _clouds) {
      c.step(dt);
      final d = feet - c.center;
      final w = 1.35 * c.size;
      if (d.x.abs() > w) {
        c.touched = false;
        continue;
      }
      if (c.storm) {
        // Anywhere on Lumi touching a storm cloud: a zap.
        final dh = head - c.center;
        final reach = 1.25 * c.size;
        final inX = (head.x - c.center.x).abs() < reach;
        final touching = inX && (dh.y.abs() < 0.9 * c.size || d.y.abs() < 0.5 * c.size || (d.y < 0 && dh.y > 0));
        if (touching && !c.touched && playing && _invuln <= 0) {
          c.touched = true;
          _invuln = 1.2;
          _streak = 0;
          _vy = -2.5;
          _glow = math.max(0, _glow - 0.25);
          _flash = 1;
          _flashColor.setValues(0.6, 0.7, 1.4);
          _shake.addTrauma(0.7);
          stop(0.12);
          screenFlash(const Color(0xFFB8CCFF), 0.8);
          _vfx
            ..bolt(c.center + Vector3(0, -0.2, -0.3), head + Vector3(0, 0, -0.3))
            ..burst(head, count: 26, speed: 3.5, color: Vector3(1.4, 1.7, 2.6), streaks: true, life: 0.5, gravity: 0);
          popup(head + Vector3(0, 0.8, 0), 'ZAP!', color: const Color(0xFFB8D4FF), size: 34);
          _lumi
            ..jolt(1.2)
            ..react(LanternFace.dizzy, 1.0);
          Sfx.heavy();
          Sfx.sound('zap');
        } else if (!touching) {
          // Slipping right past one is worth a little something.
          if (!c.touched && !c.closeCall && playing && dh.y.abs() < 0.9 && (head.x - c.center.x).abs() < reach + 0.35) {
            c.closeCall = true;
            popup(head + Vector3(0, 0.9, 0), 'Close call! +5', color: const Color(0xFF9FE8FF), size: 20);
            _bonus += 5;
          }
          c.touched = false;
        }
        continue;
      }
      // Soft clouds: land on top from above and bounce.
      if (_vy < 0 && d.y > -0.1 && d.y < 0.45 * c.size) {
        _vy = 7.4;
        _bounces++;
        _streak++;
        _streakTimer = 3.5;
        c.squash.velocity -= 6;
        _shake.addTrauma(0.3);
        _punch = 1;
        stop(0.05);
        final top = Vector3(feet.x, c.center.y + 0.25 * c.size, 0);
        _vfx
          ..ring(top, radius: 1.9, color: Vector3(1.5, 1.3, 1.4), life: 0.45, normal: Vector3(0, 1, 0))
          ..ring(top, radius: 1.2, color: Vector3(1.2, 1.0, 1.3), life: 0.3)
          ..puffs(top, count: 12, color: Vector3(0.55, 0.48, 0.55), size: 0.35)
          ..burst(top, count: 16 + _streak * 4, speed: 4, color: Vector3(2.0, 1.6, 0.9), color2: Vector3(1.6, 1.0, 1.8), shape: VfxShape.flare, life: 0.8, gravity: 4);
        _lumi
          ..jolt(1.0)
          ..react(LanternFace.delighted, 0.5);
        _glow = math.min(1, _glow + 0.12);
        _bonus += 2 * _streak;
        popup(top + Vector3(0, 0.4, 0), _streak > 1 ? 'BOING ×$_streak' : 'BOING', color: const Color(0xFFFFC8F0), size: 22.0 + math.min(_streak, 6) * 3);
        Sfx.medium();
        Sfx.sound('boing', pitch: math.pow(2, math.min(_streak - 1, 7) * 2 / 12).toDouble());
      }
    }
    for (final p in _pickups.toList()) {
      final wobble = p.lantern ? Vector3(math.sin(time * 1.3 + p.phase) * 0.12, math.sin(time * 0.9 + p.phase) * 0.1, 0) : Vector3.zero();
      final at = p.pos + wobble;
      p.node.localTransform = Matrix4.compose(
        at,
        p.lantern
            ? Quaternion.axisAngle(Vector3(0, 0, 1), math.sin(time * 1.1 + p.phase) * 0.12)
            : Quaternion.axisAngle(Vector3(0, 1, 0), time * 1.8),
        Vector3.all(1),
      );
      if ((at - head).length < 0.95 || (at - feet).length < 0.7) {
        p.node.detach();
        _pickups.remove(p);
        _lumi.react(LanternFace.delighted, 0.4);
        if (p.lantern) {
          _lanterns++;
          _glow = math.min(1, _glow + 0.45);
          _vy = math.max(_vy, 4.8);
          // The lantern bursts into fireflies that drift up.
          _vfx
            ..glow(at, size: 2.2, color: Vector3(2.0, 1.1, 0.4), life: 0.5)
            ..ring(at, radius: 1.4, color: Vector3(2.0, 1.2, 0.5), life: 0.4)
            ..burst(at, count: 34, speed: 1.6, color: Vector3(2.2, 1.4, 0.5), color2: Vector3(2.0, 0.9, 0.3), size: 0.06, life: 2.0, gravity: -0.6, drag: 1.0, shape: VfxShape.flare);
          screenFlash(const Color(0xFFFFC27A), 0.18);
          popup(at, '+10 GLOW', color: const Color(0xFFFFC27A), size: 22);
          Sfx.sound('glow_pickup');
        } else {
          _stars++;
          _vfx
            ..flare(at, size: 1.8, life: 0.4)
            ..ring(at, radius: 1.3, color: Vector3(2.0, 1.7, 0.9), life: 0.35)
            ..burst(at, count: 28, speed: 5, color: Vector3(2.0, 1.6, 0.7), streaks: true, life: 0.5, gravity: 2);
          stop(0.04);
          popup(at, '+25', color: const Color(0xFFFFE08A), size: 30);
          Sfx.sound('star_catch', pitch: 1.5);
        }
        Sfx.light();
      }
    }
    if (_y > _best && (_y * 10 ~/ 100) > _milestone) {
      _milestone = (_y * 10 ~/ 100);
      popup(head + Vector3(0.9, 0.2, 0), '${_milestone * 100} m', color: const Color(0xFFE8F0FF), size: 18);
    }
    _best = math.max(_best, _y);
    _lumi.place(Vector3(_x, _y, 0), (_vx * 0.05).clamp(-0.4, 0.4));
    _lumi.glowScale = 0.75 + (thrusting ? 0.6 : 0) + 0.2 * _glow;
    if (_lumi.mood != LanternMood.delighted) {
      _lumi.lookAtWorld(head + Vector3(_vx * 0.4, 3, 0));
    }

    // The moon.
    if (!_moonReached && _y > _moonY - 3) {
      _moonReached = true;
      _moonTime = 0;
      _flash = 1.4;
      _flashColor.setValues(1.0, 0.9, 0.6);
      _lumi
        ..celebrate()
        ..burstAt(head, count: 40);
      _shake.addTrauma(0.4);
      stop(0.25);
      screenFlash(const Color(0xFFFFF4D6), 0.9);
      banner('You reached the moon!', sub: 'Fireworks for you', color: const Color(0xFFFFF1C4), sound: 'moon_fanfare');
      _vfx.ring(head, radius: 6, color: Vector3(2, 1.8, 1.2), life: 1.0);
      // A fireworks salvo around the moon.
      const kinds = [BurstKind.peony, BurstKind.chrysanthemum, BurstKind.ring, BurstKind.willow, BurstKind.crossette, BurstKind.palm];
      final colors = [Vector3(1.0, 0.45, 0.8), Vector3(0.4, 0.8, 1.0), Vector3(1.0, 0.8, 0.3), Vector3(0.5, 1.0, 0.6), Vector3(0.8, 0.5, 1.0), Vector3(1.0, 0.5, 0.3)];
      final moon = _moon.localTransform.getTranslation();
      for (var i = 0; i < 14; i++) {
        final a = i * 2.4;
        _launches.add(
          Launch(
            time: 0.1 + i * 0.28,
            pad: moon + Vector3(math.cos(a) * 6, -14, -8 + math.sin(a) * 3),
            breakAt: moon + Vector3(math.cos(a) * (5 + i % 3 * 2.5), math.sin(a * 1.3) * 5 + 2, -10 + (i % 4) * 2.0),
            kind: kinds[i % kinds.length],
            color: colors[i % colors.length],
            pistil: i % 3 == 0 ? Vector3(1, 1, 0.9) : null,
            size: 0.35 + (i % 3) * 0.08,
            ascent: 0.9,
            seed: 31 + i * 7,
          ),
        );
      }
      Sfx.heavy();
    }
    if (_moonTime >= 0) _moonTime += dt;
    _fireworks.evaluate(_launches, math.max(0, _moonTime), camera.position);

    // The camera leads upward and never sinks; falling out of view ends it.
    // The camera leads the climb and follows a fall more slowly.
    final lead = _y + 2.6 + math.max(0, _vy) * 0.25;
    _camY += (lead - _camY) * math.min(1, dt * (lead > _camY ? 6 : 1.4));
    final jitter = _shake.update(dt).toMatrix4().getTranslation();
    camera
      ..position = Vector3(jitter.x, _camY + jitter.y, -15)
      ..target = Vector3(jitter.x * 4, _camY + 0.8 + jitter.y * 4, 0)
      ..fovRadiansY = (46 - 3.5 * _punch * _punch) * degrees2Radians;
    // Falling a long way ends the round; a short fall can be recovered.
    if (playing && _y < _best - 12) _sunk = true;
    _vfx.update(dt, camera);

    // The moon hangs above the whole climb as the goal, sinking into view
    // and growing as Lumi gets closer.
    final p = (_y / _moonY).clamp(0.0, 1.0);
    _moon.localTransform = Matrix4.compose(
      Vector3(4 - 2 * p, _camY + 17 - 9 * p, 40),
      Quaternion.identity(),
      Vector3.all(0.35 + 0.75 * p * p),
    );

    while (_nextLevel < _camY + 16) {
      _addLevel();
    }
    _clouds.removeWhere((c) {
      if (c.center.y < _best - 16) {
        c.node.detach();
        return true;
      }
      return false;
    });
    _pickups.removeWhere((p) {
      if (p.pos.y < _best - 16) {
        p.node.detach();
        return true;
      }
      return false;
    });
    _stockFar();
    _applySky(_y);
  }
}

class _Cloud {
  _Cloud(this.node, this.puffs, this.center, this.size, this.storm);
  final Node node;
  final Node puffs;
  final Vector3 center;
  final double size;
  final bool storm;
  bool touched = false;
  bool closeCall = false;

  /// Squash when bounced on: springs back with a wobble.
  final squash = _Spring();

  void step(double dt) {
    squash.step(dt);
    final s = squash.position * 0.12;
    puffs.localTransform = Matrix4.compose(Vector3(0, s * 0.6, 0), Quaternion.identity(), Vector3(1 - s * 0.6, 1 + s, 1 - s * 0.6));
  }
}

class _Spring {
  double position = 0, velocity = 0;

  void step(double dt) {
    final a = -position * 160 - velocity * 9;
    velocity += a * dt;
    position += velocity * dt;
  }
}

class _Pickup {
  _Pickup(this.node, this.pos, {required this.lantern, required this.phase});
  final Node node;
  final Vector3 pos;
  final bool lantern;
  final double phase;
}
