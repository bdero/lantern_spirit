part of 'park_screen.dart';

/// A notification your friend eats like a chocolate bar: caught in both
/// hands and read, then turned three-quarters to the side, both hands on
/// the bar's left end and its right end at the mouth, and eaten right to
/// left in three big bites (each cut out of the slab, crumbs flying), the
/// last of it gulped down, and a happy belly rub.
extension ParkSnack on ParkScreenState {
  // When each beat starts, in seconds from the catch.
  static const _arrive = 0.6, _turn = 1.2, _firstBite = 1.75, _biteEvery = 0.8, _gulp = 3.95, _swallowed = 4.3, _rubEnd = 5.9, _end = 6.15;

  /// How far it turns to the screen's left to eat, so the bites read in
  /// three-quarter view.
  static const _eatYaw = 0.6;

  /// How big each bite is (the bar's own units).
  static const _biteSize = 0.36;

  @visibleForTesting
  Future<void> eatNotification() => _startSnack('Treats', 'Warm glow churros at Starlight Treats');

  Future<void> _startSnack(String title, String body) async {
    final c = character;
    if (c == null || life.snack != null || life.snackLoading) return;
    life.snackLoading = true;
    final snack = await NotificationSnack.create(title, body, width: 1.4);
    life.snackLoading = false;
    if (!mounted || character != c) return;
    c
      ..wake()
      ..canDoze = false;
    life
      ..snack = snack
      ..snackT = 0;
    _placeSnack(snack, _snackEnter(c), roll: -0.5, yaw: 0.6);
    scene.add(snack.node);
    Sfx.light();
    Sfx.sound('notify');
  }

  // ------------------------------------------------------------- places
  double _headSize(LanternCharacter c) => c.headRadius * (c.root.globalTransform.getMaxScaleOnAxis() / c.friend.scale);

  vm.Vector3 _snackEnter(LanternCharacter c) => c.headCenter + vm.Vector3(4.2, 0.5, 0.9 * kFaceZ);

  vm.Vector3 _snackCatch(LanternCharacter c) => c.headCenter + vm.Vector3(1.35, -0.25, 0.95 * kFaceZ);

  vm.Vector3 _snackHold(LanternCharacter c) {
    final r = _headSize(c);
    return c.headCenter + vm.Vector3(0, -r * 1.38, r * 1.2 * kFaceZ);
  }

  /// Held, it is turned a touch and tipped back, so its thickness shows.
  static const _heldYaw = 0.24, _heldPitch = -0.2;

