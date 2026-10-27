import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../app/scene_clock.dart';
import '../app/clock.dart';
import '../app/profile_scope.dart';
import '../app/sfx.dart';
import '../games/shapes.dart';
import '../lantern/character.dart';
import '../lantern/friends.dart';
import '../lantern/moods.dart';
import '../lantern/themes.dart';
import '../lantern/wardrobe.dart';
import '../room/room.dart';
import '../show/fireworks.dart';
import '../ui/palette.dart';

/// Where the photo is taken.
enum Backdrop {
  fireworks('Fireworks'),
  moon('Moon'),
  aurora('Aurora'),
  room('Room');

  const Backdrop(this.label);
  final String label;
}

/// How the friend poses.
enum Pose {
  happy('Happy', LanternMood.happy),
  cheer('Cheer', LanternMood.cheer),
  wow('Wow', LanternMood.watch),
  cozy('Cozy', LanternMood.content),
  wave('Wave', LanternMood.awake),
  silly('Silly', LanternMood.dizzy);

  const Pose(this.label, this.mood);
  final String label;
  final LanternMood mood;
}

/// The photo booth: pick a backdrop, a pose, and a hat, then take the shot.
/// A countdown, a flash, and the picture drops into a polaroid card with
/// your friend's name, the date, and a park stamp, ready to save and share.
class PhotoBoothScreen extends StatefulWidget {
  const PhotoBoothScreen({super.key});

  @override
  State<PhotoBoothScreen> createState() => PhotoBoothScreenState();
}

class PhotoBoothScreenState extends State<PhotoBoothScreen> {
  final Scene scene = Scene();
  final PerspectiveCamera camera = PerspectiveCamera(
    fovRadiansY: 34 * vm.degrees2Radians,
    position: vm.Vector3(0, 1.75, -9.0),
    target: vm.Vector3(0, 1.55, 0),
  );
  LanternCharacter? lumi;
  Backdrop backdrop = Backdrop.fireworks;
  Pose pose = Pose.happy;
  final _shot = GlobalKey();
  final _card = GlobalKey();
  double _time = 0;
  int? _count;
  double _flash = 0;
  ui.Image? photo;
  String? saved;

  // Backdrop pieces.
  Node? _set;
  PreprocessedSky? _sky;
  FireworkRenderer? _fireworks;
  final List<Launch> _launches = [];
  double _nextLaunch = 0;
  FriendRoom? _room;
  PreprocessedMaterial? _aurora;
  final _rng = math.Random(31);

  @override
  void initState() {
    super.initState();
    scene
      ..debugCheckCoplanarOverlaps = false
      ..environmentIntensity = 1.0;
    scene.postProcess.bloom
      ..enabled = true
      ..threshold = 0.95
      ..intensity = 0.42;
    _load();
  }

  @override
  void dispose() {
    scene.removeAll();
    super.dispose();
  }

  Future<void> _load() async {
    final p = ProfileScope.read(context);
    final c = await LanternCharacter.load(scene, friend: Friends.byId(p.friend));
    if (!mounted) return;
    c
      ..canDoze = false
      ..idleAntics = false
      ..glowScale = p.glow
      ..hueShift = p.hueShift;
    c.setTheme(LanternTheme.all.firstWhere((t) => t.name == p.theme, orElse: () => LanternTheme.aurora));
    c.wake();
    await c.wear(hat: p.hat, scarf: p.scarf);
    _sky = await loadFmatSky('assets/show/lagoon_sky.fmat');
    scene.skybox = Skybox(_sky!);
    final fw = await Future.wait([loadFmatMaterial('assets/show/firework.fmat'), loadFmatMaterial('assets/show/smoke.fmat')]);
    _fireworks = FireworkRenderer(lightMaterial: fw[0], smokeMaterial: fw[1], trailSamples: 6);
    scene
      ..add(_fireworks!.lightNode)
      ..add(_fireworks!.smokeNode);
    await _setBackdrop(backdrop);
    await scene.warmUp([RenderView(camera: camera)], includeOffscreen: true);
    if (!mounted) return;
    setState(() => lumi = c);
    _setPose(pose);
  }

