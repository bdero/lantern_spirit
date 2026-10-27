import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../scenery/scenery.dart';
import '../vfx/vfx.dart';

/// The park as a handmade miniature, after the dusk-lagoon concept: a round
/// island with a rocky rim on a mirror lagoon at blue hour, cobbled paths
/// winding out from a fountain plaza, lamp posts, layered trees, flower
/// beds, fences, a dock with lantern boats, and a bespoke model for every
/// ride. Everything that should move does.
typedef _Put = Node Function(Geometry g, Material mat, vm.Vector3 at, vm.Vector3 scale, {vm.Quaternion? rot, Node? into});

class ParkDiorama {
  ParkDiorama._(this._scenery);

  final Scenery _scenery;
  final _rng = math.Random(21);

  /// The walking path from the gate to each ride, by ride index.
  final List<List<vm.Vector3>> routes = [];

  /// The plaza in the middle, where every path meets.
  static final hub = vm.Vector3(0, 0, -1.1);

  // Moving parts.
  late final ScenePath _coasterPath;
  late final Node _cart;
  late final ScenePath _riverPath;
  late final Node _log;
  late final Node _swingCrown;
  final List<Node> _swingSeats = [];
  late final Node _dropCar;
  late final vm.Vector3 _dropBase;
  late final Node _cupTable;
  final List<Node> _cups = [];
  late final Node _carouselTop;
  final List<(Node, vm.Vector3, double)> _boats = [];
  final List<(Node, vm.Vector3, double)> _floaters = [];
  late final vm.Vector3 _fall;
  late final vm.Vector3 _fountain;
  final List<Node> _bulbs = [];
  double _fx = 0;

  static Future<ParkDiorama> build(Scene scene, List<vm.Vector3> rides, vm.Vector3 gate) async {
    // A storybook model at dusk: a soft, nearly neutral key light from one
    // side with a cool blue fill on the shadow side, a cel-like terminator,
    // bright rims, and pieces grounded by darkening at their feet.
    final sc = Scenery()
      ..keyDir = vm.Vector3(-0.55, 0.75, -0.35)
      ..keyColor = vm.Vector3(0.84, 0.8, 0.78)
      ..sky = vm.Vector3(0.3, 0.35, 0.6)
      ..ground = vm.Vector3(0.12, 0.1, 0.16)
      ..toon = 0.8
      ..ao = 0.45;
    sc.lamps.addAll([
      SceneryLamp(hub + vm.Vector3(0, 0.9, 0), 2.6, vm.Vector3(1.1, 0.75, 0.4)),
      SceneryLamp(gate + vm.Vector3(0, 1.0, 0), 2.2, vm.Vector3(1.0, 0.7, 0.4)),
      SceneryLamp(rides[5] + vm.Vector3(0, 1.0, 0), 2.4, vm.Vector3(1.2, 0.8, 0.45)),
    ]);
    final d = ParkDiorama._(sc);
    await d._build(scene, rides, gate);
    return d;
  }

  Future<void> _build(Scene scene, List<vm.Vector3> rides, vm.Vector3 gate) async {
    final sc = _scenery;
    // Everything that stands on the ground, as (where, how wide, how tall):
    // baked at the end into the ground's shadows and occlusion.
    final casters = <(vm.Vector3, double, double)>[];
    void blob(vm.Vector3 at, double radius, {double height = 0.5}) => casters.add((at, radius, height));

    // Sky Coaster, River Run, Star Swing, Moon Drop, Tidal Twist, Comet
    // Carousel.
    const rideShapes = [(1.0, 1.3), (1.0, 0.2), (0.85, 1.5), (0.35, 2.4), (0.95, 0.55), (0.95, 1.45)];
    for (var i = 0; i < rides.length; i++) {
      final (radius, height) = rideShapes[i % rideShapes.length];
      blob(rides[i], radius, height: height);
    }
    for (final x in const [-0.55, 0.55]) {
      blob(gate + vm.Vector3(x, 0, 0), 0.24, height: 0.95);
    }
    final m = await sc.makeAll(const [
      Look(Finish.grass, (0.21, 0.43, 0.25), (0.16, 0.36, 0.22), (0.95, 0.55, 0.6), 1, 0.12),
      Look(Finish.cobbles, (0.86, 0.78, 0.64), (0.66, 0.58, 0.48), (0.32, 0.27, 0.24), 1, 0.08),
      Look(Finish.rock, (0.58, 0.5, 0.46), (0.32, 0.27, 0.27), null, 1.2, 0.1),
      Look(Finish.planks, (0.52, 0.34, 0.2), (0.32, 0.2, 0.12), null, 1.6, 0.08, 0.2),
      Look(Finish.plain, (0.24, 0.48, 0.24), null, null, 1, 0.25),
      Look(Finish.plain, (0.13, 0.32, 0.2), null, null, 1, 0.25),
      Look(Finish.plain, (0.86, 0.22, 0.2), null, null, 1, 0.2, 0.6),
      Look(Finish.plain, (0.96, 0.9, 0.78), null, null, 1, 0.2, 0.3),
      Look(Finish.plain, (0.92, 0.7, 0.3), null, null, 1, 0.2, 0.8),
      Look(Finish.plain, (0.16, 0.42, 0.6), null, null, 1, 0.35, 0.9, 0.15),
      Look(Finish.plain, (0.2, 0.18, 0.22), null, null, 1, 0.1),
      Look(Finish.plain, (0.55, 0.38, 0.85), null, null, 1, 0.2, 0.5),
      Look(Finish.plain, (0.4, 0.75, 0.9), null, null, 1, 0.2, 0.6),
    ]);
    final (grass, cobble, rock, planks, leafA, leafB, red, cream, gold, water, iron, violet, sky) =
        (m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11], m[12]);
    final bulb = await sc.make(const Look(Finish.plain, (1.0, 0.78, 0.45), null, null, 1, 0, 0, 2.6));
    // Stones laid along each path, and in rings round the plaza.
    final pathStone = await sc.make(const Look(Finish.pathStones, (0.86, 0.78, 0.64), (0.66, 0.58, 0.48), (0.32, 0.27, 0.24), 1, 0.08), width: 0.48);
    final plazaStone = await sc.make(const Look(Finish.plazaStones, (0.88, 0.8, 0.66), (0.68, 0.6, 0.5), (0.32, 0.27, 0.24), 1, 0.08), center: hub);
    // More foliage, so no two trees look stamped from one mold.
    final leafC = await sc.make(const Look(Finish.plain, (0.36, 0.52, 0.2), null, null, 1, 0.25));
    final leafD = await sc.make(const Look(Finish.plain, (0.14, 0.38, 0.3), null, null, 1, 0.25));
    final blossom = await sc.make(const Look(Finish.plain, (0.93, 0.62, 0.72), null, null, 1, 0.25, 0, 0.12));
    final autumn = await sc.make(const Look(Finish.plain, (0.86, 0.5, 0.2), null, null, 1, 0.25));
    final lily = await sc.make(const Look(Finish.plain, (0.2, 0.42, 0.26), null, null, 1, 0.2, 0.3));
    final foam = await sc.make(const Look(Finish.plain, (0.75, 0.82, 0.92), null, null, 1, 0.3, 0, 0.35));
    final paper = await sc.make(const Look(Finish.plain, (1.0, 0.72, 0.42), null, null, 1, 0, 0, 1.9));
    final moonGlow = await sc.make(const Look(Finish.plain, (1.0, 0.94, 0.78), null, null, 1, 0, 0, 2.2));
    final stripes = await sc.make(const Look(Finish.stripes, (0.88, 0.2, 0.22), (0.97, 0.92, 0.82), null, 1, 0.15, 0.5), center: rides[5]);
    final swingStripes = await sc.make(const Look(Finish.stripes, (0.5, 0.36, 0.86), (0.96, 0.9, 0.8), null, 1, 0.15, 0.5), center: rides[2]);
    final cupBase = await sc.make(const Look(Finish.stripes, (0.2, 0.5, 0.8), (0.95, 0.92, 0.85), null, 1, 0.15, 0.4), center: rides[4]);
    final lagoon = await loadFmatMaterial('assets/show/water.fmat');
    lagoon.parameters
      ..setVec4('deep_color', vm.Vector4(0.03, 0.15, 0.24, 1))
      ..setFloat('streak', 0.02)
      ..setFloat('reflectivity', 1.15);
    final skybox = await loadFmatSky('assets/show/lagoon_sky.fmat');
    skybox.parameters
      ..setVec4('horizon_color', vm.Vector4(0.62, 0.36, 0.48, 1))
      ..setVec4('zenith_color', vm.Vector4(0.1, 0.12, 0.34, 1))
      ..setFloat('star_brightness', 0.7);
    scene.skybox = Skybox(skybox);

