import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../app/profile.dart';
import '../lantern/wardrobe.dart';
import '../scenery/scenery.dart';
import '../vfx/vfx.dart';

/// Your friend's room: a cozy floating nook that unfolds around it when the
/// header grows to fill the screen.
///
/// After the cozy-nook concept: a round wooden platform floating in the
/// night, a curved plaster wall with a big round window on the moon, string
/// lights along the top, a paper lantern lamp that pools warm light on the
/// floorboards, a woven rug, a plush cushion bed with a blanket, a wall
/// shelf of hats, books, plants and ivy, and a ladder and lantern hanging
/// underneath. The friend never moves; the header becomes the room, and the
/// pieces pop in one after another. The board on the wall is a live
/// Flutter widget with a working Party button.
class FriendRoom {
  FriendRoom._(
    this.root,
    this._scenery,
    this._pieces,
    this._shelf,
    this._window,
    this._windowSky,
    this._bulbs,
    this._lampShade,
  );

  /// What a tap on the room can mean.
  static const nap = 'nap';

  static const _floor = 0.25;
  static const _wallR = 1.95;

  static Future<FriendRoom> build({
    required Profile profile,
    required String friendName,
    required VoidCallback onParty,
  }) async {
    final sc = Scenery()
      ..keyDir = vm.Vector3(0.35, 0.7, 0.6)
      ..keyColor = vm.Vector3(0.12, 0.15, 0.32)
      ..sky = vm.Vector3(0.1, 0.11, 0.24)
      ..ground = vm.Vector3(0.06, 0.04, 0.05);
    // The paper lantern, the moonlight through the window, and the friend.
    sc.lamps.addAll([
      SceneryLamp(
        vm.Vector3(1.45, 1.35, 0.85),
        3.4,
        vm.Vector3(1.7, 1.05, 0.5),
      ),
      SceneryLamp(vm.Vector3(0.8, 2.0, 1.2), 2.6, vm.Vector3(0.35, 0.45, 0.85)),
      SceneryLamp(vm.Vector3(0, 1.6, -0.3), 2.2, vm.Vector3(0.35, 0.55, 0.9)),
    ]);
    const honey = (0.55, 0.33, 0.17), walnut = (0.3, 0.17, 0.09);
    final mats = await sc.makeAll(const [
      Look(Finish.planks, honey, walnut, null, 1.0, 0.1, 0.25),
      Look(Finish.plain, walnut, null, null, 1, 0.1, 0.2),
      Look(
        Finish.plaster,
        (0.86, 0.66, 0.5),
        (0.7, 0.5, 0.38),
        null,
        1.2,
        0.05,
      ),
      Look(
        Finish.rug,
        (0.72, 0.42, 0.34),
        (0.86, 0.72, 0.56),
        (0.45, 0.24, 0.24),
        1,
        0.05,
      ),
      Look(Finish.plain, (0.95, 0.62, 0.52), null, null, 1, 0.35),
      Look(Finish.plain, (0.9, 0.84, 0.72), null, null, 1, 0.3),
      Look(Finish.plain, (0.26, 0.55, 0.3), null, null, 1, 0.3),
      Look(Finish.plain, (0.62, 0.32, 0.22), null, null, 1, 0.15),
      Look(Finish.rock, (0.32, 0.28, 0.3), (0.18, 0.15, 0.17), null, 1.4, 0.1),
      Look(Finish.plain, (0.2, 0.3, 0.55), null, null, 1, 0.2),
      Look(Finish.plain, (0.7, 0.25, 0.22), null, null, 1, 0.2),
      Look(Finish.plain, (0.85, 0.7, 0.35), null, null, 1, 0.2),
    ]);
    final (
      planks,
      wood,
      plaster,
      rug,
      cushion,
      blanket,
      leaf,
      terracotta,
      rock,
      bookBlue,
      bookRed,
      bookGold,
    ) = (
      mats[0],
      mats[1],
      mats[2],
      mats[3],
      mats[4],
      mats[5],
      mats[6],
      mats[7],
      mats[8],
      mats[9],
      mats[10],
      mats[11],
    );
    final glow = await sc.make(
      const Look(Finish.plain, (1.0, 0.72, 0.38), null, null, 1, 0, 0, 2.4),
    );
    final shade = await sc.make(
      const Look(Finish.plain, (1.0, 0.86, 0.66), null, null, 1, 0.2, 0, 1.6),
    );
    final windowSky = await loadFmatMaterial('assets/window_sky.fmat');

    final ball = SphereGeometry(radius: 1, segments: 32, rings: 16);
    final cyl = CylinderGeometry(
      bottomRadius: 1,
      topRadius: 1,
      height: 1,
      radialSegments: 64,
    );
    final cube = CuboidGeometry(vm.Vector3.all(1));
    final root = Node(name: 'Room');
    final pieces = <_Piece>[];

    Node part(
      Geometry g,
      Material m,
      vm.Vector3 at,
      vm.Vector3 scale, {
      String name = '',
      vm.Quaternion? rot,
    }) => Node(
      name: name,
      mesh: Mesh(g, m),
      localTransform: vm.Matrix4.compose(
        at,
        rot ?? vm.Quaternion.identity(),
        scale,
      ),
    );
    Node piece(
      String name,
      double delay,
      vm.Vector3 at,
      List<Node> parts, {
      double rotY = 0,
    }) {
      final n = Node(name: name);
      for (final p in parts) {
        n.add(p);
      }
      root.add(n);
      pieces.add(_Piece(n, at, delay, rotY));
      return n;
    }

    vm.Quaternion yaw(double a) =>
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), a);
    // A point on the wall at angle [t] (0 straight behind the friend).
    vm.Vector3 onWall(double t, double y, [double inset = 0]) => vm.Vector3(
      math.sin(t) * (_wallR - inset),
      y,
      math.cos(t) * (_wallR - inset),
    );

    // ---- The floating floor: planks on a thick round platform over rock.
    piece('Floor', 0.0, vm.Vector3.zero(), [
      part(
        cyl,
        planks,
        vm.Vector3(0, _floor - 0.06, 0),
        vm.Vector3(2.1, 0.12, 2.1),
      ),
      part(
        cyl,
        wood,
        vm.Vector3(0, _floor - 0.2, 0),
        vm.Vector3(2.16, 0.18, 2.16),
      ),
      part(
        CylinderGeometry(
          bottomRadius: 0.35,
          topRadius: 1,
          height: 1,
          radialSegments: 48,
        ),
        rock,
        vm.Vector3(0, -0.45, 0),
        vm.Vector3(2.0, 0.85, 2.0),
      ),
      part(ball, rock, vm.Vector3(0.2, -0.95, 0.1), vm.Vector3(0.7, 0.45, 0.7)),
    ]);
    // ---- The rug.
    piece('Rug', 0.08, vm.Vector3.zero(), [
      part(
        cyl,
        rug,
        vm.Vector3(0, _floor + 0.012, -0.05),
        vm.Vector3(1.2, 0.02, 1.05),
      ),
    ]);
    // ---- The curved wall behind, with a wooden trim along the top.
    final wall = <Node>[];
    const segs = 22;
    for (var i = 0; i < segs; i++) {
      final t = -1.45 + 2.9 * (i + 0.5) / segs;
      final w = 2.9 / segs * _wallR * 1.04;
      wall.add(
        part(
          cube,
          plaster,
          onWall(t, _floor + 1.45),
          vm.Vector3(w, 2.9, 0.14),
          rot: yaw(t),
        ),
      );
      wall.add(
        part(
          cube,
          wood,
          onWall(t, _floor + 2.92, -0.02),
          vm.Vector3(w, 0.1, 0.22),
          rot: yaw(t),
        ),
      );
      wall.add(
        part(
          cube,
          wood,
          onWall(t, _floor + 0.08, -0.04),
          vm.Vector3(w, 0.16, 0.12),
          rot: yaw(t),
        ),
      );
    }
    // Posts finish the two ends of the wall.
    for (final t in const [-1.47, 1.47]) {
      wall.add(part(cube, wood, onWall(t, _floor + 1.5, -0.01), vm.Vector3(0.16, 3.0, 0.2), rot: yaw(t)));
    }
    piece('Wall', 0.12, vm.Vector3.zero(), wall);
    // ---- The round window on the moon, to the right.
    const wt = 0.42;
    final wAt = onWall(wt, _floor + 1.85, 0.2);
    final window = piece('Window', 0.2, wAt, [
      part(
        cyl,
        windowSky,
        vm.Vector3.zero(),
        vm.Vector3(0.7, 0.02, 0.7),
        rot: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -math.pi / 2),
      ),
      part(
        TorusGeometry(
          radius: 0.72,
          tubeRadius: 0.07,
          radialSegments: 64,
          tubularSegments: 12,
        ),
        wood,
        vm.Vector3.zero(),
        vm.Vector3.all(1),
        rot: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
      ),
      part(cube, wood, vm.Vector3(0, 0, -0.02), vm.Vector3(1.4, 0.05, 0.05)),
      part(cube, wood, vm.Vector3(0, 0, -0.02), vm.Vector3(0.05, 1.4, 0.05)),
      part(
        cube,
        wood,
        vm.Vector3(0, -0.78, -0.08),
        vm.Vector3(1.0, 0.07, 0.22),
      ),
    ], rotY: wt + math.pi);
    // ---- String lights in three swags along the top of the wall.
    final bulbs = <Node>[];
    final wires = <Node>[];
    for (var swag = 0; swag < 3; swag++) {
      final t0 = -1.3 + swag * 0.87, t1 = t0 + 0.87;
      final pts = <vm.Vector3>[];
      for (var k = 0; k <= 10; k++) {
        final u = k / 10;
        final t = t0 + (t1 - t0) * u;
        pts.add(onWall(t, _floor + 2.78 - 0.3 * math.sin(u * math.pi), 0.12));
      }
      wires.add(
        Node(
          mesh: Mesh(
            TubeGeometry(
              CatmullRomPath(pts),
              radius: 0.008,
              radialSegments: 6,
              stations: 40,
              caps: false,
            ),
            wood,
          ),
        ),
      );
      for (var k = 1; k < 10; k += 2) {
        final b = part(
          ball,
          glow,
          pts[k] - vm.Vector3(0, 0.06, 0),
          vm.Vector3(0.045, 0.06, 0.045),
        );
        bulbs.add(b);
        wires.add(b);
      }
    }
    piece('Lights', 0.32, vm.Vector3.zero(), wires);
    // ---- The wall shelf of hats, with books, on the left.
    const st = -0.72;
    final shelfAt = onWall(st, _floor + 1.5, 0.22);
    final shelfParts = <Node>[
      part(cube, wood, vm.Vector3(0, 0, 0), vm.Vector3(1.05, 0.06, 0.32)),
      part(cube, wood, vm.Vector3(0, 0.62, 0), vm.Vector3(1.05, 0.06, 0.32)),
      for (final x in const [-0.42, 0.42])
        part(
          cube,
          wood,
          vm.Vector3(x, -0.1, 0.1),
          vm.Vector3(0.05, 0.18, 0.12),
        ),
      for (final (x, h, m) in [
        (0.28, 0.24, bookBlue),
        (0.35, 0.28, bookRed),
        (0.42, 0.22, bookGold),
      ])
        part(
          cube,
          m,
          vm.Vector3(x, 0.03 + 0.62 + h / 2, 0),
          vm.Vector3(0.055, h, 0.2),
        ),
    ];
    final shelfNode = piece(
      'Shelf',
      0.24,
      shelfAt,
      shelfParts,
      rotY: st + math.pi,
    );
    final shelf = <Node>[];
    final hats = [
      for (final a in Wardrobe.hats)
        if (a.unlocked(profile)) a,
    ].take(3).toList();
    for (var i = 0; i < hats.length; i++) {
      final hatNode = await loadScene(hats[i].asset);
      final holder = Node(name: 'Shelf:${hats[i].id}');
      holder.add(hatNode);
      holder.localTransform = vm.Matrix4.compose(
        vm.Vector3(i < 2 ? -0.24 + i * 0.4 : -0.2, i < 2 ? 0.03 : 0.65, 0),
        vm.Quaternion.identity(),
        vm.Vector3.all(0.34),
      );
      shelf.add(holder);
      shelfNode.add(holder);
    }
    // ---- The paper lantern lamp on a stand, on the right.
    final lampShade = part(
      ball,
      shade,
      vm.Vector3(0, 1.1, 0),
      vm.Vector3(0.24, 0.3, 0.24),
    );
    piece('Lamp', 0.28, vm.Vector3(1.45, _floor, 0.85), [
      part(cyl, wood, vm.Vector3(0, 0.5, 0), vm.Vector3(0.03, 1.0, 0.03)),
      part(cyl, wood, vm.Vector3(0, 0.03, 0), vm.Vector3(0.2, 0.06, 0.2)),
      part(cyl, wood, vm.Vector3(0, 1.42, 0), vm.Vector3(0.1, 0.03, 0.1)),
      for (var r = 0; r < 5; r++)
        part(
          TorusGeometry(
            radius: 1,
            tubeRadius: 0.02,
            radialSegments: 32,
            tubularSegments: 6,
          ),
          wood,
          vm.Vector3(0, 1.1 + (r - 2) * 0.12, 0),
          vm.Vector3(
            0.24 * math.sqrt(1 - math.pow((r - 2) * 0.12 / 0.3, 2)),
            1,
            0.24 * math.sqrt(1 - math.pow((r - 2) * 0.12 / 0.3, 2)),
          ),
        ),
      lampShade,
    ]);
    // ---- The cushion bed, with a blanket and a little pillow, front left.
    piece('Cushion', 0.36, vm.Vector3(-1.05, _floor, -0.25), [
      part(
        ball,
        cushion,
        vm.Vector3(0, 0.16, 0),
        vm.Vector3(0.62, 0.2, 0.5),
        name: 'Cushion',
      ),
      part(
        ball,
        cushion,
        vm.Vector3(0, 0.12, 0),
        vm.Vector3(0.66, 0.12, 0.54),
        name: 'Cushion',
      ),
      part(
        CapsuleGeometry(radius: 0.08, height: 0.6),
        blanket,
        vm.Vector3(0.05, 0.33, -0.12),
        vm.Vector3(1, 1, 1.6),
        name: 'Cushion',
        rot: vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), math.pi / 2),
      ),
      part(
        ball,
        blanket,
        vm.Vector3(-0.32, 0.36, 0.15),
        vm.Vector3(0.18, 0.1, 0.14),
        name: 'Cushion',
      ),
    ]);
    // ---- Books stacked by the bed, and plants.
    piece('Books', 0.4, vm.Vector3(-1.45, _floor, 0.75), [
      for (var i = 0; i < 4; i++)
        part(
          cube,
          [bookBlue, bookRed, bookGold, bookBlue][i],
          vm.Vector3(0, 0.05 + i * 0.09, 0),
          vm.Vector3(0.36 - i * 0.03, 0.08, 0.26),
          rot: yaw(i * 0.25 - 0.3),
        ),
    ]);
    Node plant(double h) {
      final n = Node();
      for (final c in [
        part(
          CylinderGeometry(
            bottomRadius: 0.75,
            topRadius: 1,
            height: 1,
            radialSegments: 24,
          ),
          terracotta,
          vm.Vector3(0, 0.11, 0),
          vm.Vector3(0.15, 0.22, 0.15),
        ),
        for (var i = 0; i < 7; i++)
          part(
            ball,
            leaf,
            vm.Vector3(
              math.cos(i * 0.9) * 0.1,
              0.3 + (i % 3) * 0.09 * h,
              math.sin(i * 0.9) * 0.1,
            ),
            vm.Vector3(0.07, 0.2 * h, 0.04),
            rot: vm.Quaternion.axisAngle(
              vm.Vector3(math.sin(i * 0.9), 0, -math.cos(i * 0.9)),
              0.55,
            ),
          ),
      ]) {
        n.add(c);
      }
      return n;
    }

    piece('Plant', 0.44, vm.Vector3(1.15, _floor, -0.95), [plant(1.0)]);
    piece('Plant2', 0.46, vm.Vector3(-1.65, _floor, 0.2), [plant(0.8)]);
    // ---- Ivy trailing from the wall trim.
    final ivy = <Node>[];
    for (final t in const [-1.2, -0.25, 0.95]) {
      for (var k = 0; k < 7; k++) {
        final p = onWall(
          t + math.sin(k * 0.8) * 0.05,
          _floor + 2.85 - k * 0.13,
          0.1,
        );
        ivy.add(
          part(ball, leaf, p, vm.Vector3(0.055, 0.04, 0.03), rot: yaw(t)),
        );
      }
    }
    piece('Ivy', 0.5, vm.Vector3.zero(), ivy);
    // ---- A ladder and a lantern hanging beneath the platform.
    piece('Below', 0.52, vm.Vector3.zero(), [
      for (final x in const [-0.12, 0.12])
        part(
          cyl,
          wood,
          vm.Vector3(-0.9 + x, -0.55, -1.75),
          vm.Vector3(0.025, 1.3, 0.025),
        ),
      for (var r = 0; r < 5; r++)
        part(
          cube,
          wood,
          vm.Vector3(-0.9, -0.05 - r * 0.24, -1.75),
          vm.Vector3(0.26, 0.03, 0.03),
        ),
      part(
        cyl,
        wood,
        vm.Vector3(1.0, -0.35, -1.55),
        vm.Vector3(0.008, 0.5, 0.008),
      ),
      part(
        ball,
        glow,
        vm.Vector3(1.0, -0.68, -1.55),
        vm.Vector3(0.09, 0.12, 0.09),
      ),
    ]);
    // ---- Far off in the night: little floating islands with lit windows,
    // and paper lanterns drifting up.
    final far = <Node>[];
    for (final (x, y, z, r) in const [(-4.6, 3.6, 7.0, 0.9), (4.2, 0.6, 9.0, 1.3), (-3.2, -1.6, 6.0, 0.6), (3.0, 4.6, 11.0, 0.7), (-5.5, 1.0, 12.0, 1.1)]) {
      far.add(part(CylinderGeometry(bottomRadius: 0.3, topRadius: 1, height: 1, radialSegments: 24), rock, vm.Vector3(x, y, z), vm.Vector3(r, r * 0.6, r)));
      far.add(part(cyl, leaf, vm.Vector3(x, y + r * 0.32, z), vm.Vector3(r * 0.95, r * 0.08, r * 0.95)));
      for (var k = 0; k < 3; k++) {
        far.add(part(ball, glow, vm.Vector3(x + (k - 1) * r * 0.35, y + r * 0.45, z - r * 0.5), vm.Vector3.all(0.05 + r * 0.02)));
      }
    }
    piece('Far', 0.06, vm.Vector3.zero(), far);
    final lanterns = <Node>[];
    for (var i = 0; i < 9; i++) {
      final a = i * 2.39;
      lanterns.add(part(ball, glow, vm.Vector3(math.cos(a) * (3.4 + i * 0.25), -1.2 + i * 0.7, 3.5 + math.sin(a) * 2.5), vm.Vector3(0.07, 0.09, 0.07)));
    }
    piece('Lanterns', 0.1, vm.Vector3.zero(), lanterns);

    // ---- The board: a live widget on the wall, left of the window.
    final board = Node(name: 'Board')
      ..addComponent(
        WidgetComponent(
          size: const Size(250, 176),
          pixelRatio: 2.5,
          worldHeight: 0.62,
          child: _Board(profile: profile, name: friendName, onParty: onParty),
        ),
      );
    piece('Easel', 0.5, onWall(-0.12, _floor + 1.95, 0.12), [
      board,
    ], rotY: -0.12);

    return FriendRoom._(
      root,
      sc,
      pieces,
      shelf,
      window,
      windowSky,
      bulbs,
      lampShade,
    );
  }

  final Node root;
  final Scenery _scenery;
  final List<_Piece> _pieces;
  final List<Node> _shelf;
  final Node _window;
  final PreprocessedMaterial _windowSky;
  final List<Node> _bulbs;
  final Node _lampShade;

  /// Effects for dust in the lamplight and fireflies outside.
  Vfx? fx;
  double _mote = 0;
  final _rng = math.Random(9);

  /// Called when a piece lands as the room opens: where, and how big it is.
  void Function(vm.Vector3 at, double size)? onLand;

  /// World positions of things to tap in clips: a hat on the shelf, the
  /// cushion, and the board's Party button.
  vm.Vector3 hatAt(int i) =>
      _shelf[math.min(i, _shelf.length - 1)].globalTransform.getTranslation() +
      vm.Vector3(0, 0.12, 0);
  int get hatCount => _shelf.length;
  String hatId(int i) => _shelf[i].name.substring(6);
  vm.Vector3 get cushionAt =>
      _pieces
          .firstWhere((p) => p.node.name == 'Cushion')
          .node
          .globalTransform
          .getTranslation() +
      vm.Vector3(0, 0.2, 0);
  vm.Vector3 get partyAt =>
      _pieces
          .firstWhere((p) => p.node.name == 'Easel')
          .node
          .globalTransform
          .getTranslation() -
      vm.Vector3(0, 0.22, 0);

  /// The sky in the window for the time of day: 0 auto, 1 morning, 2 day,
  /// 3 evening, 4 night.
  void daylight(int part) {
    final (top, bottom, moon) = switch (part) {
      1 => (vm.Vector4(0.35, 0.45, 0.8, 1), vm.Vector4(1.0, 0.65, 0.55, 1), vm.Vector4(0.3, 0.3, 0.14, 0)),
      2 => (vm.Vector4(0.25, 0.5, 0.95, 1), vm.Vector4(0.65, 0.82, 1.0, 1), vm.Vector4(0.7, 0.75, 0.15, 0)),
      _ => (vm.Vector4(0.03, 0.05, 0.16, 1), vm.Vector4(0.12, 0.12, 0.32, 1), vm.Vector4(0.62, 0.68, 0.16, 0)),
    };
    _windowSky.parameters
      ..setVec4('top_color', top)
      ..setVec4('bottom_color', bottom)
      ..setVec4('moon', moon);
  }

  /// The warm lamp, for lighting the friend to match.
  vm.Vector3 get lampAt => _scenery.lamps.first.position;

  /// Pops pieces in as [open] goes from 0 to 1, and animates the room.
  void update(
    double open,
    double time,
    vm.Vector3 cameraPosition, {
    double feet = 0.47,
    vm.Vector3? friendGlow,
    double dt = 1 / 60,
  }) {
    for (final p in _pieces) {
      final t = ((open - p.delay) / 0.45).clamp(0.0, 1.0);
      if (p.lastT < 0.22 && t >= 0.22)
        onLand?.call(p.at, p.node.name == 'Floor' ? 2.0 : 0.6);
      p.lastT = t;
      final s = t <= 0
          ? 0.0001
          : Curves.elasticOut.transform(t) * 0.98 + 0.02 * t;
      if (p.node.name == 'Easel') {
        // The board faces the room; its visible face points down -z, so it
        // is turned and mirrored to read the right way round.
        final rot = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), p.rotY);
        p.node.localTransform = vm.Matrix4.compose(
          p.at,
          rot,
          vm.Vector3(-s, s, s),
        );
        continue;
      }
      p.node.localTransform = vm.Matrix4.compose(
        p.at,
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), p.rotY),
        vm.Vector3.all(s),
      );
    }
    // The lamp breathes and flickers; the bulbs twinkle out of step.
    final flicker =
        1 +
        0.05 * math.sin(time * 9) +
        0.04 * math.sin(time * 13.7) +
        0.02 * math.sin(time * 31);
    final lit = ((open - 0.3) / 0.4).clamp(0.0, 1.0);
    _scenery.lamps[0].color = vm.Vector3(1.7, 1.05, 0.5) * (flicker * lit);
    if (friendGlow != null) _scenery.lamps[2].color = friendGlow * (0.5 * lit);
    _scenery.lamps[1].color = vm.Vector3(0.35, 0.45, 0.85) * lit;
    _scenery.relight();
    _lampShade.localTransform = vm.Matrix4.compose(
      vm.Vector3(0, 1.1, 0),
      vm.Quaternion.identity(),
      vm.Vector3(0.24, 0.3, 0.24) * (0.98 + 0.02 * flicker),
    );
    for (var i = 0; i < _bulbs.length; i++) {
      final b = _bulbs[i];
      final at = b.localTransform.getTranslation();
      final tw = 0.8 + 0.25 * math.sin(time * (1.6 + (i % 5) * 0.37) + i);
      b.localTransform = vm.Matrix4.compose(
        at,
        vm.Quaternion.identity(),
        vm.Vector3(0.045, 0.06, 0.045) * tw,
      );
    }
    _windowSky.parameters.setFloat('time', time);
    for (var i = 0; i < _shelf.length; i++) {
      final n = _shelf[i];
      final at = n.localTransform.getTranslation();
      n.localTransform = vm.Matrix4.compose(
        at,
        vm.Quaternion.axisAngle(
          vm.Vector3(0, 1, 0),
          math.sin(time * 0.7 + i) * 0.35,
        ),
        vm.Vector3.all(0.34),
      );
    }
    _window.visible = open > 0.05;
    // Dust drifting in the lamplight, and fireflies out in the night.
    final f = fx;
    if (f != null && open > 0.8) {
      _mote -= dt;
      if (_mote <= 0) {
        _mote = 0.12;
        final lamp = lampAt;
        final p =
            lamp +
            vm.Vector3(
              (_rng.nextDouble() - 0.5) * 1.6,
              (_rng.nextDouble() - 0.6) * 1.2,
              (_rng.nextDouble() - 0.5) * 1.2,
            );
        f.burst(
          p,
          count: 1,
          speed: 0.06,
          color: vm.Vector3(1.0, 0.8, 0.5) * 0.7,
          size: 0.018,
          life: 3.5,
          gravity: -0.02,
          drag: 0.2,
          shape: VfxShape.dot,
        );
        if (_rng.nextDouble() < 0.35) {
          final side = _rng.nextBool() ? 1.0 : -1.0;
          final q = vm.Vector3(
            side * (2.4 + _rng.nextDouble() * 1.2),
            -0.5 + _rng.nextDouble() * 3,
            -0.5 + _rng.nextDouble() * 2.5,
          );
          f.burst(
            q,
            count: 1,
            speed: 0.2,
            color: vm.Vector3(1.4, 1.5, 0.6),
            size: 0.04,
            life: 2.8,
            gravity: -0.05,
            drag: 0.3,
            shape: VfxShape.flare,
          );
        }
      }
    }
  }

  /// What the tapped node means: a hat id to wear, [nap], or null.
  static String? actionFor(Node? n) {
    for (var node = n; node != null; node = node.parent) {
      final name = node.name;
      if (name.startsWith('Shelf:')) return name.substring(6);
      if (name == 'Cushion') return nap;
    }
    return null;
  }
}

