part of 'park_screen.dart';

/// The time of day the app is set to, or [auto] for the clock's.
enum DayPart { auto, morning, day, evening, night }

/// The forecast the weather card shows.
enum WeatherKind { clear, rain, heat }

/// A notification your friend catches, reads, and delivers to the card it is
/// about.
class _Toast {
  _Toast(this.title, this.body, this.target);
  final String title;
  final String body;

  /// Which card or row it belongs to (see [ParkLife._targetRect]).
  final String target;
  double t = 0;
  Offset at = Offset.zero;
  double angle = 0;
  double opacity = 0;
  double scale = 1;

  /// Where the toast sat when it was thrown, and where it is headed.
  Offset? thrownFrom;
  Rect? landing;
  bool landed = false;
}

/// Everything that makes the friend feel alive around the app: tricks,
/// idle surprises, reactions to the list, the search field, the weather,
/// notifications, the time of day, and pull-to-refresh.
class _Life {
  final rng = math.Random(13);

  /// How high Juju's two little ones met, for the big one to start from.
  double mergeY = 0.45;

  /// Nova's hologram material, loaded the first time it shows.
  PreprocessedMaterial? holoMaterial;

  /// Lumi's bubble: its node, materials, where it let go, and its light (a
  /// glow point for the cards: world position, color, strength).
  Node? bubble;
  PreprocessedMaterial? bubbleMaterial, bubbleCore;
  vm.Vector3 bubbleFrom = vm.Vector3.zero();
  (vm.Vector3, vm.Vector3, double)? bubbleGlow;

  // Idle surprises.
  double nextSurprise = 14;
  int surpriseTurn = 0;

  // The butterfly.
  Node? butterfly;
  final List<Node> wings = [];
  double butterflyT = -1;
  vm.Vector3 butterflyFrom = vm.Vector3.zero();

  // The spark your friend chases.
  double chaseT = -1;
  vm.Vector3 chaseHand = vm.Vector3.zero();
  final chaseSpark = vm.Vector3.zero();
  final chaseFrom = vm.Vector3.zero();

  // The glow snowman.
  Node? snowman;
  double snowT = -1;
  bool snowMelting = false;

  // Tricks.
  double trickT = -1;
  final List<LanternCharacter> minis = [];
  Node? hologram;
  double bubblePop = -1;

  // Shyness under a lingering mouse.
  double stare = 0;
  Offset? lastMouse;

  // Pull-to-refresh.
  double pull = 0;
  double maxPull = 0;
  bool pulling = false;
  final updated = ValueNotifier<String>('Updated a moment ago');

  // Weather.
  WeatherKind weather = WeatherKind.clear;
  SfxLoop? rainVoice;
  double rainEmit = 0;
  double sweat = 0;

  // A notification being eaten.
  NotificationSnack? snack;
  double snackT = -1;
  double snackFeed = 0;
  bool snackLoading = false;

  // Notifications, and the glow where one lands.
  _Toast? toast;
  double nextToast = 40;
  final ping = ValueNotifier<(Rect, double)?>(null);

  // Search.
  final search = TextEditingController();
  Timer? searchDebounce;
  final highlight = ValueNotifier<String?>(null);
  final sparkle = ValueNotifier<(Offset, Offset, double)?>(null);

  // Time of day.
  DayPart day = DayPart.auto;

  // The layout changing under the friend.
  Size? lastSize;
  double tumbleCooldown = 0;
}

extension ParkLife on ParkScreenState {
  _Life get life => _life;

  DayPart get dayPart {
    if (life.day != DayPart.auto) return life.day;
    final h = DateTime.now().hour;
    if (h >= 5 && h < 10) return DayPart.morning;
    if (h >= 10 && h < 17) return DayPart.day;
    if (h >= 17 && h < 21) return DayPart.evening;
    return DayPart.night;
  }

  /// The header sky for the time of day, blended over the theme's own.
  List<Color> daySky(List<Color> sky) {
    final tint = switch (dayPart) {
      DayPart.morning => const [Color(0xFF2B2140), Color(0xFF6E4A6E)],
      DayPart.day => const [Color(0xFF1B3460), Color(0xFF3E6AA0)],
      DayPart.night => const [Color(0xFF03050E), Color(0xFF0A1028)],
      _ => sky,
    };
    final k = dayPart == DayPart.evening || dayPart == DayPart.auto ? 0.0 : 0.6;
    return [for (var i = 0; i < sky.length; i++) Color.lerp(sky[i], tint[math.min(i, tint.length - 1)], k)!];
  }

  void setDayPart(DayPart d) {
    life.day = d;
    final c = character;
    if (c == null) return;
    c.dozeAfter = dayPart == DayPart.night ? 10 : 25;
    _roomScene?.daylight(dayPart.index);
    if (dayPart == DayPart.morning) _morningStretch();
    _refresh();
  }

