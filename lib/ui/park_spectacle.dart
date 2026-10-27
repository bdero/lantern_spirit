part of 'park_screen.dart';

/// Full-screen moments, where the friend affects everything on screen: the
/// lantern pulse, the sneeze ripple, the pratfall, lights out, card Jenga,
/// and peeling the whole app into 3D.
class _Spectacle {
  final fx = ScreenFx();

  /// Every card in the list, by position, for shakes, glows, and snapshots.
  final cardKeys = <int, GlobalKey>{};
  final headerKey = GlobalKey();
  Duration? lastFrame;

  // The pratfall's card.
  GlobalKey? fallKey;

  // Lights out.
  double lights = 0;
  double lightsTarget = 0;
  double lightsUntil = 0;

  // Card Jenga.
  JengaSim? jenga;
  JengaBody? yanked;
  GlobalKey? tugKey;
  double jengaT = -1;
  bool yankedNow = false;
  final jengaPaint = ValueNotifier<int>(0);

  // The peel into 3D.
  double peelT = -1;
  bool peelLoading = false;
  Node? board;
  final pieces = <_PeelPiece>[];
  vm.Vector3? pivot;
  vm.Vector3? camPosition;
  vm.Vector3? camTarget;
  double camFov = 0;
  vm.Vector3 feet = vm.Vector3.zero();
  vm.Vector3? homeRoot;
  double worldPerPx = 0.01;

  /// Hides the live app while snapshots of it are on stage.
  bool hideList = false;
  bool hideApp = false;

  bool get busy => jengaT >= 0 || jenga != null || peelT >= 0 || peelLoading || lightsTarget > 0;
}

class _PeelPiece {
  _PeelPiece(this.slab, this.center, this.height);
  final Slab slab;
  final vm.Vector3 center;
  final double height;

  // Springs: how far the slab is pressed into the board (a fraction of its
  // height), and how far it rocks about its two in-plane axes (radians).
  double press = 0, pressV = 0;
  double rockX = 0, rockXV = 0, rockY = 0, rockYV = 0;

  void kick({double press = 0, double rockX = 0, double rockY = 0}) {
    pressV += press;
    rockXV += rockX;
    rockYV += rockY;
  }

  /// How far it has risen out of the board, 0 to about 1.2 (overshooting).
  double rise = 0;

  /// Springy and a little underdamped, so a landing overshoots and settles.
  void step(double dt) {
    if (dt <= 0) return;
    pressV += (-170 * press - 9 * pressV) * dt;
    press += pressV * dt;
    rockXV += (-140 * rockX - 7 * rockXV) * dt;
    rockX += rockXV * dt;
    rockYV += (-140 * rockY - 7 * rockYV) * dt;
    rockY += rockYV * dt;
  }
}

extension ParkSpectacle on ParkScreenState {
  _Spectacle get sp => spectacle;

  /// A card in the list, wrapped so it shakes with impacts, lights up as a
  /// pulse passes, and can be snapshotted.
  Widget fxCard(int i, Widget child) => Wobble(
        fx: sp.fx,
        seed: i * 1.37 + 0.4,
        child: PulseGlow(fx: sp.fx, child: RepaintBoundary(key: sp.cardKeys.putIfAbsent(i, GlobalKey.new), child: child)),
      );

  /// The cards on screen now, top to bottom, with their rects.
  List<(GlobalKey, Rect)> _visibleCards() {
    final top = _headerHeight - 4;
    final bottom = _screenSize.height;
    final out = <(GlobalKey, Rect)>[];
    for (final e in sp.cardKeys.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
      final r = globalRectOf(e.value);
      if (r == null || r.bottom < top + 20 || r.top > bottom - 20) continue;
      out.add((e.value, r));
    }
    return out;
  }

  Offset? _headGlobal() {
    final h = _headScreen();
    return h == null ? null : _headerGlobal(h);
  }

  Future<ui.Image?> _snapshot(GlobalKey key) async {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    return boundary.toImage(pixelRatio: MediaQuery.of(context).devicePixelRatio);
  }

