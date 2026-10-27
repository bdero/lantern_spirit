part of 'park_screen.dart';

extension ParkClips on ParkScreenState {
  Touches get _touch => Touches.instance;

  /// The center (or another point) of the widget behind [key], globally.
  Offset? _at(GlobalKey key, [Alignment align = Alignment.center]) {
    final r = globalRectOf(key);
    return r == null ? null : align.withinRect(r);
  }

  Offset _headerGlobal(Offset local) {
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.localToGlobal(local) ?? local;
  }

  Offset _project(vm.Vector3 world) => _headerGlobal(camera.worldToScreen(world, _headerSize) ?? Offset.zero);

  Future<void> _pause(int ms) => AppClock.delay(Duration(milliseconds: ms));

  /// Scrolls the list so [key]'s widget is fully on screen.
  Future<void> _reveal(GlobalKey key) async {
    // Cards further down are not built until the list reaches them.
    for (var i = 0; i < 10 && key.currentContext == null && _scroll.hasClients; i++) {
      final max = _scroll.position.maxScrollExtent;
      if (_scroll.offset >= max) break;
      await _scroll.animateTo(math.min(max, _scroll.offset + 360), duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 450), curve: Curves.easeInOutCubic, alignment: 0.4);
  }

  /// Glides the scripted finger to [at] and taps.
  Future<void> _tapAt(Offset? at, {int travel = 600}) async {
    if (at == null) return;
    await _hover(at, ms: travel);
    await _touch.tap(at);
  }

  /// Glides the hovering finger to [at] without pressing.
  Future<void> _hover(Offset at, {int ms = 600}) async {
    if (_touch.hover == null) {
      final size = MediaQuery.of(context).size;
      _touch.hover = Offset(size.width * 0.75, size.height * 0.92);
    }
    await _touch.glide(at, ms: ms);
  }

  /// Plays [clip]. Returns when the performance is done.
  Future<void> playClip(SocialClip clip) async {
    if (_clipRunning) return;
    _clipRunning = true;
    setPanelOpen(false);
    await _pause(420);
    try {
      switch (clip) {
        case SocialClip.fetch:
          await _clipFetch();
        case SocialClip.taffy:
          await _clipTaffy();
        case SocialClip.room:
          await _clipRoom();
        case SocialClip.swap:
          await _clipSwap();
        case SocialClip.moon:
          await _clipGame(lift: true);
        case SocialClip.constellation:
          await _clipGame(lift: false);
        case SocialClip.fireworks:
          await _clipFireworks();
        case SocialClip.map:
          await _clipMap();
        case SocialClip.shy:
          await _clipShy();
        case SocialClip.sneeze:
          await _clipSneeze();
        case SocialClip.refresh:
          await _clipRefresh();
        case SocialClip.tricks:
          await _clipTricks();
        case SocialClip.booth:
          await _clipBooth();
      }
    } finally {
      _touch
        ..lift()
        ..hover = null;
      _clipRunning = false;
    }
  }

  Future<void> _ready() async {
    final c = character;
    if (c == null) return;
    if (c.mood == LanternMood.sleepy) {
      final head = _project(c.headCenter);
      await _tapAt(head, travel: 700);
      c.wake();
      await _pause(900);
    }
  }