class _Piece {
  _Piece(this.node, this.at, this.delay, this.rotY);
  final Node node;
  final vm.Vector3 at;
  final double delay;
  final double rotY;
  double lastT = 0;
}

class _Board extends StatelessWidget {
  const _Board({
    required this.profile,
    required this.name,
    required this.onParty,
  });
  final Profile profile;
  final String name;
  final VoidCallback onParty;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: profile,
      builder: (context, _) {
        Widget row(IconData icon, String label, String value, Color color) =>
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF55607F),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF1B2340),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBF2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF8C6239), width: 5),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "$name's board",
                style: const TextStyle(
                  color: Color(0xFF1B2340),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              row(
                Icons.vpn_key_rounded,
                'Keys',
                '${profile.keys} of 5',
                const Color(0xFFE8A33D),
              ),
              row(
                Icons.star_rounded,
                'Stars',
                '${profile.stars}',
                const Color(0xFFE8A33D),
              ),
              row(
                Icons.auto_awesome_rounded,
                'Best catch',
                '${profile.bestCatch}',
                const Color(0xFF5B6BD6),
              ),
              const Spacer(),
              SizedBox(
                height: 30,
                child: FilledButton.icon(
                  onPressed: onParty,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6FA8),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.celebration_rounded, size: 16),
                  label: const Text(
                    'Party!',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
