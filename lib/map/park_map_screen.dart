import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/material.dart' as m show Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../app/scene_clock.dart';
import '../app/clock.dart';
import '../app/profile_scope.dart';
import '../app/sfx.dart';
import '../lantern/character.dart';
import '../lantern/friends.dart';
import '../lantern/moods.dart';
import '../lantern/themes.dart';
import '../vfx/shadow.dart';
import '../vfx/vfx.dart';
import 'park_diorama.dart';

/// One ride on the map.
class Ride {
  Ride(this.name, this.at, int wait) : wait = ValueNotifier(wait);
  final String name;
  final vm.Vector3 at;
  final ValueNotifier<int> wait;
  final highlighted = ValueNotifier(false);
  final here = ValueNotifier(false);
}

/// The park as a little 3D diorama floating on a mirror lagoon, with live
/// Flutter cards standing over every ride.
///
/// The cards are real widgets rendered into the scene (wait times tick,
/// buttons press), and tapping Go sends your friend hopping along the
/// paths to that ride. Your friend also suggests the shortest wait.
class ParkMapScreen extends StatefulWidget {
  const ParkMapScreen({super.key, this.chrome = true, this.holdZoom});

  /// Whether to show the title, close button, and suggestion sheet (off for
  /// rendering the card art).
  final bool chrome;

  /// Pins the camera's zoom (0 is the whole island, 1 is close on a ride).
  final double? holdZoom;

  @override
  State<ParkMapScreen> createState() => ParkMapScreenState();
}

class ParkMapScreenState extends State<ParkMapScreen> {
  final Scene scene = Scene();
  final PerspectiveCamera camera = PerspectiveCamera(fovRadiansY: 40 * vm.degrees2Radians);
  LanternCharacter? lumi;
  late Vfx _vfx;
  final _rng = math.Random(4);

  final rides = [
    Ride('Sky Coaster', vm.Vector3(-3.0, 0, 2.2), 25),
    Ride('River Run', vm.Vector3(3.1, 0, 2.6), 10),
    Ride('Star Swing', vm.Vector3(-2.3, 0, -1.6), 5),
    Ride('Moon Drop', vm.Vector3(2.7, 0, -1.2), 40),
    Ride('Tidal Twist', vm.Vector3(0.2, 0, 4.0), 15),
    Ride('Comet Carousel', vm.Vector3(-0.2, 0, 0.9), 20),
  ];
  static final _gate = vm.Vector3(0, 0, -3.6);

  // Where the friend is and where it is hopping to.
  final vm.Vector3 _pos = _gate.clone();
  final List<vm.Vector3> _route = [];
  double _hopT = 0;
  vm.Vector3 _hopFrom = _gate.clone();
  double _yaw = 0;
  Ride? _goingTo;
  Ride? _at;

  // Camera: a gentle orbit you can drag.
  double _orbit = 0.0;
  double _orbitVel = 0;
  final vm.Vector3 _focus = vm.Vector3(0, 0.6, 0.3);
  double _zoom = 0;

  final List<(Node, double)> _signs = [];
  Timer? _ticker;
  bool _ready = false;
  double _time = 0;

  /// Where a ride's card is on screen, for clips that tap it.
  Offset? signOnScreen(Ride r, Size size) {
    for (final (n, _) in _signs) {
      if (n.name == 'Sign:${r.name}') return camera.worldToScreen(n.globalTransform.getTranslation(), size);
    }
    return null;
  }

  /// Whether the friend is hopping somewhere, or a card is still turning.
  bool get travelling => _route.isNotEmpty || _flip.isNotEmpty;

  Ride get pick => rides.reduce((a, b) => a.wait.value <= b.wait.value ? a : b);