  // ------------------------------------------------------------- frame
  /// Runs once per frame, from whichever 3D view ticks first.
  void spectacleTick(double dt) {
    final stamp = SchedulerBinding.instance.currentFrameTimeStamp;
    if (stamp == sp.lastFrame) return;
    sp.lastFrame = stamp;
    sp.fx.tick(_clock);
    // A moment that trips over a bug ends itself and reports, instead of
    // stopping every frame after it (which would freeze the app).
    void guard(void Function() tick, void Function() end, String what) {
      try {
        tick();
      } catch (e, st) {
        FlutterError.reportError(FlutterErrorDetails(exception: e, stack: st, library: 'lantern spirit', context: ErrorDescription('while playing $what')));
        end();
      }
    }

    guard(() => _tickLights(dt), () => sp.lightsTarget = sp.lights = 0, 'lights out');
    guard(() => _tickJenga(dt), _endJenga, 'card Jenga');
    guard(() => _tickPeel(dt), _endPeel, 'the peel into 3D');
  }

  // ------------------------------------------------------------- pulse
  /// A ring of lantern light rolls out from the friend across every card.
  void lanternPulse() {
    final at = _headGlobal() ?? Offset(_screenSize.width / 2, _headerHeight / 2);
    sp.fx
      ..pulse(at)
      ..haze(at);
    final c = character;
    if (c != null) {
      c
        ..wake()
        ..react(LanternFace.delighted, 0.8)
        ..jolt(0.5);
      _fx?.ring(c.headCenter, radius: 1.3, color: vm.Vector3(0.9, 0.7, 0.35), life: 0.4);
    }
    Sfx.sound('dissolve', volume: 0.8);
  }