  Future<void> _setBackdrop(Backdrop b) async {
    backdrop = b;
    _set?.detach();
    _room?.root.detach();
    _room = null;
    _launches.clear();
    final set = Node(name: 'Backdrop');
    final sky = _sky!;
    final ball = SphereGeometry(radius: 1, segments: 32, rings: 16);
    switch (b) {
      case Backdrop.fireworks:
        sky.parameters
          ..setVec4('horizon_color', vm.Vector4(0.1, 0.06, 0.2, 1))
          ..setVec4('zenith_color', vm.Vector4(0.005, 0.01, 0.03, 1))
          ..setFloat('star_brightness', 1.2);
        final water = await loadFmatMaterial('assets/show/water.fmat');
        final lake = Node(mesh: Mesh(PlaneGeometry(width: 300, depth: 300), water), localTransform: vm.Matrix4.translation(vm.Vector3(0, 0.25, 0)));
        lake.addComponent(PlanarReflectorComponent(resolutionScale: 0.5));
        set.add(lake);
      case Backdrop.moon:
        sky.parameters
          ..setVec4('horizon_color', vm.Vector4(0.62, 0.32, 0.48, 1))
          ..setVec4('zenith_color', vm.Vector4(0.08, 0.06, 0.22, 1))
          ..setFloat('star_brightness', 0.6);
        final moon = await loadFmatMaterial('assets/games/moon.fmat');
        moon.parameters.setFloat('brightness', 1.1);
        set.add(Node(mesh: Mesh(ball, moon), localTransform: vm.Matrix4.compose(vm.Vector3(1.6, 3.2, 14), vm.Quaternion.identity(), vm.Vector3.all(3.2))));
        final cloud = await loadFmatMaterial('assets/games/cloud.fmat');
        cloud.parameters
          ..setVec4('lit_color', vm.Vector4(1.0, 0.78, 0.84, 1))
          ..setVec4('shade_color', vm.Vector4(0.45, 0.3, 0.55, 1));
        for (var i = 0; i < 16; i++) {
          final x = -4 + i * 0.55 + _rng.nextDouble() * 0.3;
          final s = 0.5 + _rng.nextDouble() * 0.6;
          set.add(Node(mesh: Mesh(ball, cloud), localTransform: vm.Matrix4.compose(vm.Vector3(x, 0.1 + _rng.nextDouble() * 0.4, 2 + _rng.nextDouble() * 2), vm.Quaternion.identity(), vm.Vector3(s, s * 0.6, s))));
        }
      case Backdrop.aurora:
        sky.parameters
          ..setVec4('horizon_color', vm.Vector4(0.03, 0.1, 0.12, 1))
          ..setVec4('zenith_color', vm.Vector4(0.003, 0.006, 0.02, 1))
          ..setFloat('star_brightness', 1.8);
        _aurora = await loadFmatMaterial('assets/games/aurora.fmat');
        _aurora!.parameters.setFloat('intensity', 1.5);
        for (final (x, z, w, yaw) in const [(-4.0, 16.0, 30.0, 0.2), (6.0, 22.0, 34.0, -0.25)]) {
          set.add(Node(
            mesh: Mesh(PlaneGeometry(width: w, depth: 12), _aurora!),
            localTransform: vm.Matrix4.compose(
              vm.Vector3(x, 6, z),
              vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw) * vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -math.pi / 2),
              vm.Vector3.all(1),
            ),
          ));
        }
        final gold = await loadFmatMaterial('assets/ember.fmat');
        gold.parameters
          ..setVec4('ember_color', vm.Vector4(1.0, 0.8, 0.4, 1))
          ..setFloat('intensity', 3);
        final star = starGeometry(radius: 0.12, depth: 0.05);
        for (var i = 0; i < 7; i++) {
          final a = i / 7 * math.pi * 2;
          set.add(Node(mesh: Mesh(star, gold), localTransform: vm.Matrix4.translation(vm.Vector3(math.cos(a) * 1.25, 1.4 + math.sin(a) * 1.0, 0.3))));
        }
      case Backdrop.room:
        sky.parameters
          ..setVec4('horizon_color', vm.Vector4(0.08, 0.08, 0.2, 1))
          ..setVec4('zenith_color', vm.Vector4(0.02, 0.02, 0.06, 1));
        final p = ProfileScope.read(context);
        final room = await FriendRoom.build(profile: p, friendName: lumi?.friend.name ?? 'Lumi', onParty: () => lumi?.celebrate());
        room.update(1, 0, camera.position);
        scene.add(room.root);
        _room = room;
    }
    scene.add(set);
    _set = set;
    if (mounted) setState(() {});
  }

  /// For clips: pick a backdrop or a pose as a tap would.
  Future<void> pickBackdrop(Backdrop b) => _setBackdrop(b);
  void pickPose(Pose p) => _setPose(p);

  void _setPose(Pose p) {
    pose = p;
    final c = lumi;
    if (c == null) return;
    c.reachTarget = null;
    c.restMood = p.mood.loops ? p.mood : LanternMood.awake;
    c.setMood(p.mood);
    if (p == Pose.wow) c.react(LanternFace.wow, 30);
    if (p == Pose.cheer) c.burstAt(c.headCenter, count: 20);
    setState(() {});
  }

  void _tick(Duration elapsed, double dt) {
    final c = lumi;
    if (c == null) return;
    _time += dt;
    // Fireworks keep going behind, for the fireworks backdrop.
    if (backdrop == Backdrop.fireworks && _time > _nextLaunch) {
      _nextLaunch = _time + 0.7 + _rng.nextDouble() * 0.8;
      const kinds = [BurstKind.peony, BurstKind.chrysanthemum, BurstKind.willow, BurstKind.ring, BurstKind.palm];
      final colors = [vm.Vector3(1.0, 0.45, 0.8), vm.Vector3(0.4, 0.8, 1.0), vm.Vector3(1.0, 0.8, 0.3), vm.Vector3(0.5, 1.0, 0.6), vm.Vector3(0.8, 0.5, 1.0)];
      final x = (_rng.nextDouble() - 0.5) * 30;
      _launches.add(Launch(
        time: _time,
        pad: vm.Vector3(x, 0, 50),
        breakAt: vm.Vector3(x + (_rng.nextDouble() - 0.5) * 6, 10 + _rng.nextDouble() * 9, 50 + _rng.nextDouble() * 10),
        kind: kinds[_rng.nextInt(kinds.length)],
        color: colors[_rng.nextInt(colors.length)],
        size: 0.7 + _rng.nextDouble() * 0.4,
        ascent: 1.2,
        seed: _rng.nextInt(100000),
      ));
      _launches.removeWhere((l) => _time - l.time > 9);
    }
    _fireworks?.evaluate(_launches, _time, camera.position);
    _aurora?.parameters.setFloat('time', _time);
    _sky?.parameters.setFloat('time', _time);
    _room?.update(1, _time, camera.position, feet: c.restFeet, dt: dt);
    if (pose == Pose.wave) {
      final w = math.sin(_time * 9);
      c.reachTarget = c.headCenter + vm.Vector3(-0.85 - 0.2 * w, 0.45 + 0.1 * w.abs(), -0.3);
    }
    if (pose == Pose.silly && c.mood != LanternMood.dizzy) c.setMood(LanternMood.dizzy);
    _flash = math.max(0, _flash - dt * 2.5);
    c.update(dt, _time);
    setState(() {});
  }

  /// Three, two, one, flash: the photo is taken from the 3D view alone.
  Future<void> shoot() async {
    if (_count != null || lumi == null) return;
    for (var n = 3; n >= 1; n--) {
      setState(() => _count = n);
      Sfx.tick();
      Sfx.sound('countdown');
      await AppClock.delay(const Duration(milliseconds: 650));
      if (!mounted) return;
    }
    setState(() => _count = null);
    _setPose(pose);
    await AppClock.delay(const Duration(milliseconds: 220));
    final boundary = _shot.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    final image = await boundary?.toImage(pixelRatio: 2);
    _flash = 1;
    Sfx.heavy();
    Sfx.sound('shutter');
    if (!mounted) return;
    setState(() {
      photo = image;
      saved = null;
    });
  }

  /// Saves the polaroid card as a PNG.
  Future<void> save() async {
    final boundary = _card.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    final image = await boundary?.toImage(pixelRatio: 3);
    final bytes = await image?.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final name = lumi?.friend.name.toLowerCase() ?? 'lumi';
    final file = File('${Directory.systemTemp.path}/parkday_${name}_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    if (mounted) setState(() => saved = file.path);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final p = ProfileScope.of(context);
    final c = lumi;
    final hats = [for (final a in Wardrobe.hats) if (a.unlocked(p)) a];
    return Scaffold(
      backgroundColor: Park.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null)
            RepaintBoundary(key: _shot, child: appSceneView(scene, camera: camera, onTick: _tick))
          else
            const Center(child: CircularProgressIndicator(color: Park.glow)),
          // A thin frame and corner marks, like a viewfinder.
          IgnorePointer(child: CustomPaint(painter: _Viewfinder())),
          Positioned(
            top: pad.top + 8,
            left: 8,
            right: 8,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
                const Expanded(
                  child: Text('Photo booth', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          if (_count case final n?)
            Center(
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(n),
                  tween: Tween(begin: 1.6, end: 1.0),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  builder: (_, s, _) => Transform.scale(
                    scale: s,
                    child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 110, fontWeight: FontWeight.w900, shadows: [Shadow(color: Color(0xAA000000), blurRadius: 24)])),
                  ),
                ),
              ),
            ),
          // The controls.
          if (c != null && photo == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 14, 16, pad.bottom + 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00070A15), Color(0xE6070A15), Color(0xFF070A15)], stops: [0, 0.35, 1]),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _chips([for (final b in Backdrop.values) (b.label, b == backdrop, () => _setBackdrop(b))]),
                    const SizedBox(height: 8),
                    _chips([for (final q in Pose.values) (q.label, q == pose, () => _setPose(q))]),
                    const SizedBox(height: 8),
                    _chips([
                      ('No hat', p.hat == null, () => p.wear(clearHat: true)),
                      for (final h in hats) (h.name, p.hat == h.id, () => p.wear(hat: h.id)),
                    ]),
                    const SizedBox(height: 14),
                    Semantics(
                      button: true,
                      label: 'Take the photo',
                      child: GestureDetector(
                        onTap: shoot,
                        child: Container(
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          padding: const EdgeInsets.all(5),
                          child: Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // The flash.
          if (_flash > 0.01) IgnorePointer(child: ColoredBox(color: Colors.white.withValues(alpha: _flash.clamp(0.0, 1.0)))),
          // The polaroid.
          if (photo case final img?) _polaroid(img, c!, pad),
        ],
      ),
    );
  }

  Widget _chips(List<(String, bool, VoidCallback)> items) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (label, on, tap) in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: tap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: on ? Park.button : const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(label, style: TextStyle(color: on ? Park.onLight : Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _polaroid(ui.Image img, LanternCharacter c, EdgeInsets pad) {
    final now = AppClock.now;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xCC03050C),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutBack,
              builder: (_, t, child) => Transform.translate(
                offset: Offset(0, (1 - t) * 300),
                child: Transform.rotate(angle: (1 - t) * 0.3 - 0.04, child: child),
              ),
              child: RepaintBoundary(
                key: _card,
                child: Container(
                  width: 290,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBF7EF),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 14))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 0.82,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: img.width.toDouble(), height: img.height.toDouble(), child: RawImage(image: img))),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${c.friend.name} & me', style: const TextStyle(color: Color(0xFF1B2340), fontSize: 20, fontWeight: FontWeight.w800)),
                                Text('${backdrop.label} · ${months[now.month - 1]} ${now.day}, ${now.year}', style: const TextStyle(color: Color(0xFF6D7593), fontSize: 12.5)),
                              ],
                            ),
                          ),
                          // The park stamp.
                          Transform.rotate(
                            angle: -0.22,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFD9534F), width: 2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Column(
                                children: [
                                  Text('PARKDAY', style: TextStyle(color: Color(0xFFD9534F), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                                  Text('LAGOON', style: TextStyle(color: Color(0xFFD9534F), fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 2)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => photo = null),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Park.line)),
                  child: const Text('Retake'),
                ),
                // The web has no file system to save the card to.
                if (!kIsWeb) ...[
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: save,
                    style: FilledButton.styleFrom(backgroundColor: Park.gold, foregroundColor: Park.onLight),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Save card'),
                  ),
                ],
              ],
            ),
            if (saved case final path?)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Saved to $path', textAlign: TextAlign.center, style: const TextStyle(color: Park.inkMuted, fontSize: 11.5)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Viewfinder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const m = 22.0, l = 26.0;
    final top = size.height * 0.12, bottom = size.height * 0.62;
    for (final (x, y, dx, dy) in [(m, top, 1.0, 1.0), (size.width - m, top, -1.0, 1.0), (m, bottom, 1.0, -1.0), (size.width - m, bottom, -1.0, -1.0)]) {
      canvas.drawLine(Offset(x, y), Offset(x + l * dx, y), p);
      canvas.drawLine(Offset(x, y), Offset(x, y + l * dy), p);
    }
  }

  @override
  bool shouldRepaint(_Viewfinder old) => false;
}