  @override
  void initState() {
    super.initState();
    scene
      ..debugCheckCoplanarOverlaps = false
      ..environmentIntensity = 0.4;
    // A storybook grade: richer color, a touch more contrast, a hair cool,
    // a soft vignette, and a glow round every bulb.
    scene.postProcess
      ..bloom.enabled = true
      ..bloom.threshold = 0.95
      ..bloom.intensity = 0.42
      ..bloom.scatter = 0.75
      ..colorGrading.enabled = true
      ..colorGrading.saturation = 1.18
      ..colorGrading.contrast = 1.14
      ..colorGrading.brightness = 1.04
      ..colorGrading.temperature = -0.02
      ..vignette.enabled = true
      ..vignette.intensity = 0.32
      ..vignette.radius = 0.8
      ..vignette.smoothness = 0.55;
    _load();
    // Wait times drift like the real thing.
    _ticker = AppClock.periodic(const Duration(milliseconds: 2600), (_) {
      final r = rides[_rng.nextInt(rides.length)];
      r.wait.value = (r.wait.value + (_rng.nextBool() ? 5 : -5)).clamp(5, 60);
      _highlightPick();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    scene.removeAll();
    super.dispose();
  }

  Future<void> _load() async {
    final p = ProfileScope.read(context);
    final friend = Friends.byId(p.friend);
    _vfx = await Vfx.create(scene);
    _shadow = await ContactShadow.create(scene, opacity: 0.5);
    _diorama = await ParkDiorama.build(scene, [for (final r in rides) r.at], _gate);

    // A live card over every ride.
    for (final r in rides) {
      final sign = Node(name: 'Sign:${r.name}')
        ..addComponent(
          WidgetComponent(
            size: const Size(230, 92),
            pixelRatio: 2.5,
            worldHeight: 0.8,
            child: _RideCard(ride: r, onGo: () => goTo(r)),
          ),
        );
      scene.add(sign);
      _signs.add((sign, r.name == 'Moon Drop' ? 2.85 : (r.name == 'Star Swing' ? 2.35 : 1.95)));
    }

    // The friend, at the gate.
    final c = await LanternCharacter.load(scene, friend: friend);
    c
      ..grounded = true
      ..canDoze = false
      ..idleAntics = false
      ..glowScale = p.glow
      ..hueShift = p.hueShift;
    c.setTheme(LanternTheme.all.firstWhere((t) => t.name == p.theme, orElse: () => LanternTheme.aurora));
    c.wake();
    await c.wear(hat: p.hat, scarf: p.scarf);
    _place(c, 0);
    _highlightPick();
    _updateCamera(0);
    await scene.warmUp([RenderView(camera: camera)], includeOffscreen: true);
    if (!mounted) return;
    setState(() {
      lumi = c;
      _ready = true;
    });
  }

  late ContactShadow _shadow;
  double _pin = 0;

  /// Cards turning over: a full spin that lands on the new side.
  final Map<Ride, double> _flip = {};

  late ParkDiorama _diorama;

  /// The friend's scale on the map: a tiny figure on a tiny park.
  static const _mapScale = 0.46;

  void _place(LanternCharacter c, double hop) {
    c.place(vm.Vector3(_pos.x, _pos.y + hop, _pos.z), _yaw, scale: _mapScale);
  }

  void _highlightPick() {
    final best = pick;
    for (final r in rides) {
      r.highlighted.value = r == best;
    }
    if (mounted) setState(() {});
  }

  @visibleForTesting
  vm.Vector3 get positionForTest => _pos;

  @visibleForTesting
  double get yawForTest => _yaw;

  /// [a] wrapped into -pi to pi, so a turn always goes the short way.
  static double _turn(double a) {
    while (a > math.pi) {
      a -= math.pi * 2;
    }
    while (a < -math.pi) {
      a += math.pi * 2;
    }
    return a;
  }

  /// Replaces the plaza's center (the fountain) in [pts] with an arc round
  /// the basin: in on the side the path arrives from, out on the side it
  /// leaves by, the short way round.
  static List<vm.Vector3> _aroundFountain(List<vm.Vector3> pts) {
    const r = 0.72;
    final c = ParkDiorama.hub;
    final out = <vm.Vector3>[];
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      if ((p - c).length > 0.01 || i == 0 || i == pts.length - 1) {
        out.add(p);
        continue;
      }
      final a0 = math.atan2(pts[i - 1].z - c.z, pts[i - 1].x - c.x);
      var a1 = math.atan2(pts[i + 1].z - c.z, pts[i + 1].x - c.x);
      while (a1 - a0 > math.pi) {
        a1 -= math.pi * 2;
      }
      while (a1 - a0 < -math.pi) {
        a1 += math.pi * 2;
      }
      final steps = math.max(1, ((a1 - a0).abs() / 0.35).ceil());
      for (var k = 0; k <= steps; k++) {
        final a = a0 + (a1 - a0) * k / steps;
        out.add(c + vm.Vector3(math.cos(a) * r, 0, math.sin(a) * r));
      }
    }
    return out;
  }

  /// Sends the friend hopping along the paths to [ride]: back to the gate
  /// if it is at another ride, then out along that ride's path.
  void goTo(Ride ride) {
    final c = lumi;
    if (c == null || ride == _goingTo || ride == _at) return;
    // Follow the cobbled paths: back to the plaza from where it is, then out
    // along the path to the ride, in hop-sized steps.
    _route.clear();
    List<vm.Vector3> walk(List<vm.Vector3> pts) {
      final path = CatmullRomPath(pts);
      final n = math.max(2, (path.length / 0.42).round());
      return [for (var k = 1; k <= n; k++) path.positionAtDistance(path.length * k / n)..y = 0];
    }

    int hub(List<vm.Vector3> r) => r.indexWhere((p) => (p - ParkDiorama.hub).length < 0.01);
    final to = _diorama.routes[rides.indexOf(ride)];
    final List<vm.Vector3> pts;
    if (_at != null) {
      final from = _diorama.routes[rides.indexOf(_at!)];
      pts = [_pos.clone(), ...from.sublist(hub(from)).reversed, ...to.sublist(hub(to) + 1)];
    } else {
      pts = [_pos.clone(), ...to.skip(1)];
    }
    _route.addAll(walk(_aroundFountain(pts)));
    for (final r in rides) {
      r.here.value = false;
    }
    _at = null;
    _goingTo = ride;
    _hopFrom = _pos.clone();
    _hopT = 0;
    c.setMood(LanternMood.awake);
    c.react(LanternFace.delighted, 0.6);
    Sfx.light();
    Sfx.sound('chirp_happy');
    setState(() {});
  }

  void _tick(Duration elapsed, double dt) {
    final c = lumi;
    if (c == null) return;
    _time += dt;
    _diorama.update(_time, dt, _vfx);

    // Hop along the route: a string of little parabolic hops.
    var hop = 0.0;
    if (_route.isNotEmpty) {
      final target = _route.first;
      final leg = target - _hopFrom;
      final legLen = leg.length;
      const hopLen = 0.42;
      final hops = math.max(1, (legLen / hopLen).round());
      _hopT += dt * 2.4;
      final u = (_hopT / hops).clamp(0.0, 1.0);
      _pos.setFrom(_hopFrom + leg * u);
      final f = _hopT - _hopT.floorToDouble();
      hop = 4 * 0.16 * f * (1 - f);
      if ((_hopT * 1.0).floor() != ((_hopT - dt * 2.4)).floor()) {
        c.jolt(0.35);
        _vfx.puffs(_pos + vm.Vector3(0, 0.02, 0), count: 3, color: vm.Vector3(0.3, 0.28, 0.25), size: 0.06, life: 0.5, speed: 0.4);
        Sfx.sound('map_step', pitch: 0.92 + _rng.nextDouble() * 0.16, volume: 0.8);
      }
      // Face along the leg: the face looks down -z, so a turn of yaw sends it
      // toward (-sin yaw, -cos yaw). Turn the short way round.
      _yaw += _turn(math.atan2(-leg.x, -leg.z) - _yaw) * math.min(1, dt * 10);
      if (u >= 1) {
        _route.removeAt(0);
        _hopFrom = _pos.clone();
        _hopT = 0;
        if (_route.isEmpty) _arrive();
      }
    } else {
      _yaw += _turn(0 - _yaw) * math.min(1, dt * 3);
    }
    _place(c, hop);
    _shadow.place(vm.Vector3(_pos.x, 0.03, _pos.z), radius: 0.26, height: hop * 4);
    // A pulsing ring marks where your friend is, like a pin on a map.
    _pin -= dt;
    if (_pin <= 0) {
      _pin = 1.1;
      _vfx.ring(vm.Vector3(_pos.x, 0.05, _pos.z), radius: 0.75, start: 0.15, color: vm.Vector3(0.6, 1.4, 2.2), life: 1.0, normal: vm.Vector3(0, 1, 0));
    }
    c.update(dt, _time);

    // Signs face the camera and bob a little.
    for (final (n, h) in _signs) {
      final r = rides.firstWhere((r) => 'Sign:${r.name}' == n.name);
      final at = r.at + vm.Vector3(0, h + math.sin(_time * 1.6 + r.at.x) * 0.03, 0);
      final toCam = camera.position - at;
      var yaw = math.atan2(toCam.x, toCam.z);
      // A card that is turning over spins once and lands on its new side;
      // the new side shows from the halfway point.
      if (_flip[r] case final t?) {
        final nt = math.min(1.0, t + dt / 0.7);
        _flip[r] = nt;
        yaw += math.pi * 2 * Curves.easeInOutCubic.transform(nt);
        if (t < 0.5 && nt >= 0.5) {
          r.here.value = true;
          _vfx
            ..ring(at, radius: 0.9, color: vm.Vector3(0.8, 2.0, 1.1), life: 0.4)
            ..burst(at, count: 18, speed: 1.6, size: 0.04, color: vm.Vector3(0.8, 2.0, 1.1), shape: VfxShape.flare, life: 0.6, gravity: 1);
        }
        if (nt >= 1) _flip.remove(r);
      }
      // The card's visible face points down -z; turn it to the camera and
      // mirror it so the text reads the right way round.
      n.localTransform = vm.Matrix4.compose(at, vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw + math.pi), vm.Vector3(-1, 1, 1));
    }
    _updateCamera(dt);
    _vfx.update(dt, camera);
  }

