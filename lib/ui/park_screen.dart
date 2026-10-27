import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../app/scene_clock.dart';
import '../app/clock.dart';
import '../app/profile.dart';
import '../app/preload.dart';
import '../app/profile_scope.dart';
import '../app/sfx.dart';
import '../app/show_route.dart';
import '../lantern/attention.dart';
import '../lantern/character.dart';
import '../lantern/friends.dart';
import '../lantern/moods.dart';
import '../lantern/themes.dart';
import '../show/show_screen.dart';
import '../games/game_host.dart';
import '../map/park_map_screen.dart';
import '../room/room.dart';
import '../booth/photo_booth_screen.dart';
import '../voice/lumi_brain.dart';
import '../fx/card_jenga.dart';
import '../fx/lights_out.dart';
import '../fx/peel_board.dart';
import '../fx/screen_fx.dart';
import 'notification_snack.dart';
import '../vfx/vfx.dart';
import '../clips/social_clip.dart';
import '../clips/touches.dart';
import '../games/sky_lift.dart';
import '../games/star_catch.dart';
import 'creative_panel.dart';
import 'errand.dart';
import 'wardrobe_screen.dart';
import 'inner_light.dart';
import 'palette.dart';

part 'park_clips.dart';
part 'park_life.dart';
part 'park_snack.dart';
part 'park_spectacle.dart';
part 'park_pet.dart';
part 'park_voice.dart';

/// An ordinary park-app home screen with the character living in its header.
///
/// Everything below the header is plain Flutter UI. The character reacts to
/// it: taps and drags in the header, the list's scroll speed, and a reward
/// coin that flies out of a card into the 3D scene.
class ParkScreen extends StatefulWidget {
  const ParkScreen({super.key});

  @override
  State<ParkScreen> createState() => ParkScreenState();
}

class ParkScreenState extends State<ParkScreen> with TickerProviderStateMixin {
  final Scene scene = Scene();
  LanternCharacter? character;
  Object? _loadError;

  final _headerKey = GlobalKey();
  final _collectKey = GlobalKey();
  final _scroll = ScrollController();
  final frameTick = ValueNotifier<int>(0);

  late final PerspectiveCamera camera = PerspectiveCamera(
    fovRadiansY: 27 * vm.degrees2Radians,
    position: vm.Vector3(0, 1.55, 7.6 * kFaceZ),
    target: vm.Vector3(0, 1.38, 0),
  );
  Size _headerSize = Size.zero;
  Size get headerSize => _headerSize;

  bool panelOpen = false;

  /// What Lumi pays attention to on this screen.
  final Attention attention = Attention();

  /// The emotion pad. When on, Lumi's resting pose blends four corner moods
  /// from [mood], which drifts with what happens on the screen.
  bool moodPadOn = false;
  final vm.Vector2 mood = vm.Vector2(0.45, 0.1);
  static final vm.Vector2 _moodRest = vm.Vector2(0.5, -0.25);

  void setMoodPad(bool on) => setState(() => moodPadOn = on);

  /// Nudges the mood point (x: mood, y: energy), as rewards and pokes do.
  void nudgeMood(double dx, double dy) {
    mood.setValues((mood.x + dx).clamp(-1.0, 1.0), (mood.y + dy).clamp(-1.0, 1.0));
  }

  /// Where the hands and head glow on screen, for the light painted over the
  /// list.
  final glowPoints = ValueNotifier<List<GlowPoint>>(const []);

  void setPanelOpen(bool open) => setState(() => panelOpen = open);

  // List scroll speed in logical px/s, measured from scroll updates.
  double _scrollSpeed = 0;
  Duration _lastScroll = Duration.zero;
  bool collected = false;

  // ------------------------------------------------ the room
  /// The header growing into the friend's room, 0 (header) to 1 (room).
  late final AnimationController _room = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..addListener(() => setState(() {}))
    ..addStatusListener((s) {
      if (s == AnimationStatus.dismissed) {
        _roomScene?.root.detach();
        _roomScene = null;
      }
    });
  FriendRoom? _roomScene;
  double _roomLast = 0;
  bool _roomLoading = false;

  /// How far open the room is, eased.
  double get roomOpen => Curves.easeInOutCubic.transform(_room.value);

  Future<void> _openRoom() async {
    final c = character;
    if (c == null || _roomLoading || errandActive || _room.isAnimating) return;
    _roomLoading = true;
    final room = Preload.takeRoom(c.friend.name, onParty: _party) ?? await FriendRoom.build(profile: ProfileScope.read(context), friendName: c.friend.name, onParty: _party);
    _roomLoading = false;
    if (!mounted) return;
    _roomScene?.root.detach();
    _roomScene = room;
    room.fx = _fx;
    room.onLand = (at, size) => _fx?.puffs(at + vm.Vector3(0, 0.1, 0), count: (6 + size * 6).round(), color: vm.Vector3(0.32, 0.3, 0.42), size: 0.18 * size, speed: 1.2 * size, life: 0.6);
    room.update(0, 0, camera.position);
    scene.add(room.root);
    c.wake();
    Sfx.light();
    Sfx.sound('room_open');
    _room.forward();
  }

  void _closeRoom() {
    if (_roomScene == null) return;
    _room.reverse();
  }

  @visibleForTesting
  Future<void> openRoomForTest() => _openRoom();

  @visibleForTesting
  void closeRoomForTest() => _closeRoom();

  void _party() {
    final c = character;
    if (c == null) return;
    c.celebrate();
    // Confetti cannons from both sides, then sparkle bursts overhead.
    final colors = [vm.Vector3(2.0, 0.6, 1.0), vm.Vector3(0.6, 1.4, 2.2), vm.Vector3(2.2, 1.7, 0.5), vm.Vector3(0.7, 2.0, 0.9)];
    for (var i = 0; i < 6; i++) {
      AppClock.delayed(Duration(milliseconds: 110 * i), () {
        if (!mounted) return;
        final fx = _fx;
        if (fx == null) return;
        final side = i.isEven ? 1.0 : -1.0;
        final from = vm.Vector3(side * 1.6, 0.4, -0.4);
        fx.burst(from, count: 34, speed: 4.5, color: colors[i % 4], color2: colors[(i + 1) % 4], shape: VfxShape.flare, life: 1.6, gravity: 3.2, drag: 1.2, bias: vm.Vector3(-side * 2.5, 4.5, 0));
        if (i >= 3) {
          final a = i * 1.3;
          final at = c.headCenter + vm.Vector3(math.cos(a) * 0.9, 0.9 + math.sin(a) * 0.4, -0.3);
          fx
            ..flare(at, size: 1.2, color: colors[i % 4], life: 0.4)
            ..ring(at, radius: 0.9, color: colors[(i + 2) % 4], life: 0.4);
        }
      });
    }
    Sfx.heavy();
    Sfx.sound('party');
  }

  @visibleForTesting
  void partyForTest() => _party();

