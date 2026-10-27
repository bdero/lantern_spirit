import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../games/game_host.dart';
import '../games/sky_lift.dart';
import '../games/star_catch.dart';
import '../lantern/character.dart';
import '../lantern/friends.dart';
import '../lantern/wardrobe.dart';
import '../map/park_diorama.dart';
import '../room/room.dart';
import '../show/fireworks.dart';
import '../show/lagoon_set.dart';
import '../vfx/shadow.dart';
import '../vfx/vfx.dart';
import 'profile.dart';

/// Loads and compiles what every screen draws before the park opens, so the
/// first visit to the room, the wardrobe, the show, the map, or a game opens
/// without a stall.
///
/// The loads land in flutter_scene's shared scene and material caches, and
/// the warm scenes compile their pipelines into its shared pipeline cache.
/// The warm scenes themselves are thrown away. On the web this is most of the
/// startup: every first draw of a material otherwise compiles a WebGL program
/// right then, and every first asset is a network fetch.
abstract final class Preload {
  static const _materials = [
    'assets/bubble.fmat',
    'assets/ember.fmat',
    'assets/face.fmat',
    'assets/hologram.fmat',
    'assets/scenery.fmat',
    'assets/shadow.fmat',
    'assets/skin.fmat',
    'assets/toy.fmat',
    'assets/vfx.fmat',
    'assets/window_sky.fmat',
    'assets/games/aurora.fmat',
    'assets/games/cloud.fmat',
    'assets/games/moon.fmat',
    'assets/show/firework.fmat',
    'assets/show/glow_dot.fmat',
    'assets/show/smoke.fmat',
    'assets/show/water.fmat',
  ];

  /// Each warm scene counts for this many asset loads in the progress, since
  /// building and compiling one takes far longer than fetching a file.
  static const _warmWeight = 12;

  /// How long one offscreen warm-up frame may spend building pipelines before
  /// it yields, so the loading screen keeps animating.
  static const _slice = Duration(milliseconds: 12);

  static Future<void> run(
    Profile profile, {
    required void Function(double done) onProgress,
  }) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final sounds = [
      for (final a in manifest.listAssets())
        if (a.startsWith('assets/sfx/') && a.endsWith('.wav')) a,
    ];
    final scenes = [
      'assets/lantern.glb',
      for (final a in [...Wardrobe.hats, Wardrobe.scarf]) a.asset,
    ];
    final atlases = {for (final f in Friends.all) f.atlas};

    final warms = <Future<void> Function()>[
      () => _warmPark(),
      () => _warmRoom(profile),
      () => _warmShow(),
      () => _warmMap(),
      for (final make in <MiniGame Function()>[SkyLift.new, StarCatch.new])
        () => _warmGame(make()),
    ];
    final total =
        scenes.length +
        _materials.length +
        atlases.length +
        sounds.length +
        1 +
        warms.length * _warmWeight;
    var done = 0;
    void tick([int n = 1]) => onProgress(math.min(1, (done += n) / total));

    // Fetch everything at once. Sounds only warm the HTTP cache here: each
    // scene's Sfx decodes its own clips, which is quick once the bytes are
    // local.
    await Future.wait([
      for (final s in scenes) _quiet(loadScene(s)).whenComplete(tick),
      for (final m in _materials)
        _quiet(loadFmatMaterial(m)).whenComplete(tick),
      for (final a in atlases)
        _quiet(Texture2D.fromAsset(a)).whenComplete(tick),
      for (final s in sounds) _quiet(rootBundle.load(s)).whenComplete(tick),
      _quiet(
        ui.FragmentProgram.fromAsset('shaders/screen_warp.frag'),
      ).whenComplete(tick),
    ]);