  /// A morning: a big yawn and stretch on waking.
  void _morningStretch() {
    final c = character;
    if (c == null) return;
    c.setMood(LanternMood.sleepy);
    AppClock.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      c
        ..wake()
        ..react(LanternFace.blink, 0.8)
        ..jolt(-0.9);
    });
  }

  // ---------------------------------------------------------------- frame
  void lifeTick(double dt) {
    final c = character;
    if (c == null) return;
    final fx = _fx;
    _tickShy(c, dt);
    _tickRefresh(c);
    _tickButterfly(c, dt);
    _tickChase(c, dt, fx);
    _tickSnowman(c, dt, fx);
    _tickTrick(c, dt, fx);
    _tickWeather(c, dt, fx);
    _tickToast(c, dt);
    _tickSnack(c, dt, fx);
    tickPet(c, dt);
    tickVoice(c, dt);
    life.tumbleCooldown = math.max(0, life.tumbleCooldown - dt);

    // Idle surprises, one at a time, when nothing else is going on.
    final busy = errandActive || _roomScene != null || _swapT >= 0 || life.butterflyT >= 0 || life.chaseT >= 0 || life.trickT >= 0 || life.toast != null || life.snack != null || life.snackLoading || spectacle.busy || pet.stroking || pet.level > 0.05 || voice.phase != _VoicePhase.idle || voice.typing || c.grabbing;
    final idle = _clock - _lastTouch;
    if (autoSurprises && !busy && c.mood != LanternMood.sleepy && _clock > life.nextSurprise && idle > 6 && !_clipRunning) {
      life.nextSurprise = _clock + 16 + life.rng.nextDouble() * 10;
      switch (life.surpriseTurn++ % 3) {
        case 0:
          startButterfly();
        case 1:
          startChase();
        case 2:
          _peek();
      }
    }
    if (autoSurprises && !busy && idle > 55 && life.snowman == null && c.mood != LanternMood.sleepy && !_clipRunning) buildSnowman();
    if (life.snowman != null && !life.snowMelting && idle < 0.5) {
      life.snowMelting = true;
      Sfx.sound('snow_melt');
    }
  }

  // ---------------------------------------------------------------- shy
  void _tickShy(LanternCharacter c, double dt) {
    final m = _mouse == null ? null : _toHeader(_mouse!);
    var near = false;
    if (m != null) {
      final head = camera.worldToScreen(c.headCenter, _headerSize);
      final edge = camera.worldToScreen(c.headCenter + vm.Vector3(c.headRadius, 0, 0), _headerSize);
      if (head != null && edge != null) near = (m - head).distance < (edge - head).distance * 1.15;
      final still = life.lastMouse == null || (m - life.lastMouse!).distance < 2.5;
      life.lastMouse = m;
      life.stare = near && still ? life.stare + dt : (near ? life.stare + dt * 0.4 : 0);
    } else {
      life.stare = 0;
    }
    final wasShy = c.shyTarget > 0;
    c.shyTarget = life.stare > 1.4 && !c.grabbing && c.mood != LanternMood.sleepy ? 1 : 0;
    if (wasShy && c.shyTarget == 0) c.react(LanternFace.surprised, 0.4);
  }

  // ---------------------------------------------------------------- refresh
  /// Pulling the list down past its top stretches the friend down after it;
  /// letting go far enough refreshes the wait times.
  void _tickRefresh(LanternCharacter c) {
    final m = _metrics;
    life.pull = m == null ? 0 : math.max(0.0, -m.pixels);
    final bottom = c.headCenter - vm.Vector3(0, c.headRadius * 0.55, 0);
    final at = camera.worldToScreen(bottom, _headerSize);
    if (at == null) return;
    if (life.pull > 8 && !life.pulling && !c.grabbing && !errandActive) {
      if (c.grab(scene, camera.screenPointToRay(at, _headerSize))) {
        life.pulling = true;
        life.maxPull = 0;
      }
    }
    if (life.pulling) {
      life.maxPull = math.max(life.maxPull, life.pull);
      c.drag(camera.screenPointToRay(at + Offset(0, life.pull * 1.1), _headerSize));
      if (life.pull < 3) {
        life.pulling = false;
        c.releaseGrab();
        if (life.maxPull > 70) _refreshWaits(c);
      }
    }
  }

  void _refreshWaits(LanternCharacter c) {
    for (var i = 0; i < _waits.length; i++) {
      _waits[i] = (_waits[i].$1, (_waits[i].$2 + (life.rng.nextInt(5) - 2) * 5).clamp(5, 60));
    }
    life.updated.value = 'Updated just now';
    c
      ..celebrate()
      ..jolt(1.0);
    _fx
      ?..ring(c.headCenter, radius: 1.8, color: _colorOf(c), life: 0.45)
      ..burst(c.headCenter, count: 26, speed: 3, color: _colorOf(c), shape: VfxShape.flare, life: 0.7, gravity: 2);
    Sfx.medium();
    Sfx.sound('refresh');
    lanternPulse();
    _refresh();
  }

  // ---------------------------------------------------------------- butterfly
  void startButterfly() {
    final c = character;
    if (c == null || life.butterflyT >= 0) return;
    if (life.butterfly == null) {
      final b = Node(name: 'Butterfly')..raycastable = false;
      final body = UnlitMaterial()..baseColorFactor = vm.Vector4(0.12, 0.08, 0.1, 1);
      final wingA = UnlitMaterial()..baseColorFactor = vm.Vector4(1.0, 0.62, 0.25, 1);
      final wingB = UnlitMaterial()..baseColorFactor = vm.Vector4(1.0, 0.82, 0.45, 1);
      final ball = SphereGeometry(radius: 1, segments: 16, rings: 8);
      b.add(Node(mesh: Mesh(ball, body), localTransform: vm.Matrix4.compose(vm.Vector3.zero(), vm.Quaternion.identity(), vm.Vector3(0.045, 0.045, 0.15))));
      for (final side in const [-1.0, 1.0]) {
        final hinge = Node();
        hinge.add(Node(mesh: Mesh(ball, wingA), localTransform: vm.Matrix4.compose(vm.Vector3(0.2 * side, 0, -0.05), vm.Quaternion.identity(), vm.Vector3(0.2, 0.015, 0.15))));
        hinge.add(Node(mesh: Mesh(ball, wingB), localTransform: vm.Matrix4.compose(vm.Vector3(0.15 * side, 0, 0.11), vm.Quaternion.identity(), vm.Vector3(0.13, 0.015, 0.1))));
        b.add(hinge);
        life.wings.add(hinge);
      }
      life.butterfly = b;
    }
    life.butterfly!.visible = true;
    if (life.butterfly!.parent == null) scene.add(life.butterfly!);
    life.butterflyFrom = vm.Vector3(2.6, 2.9, -0.4);
    life.butterflyT = 0;
    Sfx.sound('butterfly', volume: 0.7);
  }

  void _tickButterfly(LanternCharacter c, double dt) {
    if (life.butterflyT < 0) return;
    final b = life.butterfly!;
    final before = life.butterflyT;
    life.butterflyT += dt;
    final t = life.butterflyT;
    final top = c.headCenter + vm.Vector3(0.05, c.headRadius + 0.04, -0.05);
    late vm.Vector3 at;
    var flap = 22.0;
    if (t < 2.4) {
      // Flutter in on a wavy path and land on the head.
      final u = Curves.easeInOutCubic.transform(t / 2.4);
      at = life.butterflyFrom + (top - life.butterflyFrom) * u + vm.Vector3(0, math.sin(t * 7) * 0.12 * (1 - u), math.cos(t * 5) * 0.08 * (1 - u));
      c.lookAtWorld(at);
    } else if (t < 4.6) {
      at = top;
      flap = 3;
      c.lookAtWorld(top + vm.Vector3(0, 0.3, -0.2));
      if (before < 2.5 && t >= 2.5) c.react(LanternFace.wow, 1.2);
      if (before < 4.0 && t >= 4.0) c.sneeze();
    } else {
      // Blown away by the sneeze.
      final u = (t - 4.6) / 1.4;
      at = top + vm.Vector3(-2.4 * u, 1.4 * u + math.sin(u * 12) * 0.08, -0.4 * u);
      if (before < 4.6) c.lookAtWorld(null);
      if (u >= 1) {
        life.butterflyT = -1;
        b.visible = false;
        return;
      }
    }
    final yawA = t < 2.4 ? 0.6 : (t < 4.6 ? 0.2 : -1.2);
    b.localTransform = vm.Matrix4.compose(at, vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yawA), vm.Vector3.all(1));
    for (var i = 0; i < life.wings.length; i++) {
      final side = i == 0 ? -1.0 : 1.0;
      life.wings[i].localTransform = vm.Matrix4.rotationZ(side * (0.2 + 0.9 * (0.5 + 0.5 * math.sin(t * flap))));
    }
  }

  // ---------------------------------------------------------------- chase
  void startChase() {
    if (character == null || life.chaseT >= 0) return;
    life.chaseT = 0;
    life.chaseHand = character!.headCenter.clone();
    Sfx.sound('spark_zip');
  }

  void _tickChase(LanternCharacter c, double dt, Vfx? fx) {
    if (life.chaseT < 0) return;
    life.chaseT += dt;
    final t = life.chaseT;
    final h = c.headCenter;
    // Never inside the friend: the spark keeps a little air around the head
    // and body.
    vm.Vector3 clear(vm.Vector3 p) {
      final r = c.headRadius + 0.22;
      final d = p - h;
      if (d.length < r) p = h + d.normalized() * r;
      final body = h - vm.Vector3(0, c.headRadius * 1.25, 0);
      final b = p - body;
      final rb = c.headRadius * 0.85;
      if (b.length < rb) p = body + b.normalized() * rb;
      return p;
    }

    const escape = 3.0, gone = 3.7;
    if (t < escape) {
      // A runaway spark loops round in front; the friend follows it and
      // swipes.
      final at = clear(h + vm.Vector3(math.sin(t * 2.6) * 1.05, math.sin(t * 5.2) * 0.45 + 0.1, 0.75 * kFaceZ));
      life.chaseSpark.setFrom(at);
      fx?.burst(at, count: 2, speed: 0.15, color: vm.Vector3(2.2, 1.8, 0.8), size: 0.07, life: 0.35, gravity: 0, shape: VfxShape.flare);
      c.lookAtWorld(at);
      life.chaseHand += (at - life.chaseHand) * math.min(1.0, dt * 3.2);
      c.reachTarget = (t % 1.0) > 0.55 ? life.chaseHand : null;
    } else if (t < gone) {
      // It gets away: a quick arc up and out of the header from wherever it
      // was, trailing sparks, and the hand comes home empty.
      if (t - dt < escape) {
        life.chaseFrom.setFrom(life.chaseSpark);
        c
          ..reachTarget = null
          ..jolt(0.6);
        Sfx.sound('spark_escape');
      }
      final u = Curves.easeInCubic.transform(((t - escape) / (gone - escape)).clamp(0.0, 1.0));
      final from = life.chaseFrom;
      final side = from.x >= h.x ? 1.0 : -1.0;
      final to = h + vm.Vector3(side * 3.4, 2.6, 0.4 * kFaceZ);
      final mid = from + vm.Vector3(side * 0.6, 1.3, 0);
      final at = clear((from * ((1 - u) * (1 - u))) + (mid * (2 * u * (1 - u))) + (to * (u * u)));
      final fade = 1 - u;
      fx?.burst(at, count: 2, speed: 0.25, color: vm.Vector3(2.2, 1.8, 0.8) * (0.4 + 0.6 * fade), size: 0.06 * (0.5 + 0.5 * fade), life: 0.3, gravity: 0.4, shape: VfxShape.flare);
      c.lookAtWorld(at);
    } else {
      c
        ..lookAtWorld(null)
        ..react(LanternFace.glum, 0.9);
      life.chaseT = -1;
    }
  }

  // ---------------------------------------------------------------- snowman
  void buildSnowman() {
    final c = character;
    if (c == null || life.snowman != null) return;
    final glow = UnlitMaterial()..baseColorFactor = vm.Vector4(1.6, 1.5, 1.35, 1);
    final dark = UnlitMaterial()..baseColorFactor = vm.Vector4(0.05, 0.05, 0.08, 1);
    final carrot = UnlitMaterial()..baseColorFactor = vm.Vector4(1.4, 0.55, 0.15, 1);
    final ball = SphereGeometry(radius: 1, segments: 24, rings: 12);
    final n = Node(name: 'Snowman')..raycastable = false;
    for (final (y, r) in const [(0.0, 0.16), (0.22, 0.12), (0.39, 0.09)]) {
      n.add(Node(mesh: Mesh(ball, glow), localTransform: vm.Matrix4.compose(vm.Vector3(0, y, 0), vm.Quaternion.identity(), vm.Vector3.all(r))));
    }
    for (final x in const [-0.03, 0.03]) {
      n.add(Node(mesh: Mesh(ball, dark), localTransform: vm.Matrix4.compose(vm.Vector3(x, 0.42, -0.08), vm.Quaternion.identity(), vm.Vector3.all(0.012))));
    }
    n.add(Node(
      mesh: Mesh(CylinderGeometry(bottomRadius: 1, topRadius: 0, height: 1, radialSegments: 12), carrot),
      localTransform: vm.Matrix4.compose(vm.Vector3(0, 0.39, -0.12), vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -math.pi / 2), vm.Vector3(0.018, 0.08, 0.018)),
    ));
    // Placed and hidden before it is ever drawn; the balls grow in one by
    // one from the tick.
    n.localTransform = vm.Matrix4.translation(_snowAt);
    for (final part in n.children) {
      part.visible = false;
    }
    life.snowman = n;
    life.snowT = 0;
    life.snowMelting = false;
    scene.add(n);
  }

  static final _snowAt = vm.Vector3(1.5, 0.55, 0.2);

  void _tickSnowman(LanternCharacter c, double dt, Vfx? fx) {
    final n = life.snowman;
    if (n == null) return;
    final before = life.snowT;
    life.snowT += dt;
    final at = _snowAt;
    final parts = n.children;
    if (life.snowMelting) {
      // Melts away into sparkles when someone comes back.
      final k = (1 - life.snowT.clamp(0.0, 0.6) / 0.6);
      n.localTransform = vm.Matrix4.compose(at, vm.Quaternion.identity(), vm.Vector3(1 + (1 - k) * 0.4, k, 1 + (1 - k) * 0.4));
      if (life.snowT > 0.6 || k <= 0) {
        fx?.burst(at + vm.Vector3(0, 0.2, 0), count: 30, speed: 1.4, color: vm.Vector3(1.4, 1.4, 1.6), shape: VfxShape.flare, life: 0.8, gravity: -0.4);
        n.detach();
        life.snowman = null;
      }
      return;
    }
    // The friend builds it ball by ball, glancing over at it.
    for (var i = 0; i < parts.length; i++) {
      final appear = (life.snowT - i * 0.7) / 0.45;
      final s = appear <= 0 ? 0.0001 : Curves.elasticOut.transform(appear.clamp(0.0, 1.0));
      final base = parts[i].localTransform;
      final tr = base.getTranslation();
      final sc = base.getMaxScaleOnAxis();
      if (i < 3) {
        parts[i].visible = s > 0.001;
        parts[i].localTransform = vm.Matrix4.compose(tr, vm.Quaternion.identity(), vm.Vector3.all(const [0.16, 0.12, 0.09][i] * s));
        if (before < i * 0.7 + 0.1 && life.snowT >= i * 0.7 + 0.1) {
          fx?.puffs(at + tr, count: 6, color: vm.Vector3(0.6, 0.6, 0.7), size: 0.08, speed: 0.6);
          Sfx.sound('snow_build', pitch: 1 + i * 0.12);
        }
      } else {
        parts[i].visible = life.snowT > 2.2;
      }
      if (sc == 0) continue;
    }
    n.localTransform = vm.Matrix4.translation(at);
    if (life.snowT < 3) c.lookAtWorld(at + vm.Vector3(0, 0.3, 0));
    if (before < 3 && life.snowT >= 3) {
      c
        ..lookAtWorld(null)
        ..react(LanternFace.delighted, 0.8);
    }
  }

  // ---------------------------------------------------------------- tricks
  /// Each friend's signature trick.
  Future<void> trick() async {
    final c = character;
    if (c == null || life.trickT >= 0 || errandActive) return;
    c.wake();
    life.trickT = 0;
    Sfx.sound(switch (c.friend.id) {
      'juju' => 'trick_split',
      'mochi' => 'trick_bloom',
      'nova' => 'trick_holo',
      _ => 'trick_bubble',
    });
    switch (c.friend.id) {
      case 'juju':
        // Two little Jujus, loaded while the big one winds up, and kept out
        // of the scene until they are placed (tiny) and posed.
        final LanternCharacter a, b;
        try {
          a = await LanternCharacter.load(scene, friend: c.friend, addToScene: false);
          b = await LanternCharacter.load(scene, friend: c.friend, addToScene: false);
        } catch (e) {
          // Without them there is no trick; stand the big one back up.
          debugPrint('Juju split failed to load: $e');
          if (mounted && character == c) endTrick(c);
          return;
        }
        // Swapped away (or gone) while they loaded: never show them.
        if (!mounted || character != c || life.trickT < 0) {
          for (final m in [a, b]) {
            m.root.detach();
            m.dispose();
          }
          return;
        }
        for (final m in [a, b]) {
          m
            ..onSound = null
            ..onStep = (() => Sfx.sound('map_step', volume: 0.5, pitch: 1.25, gap: Duration.zero))
            ..grounded = true
            ..place(vm.Vector3.zero(), 0, scale: 0.001)
            ..canDoze = false
            ..idleAntics = false
            ..hueShift = c.hueShift
            ..setTheme(c.theme)
            ..wake()
            ..update(0, _clock);
          scene.add(m.root);
        }
        life.minis
          ..clear()
          ..addAll([a, b]);
        life.trickT = 0;
      case 'mochi':
        c.bloom();
        _fx?.burst(c.headCenter + vm.Vector3(0, c.headRadius + 0.2, 0), count: 24, speed: 1.2, color: vm.Vector3(2.0, 1.2, 1.5), shape: VfxShape.flare, life: 1.0, gravity: -0.5);
      case 'nova':
        _showHologram(c);
      default:
        await _makeBubble();
    }
  }

  /// Lumi's bubble: a soap film around a warm little light, built hidden
  /// (and at no size) before the trick blows it.
  Future<void> _makeBubble() async {
    _dropBubble();
    final film = life.bubbleMaterial ??= await loadFmatMaterial('assets/bubble.fmat');
    final core = life.bubbleCore ??= await loadFmatMaterial('assets/ember.fmat');
    if (!mounted || life.trickT < 0) return;
    core.parameters
      ..setVec4('ember_color', vm.Vector4(1.0, 0.62, 0.3, 1))
      ..setFloat('intensity', 3.0);
    final sphere = SphereGeometry(radius: 1, segments: 40, rings: 20);
    final node = Node(name: 'Bubble', mesh: Mesh(sphere, film))
      ..raycastable = false
      ..visible = false
      ..add(Node(name: 'BubbleCore', mesh: Mesh(SphereGeometry(radius: 0.22, segments: 16, rings: 10), core))..raycastable = false);
    life.bubble = node;
    scene.add(node);
  }

  void _dropBubble() {
    life.bubble?.detach();
    life.bubble = null;
    life.bubbleGlow = null;
    character?.ambientColor.setZero();
  }

  /// Juju's split, keyed by hand and mirrored: a shivering wind-up, a pop,
  /// two minis flung apart to land together. The left one wobbles, topples
  /// over, lies there dizzy, pops up and shakes it off; the right one
  /// overbalances and teeters, arms windmilling, then rights itself. Both
  /// cheer, hop back together, and merge.
  void _tickSplit(LanternCharacter c, List<LanternCharacter> minis, double t, double before, double dt, Vfx? fx) {
    bool crossed(double at) => before < at && t >= at;
    double span(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
    const split = 0.7, land = 1.15, cheer = 3.75, runFrom = 3.95, charge = 5.15, leap = 5.6, merge = 5.9, touch = 6.3, end = 7.15;
    const meet = 0.45;
    const spread = 0.85, size = 0.55;

    // The big one: a wind-up that shivers faster and faster, then gone.
    if (t < split) {
      final k = span(0, split);
      c
        ..tip = math.sin(t * (16 + 34 * k)) * 0.08 * k
        ..place(vm.Vector3.zero(), 0, scale: 1 - 0.07 * k);
      if (crossed(0.05)) {
        c
          ..react(LanternFace.poked, split)
          ..jolt(0.4);
      }
    } else if (t < merge) {
      c
        ..tip = 0
        ..place(vm.Vector3.zero(), 0, scale: 0.001);
    }
    if (crossed(split)) {
      final at = c.headCenter - vm.Vector3(0, c.headRadius * 0.6, 0);
      fx
        ?..ring(at, radius: 1.4, color: _colorOf(c), life: 0.35)
        ..burst(at, count: 36, speed: 3.2, color: _colorOf(c), color2: vm.Vector3(2.0, 1.7, 1.2), shape: VfxShape.flare, life: 0.6, gravity: 3);
      Sfx.sound('pop', volume: 2);
    }

    for (var i = 0; i < minis.length; i++) {
      final m = minis[i];
      final side = i == 0 ? -1.0 : 1.0;
      final out = -side; // tipping outward, away from the other
      var x = 0.0, y = 0.0, tip = 0.0, yaw = 0.0, s = 0.001;
      vm.Vector3? look = minis[minis.length - 1 - i].headCenter;
      vm.Vector3? handA, handB;
      if (t >= split && t < merge) {
        s = size * (0.55 + 0.45 * Curves.easeOutBack.transform(span(split, split + 0.3)));
        yaw = -side * 0.3;
        // Flung apart in a mirrored arc.
        final u = span(split, land);
        x = side * spread * Curves.easeOutCubic.transform(u);
        y = 0.5 * math.sin(math.pi * u);
        tip = out * 0.25 * u;
        if (crossed(land)) {
          m
            ..jolt(0.9)
            ..react(LanternFace.surprised, 0.4);
          for (final f in m.jetPoints) {
            fx?.puffs(f, count: 4, color: vm.Vector3(0.4, 0.38, 0.5), size: 0.08, speed: 0.7, life: 0.5);
          }
          if (i == 0) Sfx.sound('land', volume: 2);
        }
        if (t >= land) {
          if (i == 0) {
            // The faller: a wobble that grows, then over it goes.
            if (t < 1.45) {
              tip = out * (0.25 + 0.14 * math.sin((t - land) * 22) * span(land, 1.45));
            } else if (t < 1.8) {
              tip = out * (0.3 + 1.15 * Curves.easeIn.transform(span(1.45, 1.8)));
              look = null;
            } else if (t < 2.7) {
              final k = t - 1.8;
              tip = out * (1.45 - 0.14 * math.max(0.0, math.sin(k * 15)) * math.exp(-k * 6));
              look = null;
              if (crossed(1.8)) {
                m
                  ..jolt(1.0)
                  ..react(LanternFace.dizzy, 0.9);
                fx?.puffs(m.headCenter, count: 6, color: vm.Vector3(0.4, 0.38, 0.5), size: 0.1, speed: 0.9, life: 0.6);
                Sfx.sound('land', volume: 2.5, pitch: 0.9);
              }
            } else if (t < 3.0) {
              tip = out * 1.45 * (1 - Curves.easeOutBack.transform(span(2.7, 3.0)));
              if (crossed(2.7)) m.jolt(0.5);
            } else if (t < cheer) {
              // Shaking it off: a quick head shake that settles.
              final k = t - 3.0;
              tip = math.sin(k * 26) * 0.2 * math.exp(-k * 3.2);
              look = m.headCenter + vm.Vector3(math.sin(k * 26) * 2, 0.2, 1.0 * kFaceZ);
              if (crossed(3.0)) m.react(LanternFace.poked, 0.6);
            }
          } else {
            // The teeterer: overbalances outward and hangs there, arms
            // windmilling, then rights itself with a little overshoot.
            if (t < 1.45) {
              tip = out * (0.25 + 0.37 * Curves.easeOut.transform(span(land, 1.45)));
            } else if (t < 2.45) {
              final k = t - 1.45;
              tip = out * (0.62 + 0.07 * math.sin(k * 9));
              final r = m.headRadius * size;
              final h = m.headCenter;
              final w = k * 16;
              handA = h + vm.Vector3(r * 1.4 + math.cos(w) * r * 0.6, math.sin(w) * r * 0.7, 0.2 * kFaceZ);
              handB = h + vm.Vector3(-r * 1.4 + math.cos(w + math.pi) * r * 0.6, math.sin(w + math.pi) * r * 0.7, 0.2 * kFaceZ);
              look = h + vm.Vector3(0, 0.6, 1.0 * kFaceZ);
              if (crossed(1.45)) {
                m.react(LanternFace.surprised, 1.0);
                Sfx.sound('chirp_curious', volume: 0.8);
              }
            } else if (t < 2.85) {
              tip = out * 0.62 * (1 - Curves.easeOutBack.transform(span(2.45, 2.85)));
            } else if (t < cheer) {
              final k = t - 2.85;
              tip = -out * 0.1 * math.sin(k * 10) * math.exp(-k * 4);
              if (crossed(2.85)) {
                m
                  ..react(LanternFace.content, 0.8)
                  ..jolt(0.3);
              }
            }
          }
        }
        // Both cheer and hop.
        if (crossed(cheer)) {
          m
            ..react(LanternFace.delighted, 1.2)
            ..jolt(0.6);
          if (i == 0) Sfx.sound('giggle');
        }
        if (t >= cheer && t < runFrom) {
          y = 0.22 * math.sin(math.pi * span(cheer, runFrom));
        }
        final r = m.headRadius * size;
        final h = m.headCenter;
        final body = h - vm.Vector3(0, r * 1.3, 0);
        if (t >= runFrom && t < charge) {
          // Running back to each other, each its own way: the left one
          // determined, brow down and arms pumping; the right one thrilled,
          // arms up and waving.
          // The body glides; the feet do the walking (planted, in turn, see
          // the friend's gait), and the arms pump in time with the steps.
          final u = span(runFrom, charge);
          x = side * (spread - (spread - meet) * Curves.easeInOutSine.transform(u));
          final lean = Curves.easeInOut.transform(span(runFrom, runFrom + 0.25)) * (1 - Curves.easeInOut.transform(span(charge - 0.2, charge)));
          tip = side * 0.14 * lean;
          yaw = -side * (0.3 + 0.25 * Curves.easeInOut.transform(span(runFrom, runFrom + 0.25)));
          m.run = 0;
          final swing = m.stride;
          if (i == 0) {
            handA = body + vm.Vector3(r * 0.95, swing * r * 0.35, swing * r * 0.55 * kFaceZ);
            handB = body + vm.Vector3(-r * 0.95, -swing * r * 0.35, -swing * r * 0.55 * kFaceZ);
            if (crossed(runFrom)) m.react(LanternFace.grumpy, charge - runFrom);
          } else {
            final ph = (t - runFrom) * 10;
            handA = h + vm.Vector3(r * 1.25, r * (0.55 + 0.3 * math.sin(ph * 0.7)), 0.15 * kFaceZ);
            handB = h + vm.Vector3(-r * 1.25, r * (0.55 + 0.3 * math.sin(ph * 0.7 + 2)), 0.15 * kFaceZ);
            if (crossed(runFrom)) m.react(LanternFace.delighted, charge - runFrom);
          }
        } else if (t >= charge && t < leap) {
          // Charging up: a crouch, a shiver, and a glow that builds, sparks
          // drawn in between them.
          final u = span(charge, leap);
          m.run = 0;
          x = side * meet;
          y = -0.05 * Curves.easeOut.transform(u);
          yaw = -side * 0.55;
          tip = -side * 0.12 * Curves.easeInOut.transform(u) + math.sin(t * 60) * 0.03 * u;
          m.glowScale = 1 + 1.2 * u;
          if (crossed(charge)) {
            m
              ..jolt(0.6)
              ..react(LanternFace.poked, leap - charge);
            if (i == 0) Sfx.sound('stretch', pitch: 1.4, volume: 0.8);
          }
          if (i == 0 && life.rng.nextDouble() < dt * 40) {
            final a = life.rng.nextDouble() * math.pi * 2;
            final p = vm.Vector3(0, 0.55, 0) + vm.Vector3(math.cos(a), math.sin(a), 0) * 0.7;
            fx?.burst(p, count: 1, speed: 0.1, color: _colorOf(c), size: 0.05, life: 0.3, gravity: 0, bias: (vm.Vector3(0, 0.55, 0) - p) * 2.4, shape: VfxShape.flare);
          }
        } else if (t >= leap) {
          // And into each other: a leap that rolls inward and meets above.
          // Picking up from the crouch, so nothing jumps.
          final u = span(leap, merge);
          x = side * meet * (1 - Curves.easeIn.transform(u));
          y = -0.05 * (1 - u) + 0.95 * math.sin(math.pi * 0.6 * u);
          yaw = -side * 0.55;
          tip = -side * 0.12 * (1 - u) + side * 1.3 * Curves.easeIn.transform(u);
          m.glowScale = 2.2;
          if (crossed(leap)) {
            m
              ..jolt(-0.7)
              ..react(LanternFace.wow, merge - leap);
            if (i == 0) Sfx.sound('hop', volume: 2.5, pitch: 1.1);
          }
        }
      }
      m
        ..tip = tip
        ..reachTarget = handA
        ..reachTargetR = handB
        ..place(vm.Vector3(x, y, 0), yaw, scale: s)
        ..lookAtWorld(look)
        ..update(dt, _clock);
    }

    if (crossed(merge)) {
      // One again: a flash, and the big one pops back in mid-air where the
      // little ones' heads met, jiggling all over.
      if (minis.isNotEmpty) {
        final met = minis.map((m) => m.headCenter.y).reduce((a, b) => a + b) / minis.length;
        life.mergeY = math.max(0.0, met - c.restHead.y * 0.7);
      }
      final at = vm.Vector3(0, life.mergeY + c.restHead.y * 0.7, 0);
      for (final m in minis) {
        m.root.detach();
        m.dispose();
      }
      minis.clear();
      fx
        ?..flare(at, size: 2.2, life: 0.35)
        ..ring(at, radius: 2.0, color: _colorOf(c), life: 0.45)
        ..burst(at, count: 40, speed: 3.2, color: _colorOf(c), color2: vm.Vector3(2.0, 1.7, 1.2), shape: VfxShape.flare, life: 0.8, gravity: 2);
      c
        ..jolt(1.3)
        ..react(LanternFace.delighted, 1.4);
      c.soft.jiggle(1.8, 7);
      Sfx.sound('pop', volume: 2.5, pitch: 1.1);
      Sfx.sound('trick_split', volume: 0.6, pitch: 1.3);
    }
    if (t >= merge) {
      // Falling, stretched tall in anticipation; a squash on the floor; one
      // little rebound; settled.
      final pop = 0.7 + 0.3 * Curves.elasticOut.transform(span(merge, merge + 0.35));
      var y = 0.0;
      var tip = 0.0;
      if (t < touch) {
        final u = span(merge, touch);
        y = life.mergeY * (1 - u * u);
        tip = math.sin((t - merge) * 30) * 0.12 * math.exp(-(t - merge) * 5);
        if (crossed(merge + 0.12)) c.jolt(-0.8);
      } else {
        final k = t - touch;
        y = 0.08 * math.max(0.0, math.sin(math.pi * k / 0.32)) * (k < 0.32 ? 1 : 0);
        tip = math.sin(k * 18) * 0.06 * math.exp(-k * 5);
        if (crossed(touch)) {
          c.jolt(1.2);
          for (final f in c.jetPoints) {
            fx?.puffs(f, count: 6, color: vm.Vector3(0.4, 0.38, 0.5), size: 0.12, speed: 0.9, life: 0.6);
          }
          Sfx.sound('land', volume: 3);
        }
        if (crossed(touch + 0.32)) c.jolt(0.4);
      }
      c
        ..tip = tip
        ..place(vm.Vector3(0, y, 0), 0, scale: pop);
      if (crossed(touch + 0.2)) c.celebrate();
    }
    if (t > end) {
      c
        ..tip = 0
        ..place(vm.Vector3.zero(), 0);
      life.trickT = -1;
    }
  }

  /// Stops any trick mid-way and clears up after it: Juju's two little ones,
  /// Nova's hologram, Lumi's bubble. For a friend swap, which must not leave
  /// them stranded in the scene.
  void endTrick(LanternCharacter c) {
    for (final m in life.minis) {
      m.root.detach();
      m.dispose();
    }
    life.minis.clear();
    life.hologram?.detach();
    life.hologram = null;
    _dropBubble();
    life.trickT = -1;
    c
      ..tip = 0
      ..reachTarget = null
      ..reachTargetR = null;
    if (c.root.globalTransform.getMaxScaleOnAxis() < 0.01) c.place(vm.Vector3.zero(), 0);
  }

  Future<void> _showHologram(LanternCharacter c) async {
    life.hologram?.detach();
    life.hologram = null;
    final material = life.holoMaterial ??= await loadFmatMaterial('assets/hologram.fmat');
    if (!mounted || life.trickT < 0 || character != c) return;
    material.parameters
      ..setFloat('on', 0)
      ..setFloat('time', _clock);
    final card = Node(name: 'Hologram')
      ..addComponent(WidgetComponent(
        size: const Size(240, 150),
        pixelRatio: 2.5,
        worldHeight: 0.85,
        material: material,
        bind: (texture) => material.parameters.setTexture('screen_texture', texture),
        child: _HoloCard(waits: List.of(_waits)),
      ));
    life.hologram = card;
    scene.add(card);
  }

  /// Lumi's trick: a breath in, a bubble blown from the lips (swelling and
  /// wobbling as it goes), let go with a little squash, floating up with a
  /// warm light inside that lights Lumi and the cards, and a pop.
  void _tickBubble(LanternCharacter c, double t, double before, Vfx? fx) {
    bool crossed(double at) => before < at && t >= at;
    double span(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
    const blow = 0.45, free = 1.55, pop = 4.2, end = 4.75;
    const size = 0.3;
    if (crossed(0.02)) {
      // A breath in: a stretch, eyes closed.
      c
        ..react(LanternFace.content, blow)
        ..jolt(-0.45);
    }
    final b = life.bubble;
    if (b == null) {
      // Still building it: hold at the breath.
      if (t > blow) life.trickT = blow;
      return;
    }
    final r = c.headRadius * c.root.globalTransform.getMaxScaleOnAxis() / c.friend.scale;
    final mouth = c.headCenter + vm.Vector3(0, -r * 0.28, r * 0.92 * kFaceZ);
    // Blown off to the side, so it is not in front of the face.
    final out = vm.Vector3(0.8, 0.12, 0.55 * kFaceZ)..normalize();
    var radius = 0.0;
    var squash = 1.0;
    vm.Vector3 at;
    if (t < free) {
      // Blown: it swells from the lips, wobbling, and pushes out as it grows.
      final u = span(blow, free);
      radius = size * Curves.easeOut.transform(u) * (1 + 0.08 * math.sin(t * 22) * (1 - u));
      at = mouth + out * (radius * 1.05);
      life.bubbleFrom = at.clone();
      if (crossed(blow)) c.react(LanternFace.wow, free - blow);
      c.lookAtWorld(at + vm.Vector3(0, 0, 0.4 * kFaceZ));
    } else {
      // Free: a squash as it lets go, then up and away, bobbing.
      final k = t - free;
      radius = size;
      squash = 1 - 0.16 * math.exp(-k * 5) * math.cos(k * 18);
      final rise = k * k / (k + 0.5);
      at = life.bubbleFrom + vm.Vector3(0.3 * rise + math.sin(k * 2.2) * 0.05, 0.5 * rise, -0.1 * rise * kFaceZ);
      if (crossed(free)) {
        c
          ..jolt(0.35)
          ..react(LanternFace.delighted, 0.8);
        Sfx.sound('pop', volume: 0.35, pitch: 1.6);
      }
      c.lookAtWorld(at);
      // A tremble, and it pops.
      if (t > pop - 0.3 && t < pop) radius *= 1 + 0.04 * math.sin(t * 70);
      if (t >= pop) radius *= 1 - span(pop, pop + 0.07);
      if (crossed(pop)) {
        fx
          ?..flare(at, size: 1.0, color: vm.Vector3(2.0, 1.6, 1.0), life: 0.3)
          ..burst(at, count: 30, speed: 2.2, color: vm.Vector3(1.6, 1.2, 0.6), color2: vm.Vector3(0.9, 1.2, 1.8), shape: VfxShape.flare, life: 0.8, gravity: 1.2)
          ..ring(at, radius: 0.7, color: vm.Vector3(1.2, 1.4, 1.8), life: 0.35);
        Sfx.sound('pop');
        c
          ..lookAtWorld(null)
          ..celebrate();
      }
    }
    b
      ..visible = radius > 1e-3
      ..localTransform = vm.Matrix4.compose(at, vm.Quaternion.identity(), vm.Vector3(radius / squash.clamp(0.7, 1.3), radius * squash, radius / squash.clamp(0.7, 1.3)));
    life.bubbleMaterial?.parameters.setFloat('time', _clock);
    // Its light: on Lumi (from its side) and on the cards below, growing as
    // it is blown and fading out after the pop rather than switching off.
    final light = (radius / size).clamp(0.0, 1.0) * (t < pop ? 1.0 : 1 - span(pop, pop + 0.4)) + (t >= pop ? 0.8 * (1 - span(pop, pop + 0.4)) : 0);
    final toward = at - c.headCenter;
    final near = 1 / (1 + toward.length * 1.2);
    c.ambientColor.setFrom(vm.Vector3(1.0, 0.62, 0.3) * (0.35 * light * near));
    c.ambientDirection.setFrom(toward.normalized());
    life.bubbleGlow = (at.clone(), vm.Vector3(1.0, 0.7, 0.35), light * 0.9);
    if (t >= end) {
      _dropBubble();
      life.trickT = -1;
    }
  }

  void _tickTrick(LanternCharacter c, double dt, Vfx? fx) {
    if (life.trickT < 0) return;
    final before = life.trickT;
    life.trickT += dt;
    final t = life.trickT;
    bool crossed(double at) => before < at && t >= at;
    switch (c.friend.id) {
      case 'lumi':
        _tickBubble(c, t, before, fx);
      case 'juju':
        final minis = life.minis;
        // Still loading the two little ones (before the merge, when they
        // are let go).
        if (minis.length < 2 && t < 5.9) {
          // The big one winds up meanwhile, and holds there until they are
          // ready, so the split never skips ahead.
          if (t > 0.6) life.trickT = 0.6;
          _tickSplit(c, const [], life.trickT, before, dt, fx);
          return;
        }
        _tickSplit(c, minis, t, before, dt, fx);
      case 'nova':
        final card = life.hologram;
        if (card != null) {
          // The hologram scans on in front of the visor, glitching as it
          // forms, holds, and scans away (all in its shader; it only grows a
          // little as it comes).
          final on = t < 0.55 ? Curves.easeOut.transform(t / 0.55) : (t < 5.5 ? 1.0 : 1 - Curves.easeIn.transform(((t - 5.5) / 0.4).clamp(0.0, 1.0)));
          life.holoMaterial?.parameters
            ?..setFloat('on', on)
            ..setFloat('time', _clock);
          final grow = 0.9 + 0.1 * on;
          final at = c.headCenter + vm.Vector3(-1.05, 0.15, -0.6);
          final to = camera.position - at;
          card.localTransform = vm.Matrix4.compose(
            at,
            vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), math.atan2(to.x, to.z) + math.pi),
            vm.Vector3(-grow, grow, grow),
          );
          if (t < 5.5 && (t * 20).floor() != ((t - dt) * 20).floor()) {
            fx?.streak(c.headCenter + vm.Vector3(-0.25, 0.05, -0.55), (at - c.headCenter) * 2.2, color: vm.Vector3(0.4, 1.4, 1.8) * 0.5, width: 0.02, length: 0.06, life: 0.25);
          }
          if (crossed(0.2)) c.react(LanternFace.wow, 1.0);
        }
        if (t > 5.95) {
          life.hologram?.detach();
          life.hologram = null;
          life.trickT = -1;
        }
      default:
        if (t > 2.5) life.trickT = -1;
    }
  }

  // ---------------------------------------------------------------- weather
  void setWeather(WeatherKind w) {
    if (w != life.weather) {
      Sfx.sound(switch (w) {
        WeatherKind.rain => 'umbrella',
        WeatherKind.heat => 'shades',
        WeatherKind.clear => 'chirp_happy',
      });
      life.rainVoice?.stop();
      life.rainVoice = null;
      if (w == WeatherKind.rain) Sfx.soundLoop('rain_loop', volume: 0.5).then((v) => life.rainVoice = v);
    }
    life.weather = w;
    character?.weather(umbrella: w == WeatherKind.rain, shades: w == WeatherKind.heat);
    character?.react(w == WeatherKind.rain ? LanternFace.glum : (w == WeatherKind.heat ? LanternFace.content : LanternFace.delighted), 1.0);
    _refresh();
  }

  void _tickWeather(LanternCharacter c, double dt, Vfx? fx) {
    if (fx == null || _roomScene != null) return;
    if (life.weather == WeatherKind.rain) {
      life.rainEmit -= dt;
      while (life.rainEmit <= 0) {
        life.rainEmit += 0.012;
        final at = vm.Vector3((life.rng.nextDouble() - 0.5) * 4.6, 3.4, (life.rng.nextDouble() - 0.5) * 2);
        fx.streak(at, vm.Vector3(-0.5, -7.5, 0), color: vm.Vector3(0.55, 0.65, 0.95) * 0.45, width: 0.01, length: 0.04, life: 0.55);
      }
      // Drops bouncing off the umbrella.
      if (life.rng.nextDouble() < dt * 14) {
        final canopy = c.umbrellaTop;
        if (canopy == null) return;
        final top = canopy + vm.Vector3((life.rng.nextDouble() - 0.5) * 0.7, 0.12, -0.1);
        fx.burst(top, count: 2, speed: 0.6, color: vm.Vector3(0.7, 0.85, 1.3), size: 0.025, life: 0.3, gravity: 6, bias: vm.Vector3(0, 0.8, 0));
      }
    } else if (life.weather == WeatherKind.heat) {
      // A slow summer melt: drooping, and the odd bead of sweat.
      life.sweat -= dt;
      if (life.sweat <= 0) {
        life.sweat = 1.6 + life.rng.nextDouble();
        final side = life.rng.nextBool() ? 1.0 : -1.0;
        fx.streak(c.headCenter + vm.Vector3(side * c.headRadius * 0.85, c.headRadius * 0.3, -0.2), vm.Vector3(0, -0.8, 0), color: vm.Vector3(0.6, 0.85, 1.4), width: 0.03, length: 0.06, life: 0.7, gravity: 2);
        c.jolt(-0.25);
      }
    }
  }

  // ---------------------------------------------------------------- toasts
  // Each notification names the card or row it is about.
  static const _messages = [
    ('Moon Drop', 'The wait just dropped to 15 min', 'Moon Drop'),
    ('Fireworks', 'Lagoon show starts in 20 minutes', 'tonight'),
    ('Reward', 'A new Lagoon Key is hiding nearby', 'reward'),
    ('Weather', 'Rain rolling in this evening', 'weather'),
    ('Dining', 'Lantern Café has a table for two', 'Lantern Café'),
    // News this good gets eaten.
    ('Treats', 'Warm glow churros at Starlight Treats', 'eat'),
  ];

  static const _toastWidth = 210.0;
  static const _toastHeight = 66.0;

  /// The on-screen rect of a notification's card or row, or null when it
  /// is not built or scrolled out of view.
  Rect? _targetRect(String target) {
    final key = switch (target) {
      'tonight' => _tonightKey,
      'reward' => _rewardKey,
      'weather' => _weatherKey,
      _ => _rowKeys[target],
    };
    final r = key == null ? null : globalRectOf(key);
    if (r == null) return null;
    final top = _headerHeight + 8;
    final bottom = _screenSize.height - 8;
    return r.center.dy > top && r.center.dy < bottom ? r : null;
  }

  /// A notification arrives (one the friend delivers, or with [edible], now
  /// and then one it eats instead).
  void notify({bool edible = true}) {
    if (life.toast != null || life.snack != null || life.snackLoading || character == null) return;
    // Prefer news about something on screen, so the delivery can be seen.
    final visible = _messages.where((m) => (edible && m.$3 == 'eat') || _targetRect(m.$3) != null).toList();
    final pool = visible.isEmpty ? [for (final m in _messages) if (edible || m.$3 != 'eat') m] : visible;
    final (t, b, target) = pool[life.rng.nextInt(pool.length)];
    if (target == 'eat') {
      _startSnack(t, b);
      return;
    }
    life.toast = _Toast(t, b, target);
    Sfx.light();
    Sfx.sound('notify');
  }

  /// What the news does once it lands on its card.
  void _deliver(_Toast toast) {
    switch (toast.target) {
      case 'reward':
        _resetReward();
      case 'weather':
        setWeather(WeatherKind.rain);
      case 'Moon Drop':
        final i = _waits.indexWhere((w) => w.$1 == 'Moon Drop');
        if (i >= 0) _waits[i] = ('Moon Drop', 15);
    }
    Sfx.medium();
    Sfx.sound('deliver');
  }

  void _tickToast(LanternCharacter c, double dt) {
    if (autoSurprises && life.toast == null && life.snack == null && _clock > life.nextToast && !_clipRunning && !errandActive && _roomScene == null) {
      life.nextToast = _clock + 50 + life.rng.nextDouble() * 30;
      notify();
    }
    final ping = life.ping.value;
    if (ping != null) {
      final u = ping.$2 + dt / 1.1;
      life.ping.value = u >= 1 ? null : (ping.$1, u);
    }
    final toast = life.toast;
    if (toast == null) return;
    final before = toast.t;
    toast.t += dt;
    _refresh();
    final t = toast.t;
    bool crossed(double at) => before < at && t >= at;
    final w = _screenSize.width;
    final h = _headerHeight;
    final head = _headScreen();
    final headG = head == null ? Offset(w * 0.5, h * 0.4) : _headerGlobal(head);

    // Where it is held to be read: in front of the body, just under the
    // chin, shrunk a touch to fit between the hands. It comes in from the
    // right a little higher, and is caught there.
    final chin = head == null ? headG.dy + 40 : _headerGlobal(camera.worldToScreen(c.headCenter - vm.Vector3(0, c.headRadius * 0.8, 0), _headerSize) ?? head).dy;
    final heldScale = math.min(0.86, (w - 24) / _toastWidth);
    final heldW = _toastWidth * heldScale;
    final hold = Offset((headG.dx - heldW * 0.5 + 10).clamp(12.0, w - 12 - heldW), chin - 6);
    final catchAt = Offset(math.min(hold.dx + 40, w - 12 - _toastWidth), hold.dy - 34);
    // The hands hold its two short edges, a little below the middle. The
    // hand on the screen's right is the friend's left.
    Offset gripRight(Offset at, double scale) => at + Offset(_toastWidth * scale + 3, _toastHeight * 0.55 * scale);
    Offset gripLeft(Offset at, double scale) => at + Offset(-3, _toastHeight * 0.55 * scale);
    Offset? toGlobal(vm.Vector3 p) {
      final q = camera.worldToScreen(p, _headerSize);
      return q == null ? null : _headerGlobal(q);
    }

    vm.Vector3? world(Offset global) {
      final local = _toHeader(global);
      if (local == null) return null;
      final ray = camera.screenPointToRay(local, _headerSize);
      final d = ray.direction.normalized();
      // A little in front of the body, so the hands come forward to hold it.
      final z = c.headCenter.z + 0.35 * kFaceZ;
      return ray.origin + d * ((z - ray.origin.z) / d.z);
    }

    const arrive = 0.6, settled = 1.05, windUp = 2.6, letGo = 2.75, release = 2.95, land = 3.5, end = 4.4;
    if (t < arrive) {
      // Slides in from the right; both hands come up to meet it.
      final u = Curves.easeOutCubic.transform(t / arrive);
      toast
        ..at = Offset(w + 10 + (catchAt.dx - w - 10) * u, catchAt.dy)
        ..opacity = 1
        ..scale = 1;
      if (t > 0.2) {
        c
          ..reachTarget = world(gripRight(catchAt, 1))
          ..reachTargetR = world(gripLeft(catchAt, 1));
      }
      final local = _toHeader(toast.at + const Offset(60, 24));
      if (local != null) c.lookToward(_lookVector(local), curious: false);
    } else if (t < release) {
      if (crossed(arrive)) {
        c.jolt(0.35);
        Sfx.light();
        Sfx.sound('catch');
      }
      // Caught: brought in under the chin and read. The hands are steered
      // to where the edges should be, and the toast rides between the
      // hands, so the three never drift apart.
      final u = Curves.easeInOutCubic.transform(((t - arrive) / (settled - arrive)).clamp(0.0, 1.0));
      final scale = 1 + (heldScale - 1) * u;
      var want = Offset.lerp(catchAt, hold, u)!;
      if (t > windUp) {
        // A little wind-up to the right before the throw.
        final k = Curves.easeOut.transform(((t - windUp) / (release - windUp)).clamp(0.0, 1.0));
        want += Offset(26 * k, -18 * k);
      }
      final right = gripRight(want, scale), left = gripLeft(want, scale);
      c
        ..reachTarget = world(right)
        ..reachTargetR = t < letGo ? world(left) : null;
      final hl = toGlobal(c.handWorld), hr = toGlobal(c.handWorldR);
      final follow = ((t - arrive) / 0.15).clamp(0.0, 1.0);
      var riding = want;
      if (hl != null && hr != null) {
        // Both hands: sit between them. Once the left lets go, hang from the
        // right.
        final both = (hl + hr) / 2 - ((right + left) / 2 - want);
        final one = hl - (right - want);
        riding = Offset.lerp(both, one, ((t - letGo) / 0.15).clamp(0.0, 1.0))!;
      }
      final wobble = math.sin(t * 18) * 2.5 * math.exp(-(t - arrive) * 4);
      toast
        ..at = Offset.lerp(want, riding, follow)! + Offset(0, wobble)
        ..scale = scale
        ..angle = math.sin(t * 16) * 0.04 * math.exp(-(t - arrive) * 3) + (t > letGo ? 0.18 * ((t - letGo) / (release - letGo)).clamp(0.0, 1.0) : 0);
      // Eyes down on the text, scanning along the lines.
      final local = _toHeader(toast.at + Offset(_toastWidth * scale * 0.5, 20));
      if (local != null) {
        final scan = t > settled && t < 2.25 ? math.sin((t - settled) * 3.4) * 40 : 0.0;
        c.lookToward(_lookVector(local + Offset(scan, 0)), curious: false);
      }
      if (crossed(2.3)) c.react(LanternFace.delighted, 0.7);
    } else if (t < land) {
      // Thrown: an arc down onto its card, shrinking as it goes. With
      // nothing to land on, it is tucked away into the friend's glow.
      if (crossed(release)) {
        toast
          ..thrownFrom = toast.at
          ..landing = _targetRect(toast.target);
        c
          ..reachTarget = null
          ..reachTargetR = null
          ..jolt(0.5);
        Sfx.sound('throw');
      }
      final from = toast.thrownFrom ?? toast.at;
      final live = toast.landing == null ? null : _targetRect(toast.target);
      final to = live == null ? headG - Offset(_toastWidth * 0.15, 10) : Offset(live.center.dx - _toastWidth * 0.15, live.center.dy - 10);
      final u = Curves.easeInOutCubic.transform((t - release) / (land - release));
      final mid = Offset((from.dx + to.dx) / 2 + 40, math.min(from.dy, to.dy) - 50);
      toast
        ..at = Outing.bezier(from, mid, to, u)
        ..scale = toast.scale + (0.3 - toast.scale) * math.min(1.0, dt * 6 * (0.4 + u))
        ..angle = 0.5 * math.sin(u * math.pi) - 0.12 * (1 - u)
        ..opacity = 1 - Curves.easeIn.transform(((u - 0.7) / 0.3).clamp(0.0, 1.0));
      c.lookToward(_lookVector(_toHeader(toast.at) ?? Offset.zero), curious: false);
    } else if (t < end) {
      if (!toast.landed) {
        toast
          ..landed = true
          ..opacity = 0;
        final r = _targetRect(toast.target);
        if (toast.landing != null && r != null) {
          life.ping.value = (r, 0.0);
          _deliver(toast);
          if (_rowKeys.containsKey(toast.target)) life.highlight.value = toast.target;
          c.react(LanternFace.delighted, 0.8);
        } else {
          c
            ..react(LanternFace.content, 0.8)
            ..jolt(0.3);
        }
        c.lookToward(null);
      }
    } else {
      life.toast = null;
      if (life.highlight.value == toast.target) life.highlight.value = null;
      c.lookToward(null);
    }
  }

  // ---------------------------------------------------------------- search
  void onSearch(String q) {
    life.searchDebounce?.cancel();
    final c = character;
    if (c == null) return;
    c.wake();
    final field = globalRectOf(_searchKey);
    if (field != null) {
      final local = _toHeader(field.center);
      if (local != null) c.lookToward(_lookVector(local), curious: true);
    }
    life.searchDebounce = AppClock.timer(const Duration(milliseconds: 550), () => _findMatch(q));
  }

  Future<void> _findMatch(String q) async {
    final c = character;
    if (!mounted || c == null) return;
    c.lookToward(null);
    final query = q.trim().toLowerCase();
    if (query.length < 2) {
      life.highlight.value = null;
      return;
    }
    final names = [for (final w in _waits) w.$1, ...ParkScreenState._dining.map((d) => d.$1), ...ParkScreenState._shows.map((d) => d.$1)];
    final hit = names.where((n) => n.toLowerCase().contains(query)).firstOrNull;
    if (hit == null) {
      c.react(LanternFace.curious, 0.8);
      life.highlight.value = null;
      return;
    }
    final key = _rowKeys.putIfAbsent(hit, GlobalKey.new);
    // The row may be further down than the list has built yet: scroll down
    // until it exists, then bring it into view.
    for (var i = 0; i < 8 && key.currentContext == null && _scroll.hasClients; i++) {
      final max = _scroll.position.maxScrollExtent;
      if (_scroll.offset >= max) break;
      await _scroll.animateTo(math.min(max, _scroll.offset + 320), duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
    }
    final ctx = key.currentContext;
    if (ctx != null) await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 380), curve: Curves.easeInOutCubic, alignment: 0.5);
    if (!mounted) return;
    final row = globalRectOf(key);
    final from = _headerGlobal(camera.worldToScreen(c.handWorld, _headerSize) ?? Offset.zero);
    if (row == null) return;
    c
      ..react(LanternFace.delighted, 0.6)
      ..jolt(0.5);
    // A sparkle thrown from the friend's hand to the row.
    final start = AppClock.now;
    while (mounted) {
      final t = AppClock.now.difference(start).inMilliseconds / 650;
      if (t >= 1) break;
      life.sparkle.value = (from, row.centerLeft + const Offset(28, 0), t);
      await AppClock.delay(const Duration(milliseconds: 16));
    }
    life.sparkle.value = null;
    life.highlight.value = hit;
    Sfx.light();
    Sfx.sound('search_found');
    AppClock.delayed(const Duration(milliseconds: 2200), () {
      if (life.highlight.value == hit) life.highlight.value = null;
    });
  }

  // ---------------------------------------------------------------- resize
  void onLayout(Size size) {
    final last = life.lastSize;
    life.lastSize = size;
    if (last == null || character == null) return;
    if (((size.width - last.width).abs() > 24 || (size.height - last.height).abs() > 24) && life.tumbleCooldown <= 0) {
      life.tumbleCooldown = 1.6;
      character!.tumble();
    }
  }

  // ---------------------------------------------------------------- overlays
  List<Widget> lifeOverlays() {
    final out = <Widget>[];
    final toast = life.toast;
    if (toast != null) {
      out.add(Positioned(
        left: toast.at.dx,
        top: toast.at.dy,
        child: IgnorePointer(
          child: Opacity(
            opacity: toast.opacity.clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.centerLeft,
              transform: Matrix4.rotationZ(toast.angle)..scaleByDouble(toast.scale, toast.scale, 1, 1),
              child: Container(
                width: _toastWidth,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xF2182041),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x553A4A80)),
                  boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 18, offset: Offset(0, 8))],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_rounded, size: 18, color: Park.gold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(toast.title, style: const TextStyle(color: Park.ink, fontWeight: FontWeight.w800, fontSize: 13)),
                          Text(toast.body, style: const TextStyle(color: Park.inkMuted, fontSize: 12, height: 1.2)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));
    }
    // A glow around the card a notification just landed on.
    out.add(Positioned.fill(
      child: IgnorePointer(
        child: ValueListenableBuilder<(Rect, double)?>(
          valueListenable: life.ping,
          builder: (context, v, _) => v == null ? const SizedBox.shrink() : CustomPaint(painter: _PingPainter(v.$1, v.$2)),
        ),
      ),
    ));
    // The scrollbar, and the search sparkle.
    out.add(Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _ThumbPainter(_thumb, () => (_clock - _lastScrollAt))),
      ),
    ));
    out.add(Positioned.fill(
      child: IgnorePointer(
        child: ValueListenableBuilder<(Offset, Offset, double)?>(
          valueListenable: life.sparkle,
          builder: (context, v, _) => v == null ? const SizedBox.shrink() : CustomPaint(painter: _SparklePainter(v.$1, v.$2, v.$3)),
        ),
      ),
    ));
    return out;
  }
}