  void _arrive() {
    final c = lumi!;
    final r = _goingTo!;
    _at = r;
    _goingTo = null;
    _flip[r] = 0;
    c.celebrate();
    final head = c.headCenter;
    _vfx
      ..ring(r.at + vm.Vector3(0, 0.05, 0), radius: 1.0, normal: vm.Vector3(0, 1, 0), color: vm.Vector3(1.6, 1.4, 0.8), life: 0.6)
      ..burst(head, count: 30, speed: 1.6, size: 0.04, shape: VfxShape.flare, life: 0.9, gravity: 1);
    Sfx.medium();
    Sfx.sound('arrive');
    Sfx.sound('card_flip', delay: const Duration(milliseconds: 250));
    setState(() {});
  }

  void _updateCamera(double dt) {
    _orbit += _orbitVel * dt;
    _orbitVel *= math.exp(-dt * 3);
    // Lean toward where the friend is going.
    final want = _goingTo?.at ?? _at?.at ?? vm.Vector3(0, 0, 0.3);
    _focus.add((vm.Vector3(want.x * 0.45, 0.6, 0.3 + (want.z - 0.3) * 0.45) - _focus) * math.min(1.0, dt * 2.0));
    _zoom += ((_goingTo != null || _at != null ? 1.0 : 0.0) - _zoom) * math.min(1.0, dt * 1.5);
    if (widget.holdZoom != null) _zoom = widget.holdZoom!;
    final dist = 21.0 - 8.0 * _zoom;
    final a = _orbit + math.sin(_time * 0.15) * 0.08;
    camera
      ..position = _focus + vm.Vector3(math.sin(a) * dist * 0.62, dist * 0.78, -math.cos(a) * dist * 0.62)
      ..target = _focus.clone();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final c = lumi;
    final name = c?.friend.name ?? 'Lumi';
    final best = pick;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1433),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready)
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (d) => _orbitVel -= d.delta.dx * 0.06,
              child: appSceneView(scene, camera: camera, onTick: _tick),
            )
          else
            const Center(child: CircularProgressIndicator(color: Color(0xFF8FD3FF))),
          if (widget.chrome)
            Positioned(
              top: pad.top + 8,
              left: 8,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          if (widget.chrome)
            Positioned(
              top: pad.top + 18,
              left: 0,
              right: 0,
              child: const IgnorePointer(
                child: Text(
                  'Park map',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          if (_ready && widget.chrome)
            Positioned(
              left: 16,
              right: 16,
              bottom: pad.bottom + 18,
              child: m.Material(
                color: const Color(0xF20C122C),
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(c!.friend.thumbnail, width: 44, height: 44, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _at != null ? '$name made it to ${_at!.name}!' : (_goingTo != null ? '$name is hopping over…' : '$name suggests'),
                              style: const TextStyle(color: Color(0xFF95A2C8), fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                            ValueListenableBuilder(
                              valueListenable: (_goingTo ?? _at ?? best).wait,
                              builder: (_, w, _) => Text(
                                '${(_goingTo ?? _at ?? best).name} · $w min',
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: () => goTo(best),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8FD3FF), foregroundColor: const Color(0xFF0A1024)),
                        child: const Text('Take me'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The card standing over a ride: a real widget, rendered into the scene.
class _RideCard extends StatelessWidget {
  const _RideCard({required this.ride, required this.onGo});
  final Ride ride;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ride.wait, ride.highlighted, ride.here]),
      builder: (context, _) {
        final hot = ride.highlighted.value;
        final here = ride.here.value;
        final wait = ride.wait.value;
        final color = wait <= 10 ? const Color(0xFF2FBF71) : (wait <= 25 ? const Color(0xFFE8A33D) : const Color(0xFFE5534B));
        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xF2182041), Color(0xF20E1430)]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: here ? const Color(0xFF6BE0A5) : (hot ? const Color(0xFF8FD3FF) : const Color(0x553A4A80)), width: hot || here ? 4 : 2),
          ),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      here ? 'YOU ARE HERE' : (hot ? 'SHORTEST WAIT' : 'RIDE'),
                      style: TextStyle(
                        color: here ? const Color(0xFF6BE0A5) : const Color(0xFF8FD3FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      ride.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFEEF1FB), fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$wait min',
                          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onGo,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: here ? const Color(0xFF6BE0A5) : const Color(0xFF8FD3FF), shape: BoxShape.circle),
                  child: Icon(here ? Icons.check_rounded : Icons.near_me_rounded, color: const Color(0xFF0B1022), size: 28),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