    final ball = SphereGeometry(radius: 1, segments: 24, rings: 12);
    final cyl = CylinderGeometry(bottomRadius: 1, topRadius: 1, height: 1, radialSegments: 32);
    final cone = CylinderGeometry(bottomRadius: 1, topRadius: 0.0, height: 1, radialSegments: 32);
    final cube = CuboidGeometry(vm.Vector3.all(1));
    Node put(Geometry g, Material mat, vm.Vector3 at, vm.Vector3 scale, {vm.Quaternion? rot, Node? into}) {
      final n = Node(mesh: Mesh(g, mat), localTransform: vm.Matrix4.compose(at, rot ?? vm.Quaternion.identity(), scale))..raycastable = false;
      (into ?? scene.root).add(n);
      return n;
    }

    vm.Quaternion yaw(double a) => vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), a);
    void glowBulb(vm.Vector3 at, double r, {Node? into}) => _bulbs.add(put(ball, bulb, at, vm.Vector3.all(r), into: into));

    // ---- Lagoon and island.
    final lagoonNode = Node(name: 'Lagoon', mesh: Mesh(PlaneGeometry(width: 300, depth: 300), lagoon), localTransform: vm.Matrix4.translation(vm.Vector3(0, -0.28, 0)));
    lagoonNode.addComponent(PlanarReflectorComponent(resolutionScale: 0.5));
    scene.add(lagoonNode);
    final center = vm.Vector3(0, 0, 0.4);
    put(cyl, grass, center + vm.Vector3(0, -0.12, 0), vm.Vector3(5.5, 0.24, 5.5));
    put(CylinderGeometry(bottomRadius: 0.92, topRadius: 1, height: 1, radialSegments: 48), rock, center + vm.Vector3(0, -0.42, 0), vm.Vector3(5.7, 0.5, 5.7));
    // A rim of rounded boulders, half in the water.
    for (var i = 0; i < 46; i++) {
      final a = i / 46 * math.pi * 2 + _rng.nextDouble() * 0.05;
      final r = 5.55 + _rng.nextDouble() * 0.25;
      if ((a - math.pi * 1.5).abs() < 0.12) continue; // the dock
      final s = 0.3 + _rng.nextDouble() * 0.32;
      put(ball, rock, center + vm.Vector3(math.cos(a) * r, -0.22 + _rng.nextDouble() * 0.1, math.sin(a) * r), vm.Vector3(s * 1.3, s * 0.8, s));
    }

    // ---- Paths: from the gate to the plaza, and from the plaza to each ride.
    final pathPoints = <List<vm.Vector3>>[];
    vm.Vector3 bend(vm.Vector3 a, vm.Vector3 b, double amount) {
      final mid = (a + b) * 0.5;
      final side = vm.Vector3(-(b.z - a.z), 0, b.x - a.x)..normalize();
      return mid + side * amount;
    }

    final toHub = [gate.clone(), bend(gate, hub, 0.25), hub.clone()];
    pathPoints.add(toHub);
    for (var i = 0; i < rides.length; i++) {
      final r = rides[i];
      final dir = (r - hub)..normalize();
      final stop = r - dir * 0.78;
      // Curve gently, unless another ride stands in the way: then swing
      // round it on whichever side the path was already passing.
      var mid = bend(hub, stop, (i.isEven ? 0.45 : -0.45));
      for (var j = 0; j < rides.length; j++) {
        if (j == i) continue;
        final q = rides[j];
        final ab = stop - hub;
        final u = ((q - hub).dot(ab) / ab.length2).clamp(0.0, 1.0);
        final near = hub + ab * u;
        if (u <= 0.05 || u >= 0.95 || (near - q).length > 1.35) continue;
        final away = near - q..y = 0;
        if (away.length < 1e-3) away.setValues(-ab.z, 0, ab.x);
        mid = q + away.normalized() * 1.5;
      }
      final pts = [hub.clone(), mid, stop];
      pathPoints.add(pts);
      routes.add([...toHub, ...pts.skip(1)]);
    }
    for (var i = 0; i < pathPoints.length; i++) {
      final pts = [for (final p in pathPoints[i]) vm.Vector3(p.x, 0.012 + i * 0.002, p.z)];
      put(RibbonGeometry(CatmullRomPath(pts), width: 0.48, stations: 48), pathStone, vm.Vector3.zero(), vm.Vector3.all(1));
    }
    // The plaza and its fountain.
    put(cyl, plazaStone, hub + vm.Vector3(0, 0.03, 0), vm.Vector3(0.95, 0.04, 0.95));
    blob(hub, 0.45, height: 0.6);
    put(cyl, cream, hub + vm.Vector3(0, 0.1, 0), vm.Vector3(0.42, 0.12, 0.42));
    put(cyl, water, hub + vm.Vector3(0, 0.15, 0), vm.Vector3(0.36, 0.04, 0.36));
    put(cyl, cream, hub + vm.Vector3(0, 0.3, 0), vm.Vector3(0.06, 0.3, 0.06));
    put(cyl, cream, hub + vm.Vector3(0, 0.44, 0), vm.Vector3(0.2, 0.04, 0.2));
    _fountain = hub + vm.Vector3(0, 0.5, 0);

    // Lamp posts along every path, alternating sides.
    bool nearPath(vm.Vector3 p, double clear) {
      for (final pts in pathPoints) {
        final path = CatmullRomPath(pts);
        for (var k = 0; k <= 16; k++) {
          final q = path.positionAt(k / 16);
          if ((q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z) < clear * clear) return true;
        }
      }
      return false;
    }

    for (final pts in pathPoints) {
      final path = CatmullRomPath(pts);
      final len = path.length;
      var side = 1.0;
      for (var dd = 0.6; dd < len - 0.3; dd += 0.95) {
        final p = path.positionAtDistance(dd);
        final t = path.tangentAt(path.parameterAtDistance(dd))..normalize();
        final off = vm.Vector3(-t.z, 0, t.x) * (0.36 * side);
        side = -side;
        final at = vm.Vector3(p.x, 0, p.z) + off;
        if ((at - hub).length < 1.0) continue;
        put(cyl, iron, at + vm.Vector3(0, 0.28, 0), vm.Vector3(0.022, 0.56, 0.022));
        blob(at, 0.05, height: 0.62);
        put(cyl, iron, at + vm.Vector3(0, 0.58, 0), vm.Vector3(0.05, 0.03, 0.05));
        glowBulb(at + vm.Vector3(0, 0.63, 0), 0.045);
      }
    }

    // ---- The gate: two turrets and an arch, then a dock out into the water.
    for (final x in const [-0.55, 0.55]) {
      put(cyl, cream, gate + vm.Vector3(x, 0.45, 0), vm.Vector3(0.2, 0.9, 0.2));
      put(cyl, red, gate + vm.Vector3(x, 0.92, 0), vm.Vector3(0.23, 0.06, 0.23));
      put(cone, red, gate + vm.Vector3(x, 1.18, 0), vm.Vector3(0.26, 0.48, 0.26));
      put(ball, gold, gate + vm.Vector3(x, 1.45, 0), vm.Vector3.all(0.05));
      glowBulb(gate + vm.Vector3(x, 0.6, -0.21), 0.04);
    }
    put(TorusGeometry(radius: 0.55, tubeRadius: 0.06, radialSegments: 32, tubularSegments: 10), red, gate + vm.Vector3(0, 0.82, 0), vm.Vector3.all(1),
        rot: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2));
    for (var k = 0; k < 7; k++) {
      final a = math.pi * k / 6;
      glowBulb(gate + vm.Vector3(math.cos(a) * 0.55, 0.82 + math.sin(a) * 0.55, -0.06), 0.028);
    }
    final dockFrom = gate + vm.Vector3(0, 0, -0.55);
    for (var k = 0; k < 9; k++) {
      put(cube, planks, dockFrom + vm.Vector3(0, -0.05, -k * 0.2), vm.Vector3(0.7, 0.05, 0.17));
    }
    for (final x in const [-0.36, 0.36]) {
      for (var k = 0; k < 3; k++) {
        put(cyl, planks, dockFrom + vm.Vector3(x, -0.15, -0.3 - k * 0.65), vm.Vector3(0.04, 0.4, 0.04));
      }
      glowBulb(dockFrom + vm.Vector3(x, 0.12, -1.6), 0.035);
    }
    // Little boats with lanterns, bobbing on the lagoon.
    for (final (x, z, a) in const [(1.0, -5.8, 0.4), (-2.6, -5.4, -0.6), (5.9, -2.2, 1.2), (-6.0, 2.6, -1.0)]) {
      final boat = Node(name: 'Boat');
      put(ball, planks, vm.Vector3(0, 0, 0), vm.Vector3(0.18, 0.08, 0.42), into: boat);
      put(cyl, iron, vm.Vector3(0, 0.18, 0.2), vm.Vector3(0.01, 0.3, 0.01), into: boat);
      glowBulb(vm.Vector3(0, 0.34, 0.2), 0.04, into: boat);
      scene.add(boat);
      _boats.add((boat, vm.Vector3(x, -0.25, z), a));
    }
    // Far islands with lit windows on the horizon.
    for (final (x, z, r) in const [(-14.0, 22.0, 3.0), (9.0, 26.0, 4.0), (24.0, 12.0, 3.5), (-22.0, 8.0, 2.5)]) {
      put(ball, rock, vm.Vector3(x, -0.6, z), vm.Vector3(r, r * 0.35, r * 0.8));
      for (var k = 0; k < 4; k++) {
        put(ball, leafB, vm.Vector3(x + (k - 1.5) * r * 0.4, r * 0.18, z), vm.Vector3.all(r * 0.22));
        glowBulb(vm.Vector3(x + (k - 1.5) * r * 0.45, r * 0.08, z - r * 0.7), 0.12);
      }
    }

    // ---- The lagoon around the island: a soft foam line at the shore,
    // lily pads, little rocky islets, and paper lanterns floating out on the
    // water.
    put(TorusGeometry(radius: 5.95, tubeRadius: 0.05, radialSegments: 128, tubularSegments: 8), foam, center + vm.Vector3(0, -0.29, 0), vm.Vector3(1, 0.35, 1));
    final lagoonRng = math.Random(41);
    for (var k = 0; k < 16; k++) {
      final a = lagoonRng.nextDouble() * math.pi * 2;
      final r = 6.4 + lagoonRng.nextDouble() * 2.6;
      if ((a - math.pi * 1.5).abs() < 0.35) continue; // keep the dock clear
      final at = center + vm.Vector3(math.cos(a) * r, -0.265, math.sin(a) * r);
      for (var j = 0; j < 2 + lagoonRng.nextInt(3); j++) {
        final o = vm.Vector3((lagoonRng.nextDouble() - 0.5) * 0.6, 0, (lagoonRng.nextDouble() - 0.5) * 0.6);
        final size = 0.1 + lagoonRng.nextDouble() * 0.12;
        put(cyl, lily, at + o, vm.Vector3(size, 0.01, size), rot: yaw(lagoonRng.nextDouble() * 6));
        if (lagoonRng.nextDouble() < 0.25) put(ball, blossom, at + o + vm.Vector3(0, 0.03, 0), vm.Vector3.all(0.035));
      }
    }
    for (final (x, z, r) in const [(-8.6, -3.4, 0.9), (8.2, 5.6, 1.1), (-7.2, 6.8, 0.7), (7.6, -5.2, 0.8)]) {
      put(ball, rock, vm.Vector3(x, -0.36, z), vm.Vector3(r, r * 0.42, r * 0.85));
      put(ball, leafD, vm.Vector3(x + r * 0.15, r * 0.12, z), vm.Vector3.all(r * 0.32));
      put(ball, leafC, vm.Vector3(x - r * 0.25, r * 0.02, z + r * 0.2), vm.Vector3.all(r * 0.24));
    }
    for (var k = 0; k < 14; k++) {
      final a = lagoonRng.nextDouble() * math.pi * 2;
      final r = 6.6 + lagoonRng.nextDouble() * 4.0;
      final lantern = Node(name: 'Floater');
      put(ball, paper, vm.Vector3(0, 0.08, 0), vm.Vector3(0.07, 0.085, 0.07), into: lantern);
      put(cyl, planks, vm.Vector3(0, 0.0, 0), vm.Vector3(0.08, 0.02, 0.08), into: lantern);
      scene.add(lantern);
      _floaters.add((lantern, center + vm.Vector3(math.cos(a) * r, -0.27, math.sin(a) * r), lagoonRng.nextDouble() * 6));
    }

    // ---- The rides.
    // Sky Coaster: a red track looping over hills around a rock, with a cart.
    final co = rides[0];
    _coasterPath = CatmullRomPath([
      for (final (x, y, z) in const [(-0.9, 0.35, -0.6), (-0.2, 0.55, -0.9), (0.6, 1.2, -0.5), (0.9, 1.5, 0.3), (0.5, 0.9, 0.9), (-0.3, 0.4, 1.0), (-0.9, 0.8, 0.6), (-1.1, 1.3, 0.0), (-0.9, 0.35, -0.6)])
        co + vm.Vector3(x, y, z),
    ]);
    put(TubeGeometry(_coasterPath, radius: 0.05, radialSegments: 8, stations: 120, caps: false), red, vm.Vector3.zero(), vm.Vector3.all(1));
    put(TubeGeometry(_coasterPath, radius: 0.018, radialSegments: 6, stations: 120, caps: false), cream, vm.Vector3(0, -0.07, 0), vm.Vector3.all(1));
    for (var k = 0; k < 14; k++) {
      final p = _coasterPath.positionAt(k / 14);
      put(cyl, cream, vm.Vector3(p.x, p.y / 2, p.z), vm.Vector3(0.022, p.y, 0.022));
    }
    for (final (x, z, s) in const [(0.0, 0.1, 0.55), (0.3, -0.2, 0.4), (-0.3, 0.3, 0.35)]) {
      put(ball, rock, co + vm.Vector3(x, 0.15, z), vm.Vector3(s, s * 0.9, s));
    }
    _cart = Node(name: 'Cart');
    put(ball, gold, vm.Vector3.zero(), vm.Vector3(0.1, 0.08, 0.17), into: _cart);
    put(ball, red, vm.Vector3(0, 0.03, 0.12), vm.Vector3(0.08, 0.07, 0.06), into: _cart);
    scene.add(_cart);

    // River Run: a winding channel with stone banks, a waterfall, a log boat.
    final rv = rides[1];
    _riverPath = CatmullRomPath([
      for (var k = 0; k <= 14; k++) rv + vm.Vector3(math.cos(k / 14 * math.pi * 2) * 0.95, 0.045, math.sin(k / 14 * math.pi * 2) * 0.7 + math.sin(k / 14 * math.pi * 6) * 0.08),
    ]);
    put(RibbonGeometry(_riverPath, width: 0.5, stations: 96), cobble, vm.Vector3(0, -0.012, 0), vm.Vector3.all(1));
    put(RibbonGeometry(_riverPath, width: 0.36, stations: 96), water, vm.Vector3(0, 0.004, 0), vm.Vector3.all(1));
    for (final (x, z, s) in const [(0.0, 0.0, 0.42), (0.25, 0.15, 0.3), (-0.2, 0.2, 0.26)]) {
      put(ball, rock, rv + vm.Vector3(x, 0.2, z), vm.Vector3(s, s * 1.2, s));
    }
    put(ball, leafA, rv + vm.Vector3(0.05, 0.62, 0.05), vm.Vector3(0.2, 0.15, 0.2));
    _fall = rv + vm.Vector3(-0.05, 0.55, -0.55);
    _log = Node(name: 'Log');
    put(CapsuleGeometry(radius: 0.06, height: 0.22), planks, vm.Vector3.zero(), vm.Vector3.all(1), rot: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2), into: _log);
    scene.add(_log);

    // Star Swing: a tall pole and a tilted spinning crown of seats on chains.
    final sw = rides[2];
    put(cyl, cream, sw + vm.Vector3(0, 0.8, 0), vm.Vector3(0.07, 1.6, 0.07));
    put(cyl, swingStripes, sw + vm.Vector3(0, 0.04, 0), vm.Vector3(0.75, 0.08, 0.75));
    _swingCrown = Node(localTransform: vm.Matrix4.translation(sw + vm.Vector3(0, 1.55, 0)));
    put(cone, swingStripes, vm.Vector3(0, 0.12, 0), vm.Vector3(0.55, 0.28, 0.55), into: _swingCrown);
    put(ball, gold, vm.Vector3(0, 0.3, 0), vm.Vector3.all(0.05), into: _swingCrown);
    for (var k = 0; k < 8; k++) {
      final a = k / 8 * math.pi * 2;
      final seat = Node(localTransform: vm.Matrix4.translation(vm.Vector3(math.cos(a) * 0.5, 0, math.sin(a) * 0.5)));
      put(cyl, iron, vm.Vector3(0, -0.3, 0), vm.Vector3(0.006, 0.6, 0.006), into: seat);
      put(ball, k.isEven ? gold : red, vm.Vector3(0, -0.62, 0), vm.Vector3(0.06, 0.04, 0.06), into: seat);
      glowBulb(vm.Vector3(0, 0.0, 0), 0.025, into: seat);
      _swingCrown.add(seat);
      _swingSeats.add(seat);
    }
    scene.add(_swingCrown);

    // Moon Drop: a striped tower with a glowing moon on top and a ring car.
    final dr = rides[3];
    for (var k = 0; k < 9; k++) {
      put(cyl, k.isEven ? red : cream, dr + vm.Vector3(0, 0.12 + k * 0.24, 0), vm.Vector3(0.14, 0.24, 0.14));
    }
    put(cyl, gold, dr + vm.Vector3(0, 2.3, 0), vm.Vector3(0.24, 0.05, 0.24));
    put(ball, moonGlow, dr + vm.Vector3(0, 2.62, 0), vm.Vector3.all(0.3));
    for (var k = 0; k < 10; k++) {
      final a = k / 10 * math.pi * 2;
      glowBulb(dr + vm.Vector3(math.cos(a) * 0.25, 2.32, math.sin(a) * 0.25), 0.025);
    }
    _dropBase = dr;
    _dropCar = Node();
    put(TorusGeometry(radius: 0.24, tubeRadius: 0.06, radialSegments: 24, tubularSegments: 8), violet, vm.Vector3.zero(), vm.Vector3.all(1), into: _dropCar);
    scene.add(_dropCar);

    // Tidal Twist: teacups spinning on a turntable round a teapot.
    final tw = rides[4];
    put(cyl, cupBase, tw + vm.Vector3(0, 0.05, 0), vm.Vector3(0.95, 0.1, 0.95));
    _cupTable = Node(localTransform: vm.Matrix4.translation(tw + vm.Vector3(0, 0.1, 0)));
    put(ball, cream, vm.Vector3(0, 0.22, 0), vm.Vector3(0.2, 0.18, 0.2), into: _cupTable);
    put(ball, gold, vm.Vector3(0, 0.42, 0), vm.Vector3.all(0.05), into: _cupTable);
    put(cyl, cream, vm.Vector3(0.22, 0.26, 0), vm.Vector3(0.03, 0.18, 0.03), rot: vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), -0.8), into: _cupTable);
    final cupGeo = CylinderGeometry(bottomRadius: 0.6, topRadius: 1, height: 1, radialSegments: 24);
    for (var k = 0; k < 4; k++) {
      final a = k / 4 * math.pi * 2;
      final cup = Node(localTransform: vm.Matrix4.translation(vm.Vector3(math.cos(a) * 0.58, 0.08, math.sin(a) * 0.58)));
      put(cupGeo, [red, sky, gold, violet][k], vm.Vector3(0, 0.08, 0), vm.Vector3(0.17, 0.16, 0.17), into: cup);
      put(cyl, cream, vm.Vector3(0, 0.0, 0), vm.Vector3(0.2, 0.02, 0.2), into: cup);
      _cupTable.add(cup);
      _cups.add(cup);
    }
    scene.add(_cupTable);

    // Comet Carousel: a striped canopy ringed with bulbs, horses on gold poles.
    final ca = rides[5];
    put(cyl, cream, ca + vm.Vector3(0, 0.05, 0), vm.Vector3(0.78, 0.1, 0.78));
    put(cyl, gold, ca + vm.Vector3(0, 0.11, 0), vm.Vector3(0.8, 0.02, 0.8));
    _carouselTop = Node(localTransform: vm.Matrix4.translation(ca + vm.Vector3(0, 0.12, 0)));
    put(cone, stripes, vm.Vector3(0, 1.08, 0), vm.Vector3(0.88, 0.42, 0.88), into: _carouselTop);
    put(cyl, stripes, vm.Vector3(0, 0.84, 0), vm.Vector3(0.86, 0.1, 0.86), into: _carouselTop);
    put(cyl, gold, vm.Vector3(0, 0.5, 0), vm.Vector3(0.1, 0.8, 0.1), into: _carouselTop);
    put(ball, gold, vm.Vector3(0, 1.34, 0), vm.Vector3.all(0.06), into: _carouselTop);
    for (var k = 0; k < 16; k++) {
      final a = k / 16 * math.pi * 2;
      glowBulb(vm.Vector3(math.cos(a) * 0.86, 0.78, math.sin(a) * 0.86), 0.03, into: _carouselTop);
    }
    for (var k = 0; k < 6; k++) {
      final a = k / 6 * math.pi * 2;
      final at = vm.Vector3(math.cos(a) * 0.56, 0, math.sin(a) * 0.56);
      put(cyl, gold, at + vm.Vector3(0, 0.42, 0), vm.Vector3(0.015, 0.84, 0.015), into: _carouselTop);
      put(CapsuleGeometry(radius: 0.06, height: 0.14), cream, at + vm.Vector3(0, 0.34 + (k % 2) * 0.06, 0), vm.Vector3.all(1),
          rot: yaw(-a) * vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2), into: _carouselTop);
      put(ball, [red, sky, violet][k % 3], at + vm.Vector3(0, 0.4 + (k % 2) * 0.06, 0), vm.Vector3(0.05, 0.02, 0.05), into: _carouselTop);
    }
    scene.add(_carouselTop);

    // ---- Trees, flowers, benches, and fences, kept clear of paths and rides.
    final trees = <vm.Vector3>[];
    var tries = 0;
    while (trees.length < 52 && tries < 2000) {
      tries++;
      final a = _rng.nextDouble() * math.pi * 2;
      final r = math.sqrt(_rng.nextDouble()) * 5.1;
      final p = center + vm.Vector3(math.cos(a) * r, 0, math.sin(a) * r);
      if (nearPath(p, 0.45)) continue;
      if (rides.any((q) => (q - p).length < 1.15) || (p - hub).length < 1.1 || (p - gate).length < 0.9) continue;
      if (trees.any((q) => (q - p).length < 0.42)) continue;
      trees.add(p);
      _tree(p, put, ball, cyl, cone, planks, [leafA, leafB, leafC, leafD], blossom, autumn, blob);
    }
    final flowerColors = [red, gold, violet, cream, sky];
    for (var bed = 0; bed < 22; bed++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final r = 1.2 + _rng.nextDouble() * 3.8;
      final p = center + vm.Vector3(math.cos(a) * r, 0, math.sin(a) * r);
      if (nearPath(p, 0.32) || rides.any((q) => (q - p).length < 0.95)) continue;
      put(ball, leafB, p + vm.Vector3(0, 0.02, 0), vm.Vector3(0.2, 0.05, 0.14));
      for (var k = 0; k < 6; k++) {
        put(ball, flowerColors[(bed + k) % flowerColors.length], p + vm.Vector3((_rng.nextDouble() - 0.5) * 0.3, 0.06, (_rng.nextDouble() - 0.5) * 0.2), vm.Vector3.all(0.03));
      }
    }
    for (final a in const [0.6, 2.5, 4.0]) {
      final p = hub + vm.Vector3(math.cos(a) * 1.05, 0, math.sin(a) * 1.05);
      put(cube, planks, p + vm.Vector3(0, 0.1, 0), vm.Vector3(0.36, 0.035, 0.12), rot: yaw(-a + math.pi / 2));
      put(cube, iron, p + vm.Vector3(0, 0.05, 0), vm.Vector3(0.32, 0.1, 0.08), rot: yaw(-a + math.pi / 2));
    }
    // Picket fences along the front of the island, either side of the gate.
    for (final side in const [-1.0, 1.0]) {
      for (var k = 0; k < 16; k++) {
        final a = math.pi * 1.5 + side * (0.18 + k * 0.045);
        final p = center + vm.Vector3(math.cos(a) * 5.15, 0, math.sin(a) * 5.15);
        put(cube, cream, p + vm.Vector3(0, 0.1, 0), vm.Vector3(0.04, 0.2, 0.025), rot: yaw(-a));
        if (k < 15) {
          final a2 = a + side * 0.0225;
          final q = center + vm.Vector3(math.cos(a2) * 5.15, 0, math.sin(a2) * 5.15);
          put(cube, cream, q + vm.Vector3(0, 0.12, 0), vm.Vector3(0.025, 0.025, 0.24), rot: yaw(-a2));
        }
      }
    }
    // Food carts with striped awnings near the plaza.
    for (final (a, col) in [(1.4, red), (3.3, sky)]) {
      final p = hub + vm.Vector3(math.cos(a) * 1.35, 0, math.sin(a) * 1.35);
      put(cube, cream, p + vm.Vector3(0, 0.14, 0), vm.Vector3(0.32, 0.22, 0.2), rot: yaw(-a));
      blob(p, 0.22, height: 0.38);
      put(cube, col, p + vm.Vector3(0, 0.34, 0), vm.Vector3(0.38, 0.03, 0.28), rot: yaw(-a) * vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.25));
      glowBulb(p + vm.Vector3(0, 0.3, 0), 0.03);
    }

    await _bakeShade(casters, center);
  }

  /// One tree, never quite like the last: a round tree of a few soft
  /// clumps, a conifer of stacked cones, a tall poplar, a low bush, and now
  /// and then one in blossom or turning, each a different size, shape,
  /// green, turn, and lean.
  void _tree(
    vm.Vector3 p,
    _Put put,
    Geometry ball,
    Geometry cyl,
    Geometry cone,
    Material trunk,
    List<Material> greens,
    Material blossom,
    Material autumn,
    void Function(vm.Vector3, double, {double height}) blob,
  ) {
    final rng = _rng;
    final s = 0.7 + rng.nextDouble() * 0.6;
    final tall = 0.85 + rng.nextDouble() * 0.45;
    final turn = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), rng.nextDouble() * math.pi * 2);
    final tilt = vm.Quaternion.axisAngle(vm.Vector3(rng.nextDouble() - 0.5, 0, rng.nextDouble() - 0.5)..normalize(), rng.nextDouble() * 0.1);
    final lean = tilt * turn;
    Material green() => greens[rng.nextInt(greens.length)];
    vm.Vector3 up(double h) => lean.rotated(vm.Vector3(0, h, 0));
    final kind = rng.nextDouble();
    if (kind < 0.26) {
      // A conifer: two to four stacked cones.
      final layers = 2 + rng.nextInt(3);
      final wide = 0.2 + rng.nextDouble() * 0.08;
      final c = rng.nextBool() ? greens[1] : greens[3];
      put(cyl, trunk, p + up(0.08 * s), vm.Vector3(0.032 * s, 0.16 * s, 0.032 * s), rot: lean);
      for (var k = 0; k < layers; k++) {
        final f = k / layers;
        put(cone, c, p + up((0.18 + f * 0.5 * tall) * s), vm.Vector3((wide - f * wide * 0.55) * s, 0.3 * s * tall, (wide - f * wide * 0.55) * s), rot: lean);
      }
      blob(p, wide * s, height: 0.75 * s * tall);
    } else if (kind < 0.4) {
      // A poplar: tall and narrow.
      put(cyl, trunk, p + up(0.08 * s), vm.Vector3(0.03 * s, 0.16 * s, 0.03 * s), rot: lean);
      put(ball, green(), p + up(0.42 * s * tall), vm.Vector3(0.12 * s, 0.36 * s * tall, 0.12 * s), rot: lean);
      blob(p, 0.13 * s, height: 0.8 * s * tall);
    } else if (kind < 0.54) {
      // A low bush: a few clumps, no trunk.
      final c = green();
      for (var k = 0; k < 3 + rng.nextInt(2); k++) {
        final a = rng.nextDouble() * math.pi * 2;
        final r = (0.08 + rng.nextDouble() * 0.06) * s;
        put(ball, k == 0 ? c : green(), p + vm.Vector3(math.cos(a) * 0.08 * s, r * 0.7, math.sin(a) * 0.08 * s), vm.Vector3(r, r * 0.85, r), rot: turn);
      }
      blob(p, 0.16 * s, height: 0.2 * s);
    } else {
      // A round tree: a main crown and a few clumps round it; sometimes in
      // blossom, sometimes turning.
      final c = kind < 0.6 ? blossom : (kind < 0.64 ? autumn : green());
      final crown = (0.18 + rng.nextDouble() * 0.08) * s;
      final h = (0.34 + rng.nextDouble() * 0.08) * s * tall;
      put(cyl, trunk, p + up(h * 0.4), vm.Vector3(0.034 * s, h * 0.8, 0.034 * s), rot: lean);
      put(ball, c, p + up(h), vm.Vector3(crown, crown * (0.85 + rng.nextDouble() * 0.25), crown), rot: lean);
      for (var k = 0; k < 2 + rng.nextInt(3); k++) {
        final a = rng.nextDouble() * math.pi * 2;
        final o = vm.Vector3(math.cos(a) * crown * 0.75, crown * (rng.nextDouble() * 0.7 - 0.1), math.sin(a) * crown * 0.75);
        final r = crown * (0.5 + rng.nextDouble() * 0.25);
        put(ball, rng.nextDouble() < 0.7 ? c : green(), p + up(h) + lean.rotated(o), vm.Vector3.all(r), rot: lean);
      }
      blob(p, crown * 1.05, height: h + crown);
    }
  }

  /// Bakes every caster's shadow into one texture over the island: a soft
  /// pool of occlusion at its foot, and its shadow thrown away from the key
  /// light, longer the taller it stands. The ground and the feet of
  /// everything on it read it back.
  Future<void> _bakeShade(List<(vm.Vector3, double, double)> casters, vm.Vector3 center) async {
    const size = 13.0, res = 512;
    final x0 = center.x - size / 2, z0 = center.z - size / 2;
    const k = res / size;
    final light = _scenery.keyDir.normalized();
    final away = Offset(-light.x / light.y, -light.z / light.y);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, res * 1.0, res * 1.0), Paint()..color = const Color(0xFF000000));
    final paint = Paint()..blendMode = BlendMode.lighten;
    for (final (at, radius, height) in casters) {
      final c = Offset((at.x - x0) * k, (at.z - z0) * k);
      final r = radius * k;
      // Occlusion at the foot.
      canvas.drawCircle(
        c,
        r * 1.35,
        paint
          ..maskFilter = null
          ..shader = RadialGradient(colors: const [Color(0xE6FFFFFF), Color(0x00FFFFFF)]).createShader(Rect.fromCircle(center: c, radius: r * 1.35)),
      );
      // The cast shadow: a soft capsule from the foot out along the light.
      final reach = away * (height * k * 0.85);
      final mid = c + reach * 0.5;
      canvas.save();
      canvas.translate(mid.dx, mid.dy);
      canvas.rotate(math.atan2(reach.dy, reach.dx));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: reach.distance + r * 1.6, height: r * 1.7), Radius.circular(r * 0.85)),
        paint
          ..shader = null
          ..color = const Color(0xC8FFFFFF)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1.5, r * 0.45)),
      );
      canvas.restore();
    }
    final image = await recorder.endRecording().toImage(res, res);
    // Through PNG: a data map, not a picture, so read as is, no mips.
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final texture = await Texture2D.fromEncodedBytes(png!.buffer.asUint8List(), content: TextureContent.data, sampling: const TextureSampling(mipmaps: false));
    _scenery
      ..shade = texture
      ..shadeRect = vm.Vector4(x0, z0, 1 / size, 0.85)
      ..relight();
  }

  /// Animates the rides, the boats, the bulbs, the fountain and waterfall,
  /// and fireflies.
  void update(double time, double dt, Vfx vfx) {
    // The coaster cart rides its track, nose along the rails.
    final ct = (time * 0.11) % 1.0;
    final cp = _coasterPath.positionAt(ct);
    final tan = _coasterPath.tangentAt(ct)..normalize();
    _cart.localTransform = vm.Matrix4.compose(cp + vm.Vector3(0, 0.07, 0), _look(tan), vm.Vector3.all(1));
    // The log floats round the river.
    final lt = (time * 0.07) % 1.0;
    final lp = _riverPath.positionAt(lt);
    _log.localTransform = vm.Matrix4.compose(lp + vm.Vector3(0, 0.03 + math.sin(time * 3) * 0.008, 0), _look(_riverPath.tangentAt(lt)..normalize()), vm.Vector3.all(1));
    // The swing spins, its crown tilts, and the seats fly outward.
    final spin = time * 1.6;
    final tilt = 0.18 * math.sin(time * 0.5);
    _swingCrown.localTransform = vm.Matrix4.compose(
      _swingCrown.localTransform.getTranslation(),
      vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), tilt) * vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), spin),
      vm.Vector3.all(1),
    );
    for (var k = 0; k < _swingSeats.length; k++) {
      final a = k / _swingSeats.length * math.pi * 2;
      final out = vm.Vector3(math.cos(a), 0, math.sin(a));
      _swingSeats[k].localTransform = vm.Matrix4.compose(out * 0.5, vm.Quaternion.axisAngle(vm.Vector3(-out.z, 0, out.x), -0.55), vm.Vector3.all(1));
    }
    // The drop car rises slowly and falls fast.
    final cycle = (time * 0.22) % 1.0;
    final h = cycle < 0.75 ? _smooth(cycle / 0.75) : 1 - _easeIn((cycle - 0.75) / 0.25);
    _dropCar.localTransform = vm.Matrix4.compose(_dropBase + vm.Vector3(0, 0.3 + h * 1.8, 0), vm.Quaternion.identity(), vm.Vector3.all(1));
    // Teacups turn on the table and each on its own.
    _cupTable.localTransform = vm.Matrix4.compose(_cupTable.localTransform.getTranslation(), vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), time * 0.6), vm.Vector3.all(1));
    for (var k = 0; k < _cups.length; k++) {
      final a = k / _cups.length * math.pi * 2;
      _cups[k].localTransform = vm.Matrix4.compose(
        vm.Vector3(math.cos(a) * 0.58, 0.08, math.sin(a) * 0.58),
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), time * (1.5 + k * 0.3)),
        vm.Vector3.all(1),
      );
    }
    _carouselTop.localTransform = vm.Matrix4.compose(_carouselTop.localTransform.getTranslation(), vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), time * 0.5), vm.Vector3.all(1));
    for (final (boat, at, a) in _boats) {
      boat.localTransform = vm.Matrix4.compose(
        at + vm.Vector3(math.sin(time * 0.2 + a) * 0.1, math.sin(time * 1.3 + a) * 0.02, 0),
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), a) * vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), math.sin(time * 1.1 + a) * 0.06),
        vm.Vector3.all(1),
      );
    }
    // Paper lanterns rocking gently on the water.
    for (final (lantern, at, phase) in _floaters) {
      lantern.localTransform = vm.Matrix4.compose(
        at + vm.Vector3(math.sin(time * 0.15 + phase) * 0.15, math.sin(time * 1.2 + phase) * 0.015, math.cos(time * 0.12 + phase) * 0.15),
        vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0.4).normalized(), math.sin(time * 1.4 + phase) * 0.12),
        vm.Vector3.all(1),
      );
    }
    for (var i = 0; i < _bulbs.length; i += 7) {
      final b = _bulbs[i];
      final s = b.localTransform.getMaxScaleOnAxis();
      final base = s / (0.92 + 0.08 * math.sin((time - dt) * 3 + i));
      b.localTransform = vm.Matrix4.compose(b.localTransform.getTranslation(), vm.Quaternion.identity(), vm.Vector3.all(base * (0.92 + 0.08 * math.sin(time * 3 + i))));
    }
    // Water: the fountain's arcs, the waterfall, and fireflies over the island.
    _fx -= dt;
    if (_fx <= 0) {
      _fx = 0.05;
      final a = _rng.nextDouble() * math.pi * 2;
      vfx
        ..streak(_fountain, vm.Vector3(math.cos(a) * 0.35, 1.2, math.sin(a) * 0.35), color: vm.Vector3(0.6, 0.8, 1.1) * 0.5, width: 0.012, length: 0.05, life: 0.6, gravity: 3.2)
        ..streak(_fall + vm.Vector3((_rng.nextDouble() - 0.5) * 0.18, 0, 0), vm.Vector3(0, -1.6, -0.1), color: vm.Vector3(0.7, 0.9, 1.2) * 0.5, width: 0.02, length: 0.06, life: 0.3);
      if (_rng.nextDouble() < 0.4) {
        final p = vm.Vector3((_rng.nextDouble() - 0.5) * 9, 0.3 + _rng.nextDouble() * 1.0, 0.4 + (_rng.nextDouble() - 0.5) * 9);
        vfx.burst(p, count: 1, speed: 0.15, color: vm.Vector3(1.4, 1.5, 0.6), size: 0.05, life: 2.2, gravity: -0.05, drag: 0.3, shape: VfxShape.flare);
      }
    }
  }

  static vm.Quaternion _look(vm.Vector3 dir) {
    final yawA = math.atan2(dir.x, dir.z);
    final pitch = -math.asin(dir.y.clamp(-1.0, 1.0));
    return vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yawA) * vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), pitch);
  }

  static double _easeIn(double t) => t * t;
  static double _smooth(double t) => t * t * (3 - 2 * t);
}