    // Then build and compile one screen at a time, which is where the time
    // goes on the web.
    for (final warm in warms) {
      await _quiet(warm());
      tick(_warmWeight);
    }
  }

  /// A failed preload step only means that screen loads on first use, as it
  /// would without the preload, so it never stops the park from opening.
  static Future<T?> _quiet<T>(Future<T> f) async {
    try {
      return await f;
    } catch (e, st) {
      debugPrint('Preload step failed: $e\n$st');
      return null;
    }
  }

  static PerspectiveCamera _camera() => PerspectiveCamera(
    position: vm.Vector3(0, 1.6, 7.6),
    target: vm.Vector3(0, 1.2, 0),
  );

  static Future<void> _warm(Scene scene, Camera camera) async {
    await scene.warmUp(
      [RenderView(camera: camera)],
      includeOffscreen: true,
      sliceBudget: _slice,
    );
    scene.dispose();
  }

  /// The header and overlay: a lantern friend and a toy friend, every
  /// accessory, the effects, the contact shadow, and each material on its
  /// own sphere so screens that draw it on other geometry still find its
  /// fragment shader compiled.
  static Future<void> _warmPark() async {
    final scene = Scene();
    scene.postProcess.bloom.enabled = true;
    await LanternCharacter.load(scene, friend: Friends.lumi);
    await LanternCharacter.load(
      scene,
      friend: Friends.all.firstWhere(
        (f) => !f.isLantern,
        orElse: () => Friends.lumi,
      ),
    );
    for (final a in [...Wardrobe.hats, Wardrobe.scarf]) {
      scene.add(await loadScene(a.asset));
    }
    await Vfx.create(scene);
    await ContactShadow.create(scene);
    final sphere = SphereGeometry(radius: 0.2, segments: 12, rings: 8);
    for (final m in _materials) {
      final material = await _quiet(loadFmatMaterial(m));
      if (material != null) scene.add(Node(mesh: Mesh(sphere, material)));
    }
    await _warm(scene, _camera());
  }

  /// The room built for the starting friend, kept for its first visit (see
  /// [takeRoom]), since building it is most of what that visit costs.
  static FriendRoom? _room;
  static String? _roomFriend;
  static VoidCallback? _roomParty;

  /// The preloaded room, once, when [friendName] is still the friend it was
  /// built for. Its party button calls [onParty].
  static FriendRoom? takeRoom(
    String friendName, {
    required VoidCallback onParty,
  }) {
    final room = _room;
    _room = null;
    if (room == null || _roomFriend != friendName) return null;
    _roomParty = onParty;
    return room;
  }

  static Future<void> _warmRoom(Profile profile) async {
    final friendName = Friends.byId(profile.friend).name;
    final room = await FriendRoom.build(
      profile: profile,
      friendName: friendName,
      onParty: () => _roomParty?.call(),
    );
    final scene = Scene();
    final camera = _camera();
    scene.add(room.root);
    room.update(0, 0, camera.position);
    await scene.warmUp(
      [RenderView(camera: camera)],
      includeOffscreen: true,
      sliceBudget: _slice,
    );
    room.root.detach();
    scene.dispose();
    _room = room;
    _roomFriend = friendName;
  }

  static Future<void> _warmShow() async {
    final results = await Future.wait([
      LagoonSet.build(),
      loadFmatMaterial('assets/show/firework.fmat'),
      loadFmatMaterial('assets/show/smoke.fmat'),
    ]);
    final set = results[0] as LagoonSet;
    final fireworks = FireworkRenderer(
      lightMaterial: results[1] as PreprocessedMaterial,
      smokeMaterial: results[2] as PreprocessedMaterial,
    );
    final scene = Scene()
      ..skybox = Skybox(set.sky)
      ..add(set.root)
      ..add(fireworks.smokeNode)
      ..add(fireworks.lightNode);
    await LanternCharacter.load(scene);
    await _warm(scene, _camera());
  }

  static Future<void> _warmMap() async {
    final scene = Scene();
    // The map's six rides and its gate (lib/map/park_map_screen.dart).
    await ParkDiorama.build(
      scene,
      [
        vm.Vector3(-3.0, 0, 2.2),
        vm.Vector3(3.1, 0, 2.6),
        vm.Vector3(-2.3, 0, -1.6),
        vm.Vector3(2.7, 0, -1.2),
        vm.Vector3(0.2, 0, 4.0),
        vm.Vector3(-0.2, 0, 0.9),
      ],
      vm.Vector3(0, 0, -3.6),
    );
    await LanternCharacter.load(scene);
    await _warm(
      scene,
      PerspectiveCamera(
        position: vm.Vector3(0, 9, 9),
        target: vm.Vector3.zero(),
      ),
    );
  }

  static Future<void> _warmGame(MiniGame game) async {
    final lumi = await LanternCharacter.load(game.scene);
    await game.load(lumi);
    await game.scene.warmUp(
      [RenderView(camera: game.camera)],
      includeOffscreen: true,
      sliceBudget: _slice,
    );
    game.dispose();
    game.scene.dispose();
  }
}