  // ---------------------------------------------------------------- clips
  Future<void> _clipFetch() async {
    await _scroll.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeInOutCubic);
    if (collected) _resetReward();
    await _ready();
    await _pause(300);
    await _tapAt(_at(_sendKey), travel: 800);
    _sendLumi();
    while (errandActive) {
      await _pause(50);
    }
    await _pause(1600);
  }

  Future<void> _clipTaffy() async {
    await _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
    await _ready();
    final c = character!;
    // The middle of the face, well clear of the crown (where a drag pets).
    final start = camera.worldToScreen(c.headCenter, _headerSize)!;
    final startG = _headerGlobal(start);
    await _hover(startG, ms: 700);
    // Press in, hold a beat, then pull up and out like taffy.
    _touch.press(startG);
    _dragStart(start);
    await _pause(350);
    Future<void> pullTo(Offset local, int ms) => _touch.glide(_headerGlobal(local), ms: ms, each: (g) {
      final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) _dragMove(box.globalToLocal(g));
    });
    await pullTo(start + const Offset(0, 12), 260);
    await pullTo(start + const Offset(110, -150), 900);
    await pullTo(start + const Offset(-90, -170), 650);
    await pullTo(start + const Offset(140, -120), 550);
    await _pause(250);
    _touch.lift();
    _dragEnd();
    await _pause(1500);
    // Then a cheek, pulled sideways and let go.
    final cheek = camera.worldToScreen(c.headCenter, _headerSize)! + Offset(-c.headRadius * 60, 6);
    await _hover(_headerGlobal(cheek), ms: 500);
    _touch.press(_headerGlobal(cheek));
    _dragStart(cheek);
    await _pause(200);
    await pullTo(cheek + const Offset(-150, 30), 700);
    await _pause(200);
    _touch.lift();
    _dragEnd();
    await _pause(1800);
  }

  Future<void> _clipRoom() async {
    await _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
    await _ready();
    await _tapAt(_at(_roomKey), travel: 800);
    await _openRoom();
    await _pause(1700);
    final room = _roomScene;
    if (room == null) return;
    // Try on a hat or two from the shelf.
    for (var i = 0; i < math.min(2, room.hatCount); i++) {
      await _tapAt(_project(room.hatAt(i)), travel: 650);
      _roomAction(room.hatId(i));
      await _pause(1300);
    }
    // Throw a party from the board.
    await _tapAt(_project(room.partyAt), travel: 700);
    _party();
    await _pause(2600);
    // And back out.
    final back = MediaQuery.of(context).padding.top + 32;
    await _tapAt(Offset(32, back), travel: 650);
    _closeRoom();
    await _pause(1500);
  }

  Future<void> _clipSwap() async {
    await _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
    await _ready();
    await _tapAt(_at(_friendsKey), travel: 800);
    _openWardrobe(tab: 3);
    await _pause(700);
    final profile = ProfileScope.read(context);
    final order = [for (final f in Friends.all) f.id];
    final start = order.indexOf(profile.friend);
    for (var k = 1; k <= order.length; k++) {
      final id = order[(start + k) % order.length];
      final tile = WardrobeScreen.friendTiles[id];
      if (tile == null) continue;
      await _tapAt(_at(tile, const Alignment(0, -0.2)), travel: 550);
      profile.chooseFriend(id);
      await _pause(300);
      while (swapping) {
        await _pause(40);
      }
      await _pause(1500);
    }
    // Close the sheet by tapping the header.
    await _tapAt(Offset(MediaQuery.of(context).size.width * 0.5, _headerHeight * 0.45), travel: 600);
    if (!mounted) return;
    Navigator.of(context).maybePop();
    await _pause(800);
  }

  Future<void> _clipGame({required bool lift}) async {
    await _reveal(lift ? _liftKey : _catchKey);
    await _pause(300);
    await _tapAt(_at(lift ? _liftKey : _catchKey), travel: 800);
    _openGame(lift ? _liftKey : _catchKey, lift ? SkyLift.new : StarCatch.new);
    GameScreenState? g() => _gameKey.currentState;
    while (g() == null || g()!.phase != GamePhase.playing) {
      await _pause(50);
      if (!mounted) return;
    }
    final size = MediaQuery.of(context).size;
    Offset finger(double steer) => Offset(size.width * (0.5 + steer * 0.42), size.height * 0.9);
    var holding = false;
    var steer = 0.0;
    while (g() != null && g()!.phase == GamePhase.playing) {
      final game = g()!.game;
      final target = lift ? (game as SkyLift).botSteer() : (game as StarCatch).botSteer();
      steer += (target - steer) * 0.2;
      game.steer(steer);
      if (lift) {
        final sky = game as SkyLift;
        final m = sky.meter;
        if (holding && m < 0.08) holding = false;
        if (!holding && m > 0.6) holding = true;
        sky.thrustForTest = holding;
        if (holding && !_holdingFinger) {
          _touch.press(finger(steer));
          _holdingFinger = true;
        } else if (!holding && _holdingFinger) {
          _touch.lift();
          _holdingFinger = false;
        }
        if (holding) _touch.move(finger(steer));
      } else {
        if (!_holdingFinger) {
          _touch.press(finger(steer));
          _holdingFinger = true;
        }
        _touch.move(finger(steer));
      }
      await _pause(16);
    }
    _touch.lift();
    _holdingFinger = false;
    await _pause(2500);
  }

  Future<void> _clipFireworks() async {
    await _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
    await _ready();
    await _tapAt(_at(_watchKey), travel: 800);
    // Start just before the first break so the clip opens on the action.
    _openShow(startAt: 3.2);
  }

  Future<void> _clipShy() async {
    await _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
    await _ready();
    final head = _project(character!.headCenter);
    // A pointer that comes to rest on the face, and stays.
    await _hover(head, ms: 900);
    _mouse = head;
    await _pause(4200);
    await _hover(head + const Offset(150, 140), ms: 600);
    _mouse = null;
    await _pause(1200);
  }

  Future<void> _clipSneeze() async {
    await _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
    await _ready();
    final p = ProfileScope.read(context);
    if (p.hat == null) {
      p.wear(hat: 'beanie');
      await _pause(900);
    }
    startButterfly();
    await _pause(7200);
  }

  Future<void> _clipRefresh() async {
    await _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
    await _ready();
    final list = globalRectOf(_listKey);
    if (list == null) return;
    final start = list.topCenter + const Offset(0, 90);
    await _hover(start, ms: 700);
    _touch.press(start);
    // Drag down past the top, as a finger would: the list follows with a
    // rubber band, and so does the friend. (Jumping the list instead lets it
    // spring back between steps, and it judders.)
    final drag = _scroll.position.drag(DragStartDetails(globalPosition: start), () {});
    var last = 0.0;
    for (var i = 1; i <= 30; i++) {
      final y = 260.0 * Curves.easeOut.transform(i / 30);
      drag.update(DragUpdateDetails(globalPosition: start + Offset(0, y), delta: Offset(0, y - last), primaryDelta: y - last));
      last = y;
      _touch.move(start + Offset(0, y));
      await _pause(16);
    }
    await _pause(500);
    _touch.lift();
    drag.end(DragEndDetails(primaryVelocity: 0));
    await _pause(2300);
  }

  Future<void> _clipTricks() async {
    await _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
    await _ready();
    final profile = ProfileScope.read(context);
    final order = [for (final f in Friends.all) f.id];
    final start = order.indexOf(profile.friend);
    for (var k = 0; k < order.length; k++) {
      final id = order[(start + k) % order.length];
      if (character?.friend.id != id) {
        profile.chooseFriend(id);
        await _pause(300);
        while (swapping) {
          await _pause(40);
        }
        await _pause(1600);
      }
      await _tapAt(_at(_trickKey), travel: 600);
      await trick();
      await _pause(id == 'lumi' ? 4600 : (id == 'nova' ? 6300 : 4400));
    }
  }

  Future<void> _clipBooth() async {
    await _reveal(_boothKey);
    await _pause(300);
    await _tapAt(_at(_boothKey), travel: 800);
    final key = GlobalKey<PhotoBoothScreenState>();
    final rect = globalRectOf(_boothKey);
    if (rect == null) return;
    Navigator.of(context).push(CardRevealRoute<void>(from: rect, fromKey: _boothKey, builder: (_) => PhotoBoothScreen(key: key)));
    while (key.currentState?.lumi == null) {
      await _pause(50);
      if (!mounted) return;
    }
    await _pause(1600);
    final booth = key.currentState!;
    for (final (label, ms) in [('Moon', 1600), ('Cheer', 900), ('Fireworks', 1800)]) {
      final at = _textCenter(label);
      if (at != null) await _tapAt(at, travel: 500);
      switch (label) {
        case 'Moon':
          await booth.pickBackdrop(Backdrop.moon);
        case 'Fireworks':
          await booth.pickBackdrop(Backdrop.fireworks);
        case 'Cheer':
          booth.pickPose(Pose.cheer);
      }
      await _pause(ms);
    }
    final size = MediaQuery.of(context).size;
    await _tapAt(Offset(size.width / 2, size.height - MediaQuery.of(context).padding.bottom - 53), travel: 600);
    await booth.shoot();
    await _pause(2600);
  }

  /// Where a piece of text is on screen (a chip in the booth).
  Offset? _textCenter(String label) {
    Offset? found;
    void visit(Element e) {
      if (found != null) return;
      final w = e.widget;
      if (w is Text && w.data == label) {
        final box = e.renderObject as RenderBox?;
        if (box != null && box.hasSize) found = box.localToGlobal(box.size.center(Offset.zero));
        return;
      }
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found;
  }

  Future<void> _clipMap() async {
    await _reveal(_mapKey);
    await _pause(300);
    await _tapAt(_at(_mapKey, const Alignment(0.6, 0.6)), travel: 800);
    final mapKey = GlobalKey<ParkMapScreenState>();
    final rect = globalRectOf(_mapKey);
    if (rect == null) return;
    Navigator.of(context).push(CardRevealRoute<void>(from: rect, fromKey: _mapKey, builder: (_) => ParkMapScreen(key: mapKey)));
    while (mapKey.currentState?.lumi == null) {
      await _pause(50);
      if (!mounted) return;
    }
    await _pause(2200);
    final map = mapKey.currentState!;
    final size = MediaQuery.of(context).size;
    for (final r in [map.pick, map.rides.firstWhere((r) => r.name == 'Moon Drop'), map.rides.firstWhere((r) => r.name == 'Tidal Twist')]) {
      final at = map.signOnScreen(r, size);
      if (at == null) continue;
      // The Go button sits on the right of each card.
      await _tapAt(at + const Offset(52, 0), travel: 700);
      map.goTo(r);
      await _pause(700);
      while (map.travelling) {
        await _pause(60);
      }
      await _pause(1800);
    }
  }
}