  void _placeSnack(NotificationSnack s, vm.Vector3 at, {double roll = 0, double yaw = 0, double pitch = 0, double scale = 1}) {
    s.node.localTransform = vm.Matrix4.compose(
      at,
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw) *
          vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), pitch) *
          vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), roll),
      vm.Vector3.all(scale),
    );
  }

  vm.Vector3 _snackWorld(NotificationSnack s, double x, double y) => s.node.localTransform.transformed3(vm.Vector3(x, y, 0));

  /// The read-it pose: held flat under the chin, turned a touch.
  (vm.Vector3, vm.Quaternion) _readPose(vm.Vector3 at, double roll) => (
        at,
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _heldYaw) *
            vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), _heldPitch) *
            vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), roll),
      );

  /// The eating pose: from the hands at the chest (the bar's left end) up to
  /// the mouth (its right end, [feed] along the bar), text toward the camera.
  /// [push] 1 has the right end in the mouth; 0 is pulled back to chew.
  (vm.Vector3, vm.Quaternion) _eatPose(LanternCharacter c, NotificationSnack s, double feed, double push) {
    final r = _headSize(c);
    final mouth = c.mouthWorld + c.facing * (0.05 * r);
    final hands = c.bellyWorld + c.facing * (r * 1.45) + vm.Vector3(0, r * 0.3, 0);
    final along = (mouth - hands).normalized();
    // Face the camera as much as the bar's direction allows.
    final toCamera = vm.Vector3(0, 0, 1);
    final z = (toCamera - along * along.dot(toCamera))..normalize();
    final y = z.cross(along)..normalize();
    final basis = vm.Matrix3.columns(along, y, z);
    final q = vm.Quaternion.fromRotation(basis);
    final center = mouth - along * (feed + (1 - push) * 0.22 * r);
    return (center, q);
  }

  void _pose(NotificationSnack s, (vm.Vector3, vm.Quaternion) a, (vm.Vector3, vm.Quaternion) b, double u, {double scale = 1}) {
    final qa = a.$2, qb = b.$2;
    // Blend the turns the short way round.
    final sign = (qa.x * qb.x + qa.y * qb.y + qa.z * qb.z + qa.w * qb.w) < 0 ? -1.0 : 1.0;
    final q = vm.Quaternion(
      qa.x * (1 - u) + qb.x * u * sign,
      qa.y * (1 - u) + qb.y * u * sign,
      qa.z * (1 - u) + qb.z * u * sign,
      qa.w * (1 - u) + qb.w * u * sign,
    )..normalize();
    s.node.localTransform = vm.Matrix4.compose(a.$1 + (b.$1 - a.$1) * u, q, vm.Vector3.all(scale));
  }

  // ------------------------------------------------------------- frame
  void _tickSnack(LanternCharacter c, double dt, Vfx? fx) {
    final s = life.snack;
    if (s == null) return;
    final before = life.snackT;
    life.snackT += dt;
    final t = life.snackT;
    bool crossed(double at) => before < at && t >= at;
    double span(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
    final hold = _snackHold(c);

    if (t < _arrive) {
      // Tumbling in from the right, settling flat as both hands meet it.
      final u = Curves.easeOutCubic.transform(t / _arrive);
      final at = _snackEnter(c) + (_snackCatch(c) - _snackEnter(c)) * u;
      _placeSnack(s, at, roll: -0.5 * (1 - u) + math.sin(t * 9) * 0.04 * (1 - u), yaw: 0.6 * (1 - u) + _heldYaw * u, pitch: _heldPitch * u);
      c.lookAtWorld(at);
      if (t > 0.25) _gripSnack(c, s);
    } else if (t < _gulp) {
      if (crossed(_arrive)) {
        c.jolt(0.35);
        Sfx.light();
        Sfx.sound('catch');
      }
      // Pulled in close and read; then a turn to the side, and the bar is
      // fed in from its right end, bite by bite.
      final read = _snackCatch(c) + (hold - _snackCatch(c)) * Curves.easeInOutCubic.transform(span(_arrive, _arrive + 0.45));
      final roll = math.sin(t * 14) * 0.05 * math.exp(-(t - _arrive) * 4);
      final turn = Curves.easeInOutCubic.transform(span(_turn, _firstBite));
      c.place(vm.Vector3.zero(), _eatYaw * turn);
      final right = s.span(0)?.$2 ?? s.nearestSolid(vm.Vector2(s.width, 0)).x;
      // Where the bar's end is fed to, easing forward as bites shorten it
      // (so a bite never makes it jump).
      life.snackFeed += (right - 0.03 - life.snackFeed) * math.min(1.0, dt * 5);
      var push = 0.0;
      for (var i = 0; i < 3; i++) {
        final start = _firstBite + i * _biteEvery;
        final chomp = start + 0.3;
        if (t >= start && t < chomp) push = Curves.easeIn.transform(span(start, chomp));
        if (t >= chomp && t < chomp + 0.28) push = 1 - Curves.easeOut.transform(span(chomp, chomp + 0.28));
        if (crossed(start)) c.react(LanternFace.wow, 0.3);
        if (crossed(chomp)) {
          final at = vm.Vector2(right - 0.02, 0);
          s.bite(at, _biteSize);
          _crumbs(_snackWorld(s, at.x, at.y), fx, i);
          c
            ..react(LanternFace.poked, 0.3)
            ..jolt(0.65);
          Sfx.medium();
          Sfx.sound('bite_${i + 1}');
        }
        if (t > chomp && t < chomp + 0.5) {
          // Chewing.
          final k = t - chomp;
          final chew = ((k - 0.2) / 0.12).floor();
          if (k > 0.2 && ((before - chomp - 0.2) / 0.12).floor() != chew) {
            c
              ..react(chew.isEven ? LanternFace.content : LanternFace.poked, 0.12)
              ..jolt(0.12);
          }
        }
      }
      if (crossed(_turn)) {
        life.snackFeed = right - 0.03;
        Sfx.sound('chirp_happy', volume: 0.7);
      }
      _pose(s, _readPose(read, roll), _eatPose(c, s, life.snackFeed, push), turn);
      if (turn < 0.5) {
        _gripSnack(c, s);
      } else {
        // Both hands on the bar's left end, one above, one below.
        final left = s.span(0)?.$1 ?? -s.width / 2;
        final h = s.height / 2;
        c
          ..reachTarget = _snackWorld(s, left + 0.08, -h - 0.03)
          ..reachTargetR = _snackWorld(s, left + 0.08, h + 0.03);
      }
      c.lookAtWorld(turn < 0.5 ? read : _snackWorld(s, right, 0));
    } else if (t < _swallowed) {
      // The last of it, popped in whole.
      final u = Curves.easeInCubic.transform(span(_gulp, _swallowed));
      final rest = s.nearestSolid(vm.Vector2(s.width, 0));
      final pose = _eatPose(c, s, rest.x, 1);
      _pose(s, pose, (c.mouthWorld, pose.$2), u, scale: 1 - 0.85 * u);
      c
        ..reachTarget = null
        ..reachTargetR = null
        ..lookAtWorld(c.mouthWorld);
      if (crossed(_gulp)) c.react(LanternFace.wow, 0.35);
    } else if (t < _end) {
      if (crossed(_swallowed)) {
        s.node.detach();
        c
          ..react(LanternFace.surprised, 0.3)
          ..jolt(0.9)
          ..lookAtWorld(null);
        Sfx.sound('gulp');
        AppClock.delayed(const Duration(milliseconds: 500), () {
          if (mounted) lanternPulse();
        });
        Sfx.sound('belly_rub', delay: const Duration(milliseconds: 420));
        fx
          ?..flare(c.bellyWorld, size: 0.7, color: vm.Vector3(1.6, 1.2, 0.5), life: 0.45)
          ..ring(c.bellyWorld, radius: 0.8, color: vm.Vector3(1.2, 0.9, 0.4), life: 0.4);
        Sfx.medium();
      }
      // Turning back to face us.
      c.place(vm.Vector3.zero(), _eatYaw * (1 - Curves.easeInOutCubic.transform(span(_swallowed, _swallowed + 0.5))));
      // Full: both hands rub the tummy in circles, eyes closed and smiling.
      if (t < _rubEnd) {
        final belly = c.bellyWorld;
        final w = c.bellyRadius * 0.55;
        final a = (t - _swallowed) * 6.5;
        final k = Curves.easeOut.transform(span(_swallowed + 0.15, _swallowed + 0.5));
        c
          ..reachTarget = belly + vm.Vector3(w * 0.7 + math.cos(a) * w * 0.45, math.sin(a) * w * 0.4, 0) * k
          ..reachTargetR = belly + vm.Vector3(-w * 0.7 + math.cos(a + math.pi) * w * 0.45, math.sin(a + math.pi) * w * 0.4, 0) * k;
        if (t > _swallowed + 0.3 && ((before - _swallowed) / 0.5).floor() != ((t - _swallowed) / 0.5).floor()) {
          c.react(LanternFace.content, 0.55);
          fx?.burst(belly + vm.Vector3(0, w, 0), count: 2, speed: 0.4, color: vm.Vector3(2.0, 1.1, 1.3), size: 0.06, life: 0.9, gravity: -0.8, shape: VfxShape.flare);
        }
        // A tiny, polite burp.
        if (crossed(5.4)) {
          Sfx.sound('burp');
          c
            ..react(LanternFace.surprised, 0.25)
            ..jolt(0.4);
          fx?.puffs(c.mouthWorld + vm.Vector3(0, 0, 0.1 * kFaceZ), count: 3, size: 0.08, speed: 0.4, color: vm.Vector3(0.6, 0.5, 0.35), life: 0.6);
        }
        if (crossed(5.65)) c.react(LanternFace.delighted, 0.6);
      } else if (crossed(_rubEnd)) {
        c
          ..reachTarget = null
          ..reachTargetR = null
          ..react(LanternFace.delighted, 0.6);
      }
    } else {
      s.node.detach();
      life.snack = null;
      life.snackT = -1;
      c
        ..place(vm.Vector3.zero(), 0)
        ..reachTarget = null
        ..reachTargetR = null
        ..canDoze = true
        ..lookAtWorld(null);
    }
  }

  /// Both hands on the slab's short edges, a little below the middle, moving
  /// in as the ends get eaten.
  void _gripSnack(LanternCharacter c, NotificationSnack s) {
    const y = -0.08;
    final row = s.span(y);
    final lo = row?.$1 ?? s.nearestSolid(vm.Vector2(-s.width, y)).x;
    final hi = row?.$2 ?? s.nearestSolid(vm.Vector2(s.width, y)).x;
    // The left hand is the one on the screen's right.
    c
      ..reachTarget = _snackWorld(s, hi + 0.04, y)
      ..reachTargetR = _snackWorld(s, lo - 0.04, y);
  }

  /// Crumbs off a bite: flecks of the panel, sparks of the light inside it,
  /// and a soft puff.
  void _crumbs(vm.Vector3 at, Vfx? fx, int i) {
    if (fx == null) return;
    fx
      ..burst(at, count: 16, speed: 2.0, color: vm.Vector3(0.55, 0.62, 1.25), color2: vm.Vector3(0.9, 0.95, 1.6), size: 0.04, life: 0.75, gravity: 5.5, drag: 1.2, bias: vm.Vector3(0, 0.6, 0.4 * kFaceZ))
      ..burst(at, count: 12, speed: 2.6, color: vm.Vector3(2.2, 1.6, 0.6), size: 0.05, life: 0.55, gravity: 3, shape: VfxShape.flare)
      ..ring(at, radius: 0.5 + 0.1 * i, color: vm.Vector3(1.4, 1.1, 0.5), life: 0.25)
      ..puffs(at, count: 3, size: 0.12, speed: 0.6, color: vm.Vector3(0.35, 0.32, 0.5), life: 0.5);
  }
}