  late final AnimationController _coin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );
  Offset _coinFrom = Offset.zero;
  Offset _coinTo = Offset.zero;

  // ------------------------------------------------ leaving the header
  /// A full-screen, transparent 3D layer over the whole app that Lumi moves
  /// into when it leaves the header. Only mounted while Lumi is out.
  final Scene _outScene = Scene();

  /// The peel's board, in a layer of its own under the overlay: its cards
  /// keep the app's exact colors (display-referred), and the friend's bloom
  /// and effects, drawn above, still glow over them.
  final Scene _boardScene = Scene();
  PerspectiveCamera _outCamera = PerspectiveCamera();
  Rect _outRect = Rect.zero;
  Size _screenSize = Size.zero;
  double _headerHeight = 0;
  Outing? _errand;

  /// The card a peek visit hides behind.
  GlobalKey? _peekKey;

  /// The card Lumi is behind, while it is behind one; the overlay is clipped
  /// below the card's top edge there.
  final _behind = ValueNotifier<Rect?>(null);

  /// The full-screen moments: shakes, pulses, ripples, lights out, card
  /// Jenga, and the peel into 3D.
  final spectacle = _Spectacle();

  /// Being petted: strokes, hearts, and the trance.
  final pet = _Pet();

  /// Talking to the friend: listening, thinking, answering, showing.
  final voice = _Voice();

  /// The park map, while it is open, so the friend can walk somewhere in it.
  final _mapScreenKey = GlobalKey<ParkMapScreenState>();

  /// The key in flight or in Lumi's hand: global position and size.
  final _carried = ValueNotifier<(Offset, double)?>(null);
  bool _lumiPressing = false;

  /// Whether Lumi is out of the header on an errand.
  bool get errandActive => _errand != null;

  /// Pulls the header camera back into the room as the header grows.
  void _roomCamera(double time) {
    final e = roomOpen;
    vm.Vector3 lerp(vm.Vector3 a, vm.Vector3 b) => a + (b - a) * e;
    camera
      ..position = lerp(vm.Vector3(0, 1.55, 7.6 * kFaceZ), vm.Vector3(0.0, 4.4, 13.4 * kFaceZ))
      ..target = lerp(vm.Vector3(0, 1.38, 0), vm.Vector3(0, 1.25, 0.4))
      ..fovRadiansY = (27 + 11 * e) * vm.degrees2Radians;
    final c = character;
    final room = _roomScene;
    // Standing on the room's floor; floating everywhere else in the header.
    c?.grounded = room != null && e > 0.5;
    if (room != null && c != null) {
      final dt = (time - _roomLast).clamp(0.0, 0.05);
      _roomLast = time;
      final glow = _colorOf(c) * 0.5;
      room.update(_room.value, time, camera.position, feet: c.restFeet, friendGlow: glow, dt: dt);
      // The lamp lights the friend too, warm from its side.
      final lamp = room.lampAt;
      c.ambientColor.setFrom(vm.Vector3(0.55, 0.34, 0.16) * e);
      c.ambientDirection.setFrom((lamp - c.headCenter)..normalize());
    } else if (c != null && e <= 0) {
      c.ambientColor.setZero();
    }
  }

  /// Seconds into the current errand, for tests.
  @visibleForTesting
  double get errandTime => _errand?.time ?? -1;

  @override
  void initState() {
    super.initState();
    for (final s in [scene, _outScene]) {
      s.postProcess.bloom
        ..enabled = true
        ..threshold = 1.0
        ..intensity = 0.32
        ..scatter = 0.72;
    }
    _outScene.debugCheckCoplanarOverlaps = false;
    _boardScene.debugCheckCoplanarOverlaps = false;
    // The app's sounds play through this scene, which stays mounted under
    // every screen pushed over the park.
    Sfx.ui = Sfx(scene)..preload(_sounds);
    _coin.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        character?.celebrate();
        nudgeMood(0.4, 0.55);
        ProfileScope.read(context).addKey();
        setState(() => collected = true);
      }
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await LanternCharacter.load(scene, friend: Friends.byId(ProfileScope.read(context).friend));
      if (!mounted) return;
      // Compile every pipeline the character, its sparks, and the post
      // effects use before it first appears, so nothing hitches mid-animation.
      c.update(0, 0);
      c.sparks.showAllForWarmUp(true);
      await scene.warmUp([RenderView(camera: camera)], includeOffscreen: true);
      c.sparks.showAllForWarmUp(false);
      if (!mounted) return;
      c.addListener(() => setState(() {}));
      _fx = await Vfx.create(scene);
      _outFx = await Vfx.create(_outScene);
      if (!mounted) return;
      setState(() => character = c);
      _dress();
    } catch (e, st) {
      debugPrint('Lantern Spirit failed to load: $e\n$st');
      if (mounted) setState(() => _loadError = e);
    }
  }

  Profile? _profile;

  /// Effects in the header, and in the layer over the app during an errand.
  Vfx? _fx;
  Vfx? _outFx;

  /// A greeting from a friend who just arrived, shown for a moment.
  String? _hello;
  double _helloUntil = 0;
  double _clock = 0;

  vm.Vector3 _colorOf(LanternCharacter c) {
    final col = c.glowSources.first.$2;
    return vm.Vector3(col.x, col.y, col.z) * 1.6 + vm.Vector3.all(0.3);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = ProfileScope.read(context);
    if (!identical(p, _profile)) {
      _profile?.removeListener(_dress);
      _profile = p..addListener(_dress);
    }
  }

  /// Dresses Lumi from the profile: hat, scarf, theme, hue, glow.
  void _dress() {
    final c = character;
    final p = _profile;
    if (c == null || p == null) return;
    if (c.friend.id != p.friend) {
      _swapTo(Friends.byId(p.friend));
      return;
    }
    c
      ..glowScale = p.glow
      ..hueShift = p.hueShift;
    final theme = LanternTheme.all.firstWhere((t) => t.name == p.theme, orElse: () => LanternTheme.aurora);
    if (c.theme != theme) c.setTheme(theme);
    c.wear(hat: p.hat, scarf: p.scarf);
  }

  /// Opens the wardrobe as a sheet under the header. Lumi stays exactly
  /// where it is and changes outfits live as the guest picks.
  void _openWardrobe({int tab = 0}) {
    final header = _headerSize.height;
    if (header <= 0) return;
    character?.wake();
    Sfx.sound('open');
    Navigator.of(context)
        .push(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, _, _) => WardrobeScreen(headerHeight: header, initialTab: tab),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
          ),
          child: child,
        ),
      ),
    )
        .then((_) => Sfx.sound('close'));
  }

  @override
  void dispose() {
    if (Sfx.ui != null) {
      Sfx.ui!.dispose();
      Sfx.ui = null;
    }
    life.rainVoice?.stop();
    voice.stt.cancel();
    voice.field.dispose();
    voice.focus.dispose();
    _profile?.removeListener(_dress);
    _coin.dispose();
    _room.dispose();
    _scroll.dispose();
    scene.removeAll();
    _outScene.removeAll();
    super.dispose();
  }

  // ---------------------------------------------------------------- friends
  LanternCharacter? _leaving;
  double _swapT = -1;
  bool _loadingFriend = false;

  /// Swaps in another friend: the new one loads off screen, the current one
  /// pops out in a burst of sparks, and the new one springs into its place.
  Future<void> _swapTo(Friend f) async {
    final old = character;
    if (old == null || _loadingFriend || _leaving != null) return;
    _loadingFriend = true;
    // Whatever trick was playing belongs to the friend who is leaving.
    endTrick(old);
    try {
      final next = await LanternCharacter.load(scene, friend: f);
      if (!mounted) return;
      next
        ..place(vm.Vector3.zero(), 0, scale: 0.001)
        ..update(0, 0);
      await scene.warmUp([RenderView(camera: camera)], includeOffscreen: true);
      if (!mounted) return;
      next.addListener(() => setState(() {}));
      setState(() {
        _leaving = old;
        character = next;
        _swapT = 0;
      });
      _dress();
      next.wake();
      Sfx.medium();
      Sfx.sound('swap');
    } finally {
      _loadingFriend = false;
    }
    // A choice made while loading wins.
    final p = _profile;
    if (p != null && character?.friend.id != p.friend) _dress();
  }

  void _swapTick(double dt, double time) {
    final leaving = _leaving;
    final c = character;
    if (_swapT < 0 || c == null) return;
    final before = _swapT;
    _swapT += dt;
    bool crossed(double at) => before < at && _swapT >= at;
    final fx = _fx;
    final center = vm.Vector3(0, 1.45, 0);
    if (leaving != null) {
      // A quick inhale, a pop into confetti in its own colors, then gone.
      final t = (_swapT / 0.26).clamp(0.0, 1.0);
      final s = t < 0.4 ? 1 + 0.14 * Curves.easeOut.transform(t / 0.4) : 1.14 * (1 - Curves.easeIn.transform((t - 0.4) / 0.6));
      leaving
        ..place(vm.Vector3.zero(), 0, scale: math.max(s, 0.001))
        ..update(dt, time);
      if (crossed(0.1) && fx != null) {
        final col = _colorOf(leaving);
        fx
          ..ring(leaving.headCenter, radius: 1.6, color: col, life: 0.4)
          ..flare(leaving.headCenter, size: 1.6, color: col * 1.2, life: 0.3)
          ..burst(leaving.headCenter, count: 46, speed: 4.2, color: col, color2: vm.Vector3(2, 1.8, 1.4), shape: VfxShape.flare, life: 0.8, gravity: 3.5);
      }
      if (t >= 1) {
        leaving.root.detach();
        leaving.dispose();
        _leaving = null;
      }
    }
    // Sparkles spiral in to where the new friend will form.
    if (fx != null && _swapT > 0.08 && _swapT < 0.42) {
      final col = _colorOf(c);
      for (var i = 0; i < 5; i++) {
        final a = math.Random().nextDouble() * math.pi * 2;
        final r = 1.5 + math.Random().nextDouble() * 0.5;
        final at = center + vm.Vector3(math.cos(a) * r, math.sin(a) * r * 0.9, -0.2);
        final toward = (center - at)..scale(1 / 0.28);
        toward.add(vm.Vector3(-math.sin(a), math.cos(a), 0) * 2.5);
        fx.streak(at, toward, color: col * 0.8, width: 0.03, length: 0.05, life: 0.28);
      }
    }
    if (crossed(0.4) && fx != null) {
      fx
        ..flare(center, size: 2.2, color: _colorOf(c) * 1.3, life: 0.35)
        ..ring(center, radius: 1.9, color: _colorOf(c), life: 0.45);
    }
    final t = ((_swapT - 0.38) / 0.6).clamp(0.0, 1.0);
    c.place(vm.Vector3.zero(), 0, scale: math.max(Curves.elasticOut.transform(t), 0.001));
    if (t >= 1) {
      c.place(vm.Vector3.zero(), 0);
      c
        ..jolt(0.6)
        ..celebrate();
      _hello = "Hi, I'm ${c.friend.name}!";
      _helloUntil = _clock + 2.4;
      _swapT = -1;
    }
  }

  @visibleForTesting
  bool get swapping => _swapT >= 0 || _loadingFriend;

  // ---------------------------------------------------------------- input
  Offset? _headScreen() {
    final c = character;
    if (c == null || _headerSize.isEmpty) return null;
    return camera.worldToScreen(c.headCenter, _headerSize);
  }

  vm.Vector2 _lookVector(Offset local) {
    final head = _headScreen() ?? _headerSize.center(Offset.zero);
    final half = _headerSize.width * 0.5;
    return vm.Vector2(
      ((local.dx - head.dx) / half).clamp(-1.0, 1.0),
      (-(local.dy - head.dy) / half).clamp(-1.0, 1.0),
    );
  }

  void _onHeaderTap(TapUpDetails d) {
    final c = character;
    if (c == null || errandActive) return;
    final ray = camera.screenPointToRay(d.localPosition, _headerSize);
    if (_roomScene != null && roomOpen > 0.9) {
      final hit = scene.raycast(ray, where: (n) => n != c.root && !_isOn(n, c.root));
      final action = FriendRoom.actionFor(hit?.node);
      if (action != null) {
        _roomAction(action);
        return;
      }
    }
    if (c.poke(scene, ray)) {
      nudgeMood(-0.06, 0.18);
      Sfx.light();
    } else {
      c.wake();
      attention.ping('tap', d.localPosition, weight: 0.9);
    }
  }

  /// A hat from the shelf, or a nap on the cushion.
  void _roomAction(String action) {
    final c = character;
    if (c == null) return;
    if (action == FriendRoom.nap) {
      c.setMood(LanternMood.sleepy);
      _fx?.puffs(vm.Vector3(1.0, 0.45, -0.55), count: 8, color: vm.Vector3(0.4, 0.3, 0.4), size: 0.15, speed: 0.6);
      Sfx.light();
      return;
    }
    ProfileScope.read(context).wear(hat: action);
    c
      ..wake()
      ..react(LanternFace.delighted, 0.6);
    final top = c.headCenter + vm.Vector3(0, c.headRadius + 0.1, 0);
    _fx
      ?..ring(top, radius: 0.9, color: _colorOf(c), life: 0.35)
      ..burst(top, count: 22, speed: 2.2, color: _colorOf(c), color2: vm.Vector3(2, 1.8, 1.2), shape: VfxShape.flare, life: 0.6, gravity: 2);
    Sfx.medium();
    Sfx.sound('hat_equip');
  }

  static bool _isOn(Node n, Node root) {
    for (Node? p = n; p != null; p = p.parent) {
      if (p == root) return true;
    }
    return false;
  }

  /// Converts a global point into the header's coordinates.
  Offset? _toHeader(Offset global) {
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  /// Where the mouse is over the app, or null when it is outside.
  Offset? _mouse;
  bool _followingMouse = false;

  /// Reports what is on screen to the attention system, feeds Lumi's gaze,
  /// lets the mood drift, and places the light painted over the list.
  void _perceive(LanternCharacter c, double dt) {
    for (final (id, key, weight) in [('tonight', _tonightKey, 0.32), ('reward', _rewardKey, collected ? 0.25 : 0.45)]) {
      final r = globalRectOf(key);
      if (r == null) continue;
      final p = _toHeader(r.center);
      if (p != null) attention.report(id, p, weight: weight);
    }
    if (_coin.isAnimating) {
      final p = _toHeader(_coinPosition());
      if (p != null) attention.report('coin', p, weight: 3.0);
    }
    attention.update(dt);
    final g = attention.gaze;
    c.gaze(g == null ? null : _lookVector(g), blink: attention.takeShift());
    // With a mouse over the app, an idle friend follows it, head and eyes.
    final mouse = _mouse == null ? null : _toHeader(_mouse!);
    final follow = mouse != null && !c.grabbing && !_draggingHeader && c.mood != LanternMood.sleepy;
    if (follow) {
      attention.report('finger', mouse, weight: 1.0);
      c.lookToward(_lookVector(mouse), curious: false);
      _followingMouse = true;
    } else if (_followingMouse) {
      _followingMouse = false;
      if (!_draggingHeader) c.lookToward(null);
    }

    if (moodPadOn) {
      mood.add((_moodRest - mood)..scale(math.min(1.0, dt * 0.06)));
      c.moodPoint = mood;
    } else {
      c.moodPoint = null;
    }

    _placeGlow(c);
  }

  /// Light from inside: the hands and head, projected to the screen from
  /// whichever view Lumi is in.
  void _placeGlow(LanternCharacter c) {
    // Out in the overlay on an errand, or for the peel.
    final out = (_errand?.out ?? false) || spectacle.peelT >= 0 || spectacle.peelLoading;
    final header = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (header == null || _headerSize.isEmpty) return;
    final pts = <GlowPoint>[];
    for (final (world, color, strength) in [...c.glowSources, ?life.bubbleGlow]) {
      final at = out ? _outToGlobal(world) : camera.worldToScreen(world, _headerSize);
      if (at == null) continue;
      pts.add(GlowPoint(out ? at : header.localToGlobal(at), color, strength));
    }
    glowPoints.value = pts;
  }

  // ---------------------------------------------------------------- errand
  /// Where a global screen point lands on the overlay's z = 0 plane.
  vm.Vector3 _outWorld(Offset global) {
    _fitOutView();
    final ray = _outCamera.screenPointToRay(global - _outRect.topLeft, _outRect.size);
    final d = ray.direction.normalized();
    return ray.origin + d * (-ray.origin.z / d.z);
  }

  /// Sends Lumi out of the header to fetch the reward key.
  void _sendLumi() {
    final c = character;
    final header = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (c == null || header == null || collected || errandActive || _coin.isAnimating) return;
    // Lumi's head (before any bob) as the header camera sees it, and how
    // many pixels a world unit is there. The overlay camera is set up so a
    // world unit is the same size on screen, so the hand-off is seamless.
    final home = camera.worldToScreen(c.restHead, _headerSize);
    if (home == null) return;
    final ppu = _headerHeight / (2 * 7.6 * math.tan(13.5 * vm.degrees2Radians));
    c
      ..wake()
      ..canDoze = false
      ..lookToward(null);
    attention.ping('reward-tap', _toHeader(globalRectOf(_rewardKey)?.center ?? Offset.zero) ?? Offset.zero);
    Sfx.light();
    Sfx.sound('tap');
    setState(() {
      _errand = FetchErrand(home: header.localToGlobal(home), headPx: c.headRadius * ppu, footPx: (c.restHead.y - c.restFeet) * ppu);
    });
  }

  @visibleForTesting
  void sendLumiForTest() => _sendLumi();

  /// Starts a trip out of the header built by [make] (home, head and foot
  /// sizes in pixels).
  bool _startOuting(Outing Function(Offset home, double headPx, double footPx) make) {
    final c = character;
    final header = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (c == null || header == null || errandActive || _roomScene != null || _swapT >= 0) return false;
    final home = camera.worldToScreen(c.restHead, _headerSize);
    if (home == null) return false;
    final ppu = _headerHeight / (2 * 7.6 * math.tan(13.5 * vm.degrees2Radians));
    c
      ..wake()
      ..canDoze = false
      ..lookToward(null);
    // Particles left in the overlay from the last trip would show, frozen,
    // until its first update.
    _outFx?.clear();
    setState(() => _errand = make(header.localToGlobal(home), c.headRadius * ppu, (c.restHead.y - c.restFeet) * ppu));
    return true;
  }

  /// A surprise: hide behind a card that is fully on screen, peek, and wave.
  void _peek() {
    final listTop = _headerHeight;
    final bottom = _screenSize.height;
    final keys = [_tonightKey, _rewardKey, _mapKey, _catchKey, _weatherKey].where((k) {
      final r = globalRectOf(k);
      return r != null && r.top > listTop + 70 && r.bottom < bottom - 10;
    }).toList();
    if (keys.isEmpty) return;
    _peekKey = keys[math.Random().nextInt(keys.length)];
    _startOuting((home, h, f) => PeekVisit(home: home, headPx: h, footPx: f));
  }

  @visibleForTesting
  void peekForTest() => _peek();

  /// Every app sound, loaded up front so none is late the first time.
  static const _sounds = [
    'tap', 'toggle', 'open', 'close', 'card_flip', 'dissolve', 'poke', 'squish', 'stretch', 'snap_back', 'hop', 'land',
    'chirp_happy', 'chirp_curious', 'chirp_sad', 'giggle', 'yawn', 'sneeze_in', 'sneeze_out', 'hat_pop', 'hat_land', 'dizzy',
    'tumble', 'shy', 'wake', 'swap', 'notify', 'catch', 'throw', 'deliver', 'bite_1', 'bite_2', 'bite_3', 'gulp', 'belly_rub',
    'burp', 'butterfly', 'spark_zip', 'spark_escape', 'snow_build', 'snow_melt', 'refresh', 'scroll_ride', 'rain_loop',
    'umbrella', 'shades', 'search_found', 'trick_bubble', 'trick_split', 'trick_bloom', 'trick_holo', 'pop', 'press', 'key_get',
    'room_open', 'hat_equip', 'party', 'map_step', 'arrive', 'countdown', 'countdown_go', 'shutter', 'star_catch', 'star_miss',
    'combo', 'banner', 'thrust_loop', 'zap', 'boing', 'glow_pickup', 'moon_fanfare', 'results', 'game_start', 'pet_stroke', 'soft_sweep',
    'heart',
  ];

  void _rideScrollbar() {
    if (_thumb.value == null) return;
    _lastRideAt = _clock;
    _startOuting((home, h, f) => ScrollRide(home: home, headPx: h, footPx: f));
  }

  @visibleForTesting
  void rideForTest() => _rideScrollbar();

  /// Moves the friend back into the header's scene, at home. The header has
  /// already stepped this frame, so it steps again (by nothing) to pick the
  /// friend up there; otherwise the frame of the hand-back draws no one, or
  /// the friend where it was in the other scene.
  void _comeHome(LanternCharacter c) {
    if (_flailing) {
      c.reachTargetR = null;
      _flailing = false;
    }
    c.root.detach();
    scene.add(c.root);
    c.place(vm.Vector3.zero(), 0);
    scene.update(0);
  }

  bool _flailing = false;

  void _errandTick(Duration elapsed, double dt) {
    final c = character;
    _clock = AppClock.seconds;
    spectacleTick(dt);
    final errand = _errand;
    if (c == null || errand == null) return;
    final Rect? card = switch (errand) {
      FetchErrand() => globalRectOf(_rewardKey),
      PeekVisit() => _peekKey == null ? null : globalRectOf(_peekKey!),
      Pratfall() => spectacle.fallKey == null ? null : globalRectOf(spectacle.fallKey!),
      TugVisit() => spectacle.yanked?.home ?? (spectacle.tugKey == null ? null : globalRectOf(spectacle.tugKey!)),
      _ => _thumb.value ?? _lastThumb,
    };
    final button = errand is FetchErrand ? (globalRectOf(_collectKey) ?? card) : card;
    if (card == null || button == null) return;
    final m = _metrics;
    final atEnd = m != null && m.pixels >= m.maxScrollExtent - 2;
    final moving = _clock - _lastScrollAt < 0.3;
    final f = errand.update(dt, card: card, button: button, atEnd: atEnd, moving: moving);

    if (f.handOffNow) {
      c.root.detach();
      _outScene.add(c.root);
      Sfx.sound(errand is ScrollRide ? 'scroll_ride' : 'hop');
    }
    if (errand.out) {
      final world = _outWorld(f.head) - c.restHead * f.scale;
      c.place(world, 0, scale: f.scale);
      if (f.roll != 0) {
        // Tipped about the head: lying down, tumbling.
        final pivot = _outWorld(f.head);
        c.root.localTransform = vm.Matrix4.translation(pivot) * vm.Matrix4.rotationZ(f.roll) * vm.Matrix4.translation(-pivot) * c.root.localTransform;
      }
      c.lookAtWorld(f.look == null ? null : _outWorld(f.look!));
      c.reachTarget = f.reach == null ? null : _outWorld(f.reach!) + vm.Vector3(0, 0, 0.35 * kFaceZ);
      // The free hand windmills for balance.
      if (f.flail > 0) {
        final h = c.headCenter;
        final r = c.headRadius * f.scale;
        final w = errand.time * 17;
        c.reachTargetR = h + vm.Vector3(-r * 1.5 + math.cos(w) * r * 0.7 * f.flail, r * 0.2 + math.sin(w) * r * 0.8 * f.flail, 0.2 * kFaceZ);
        _flailing = true;
      } else if (_flailing) {
        c.reachTargetR = null;
        _flailing = false;
      }
    } else if (f.look != null) {
      final p = _toHeader(f.look!);
      if (p != null) c.lookToward(_lookVector(p), curious: false);
    }
    if (f.jolt > 0) c.jolt(f.jolt);
    c.airborne = errand.out && errand.flying;
    if (f.impact > 0) _landImpact(Offset(f.head.dx, card.top), f.impact);
    if (errand is TugVisit) {
      final y = spectacle.yanked;
      if (y != null && y.pinned && errand.time < TugVisit.yank) y.pos = y.home.center + f.tug;
      if (errand.time >= TugVisit.yank && spectacle.jengaT == 0) spectacle.yankedNow = true;
    }
    // Effects in the layer over the app.
    final ofx = _outFx;
    final spark = f.spark;
    if (ofx != null && spark != null) {
      final at = _outWorld(spark);
      ofx
        ..flare(at, size: 0.34, color: vm.Vector3(2.2, 1.8, 0.8), life: 0.06)
        ..burst(at, count: 1, speed: 0.35, color: vm.Vector3(2.0, 1.6, 0.7), size: 0.05, life: 0.5, gravity: 0.4, shape: VfxShape.flare);
      if (!errand.out) ofx.update(dt, _outCamera);
    }
    if (ofx != null && errand.out) {
      final head = _outWorld(f.head);
      final col = _colorOf(c);
      final flying = errand.flying;
      if (flying && !f.hidden) {
        for (var i = 0; i < 2; i++) {
          ofx.burst(head + vm.Vector3(0, -0.5 * f.scale, 0.2), count: 1, speed: 0.5, color: col, size: 0.06 * f.scale + 0.02, life: 0.6, gravity: 0.6, shape: VfxShape.flare);
        }
      }
      if (f.jolt >= 0.7 && !f.hidden) {
        Sfx.sound('land');
        // Landing on the card: a puff of dust and a ring along its edge.
        final feet = _outWorld(f.head) - vm.Vector3(0, (c.restHead.y - c.restFeet) * f.scale, 0);
        ofx
          ..puffs(feet, count: 8, color: vm.Vector3(0.35, 0.35, 0.45), size: 0.12, speed: 0.8, life: 0.5)
          ..ring(feet, radius: 0.7, color: col * 0.7, life: 0.35);
      }
      if (f.pressNow) {
        final at = _outWorld(button.center);
        ofx
          ..ring(at, radius: 0.8, color: vm.Vector3(2.0, 1.6, 0.7), life: 0.35)
          ..flare(at, size: 0.9, life: 0.3)
          ..burst(at, count: 18, speed: 2.4, color: vm.Vector3(2.0, 1.6, 0.6), shape: VfxShape.flare, life: 0.6, gravity: 3);
      }
      if (f.carrying) {
        final hand = c.handWorld;
        ofx.burst(hand, count: 1, speed: 0.3, color: vm.Vector3(2.0, 1.6, 0.6), size: 0.04, life: 0.5, gravity: 1, shape: VfxShape.flare);
      }
      ofx.update(dt, _outCamera);
    }
    switch (f.face) {
      case 'curious':
        c.react(LanternFace.curious, 1.6);
      case 'delighted':
        c.react(LanternFace.delighted, 0.6);
        Sfx.sound(errand is PeekVisit ? 'giggle' : 'chirp_happy');
      case 'dizzy':
        c.setMood(LanternMood.dizzy);
        Sfx.sound('dizzy');
      case 'surprised':
        c.react(LanternFace.surprised, 0.5);
      case 'poked':
        c.react(LanternFace.poked, 0.4);
    }
    _behind.value = f.hidden ? card : null;

    // The key: it pops out of the button and into Lumi's hand.
    if (f.keyFlight != null || f.carrying) {
      final hand = _outToGlobal(c.handWorld) ?? f.head;
      if (f.carrying) {
        _carried.value = (hand, 30 * f.scale + 6);
      } else {
        final t = Curves.easeOutCubic.transform(f.keyFlight!);
        final from = button.center;
        final lift = Offset(0, -40 * math.sin(t * math.pi));
        _carried.value = (Offset.lerp(from, hand, t)! + lift, 24 + 6 * t);
      }
    }
    if (f.pressNow) {
      Sfx.medium();
      Sfx.sound('press');
      nudgeMood(0.2, 0.3);
    }
    if (f.pressing != _lumiPressing) setState(() => _lumiPressing = f.pressing);

    _scrollSpeed *= dt > 0 ? math.exp(-dt * 6) : 1;
    c.scrollVelocity(errand.out ? 0 : _scrollSpeed);
    // The screen's one clock, not this view's own (which restarts each
    // outing), so the friend's sparks never jump when it changes scenes.
    c.update(dt, _clock);
    _placeGlow(c);

    if (errand.done && errand is! FetchErrand) {
      _comeHome(c);
      c
        ..place(vm.Vector3.zero(), 0)
        ..reachTarget = null
        ..airborne = false
        ..lookAtWorld(null)
        ..canDoze = true
        ..react(LanternFace.delighted, 0.6)
        ..jolt(0.6);
      _behind.value = null;
      _outFx?.clear();
      setState(() => _errand = null);
      return;
    }
    if (errand.done) {
      _comeHome(c);
      c
        ..place(vm.Vector3.zero(), 0)
        ..reachTarget = null
        ..airborne = false
        ..lookAtWorld(null)
        ..canDoze = true
        ..celebrate();
      Sfx.sound('key_get');
      AppClock.delayed(const Duration(milliseconds: 350), () {
        if (mounted) lanternPulse();
      });
      _carried.value = null;
      _behind.value = null;
      _outFx?.clear();
      _fx
        ?..ring(c.headCenter, radius: 1.8, color: vm.Vector3(2.0, 1.6, 0.7), life: 0.45)
        ..burst(c.handWorld, count: 30, speed: 3, color: vm.Vector3(2.2, 1.7, 0.6), shape: VfxShape.flare, life: 0.8, gravity: 2.5);
      nudgeMood(0.4, 0.55);
      ProfileScope.read(context).addKey();
      setState(() {
        _errand = null;
        _lumiPressing = false;
        collected = true;
      });
    }
  }

  /// Fits the overlay to the header: the header's own camera, with the same
  /// pixels per unit, centered on the header and reaching every edge of the
  /// screen (and past some, clipped). The friend and everything around it
  /// then draws exactly as it did in the header, whatever its depth, so
  /// nothing shifts when it moves between the two.
  void _fitOutView() {
    final header = globalRectOf(_headerKey);
    if (header == null || header.isEmpty || _screenSize.isEmpty) return;
    final c = header.center;
    final view = Rect.fromCenter(
      center: c,
      width: 2 * math.max(c.dx, _screenSize.width - c.dx),
      height: 2 * math.max(c.dy, _screenSize.height - c.dy),
    );
    if (view == _outRect) return;
    _outRect = view;
    final fov = 2 * math.atan(math.tan(camera.fovRadiansY / 2) * view.height / header.height);
    _outCamera = PerspectiveCamera(
      fovRadiansY: fov,
      position: camera.position.clone(),
      target: camera.target.clone(),
    );
  }

  /// Where a world point in the overlay shows on screen.
  Offset? _outToGlobal(vm.Vector3 world) {
    final local = _outCamera.worldToScreen(world, _outRect.size);
    return local == null ? null : local + _outRect.topLeft;
  }

  Widget _boardLayer() {
    if (spectacle.board == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: _outRect,
              child: appSceneView(_boardScene, camera: _outCamera, onTick: (_, _) {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outLayer() {
    if (_errand == null && spectacle.peelT < 0 && !spectacle.peelLoading) return const SizedBox.shrink();
    _fitOutView();
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipPath(
          clipper: _BehindClipper(_behind),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                rect: _outRect,
                child: appSceneView(_outScene, camera: _outCamera, onTick: _errandTick),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // A drag that starts on the head squishes it (press or pull); anywhere
  // else in the header, the head and eyes follow the finger.
  bool _draggingHeader = false;

  void _dragStart(Offset p) {
    _draggingHeader = true;
    _dragFrom = p;
    _dragAt = p;
    final c = character;
    if (c == null || errandActive) return;
    // A drag that starts on the crown pets instead of squishing.
    if (startPet(c, p)) return;
    final ray = camera.screenPointToRay(p, _headerSize);
    if (c.grab(scene, ray)) {
      c.drag(ray);
      Sfx.tick();
    } else {
      c.lookToward(_lookVector(p));
    }
  }

  Offset _dragFrom = Offset.zero;
  Offset _dragAt = Offset.zero;

  void _dragMove(Offset p) {
    _dragAt = p;
    final c = character;
    if (c == null || errandActive) return;
    attention.report('finger', p, weight: 1.2);
    if (pet.stroking) {
      movePet(c, p);
    } else if (c.grabbing) {
      c.drag(camera.screenPointToRay(p, _headerSize));
    } else {
      c.lookToward(_lookVector(p));
    }
  }

  void _dragEnd() {
    _draggingHeader = false;
    final c = character;
    if (c == null) return;
    if (pet.stroking) {
      endPet(c);
    } else if (c.grabbing) {
      // A big stretch lets go with a snap.
      final pull = c.grabStretch;
      c.releaseGrab();
      if (pull > 0.35) {
        // A small puff of sparks; the snap itself does the talking: it
        // whips the friend round, away from the pull, and leaves it dizzy.
        final head = c.headCenter;
        _fx
          ?..ring(head, radius: 0.7 + pull * 0.3, color: _colorOf(c) * 0.6, life: 0.25)
          ..burst(head + vm.Vector3(0, 0, -0.4), count: 6 + (pull * 6).round(), speed: 1.4, color: _colorOf(c), shape: VfxShape.flare, life: 0.4, gravity: 1.5);
        final pulled = _dragAt.dx - _dragFrom.dx;
        c.snapSpin(pulled >= 0 ? 1 : -1, ((pull - 0.35) / 0.8).clamp(0.0, 1.0));
      }
      Sfx.light();
    } else {
      c.lookToward(null);
    }
  }

  void _collect() {
    if (collected || _coin.isAnimating) return;
    final button = _collectKey.currentContext?.findRenderObject() as RenderBox?;
    final header = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    final head = _headScreen();
    if (button == null || header == null || head == null) return;
    character?.wake();
    attention.ping('reward-tap', _toHeader(button.localToGlobal(button.size.center(Offset.zero))) ?? Offset.zero);
    setState(() {
      _coinFrom = button.localToGlobal(button.size.center(Offset.zero));
      _coinTo = header.localToGlobal(head);
    });
    _coin.forward(from: 0);
  }

  bool _onScroll(ScrollNotification n) {
    final c = character;
    if (c == null) return false;
    _metrics = n.metrics;
    if (n is ScrollUpdateNotification && n.dragDetails != null) _lastTouch = _clock;
    _updateThumb();
    if (n is ScrollStartNotification) _dragTravel = 0;
    if (n is ScrollUpdateNotification) {
      _lastScrollAt = _clock;
      if (n.dragDetails != null) _dragTravel += (n.scrollDelta ?? 0).abs();
      // A long drag through the list: hop on the scrollbar for a ride.
      if (_dragTravel > 320 && !errandActive && _clock - _lastRideAt > 25 && c.mood != LanternMood.sleepy) _rideScrollbar();
    }
    if (n is ScrollUpdateNotification && n.scrollDelta != null) {
      final now = Duration(microseconds: AppClock.micros);
      final dt = (now - _lastScroll).inMicroseconds / 1e6;
      _lastScroll = now;
      if (dt > 0 && dt < 0.1) {
        _scrollSpeed = _scrollSpeed * 0.6 + (n.scrollDelta! / dt) * 0.4;
      }
    }
    if (n is ScrollEndNotification) {
      final v = n.dragDetails?.primaryVelocity ?? 0;
      if (v.abs() > 200) c.fling(v);
    }
    return false;
  }

  // ---------------------------------------------------------------- scrollbar
  ScrollMetrics? _metrics;
  double _lastScrollAt = -10;
  double _dragTravel = 0;
  double _lastRideAt = -100;
  double _lastTouch = 0;
  final _thumb = ValueNotifier<Rect?>(null);
  Rect? _lastThumb;
  final _listKey = GlobalKey();
  final _weatherKey = GlobalKey();

  /// Where the scrollbar thumb is on screen (the friend can sit on it).
  void _updateThumb() {
    final m = _metrics;
    final list = globalRectOf(_listKey);
    if (m == null || list == null || m.maxScrollExtent <= 0) {
      _thumb.value = null;
      return;
    }
    final view = m.viewportDimension;
    final len = math.max(44.0, view * view / (view + m.maxScrollExtent));
    final k = (m.pixels / m.maxScrollExtent).clamp(0.0, 1.0);
    final r = Rect.fromLTWH(list.right - 9, list.top + 6 + k * (view - len - 12), 5, len);
    _thumb.value = r;
    _lastThumb = r;
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final theme = character?.theme ?? LanternTheme.aurora;
    final media = MediaQuery.of(context);
    final headerHeight = math.min(420.0, media.size.height * 0.46);
    // The header and the taller overlay bloom alike, measured against the
    // header, so the friend's glow is the same in either.
    if (!_headerSize.isEmpty) {
      final reference = math.max(_headerSize.width, _headerSize.height) * media.devicePixelRatio;
      scene.postProcess.bloom.referenceSize = reference;
      _outScene.postProcess.bloom.referenceSize = reference;
    }
    onLayout(media.size);
    if (media.size != _screenSize || headerHeight != _headerHeight) {
      _screenSize = media.size;
      _headerHeight = headerHeight;
    }
    return Scaffold(
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          _lastTouch = _clock;
          if (spectacle.lights > 0.3) lightsOn();
        },
        child: MouseRegion(
        // On desktop the eyes follow the cursor anywhere on the screen.
        onHover: (e) => _mouse = e.position,
        onExit: (_) => _mouse = null,
        child: Stack(
          children: [
            // The app itself, bent by any warp running (a ripple, a haze),
            // and hidden while a snapshot of it is on stage.
            WarpLayer(
              fx: spectacle.fx,
              child: Opacity(
                opacity: spectacle.hideApp ? 0 : 1,
                child: Column(
                  children: [
                    SizedBox(
                      height: headerHeight + (media.size.height - headerHeight) * roomOpen,
                      child: Wobble(
                        fx: spectacle.fx,
                        seed: 9.1,
                        amount: 0.45,
                        child: RepaintBoundary(key: spectacle.headerKey, child: _header(theme, media.padding.top)),
                      ),
                    ),
                    Expanded(
                      child: Opacity(
                        opacity: spectacle.hideList ? 0 : 1,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _onScroll,
                          child: _content(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _boardLayer(),
            // The friend's light on the app (or, mid-peel, on the board), below
            // the header as always.
            if (roomOpen < 0.02 && (!spectacle.hideApp || spectacle.board != null))
              Positioned.fill(child: InnerLight(points: glowPoints, top: headerHeight)),
            _jengaLayer(),
            _outLayer(),
            ...lifeOverlays(),
            _heartsLayer(),
            _voiceOverlay(),
            _pulseRing(),
            _lightsOverlay(),
            _coinLayer(),
            _carriedKey(),
            CreativePanel(
              open: panelOpen,
              character: character,
              frameTick: frameTick,
              onClose: () => setState(() => panelOpen = false),
              moodPadOn: moodPadOn,
              onMoodPad: setMoodPad,
              mood: mood,
              lookingAt: () => attention.focusLabel,
              onClip: playClip,
              showTouches: Touches.instance.showReal,
              onShowTouches: (v) => setState(() => Touches.instance.showReal = v),
              day: life.day,
              onDay: (i) => setDayPart(DayPart.values[i as int]),
              moments: {
                'Trick': trick,
                'Sneeze': () => character?.sneeze(),
                'Butterfly': startButterfly,
                'Spark chase': startChase,
                'Snowman': buildSnowman,
                'Peek': _peek,
                'Scroll ride': _rideScrollbar,
                'Notification': notify,
                'Eat a notification': eatNotification,
                'Lantern pulse': lanternPulse,
                'Sneeze ripple': () => character?.sneeze(),
                'Pratfall': pratfall,
                'Lights out': lightsOut,
                'Card Jenga': cardJenga,
                'Peel into 3D': peelInto3D,
                'Tumble': () => character?.tumble(),
              },
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _header(LanternTheme theme, double topInset) {
    final e = roomOpen;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(28 * (1 - e))),
      child: TweenAnimationBuilder<List<Color>>(
        tween: _ColorsTween(end: daySky(theme.sky)),
        duration: const Duration(milliseconds: 600),
        builder: (context, sky, child) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.1),
              radius: 0.9,
              colors: [Color.lerp(sky[1], Park.glow, 0.12)!, sky[1], sky[0]],
              stops: const [0, 0.55, 1],
            ),
          ),
          child: child,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _headerSize = constraints.biggest;
                  return GestureDetector(
                    key: _headerKey,
                    behavior: HitTestBehavior.opaque,
                    onTapUp: _onHeaderTap,
                    onPanStart: (d) => _dragStart(d.localPosition),
                    onPanUpdate: (d) => _dragMove(d.localPosition),
                    onPanEnd: (_) => _dragEnd(),
                    onPanCancel: _dragEnd,
                    onLongPressStart: (d) => _dragStart(d.localPosition),
                    onLongPressMoveUpdate: (d) => _dragMove(d.localPosition),
                    onLongPressEnd: (_) => _dragEnd(),
                    child: _sceneView(),
                  );
                },
              ),
            ),
            Positioned(
              left: 22,
              right: 22,
              top: topInset + 14,
              child: IgnorePointer(
                ignoring: e > 0.01,
                child: Opacity(
                  opacity: (1 - e * 2).clamp(0.0, 1.0),
                  child: Row(
                children: [
                  const Text(
                    'Parkday',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Spacer(),
                  for (final t in LanternTheme.all) _swatch(t),
                  const SizedBox(width: 6),
                  IconButton(
                    key: _friendsKey,
                    tooltip: 'Friends',
                    onPressed: () => _openWardrobe(tab: 3),
                    icon: const Icon(Icons.emoji_emotions_rounded, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: 'Wardrobe',
                    onPressed: _openWardrobe,
                    icon: const Icon(Icons.checkroom_rounded, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: 'Creative panel',
                    onPressed: () => setState(() => panelOpen = !panelOpen),
                    icon: const Icon(Icons.tune_rounded, color: Colors.white),
                  ),
                ],
              ),
                ),
              ),
            ),
            Positioned(
              left: 22,
              bottom: 18,
              right: 158,
              child: IgnorePointer(child: Opacity(opacity: ((1 - e * 2) * (1 - voice.shown)).clamp(0.0, 1.0), child: _greeting())),
            ),
            // A trick, the door to the room, and the way back out.
            // Talk to the friend.
            if (e < 0.5)
              Positioned(
                right: 114,
                bottom: 12,
                child: Opacity(
                  opacity: (1 - e * 2).clamp(0.0, 1.0),
                  child: IconButton.filledTonal(
                    tooltip: 'Talk to ${character?.friend.name ?? 'Lumi'}',
                    onPressed: toggleVoice,
                    style: IconButton.styleFrom(
                      backgroundColor: voice.phase == _VoicePhase.listening ? Park.gold.withValues(alpha: 0.85) : const Color(0x33FFFFFF),
                    ),
                    icon: Icon(
                      voice.phase == _VoicePhase.listening ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                      color: voice.phase == _VoicePhase.listening ? Park.onLight : Colors.white,
                    ),
                  ),
                ),
              ),
            if (e < 0.5)
              Positioned(
                right: 64,
                bottom: 12,
                child: Opacity(
                  opacity: (1 - e * 2).clamp(0.0, 1.0),
                  child: IconButton.filledTonal(
                    key: _trickKey,
                    tooltip: 'Do a trick',
                    onPressed: trick,
                    style: IconButton.styleFrom(backgroundColor: const Color(0x33FFFFFF)),
                    icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                  ),
                ),
              ),
            if (e < 0.5)
              Positioned(
                right: 14,
                bottom: 12,
                child: Opacity(
                  opacity: (1 - e * 2).clamp(0.0, 1.0),
                  child: IconButton.filledTonal(
                    key: _roomKey,
                    tooltip: "Visit ${character?.friend.name ?? 'Lumi'}'s room",
                    onPressed: _openRoom,
                    style: IconButton.styleFrom(backgroundColor: const Color(0x33FFFFFF)),
                    icon: const Icon(Icons.cottage_rounded, color: Colors.white),
                  ),
                ),
              ),
            if (e > 0.01)
              Positioned(
                left: 8,
                right: 8,
                top: topInset + 8,
                child: Opacity(
                  opacity: ((e - 0.5) * 2).clamp(0.0, 1.0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: _closeRoom,
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          "${character?.friend.name ?? 'Lumi'}'s room",
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (e > 0.5)
              Positioned(
                left: 0,
                right: 0,
                bottom: media0(context) + 24,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: ((e - 0.7) / 0.3).clamp(0.0, 1.0),
                    child: const Text(
                      'Tap a hat to wear it · tap the cushion for a nap',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFB4C1E6), fontSize: 13),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sceneView() {
    final error = _loadError;
    if (error != null) {
      return Center(
        child: Text('Could not load the character.\n$error',
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
      );
    }
    return appSceneView(
      scene,
      camera: camera,
      onTick: (elapsed, dt) {
        final c = character;
        if (c == null) return;
        _clock = AppClock.seconds;
        spectacleTick(dt);
        if (errandActive) return;
        _swapTick(dt, _clock);
        _roomCamera(_clock);
        _fx?.update(dt, camera);
        // Let the measured speed fall away once updates stop arriving.
        _scrollSpeed *= dt > 0 ? math.exp(-dt * 6) : 1;
        c.scrollVelocity(_scrollSpeed);
        _perceive(c, dt);
        c.onSneeze ??= (head) {
          _fx
            ?..puffs(head + vm.Vector3(0, -0.2, c.headRadius * 1.1 * kFaceZ), count: 10, color: vm.Vector3(0.5, 0.55, 0.7), size: 0.12, speed: 2.4, life: 0.6)
            ..burst(head + vm.Vector3(0, -0.15, c.headRadius * kFaceZ), count: 18, speed: 3.5, color: vm.Vector3(1.2, 1.3, 1.6), shape: VfxShape.flare, life: 0.5, gravity: 2, bias: vm.Vector3(0, 0, -2.5));
          Sfx.medium();
          sneezeRipple();
        };
        lifeTick(dt);
        c.update(dt, _clock);
        if (panelOpen) frameTick.value++;
      },
    );
  }

  Widget _swatch(LanternTheme t) {
    final selected = character?.theme == t;
    return Semantics(
      button: true,
      label: '${t.name} theme',
      child: GestureDetector(
        onTap: () {
          ProfileScope.read(context).setLook(theme: t.name);
          attention.ping('theme', Offset(_headerSize.width - 90, 30));
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: t.swatch,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: selected ? 0.95 : 0.25), width: selected ? 2.5 : 1.5),
            boxShadow: selected
                ? [BoxShadow(color: t.swatch.withValues(alpha: 0.6), blurRadius: 12)]
                : null,
          ),
        ),
      ),
    );
  }

  Widget _greeting() {
    final mood = character?.mood ?? LanternMood.sleepy;
    final name = character?.friend.name ?? 'Lumi';
    final hello = _hello != null && _clock < _helloUntil ? _hello : null;
    final outing = switch (_errand) {
      FetchErrand() => '$name went to fetch your key',
      PeekVisit() => '$name is playing peekaboo',
      ScrollRide() => '$name is riding the scrollbar',
      _ => null,
    };
    final talking = switch (voice.phase) {
      _VoicePhase.listening => '$name is listening',
      _VoicePhase.thinking => '$name is thinking',
      _ => null,
    };
    final line = hello ?? outing ?? talking ?? switch (mood) {
      LanternMood.sleepy => '$name is dozing. Tap to wake.',
      LanternMood.awake => 'Fireworks over the lagoon at 9:15',
      LanternMood.curious => '$name is following along',
      LanternMood.poked => 'Hey!',
      LanternMood.delighted => 'Key found! ${ProfileScope.of(context).keys} of 5 collected',
      LanternMood.dizzy => 'Whoa, slow down',
      _ => 'Fireworks over the lagoon at 9:15',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Good evening',
          style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, height: 1.1),
        ),
        const SizedBox(height: 4),
        // Pinned to the left so the outgoing and incoming lines overlap in
        // place instead of centering against each other's widths.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          child: Text(
            line,
            key: ValueKey(line),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFB4C1E6), fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _content() {
    return ListView(
      key: _listKey,
      controller: _scroll,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        fxCard(0, _searchCard()),
        const SizedBox(height: 12),
        fxCard(1, _tonightCard()),
        const SizedBox(height: 12),
        fxCard(2, _rewardCard()),
        const SizedBox(height: 12),
        fxCard(3, _weatherCard()),
        const SizedBox(height: 12),
        fxCard(4, _boothCard()),
        const SizedBox(height: 12),
        fxCard(5, _gamesCard()),
        const SizedBox(height: 12),
        fxCard(6, _mapCard()),
        const SizedBox(height: 12),
        fxCard(7, _card(
          eyebrow: 'WAIT TIMES',
          action: ValueListenableBuilder(
            valueListenable: life.updated,
            builder: (_, v, _) => Text(v, style: const TextStyle(color: Park.inkMuted, fontSize: 11)),
          ),
          child: Column(children: [for (final (n, w) in _waits) _row(n, '$w min')]),
        )),
        const SizedBox(height: 12),
        fxCard(8, _card(
          eyebrow: 'DINING',
          child: Column(children: [for (final (n, v) in _dining) _row(n, v)]),
        )),
        const SizedBox(height: 12),
        fxCard(9, _card(
          eyebrow: 'SHOWS',
          child: Column(children: [for (final (n, v) in _shows) _row(n, v)]),
        )),
        const SizedBox(height: 22),
        const Center(
          child: Text('3D companion rendered with Flutter Scene', style: TextStyle(color: Park.inkMuted, fontSize: 12)),
        ),
      ],
    );
  }

  final _tonightKey = GlobalKey();

  /// A row in a list card; it lights up when search lands on it.
  Widget _row(String label, String value) {
    final key = _rowKeys.putIfAbsent(label, GlobalKey.new);
    return ValueListenableBuilder<String?>(
      key: key,
      valueListenable: life.highlight,
      builder: (context, hit, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -8,
            right: -8,
            top: 0,
            bottom: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              decoration: BoxDecoration(
                color: hit == label ? const Color(0x22F5B83D) : const Color(0x00000000),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: hit == label ? const Color(0xAAF5B83D) : const Color(0x00000000)),
              ),
            ),
          ),
          _Row(label, value),
        ],
      ),
    );
  }

  /// Search: your friend watches you type and throws a sparkle at the match.
  Widget _searchCard() {
    return Container(
      key: _searchKey,
      decoration: Park.cardDecoration(radius: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Park.inkMuted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: life.search,
              onChanged: onSearch,
              style: const TextStyle(color: Park.ink, fontSize: 15),
              cursorColor: Park.glow,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Search rides, food, shows',
                hintStyle: TextStyle(color: Park.inkMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tonight's weather: rain brings out a little umbrella, heat a pair of
  /// sunglasses.
  Widget _weatherCard() {
    final w = life.weather;
    final (icon, line) = switch (w) {
      WeatherKind.clear => (Icons.nightlight_round, 'Clear skies · 18°'),
      WeatherKind.rain => (Icons.umbrella_rounded, 'Light rain from 10 PM · 15°'),
      WeatherKind.heat => (Icons.wb_sunny_rounded, 'Warm evening · 31°'),
    };
    return _card(
      key: _weatherKey,
      eyebrow: 'WEATHER',
      child: Row(
        children: [
          Icon(icon, color: Park.gold, size: 26),
          const SizedBox(width: 12),
          Expanded(child: Text(line, style: Park.body)),
          for (final k in WeatherKind.values)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: () => setWeather(k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: w == k ? Park.glow : Park.raised,
                    shape: BoxShape.circle,
                    border: Border.all(color: Park.line),
                  ),
                  child: Icon(
                    switch (k) {
                      WeatherKind.clear => Icons.nightlight_round,
                      WeatherKind.rain => Icons.water_drop_rounded,
                      WeatherKind.heat => Icons.wb_sunny_rounded,
                    },
                    size: 16,
                    color: w == k ? Park.onLight : Park.inkMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The photo booth: strike a pose with your friend and save a card.
  Widget _boothCard() {
    final name = character?.friend.name ?? 'Lumi';
    return Semantics(
      button: true,
      label: 'Open the photo booth',
      child: GestureDetector(
        onTap: _openBooth,
        child: Container(
          key: _boothKey,
          decoration: Park.cardDecoration(),
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [Color(0xFFFFC98A), Color(0xFFFF7EB6)]),
                ),
                child: const Icon(Icons.photo_camera_rounded, color: Park.onLight),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PHOTO BOOTH', style: Park.eyebrow),
                    const SizedBox(height: 2),
                    Text('Strike a pose with $name', style: Park.title),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Park.inkMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _openBooth() {
    final rect = globalRectOf(_boothKey);
    if (rect == null) return;
    Navigator.of(context).push(CardRevealRoute<void>(from: rect, fromKey: _boothKey, builder: (_) => const PhotoBoothScreen()));
  }

  @visibleForTesting
  void openBoothForTest() => _openBooth();

  /// Where the friend's head is on screen, for tests.
  @visibleForTesting
  Offset? headCenterOnScreen() {
    final h = _headScreen();
    return h == null ? null : _headerGlobal(h);
  }

  void _openShow({double startAt = 0}) {
    final rect = globalRectOf(_tonightKey);
    if (rect == null) return;
    character?.lookToward(null);
    Navigator.of(context).push(
      CardRevealRoute<void>(from: rect, fromKey: _tonightKey, builder: (_) => ShowScreen(theme: character?.theme, startAt: startAt)),
    );
  }

  @visibleForTesting
  void openShowForTest() => _openShow();

  /// Tonight's fireworks: the card that becomes the show.
  Widget _tonightCard() {
    final watched = ProfileScope.of(context).watchedFireworks;
    return Semantics(
      button: true,
      label: 'Watch the fireworks over the lagoon with ${character?.friend.name ?? 'Lumi'}',
      child: GestureDetector(
        onTap: _openShow,
        child: Container(
          key: _tonightKey,
          height: 196,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0x331B2340), blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/ui/tonight.jpg', fit: BoxFit.cover, alignment: const Alignment(0, -0.2)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC060A1C)],
                    stops: [0.35, 1],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            watched ? 'TONIGHT · WATCHED' : 'TONIGHT · 9:15 PM',
                            style: const TextStyle(color: Color(0xFFFFC98A), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Fireworks over the lagoon',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, height: 1.15),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      key: _watchKey,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow_rounded, size: 18, color: Park.onLight),
                          const SizedBox(width: 2),
                          Text('Watch with ${character?.friend.name ?? 'Lumi'}', style: const TextStyle(color: Park.onLight, fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  final _catchKey = GlobalKey();
  final _liftKey = GlobalKey();

  void _openGame(GlobalKey key, MiniGame Function() create) {
    final rect = globalRectOf(key);
    if (rect == null) return;
    Navigator.of(context).push(CardRevealRoute<void>(from: rect, fromKey: key, fromRadius: 14, builder: (_) => GameScreen(key: _gameKey, create: create)));
  }

  @visibleForTesting
  void openGameForTest(bool lift) => lift ? _openGame(_liftKey, SkyLift.new) : _openGame(_catchKey, StarCatch.new);

  /// Two small games to play with Lumi while waiting.
  Widget _gamesCard() {
    final p = ProfileScope.of(context);
    Widget tile(GlobalKey key, String image, String title, String best, MiniGame Function() create) => Expanded(
      child: Semantics(
        button: true,
        label: 'Play $title',
        child: GestureDetector(
          onTap: () => _openGame(key, create),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  key: key,
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(image, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Park.ink)),
              Text(best, style: const TextStyle(color: Park.inkMuted, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
    return _card(
      eyebrow: 'PLAY WITH ${(character?.friend.name ?? 'Lumi').toUpperCase()} · ${p.stars} STARS',
      child: Row(
        children: [
          tile(_catchKey, 'assets/ui/game_catch.jpg', 'Star Catch', p.bestCatch > 0 ? 'Best ${p.bestCatch}' : '45 seconds', StarCatch.new),
          const SizedBox(width: 12),
          tile(_liftKey, 'assets/ui/game_lift.jpg', 'Sky Lift', p.bestLift > 0 ? 'Best ${p.bestLift} m' : 'How high can ${character?.friend.name ?? 'Lumi'} go?', SkyLift.new),
        ],
      ),
    );
  }

  final _rewardKey = GlobalKey();
  final _sendKey = GlobalKey();
  final _watchKey = GlobalKey();
  final _friendsKey = GlobalKey();
  final _roomKey = GlobalKey();
  final _gameKey = GlobalKey<GameScreenState>();
  bool _clipRunning = false;

  /// Whether idle surprises and notifications happen on their own (tests and
  /// recordings turn them off).
  bool autoSurprises = true;

  final _life = _Life();
  final _searchKey = GlobalKey();
  final _boothKey = GlobalKey();
  final _trickKey = GlobalKey();
  final Map<String, GlobalKey> _rowKeys = {};
  final List<(String, int)> _waits = [
    ('Sky Coaster', 25),
    ('River Run', 10),
    ('Star Swing', 5),
    ('Moon Drop', 40),
    ('Tidal Twist', 15),
    ('Comet Carousel', 5),
  ];
  static const _dining = [('Harbor Grill', 'Open'), ('Lantern Café', 'Open'), ('Starlight Treats', 'Closes 10 PM')];
  static const _shows = [('Night Parade', '8:00 PM'), ('Glow Garden', 'All evening'), ('Fireworks', '9:15 PM')];

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _resetReward() => setState(() => collected = false);
  bool _holdingFinger = false;
  final _mapKey = GlobalKey();

  Future<void> _openMap() async {
    if (_mapKey.currentContext == null) await _reveal(_mapKey);
    if (!mounted) return;
    final rect = globalRectOf(_mapKey);
    if (rect == null) return;
    Navigator.of(context).push(CardRevealRoute<void>(from: rect, fromKey: _mapKey, builder: (_) => ParkMapScreen(key: _mapScreenKey)));
  }

  @visibleForTesting
  Future<void> openMapForTest() => _openMap();

  /// The park as a 3D diorama, with live wait times over every ride.
  Widget _mapCard() {
    final name = character?.friend.name ?? 'Lumi';
    return Semantics(
      button: true,
      label: 'Open the park map with $name',
      child: GestureDetector(
        onTap: _openMap,
        child: Container(
          key: _mapKey,
          height: 150,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0x331B2340), blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/ui/park_map.jpg', fit: BoxFit.cover, alignment: const Alignment(0, -0.1)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC060A1C)],
                    stops: [0.3, 1],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'PARK MAP · LIVE WAITS',
                            style: TextStyle(color: Color(0xFF9FE8C8), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Where to next, $name?',
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, height: 1.15),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_rounded, size: 17, color: Park.onLight),
                          SizedBox(width: 4),
                          Text('Open map', style: TextStyle(color: Park.onLight, fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rewardCard() {
    return _card(
      key: _rewardKey,
      eyebrow: collected ? 'REWARD' : 'REWARD NEARBY',
      action: collected || errandActive
          ? null
          : _EyebrowAction(key: _sendKey, label: 'Send ${character?.friend.name ?? 'Lumi'}', icon: Icons.auto_awesome_rounded, onTap: _sendLumi),
      child: Row(
        children: [
          const _CoinIcon(size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Lagoon Key', style: Park.title),
                const SizedBox(height: 2),
                Text('${ProfileScope.of(context).keys} of 5 keys found', style: const TextStyle(color: Park.inkMuted, fontSize: 13)),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: collected
                ? TextButton.icon(
                    key: const ValueKey('done'),
                    onPressed: () => setState(() => collected = false),
                    style: TextButton.styleFrom(backgroundColor: Park.goodBg, foregroundColor: Park.good, shape: const StadiumBorder()),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Collected'),
                  )
                : AnimatedScale(
                    key: const ValueKey('collect'),
                    scale: _lumiPressing ? 0.88 : 1,
                    duration: const Duration(milliseconds: 110),
                    curve: Curves.easeOut,
                    child: FilledButton(
                      key: _collectKey,
                      onPressed: errandActive ? () {} : _collect,
                      style: FilledButton.styleFrom(
                        backgroundColor: _lumiPressing ? const Color(0xFF9FB4FF) : Park.button,
                        foregroundColor: Park.onLight,
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Collect'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card({Key? key, required String eyebrow, Widget? action, required Widget child}) {
    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: Park.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(eyebrow, style: Park.eyebrow)),
              ?action,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  /// The reward coin's flight from the card into the 3D header.
  /// Where the flying coin is right now, in global coordinates: a quadratic
  /// arc that lifts above the straight line from the card to Lumi.
  Offset _coinPosition() {
    final t = Curves.easeInOutCubic.transform(_coin.value);
    final mid = Offset((_coinFrom.dx + _coinTo.dx) / 2 + 60, math.min(_coinFrom.dy, _coinTo.dy) - 40);
    final a = Offset.lerp(_coinFrom, mid, t)!;
    final b = Offset.lerp(mid, _coinTo, t)!;
    return Offset.lerp(a, b, t)!;
  }

  Widget _coinLayer() {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _coin,
        builder: (context, _) {
          if (!_coin.isAnimating) return const SizedBox.shrink();
          final t = Curves.easeInOutCubic.transform(_coin.value);
          final p = _coinPosition();
          final size = 38 * (1 - 0.45 * t);
          return Stack(
            children: [
              Positioned(
                left: p.dx - size / 2,
                top: p.dy - size / 2,
                child: Transform.rotate(
                  angle: t * math.pi * 3,
                  child: _CoinIcon(size: size, glow: 0.4 + t * 0.8),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

extension on ParkScreenState {
  /// The key Lumi carries home, drawn over everything.
  Widget _carriedKey() {
    return IgnorePointer(
      child: ValueListenableBuilder<(Offset, double)?>(
        valueListenable: _carried,
        builder: (context, v, _) {
          if (v == null) return const SizedBox.shrink();
          final (p, size) = v;
          return Stack(
            children: [
              Positioned(
                left: p.dx - size / 2,
                top: p.dy - size / 2,
                child: _CoinIcon(size: size, glow: 0.9),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Clips the 3D overlay below a card's top edge (and down to the bottom of
/// the screen across the card's width), so Lumi reads as behind the list.
class _BehindClipper extends CustomClipper<Path> {
  _BehindClipper(this.behind) : super(reclip: behind);

  final ValueListenable<Rect?> behind;

  @override
  Path getClip(Size size) {
    final path = Path()..addRect(Offset.zero & size);
    final r = behind.value;
    if (r == null) return path;
    final hole = Path()
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTRB(r.left, r.top, r.right, size.height),
        topLeft: const Radius.circular(18),
        topRight: const Radius.circular(18),
      ));
    return Path.combine(PathOperation.difference, path, hole);
  }

  @override
  bool shouldReclip(_BehindClipper old) => old.behind != behind;
}

/// A small text action on the right of a card's eyebrow line.
class _EyebrowAction extends StatelessWidget {
  const _EyebrowAction({super.key, required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: const Color(0xFF5B6BD6)),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(color: Color(0xFF5B6BD6), fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

double media0(BuildContext context) => MediaQuery.of(context).padding.bottom;

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Park.body)),
          Text(value, style: Park.tabular),
        ],
      ),
    );
  }
}

class _CoinIcon extends StatelessWidget {
  const _CoinIcon({required this.size, this.glow = 0});
  final double size;
  final double glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [Color(0xFFFFF1C4), Color(0xFFF5B83D), Color(0xFFC9871B)],
          stops: [0, 0.55, 1],
        ),
        boxShadow: [
          if (glow > 0) BoxShadow(color: const Color(0xFFFFC450).withValues(alpha: glow.clamp(0, 1)), blurRadius: 24 * glow),
        ],
      ),
      child: Icon(Icons.vpn_key_rounded, size: size * 0.5, color: const Color(0xFF8A5A0E)),
    );
  }
}

class _ColorsTween extends Tween<List<Color>> {
  _ColorsTween({required List<Color> end}) : super(begin: end, end: end);

  @override
  List<Color> lerp(double t) => [
    for (var i = 0; i < end!.length; i++) Color.lerp(begin![i], end![i], t)!,
  ];
}