  /// The ring of a pulse, drawn over everything as it spreads.
  Widget _pulseRing() => Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: sp.fx,
            builder: (context, _) {
              final ring = sp.fx.pulseRing;
              if (ring == null) return const SizedBox.shrink();
              return CustomPaint(painter: _RingPainter(ring.$1, ring.$2, ring.$3, ring.$4));
            },
          ),
        ),
      );

  // ------------------------------------------------------------- ripple
  /// A sneeze big enough to ripple the screen.
  void sneezeRipple() {
    final at = _headGlobal();
    if (at == null) return;
    sp.fx.ripple(at + const Offset(0, 20));
  }

  // ------------------------------------------------------------- pratfall
  /// The friend trips out of the header and lands face-first on a card.
  void pratfall() {
    final keys = [_tonightKey, _rewardKey, _weatherKey, _boothKey].where((k) {
      final r = globalRectOf(k);
      return r != null && r.top > _headerHeight + 60 && r.bottom < _screenSize.height - 10;
    }).toList();
    if (keys.isEmpty) return;
    sp.fallKey = keys.first;
    if (_startOuting((home, h, f) => Pratfall(home: home, headPx: h, footPx: f))) {
      Sfx.sound('spark_zip', volume: 0.7);
      Sfx.sound('chirp_curious', delay: const Duration(milliseconds: 250));
    }
  }

  /// The pratfall's landing: everything on screen jumps.
  void _landImpact(Offset at, double strength) {
    sp.fx.impact(at, strength: strength);
    Sfx.heavy();
    Sfx.sound('land', volume: 3);
    Sfx.sound('boing', volume: 0.35, pitch: 0.7);
  }

  // ------------------------------------------------------------- lights out
  /// The app goes dark and the friend is the only light, until a tap.
  void lightsOut() {
    final c = character;
    if (c == null || sp.lightsTarget > 0) return;
    c
      ..wake()
      ..react(LanternFace.content, 1.2);
    sp
      ..lightsTarget = 1
      ..lightsUntil = _clock + 14;
    Sfx.sound('lamp');
  }

  void lightsOn() {
    if (sp.lightsTarget <= 0) return;
    sp.lightsTarget = 0;
    Sfx.sound('lamp');
  }

  void _tickLights(double dt) {
    if (sp.lightsTarget > 0 && _clock > sp.lightsUntil) lightsOn();
    final before = sp.lights;
    sp.lights += ((sp.lightsTarget - sp.lights) * math.min(1.0, dt * 3.2)).clamp(-dt * 1.8, dt * 1.8);
    if (sp.lights < 0.002 && sp.lightsTarget == 0) sp.lights = 0;
    final c = character;
    if (c != null && (sp.lights > 0 || before > 0)) c.glowScale = 1 + 0.7 * sp.lights;
    if (sp.lights > 0 || before > 0) _refresh();
  }

  Widget _lightsOverlay() {
    if (sp.lights <= 0) return const SizedBox.shrink();
    final head = _headGlobal() ?? Offset(_screenSize.width / 2, _headerHeight / 2);
    final cards = [for (final (_, r) in _visibleCards()) RRect.fromRectAndRadius(r, const Radius.circular(18))];
    final flicker = 1 + 0.025 * math.sin(_clock * 2.3) + 0.015 * math.sin(_clock * 5.1);
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: LightsOutPainter(light: head + const Offset(0, 30), cards: cards, amount: sp.lights, flicker: flicker, warmth: const Color(0xFFFFC982)),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- jenga
  /// The friend yanks a card out of the middle of the list, and the cards
  /// tumble down into a pile with real physics. Then it waves them home.
  Future<void> cardJenga() async {
    final c = character;
    if (c == null || errandActive || sp.busy) return;
    final cards = _visibleCards();
    if (cards.length < 3) return;
    sp.jengaT = 0;
    final bodies = <JengaBody>[];
    for (final (key, rect) in cards) {
      final image = await _snapshot(key);
      if (image == null || !mounted) {
        sp.jengaT = -1;
        return;
      }
      bodies.add(JengaBody(image, rect, 18));
    }
    final k = cards.length >= 4 ? cards.length ~/ 2 : 1;
    sp
      ..jenga = JengaSim(bodies, floor: _screenSize.height - 10, left: 8, right: _screenSize.width - 8)
      ..yanked = bodies[k]
      ..tugKey = cards[k].$1
      ..yankedNow = false
      ..hideList = true;
    _refresh();
    if (!_startOuting((home, h, f) => TugVisit(home: home, headPx: h, footPx: f))) {
      _endJenga();
      return;
    }
    Sfx.sound('chirp_curious');
  }

  void _endJenga() {
    final j = sp.jenga;
    if (j != null) {
      for (final b in j.bodies) {
        b.image.dispose();
      }
    }
    sp
      ..jenga = null
      ..yanked = null
      ..jengaT = -1
      ..hideList = false;
    _refresh();
  }

  void _tickJenga(double dt) {
    final j = sp.jenga;
    if (j == null) return;
    final c = character;
    if (sp.yankedNow) {
      sp.yankedNow = false;
      sp.jengaT = 0.001;
      final y = sp.yanked!;
      y
        ..pinned = false
        ..vel = const Offset(2300, -650)
        ..spin = 9;
      Sfx.sound('throw', volume: 1.2);
      Sfx.sound('card_flip');
    }
    if (sp.jengaT <= 0) {
      sp.jengaPaint.value++;
      return;
    }
    final before = sp.jengaT;
    sp.jengaT += dt;
    final t = sp.jengaT;
    bool crossed(double at) => before < at && t >= at;
    // A beat after the yank, everything above the floor lets go.
    if (crossed(0.18)) {
      final rng = math.Random(5);
      for (final b in j.bodies) {
        if (b == sp.yanked) continue;
        b
          ..pinned = false
          ..spin = (rng.nextBool() ? 1 : -1) * (1.2 + rng.nextDouble() * 2.6)
          ..vel = Offset((rng.nextDouble() - 0.5) * 420, -180 - rng.nextDouble() * 220);
      }
      sp.fx.impact(Offset(_screenSize.width / 2, _screenSize.height - 40), strength: 0.5);
      Sfx.sound('tumble', volume: 2.5);
    }
    // Landings thud.
    if (t > 0.3 && t < 2.6 && ((before * 6).floor() != (t * 6).floor()) && j.bodies.any((b) => !b.pinned && b.vel.dy > 400 && b.pos.dy > _screenSize.height - 260)) {
      Sfx.sound('land', volume: 2.5, pitch: 0.8 + math.Random().nextDouble() * 0.3);
    }
    const settle = 2.2;
    if (t < settle) {
      // The yanked card flies off on its own, clear of the pile.
      final y = sp.yanked!;
      y.pinned = true;
      y.vel += const Offset(0, JengaSim.gravity * 0.5) * dt;
      y.pos += y.vel * dt;
      y.angle += y.spin * dt;
      j.step(dt);
      if (crossed(1.4)) c?.react(LanternFace.surprised, 1.0);
    } else {
      if (crossed(settle)) {
        j.startHome();
        if (c != null) {
          c
            ..react(LanternFace.delighted, 1.2)
            ..jolt(0.6);
          _fx?.burst(c.handWorld, count: 30, speed: 2.6, color: vm.Vector3(1.8, 1.5, 0.8), shape: VfxShape.flare, life: 0.8, gravity: 0.5);
        }
        Sfx.sound('trick_holo');
      }
      // Waving the cards home, one by one from the top, the runaway last.
      if (c != null) c.reachTarget = t < settle + 1.6 ? c.headCenter + vm.Vector3(0.9 + 0.25 * math.sin(t * 12), 0.6, 0.3 * kFaceZ) : null;
      final order = [...j.bodies.where((b) => b != sp.yanked), sp.yanked!];
      var all = true;
      for (var i = 0; i < order.length; i++) {
        final start = settle + 0.15 + i * 0.1;
        final u = (t - start) / 0.6;
        if (crossed(start)) Sfx.sound('card_flip', volume: 0.8, gap: Duration.zero);
        j.home(j.bodies.indexOf(order[i]), u);
        if (u < 1) all = false;
      }
      if (all) {
        c?.reachTarget = null;
        _endJenga();
        return;
      }
    }
    sp.jengaPaint.value++;
  }

  Widget _jengaLayer() {
    final j = sp.jenga;
    if (j == null) return const SizedBox.shrink();
    return Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: JengaPainter(j.bodies, sp.jengaPaint))));
  }

  // ------------------------------------------------------------- peel
  /// The whole app peels back into 3D: every card becomes a raised slab on
  /// a floor, the friend hops across them, and it all folds flat again.
  Future<void> peelInto3D() async {
    final c = character;
    if (c == null || errandActive || sp.busy || _roomScene != null) return;
    final home = _headGlobal();
    if (home == null) return;
    sp.peelLoading = true;
    c
      ..wake()
      ..canDoze = false
      ..lookToward(null);
    // The friend steps out of the header into the 3D layer, exactly where
    // it was, so the header can be photographed without it.
    sp.homeRoot = _outWorld(home) - c.restHead;
    c.root.detach();
    _outScene.add(c.root);
    c.place(sp.homeRoot!, 0);
    _outFx?.clear();
    _refresh();
    await SchedulerBinding.instance.endOfFrame;
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted) return;
    final shots = <(Rect, ui.Image, double)>[];
    final headerRect = globalRectOf(sp.headerKey);
    final headerShot = await _snapshot(sp.headerKey);
    if (headerRect != null && headerShot != null) shots.add((headerRect, headerShot, 28));
    for (final (key, rect) in _visibleCards()) {
      final image = await _snapshot(key);
      if (image != null) shots.add((rect, image, 18));
    }
    if (!mounted) return;
    final k = (_outWorld(const Offset(200, 0)) - _outWorld(Offset.zero)).length / 200;
    sp.worldPerPx = k;
    final board = Node(name: 'Board');
    sp.pieces.clear();
    for (var i = 0; i < shots.length; i++) {
      final (rect, image, radius) = shots[i];
      // Each card's own edges, projected, so that lying flat it covers the
      // card exactly (the camera looks a little down, so a world unit is not
      // quite the same number of pixels everywhere).
      final left = _outWorld(rect.centerLeft), right = _outWorld(rect.centerRight);
      final top = _outWorld(rect.topCenter), bottom = _outWorld(rect.bottomCenter);
      final size = vm.Vector2((right - left).length, (top - bottom).length);
      final center = vm.Vector3((left.x + right.x) / 2, (top.y + bottom.y) / 2, 0);
      final slab = await Slab.create(image, size: size, radius: radius * size.x / rect.width, side: i == 0 ? vm.Vector3(0.16, 0.2, 0.42) : null);
      image.dispose();
      final height = (i == 0 ? 70.0 : 34.0 + 22 * ((i * 7) % 3)) * k;
      board.add(slab.node);
      sp.pieces.add(_PeelPiece(slab, center, height));
    }
    if (!mounted) return;
    sp
      ..board = board
      ..pivot = _outWorld(Offset(_screenSize.width / 2, _screenSize.height * 0.6))
      ..camPosition = _outCamera.position.clone()
      ..camTarget = _outCamera.target.clone()
      ..camFov = _outCamera.fovRadiansY
      ..feet = sp.homeRoot! + vm.Vector3(0, c.restFeet, 0)
      ..hideApp = true
      ..peelLoading = false
      ..peelT = 0;
    _boardScene.add(board);
    _layBoard(0);
    c.react(LanternFace.wow, 1.0);
    Sfx.sound('open');
    _refresh();
  }

  /// Poses the board: [tilt] 0 (flat, the app as it was) to 1 (a floor),
  /// with each slab raised by its own [_PeelPiece.rise].
  void _layBoard(double tilt) {
    final board = sp.board!;
    final p = sp.pivot!;
    final a = 62 * vm.degrees2Radians * tilt;
    board.localTransform = vm.Matrix4.translation(p) * vm.Matrix4.rotationX(a) * vm.Matrix4.translation(-p);
    for (var i = 0; i < sp.pieces.length; i++) {
      final piece = sp.pieces[i];
      final h = math.max(piece.height * piece.rise * (1 - piece.press), 0.002);
      final rock = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), piece.rockX) * vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), piece.rockY);
      piece.slab.node.localTransform = vm.Matrix4.compose(piece.center + vm.Vector3(0, 0, -h), rock, vm.Vector3(1, 1, h));
    }
    // The camera eases back and swings a little round while the board is
    // down, and returns exactly to where it was.
    // It frames the middle of the board as it lies now.
    final pos0 = sp.camPosition!, tgt0 = sp.camTarget!;
    final middle = vm.Vector3.zero();
    for (final piece in sp.pieces) {
      middle.add(board.localTransform.transformed3(piece.center.clone()));
    }
    middle.scale(1 / math.max(1, sp.pieces.length));
    final target = tgt0 + (middle - tgt0) * tilt;
    final yaw = 0.2 * math.sin(math.max(0.0, sp.peelT - 1.6) * 0.7) * tilt;
    // Flat, this is exactly the overlay's own camera (the header's, made
    // taller). Tipping, the lens narrows to a calmer 27 degrees while the
    // camera pulls back to keep the cards the size they were, easing back a
    // touch more.
    final fov0 = sp.camFov;
    final fov = fov0 + (27 * vm.degrees2Radians - fov0) * tilt;
    final off = pos0 - tgt0;
    final turned = vm.Matrix4.rotationY(yaw).transformed3(off)..scale(math.tan(fov0 / 2) / math.tan(fov / 2) * (1 - 0.08 * tilt));
    final position = target + turned + vm.Vector3(0, 2.2 * tilt, 0);
    // The overlay is centered on the header, high on the screen; aim a little
    // above the board so its middle sits in the middle of the screen.
    final forward = (target - position)..normalize();
    final right = forward.cross(vm.Vector3(0, 1, 0))..normalize();
    final up = right.cross(forward);
    final focal = _outRect.height / 2 / math.tan(fov / 2);
    final lift = tilt * math.atan((_screenSize.height / 2 - _outRect.center.dy) / focal);
    final aim = forward * math.cos(lift) + up * math.sin(lift);
    _outCamera
      ..fovRadiansY = fov
      ..position = position
      ..target = position + aim * (target - position).length;
  }

  /// The top of slab [i], in the world, as the board lies now (pressed in
  /// under the friend's weight, too).
  vm.Vector3 _slabTop(int i) {
    final piece = sp.pieces[i];
    final local = piece.center + vm.Vector3(0, 0, -piece.height * piece.rise * (1 - piece.press));
    return sp.board!.localTransform.transformed3(local);
  }

  /// A landing (or a push-off) on slab [i]: it sinks and rocks toward where
  /// the friend came from, and its neighbours feel it too.
  void _thump(int i, vm.Vector3 from, double strength) {
    if (i < 0 || i >= sp.pieces.length) return;
    final piece = sp.pieces[i];
    final world = sp.board!.localTransform.transformed3(piece.center.clone());
    final d = from - world;
    piece.kick(press: 1.6 * strength, rockX: (d.y.sign) * 2.2 * strength, rockY: -(d.x.sign) * 2.6 * strength);
    for (final j in [i - 1, i + 1]) {
      if (j >= 0 && j < sp.pieces.length) sp.pieces[j].kick(press: 0.45 * strength, rockX: 0.8 * strength * (j < i ? 1 : -1));
    }
  }

  void _tickPeel(double dt) {
    if (sp.peelT < 0) return;
    final c = character;
    if (c == null || sp.board == null) return;
    final before = sp.peelT;
    sp.peelT += dt;
    final t = sp.peelT;
    bool crossed(double at) => before < at && t >= at;
    double span(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
    // Tight for recording: it starts tipping at once, hops briskly, and
    // folds back the moment the friend is home on the header.
    final stops = [0, for (var i = 1; i < sp.pieces.length; i++) i, 0];
    const tiltIn = 0.12, down = 1.35, hop = 0.48, firstHop = 1.55;
    final fold = firstHop + hop * (stops.length - 1) + 0.1, flat = fold + 1.1, end = flat + 0.2;
    final tilt = Curves.easeInOutCubic.transform(span(tiltIn, down)) * (1 - Curves.easeInOutCubic.transform(span(fold, flat)));
    // The slabs come up one after another, the header first, each with a
    // little overshoot, and all go down together.
    final settle = 1 - Curves.easeInOutCubic.transform(span(fold - 0.2, flat - 0.3));
    for (var i = 0; i < sp.pieces.length; i++) {
      final lag = math.min(0.07 * i, 0.42);
      sp.pieces[i]
        ..rise = (Curves.easeOutBack.transform(span(tiltIn + 0.4 + lag, down + 0.2 + lag)) * settle).clamp(0.0, 1.2)
        ..step(dt);
    }
    _layBoard(tilt);
    if (crossed(tiltIn)) Sfx.sound('soft_sweep', volume: 0.6);
    if (crossed(tiltIn + 0.4)) Sfx.sound('trick_holo', volume: 0.7);

    // The friend: onto the header slab, across every card, back to the
    // header, and home.
    const scale = 0.55;
    final up = (sp.board!.localTransform.transformed3(vm.Vector3(0, 0, -1)) - sp.board!.localTransform.transformed3(vm.Vector3.zero()))..normalize();
    vm.Vector3 standOn(int i) => _slabTop(i) + up * 0.01;
    vm.Vector3 feet;
    if (t < firstHop) {
      final u = Curves.easeInOutCubic.transform(span(down - 0.5, firstHop));
      final start = sp.homeRoot! + vm.Vector3(0, c.restFeet, 0);
      feet = start + (standOn(0) - start) * u;
    } else if (t < firstHop + hop * (stops.length - 1)) {
      final k = ((t - firstHop) / hop).floor();
      final u = (t - firstHop) / hop - k;
      final a = standOn(stops[k]), b = standOn(stops[k + 1]);
      final height = 120 * sp.worldPerPx + (a - b).length * 0.25;
      feet = a + (b - a) * u + vm.Vector3(0, 4 * height * u * (1 - u), 0);
      if (((before - firstHop) / hop).floor() != k || crossed(firstHop)) {
        // Landed on this slab (or, first, pushing off the header's).
        _thump(stops[k], k == 0 ? sp.homeRoot! : standOn(stops[k - 1]), k == 0 ? 0.5 : 1.0);
        c
          ..jolt(0.5)
          ..react(k.isEven ? LanternFace.delighted : LanternFace.wow, 0.4);
        Sfx.sound('hop', pitch: 0.95 + 0.04 * k);
        // Landing: a puff of dust off the card, a ring along it, and a
        // spray of sparks.
        final glow = _colorOf(c);
        _outFx
          ?..puffs(a, count: 10, color: vm.Vector3(0.5, 0.5, 0.65), size: 0.14, speed: 1.1, life: 0.6, flatten: 0.25)
          ..ring(a, radius: 0.6, color: vm.Vector3(1.3, 1.1, 0.65), life: 0.35, normal: up)
          ..burst(a + up * 0.05, count: 14, speed: 1.8, color: vm.Vector3(1.8, 1.4, 0.7), color2: glow, shape: VfxShape.flare, life: 0.55, gravity: 3, bias: up * 1.6);
      }
      // A light trail through the air.
      if (u > 0.08 && u < 0.92 && math.Random().nextDouble() < dt * 40) {
        _outFx?.burst(feet, count: 1, speed: 0.3, color: _colorOf(c) * 0.9, size: 0.05, life: 0.45, gravity: 0.8, shape: VfxShape.flare);
      }
    } else {
      final u = Curves.easeInOutCubic.transform(span(fold, flat));
      final from = standOn(0);
      final home = sp.homeRoot! + vm.Vector3(0, c.restFeet, 0);
      feet = from + (home - from) * u;
    }
    final s = t < firstHop ? 1 + (scale - 1) * span(down - 0.5, firstHop) : (t < fold ? scale : scale + (1 - scale) * span(fold, flat));
    c.place(feet - vm.Vector3(0, c.restFeet * s, 0), 0, scale: s);
    c.airborne = t > firstHop && t < fold;
    // Motes drifting up through the space.
    final ofx = _outFx;
    if (ofx != null) {
      if (tilt > 0.2 && math.Random().nextDouble() < dt * 30 * tilt) {
        final p = sp.pivot! + vm.Vector3((math.Random().nextDouble() - 0.5) * 9, -1 + math.Random().nextDouble() * 2, (math.Random().nextDouble() - 0.2) * 9);
        ofx.burst(p, count: 1, speed: 0.2, color: vm.Vector3(1.6, 1.3, 0.8), size: 0.05, life: 2.5, gravity: -0.3, shape: VfxShape.flare);
      }
      ofx.update(dt, _outCamera);
    }
    if (crossed(fold)) Sfx.sound('soft_sweep', volume: 0.5, pitch: 0.94);
    if (t >= end) _endPeel();
  }

  void _endPeel() {
    final c = character;
    final board = sp.board;
    _outCamera
      ..position = sp.camPosition ?? _outCamera.position
      ..target = sp.camTarget ?? _outCamera.target;
    if (sp.camFov > 0) _outCamera.fovRadiansY = sp.camFov;
    board?.detach();
    sp
      ..board = null
      ..pieces.clear()
      ..peelT = -1
      ..hideApp = false;
    _outFx?.clear();
    if (c != null) {
      _comeHome(c);
      c
        ..place(vm.Vector3.zero(), 0)
        ..airborne = false
        ..canDoze = true
        ..react(LanternFace.delighted, 0.8)
        ..jolt(0.5);
    }
    Sfx.sound('land');
    _refresh();
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.center, this.radius, this.color, this.strength);
  final Offset center;
  final double radius, strength;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0 || radius <= 0) return;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = color.withValues(alpha: 0.1 * strength)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.35 * strength),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => true;
}