/// The scrollbar: a slim glowing pill at the list's right edge while it
/// scrolls (and while the friend rides it).
class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.thumb, this.since) : super(repaint: thumb);
  final ValueListenable<Rect?> thumb;
  final double Function() since;

  @override
  void paint(Canvas canvas, Size size) {
    final r = thumb.value;
    if (r == null) return;
    final a = (1 - (since() - 0.8) / 0.4).clamp(0.0, 1.0);
    if (a <= 0) return;
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(3));
    canvas.drawRRect(rr.inflate(3), Paint()..color = const Color(0xFF8FD3FF).withValues(alpha: 0.15 * a)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawRRect(rr, Paint()..color = const Color(0xFFB9D8FF).withValues(alpha: 0.75 * a));
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => true;
}

/// A sparkle flying on an arc from the friend to a search result.
class _SparklePainter extends CustomPainter {
  _SparklePainter(this.from, this.to, this.t);
  final Offset from, to;
  final double t;

  Offset _at(double u) {
    final mid = Offset((from.dx + to.dx) / 2 + 80, math.min(from.dy, to.dy) - 60);
    return Offset.lerp(Offset.lerp(from, mid, u)!, Offset.lerp(mid, to, u)!, u)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final e = Curves.easeInOutCubic.transform(t);
    for (var i = 0; i < 10; i++) {
      final u = (e - i * 0.03).clamp(0.0, 1.0);
      final k = 1 - i / 10;
      canvas.drawCircle(_at(u), 7 * k, Paint()..color = const Color(0xFFFFD58A).withValues(alpha: 0.5 * k)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }
    canvas.drawCircle(_at(e), 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SparklePainter old) => true;
}

/// Nova's hologram: wait times, projected in front of its visor.
class _HoloCard extends StatelessWidget {
  const _HoloCard({required this.waits});
  final List<(String, int)> waits;

  @override
  Widget build(BuildContext context) {
    final sorted = [...waits]..sort((a, b) => a.$2.compareTo(b.$2));
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x5539E6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xCC7DF3FF), width: 2),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: CustomPaint(
        painter: _Scanlines(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SHORTEST WAITS', style: TextStyle(color: Color(0xFFCFFBFF), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
            const SizedBox(height: 4),
            for (final (name, w) in sorted.take(4))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
                    Text('$w min', style: const TextStyle(color: Color(0xFF9FF6FF), fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Scanlines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x1AFFFFFF);
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(-12, y, size.width + 24, 1.2), p);
    }
  }

  @override
  bool shouldRepaint(_Scanlines old) => false;
}

/// A soft gold ring that swells off a card and fades.
class _PingPainter extends CustomPainter {
  _PingPainter(this.rect, this.t);
  final Rect rect;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final a = math.sin(math.min(1.0, t * 4) * math.pi / 2) * (1 - t);
    final rr = RRect.fromRectAndRadius(rect.inflate(2 + 10 * Curves.easeOut.transform(t)), const Radius.circular(20));
    canvas.drawRRect(rr, Paint()
      ..color = Park.gold.withValues(alpha: 0.35 * a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawRRect(rr, Paint()
      ..color = Park.gold.withValues(alpha: 0.8 * a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_PingPainter old) => old.t != t || old.rect != rect;
}
