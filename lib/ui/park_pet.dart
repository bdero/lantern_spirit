part of 'park_screen.dart';

/// A heart floating up off the friend while it is petted.
class _Heart {
  _Heart(this.at, this.velocity, this.size, this.spin, this.top, this.bottom, {this.life = 1.7});
  Offset at;
  Offset velocity;
  final double size;
  final double spin;
  final Color top;
  final Color bottom;
  final double life;
  double age = 0;
}

/// Petting: stroke the top of the friend's head (press and drag near the
/// crown) and it leans into your hand, the head dents under it, and hearts
/// float up. Keep going and it melts into a sleepy, swaying trance; stop and it
/// lingers there a while, then blinks back with a happy sigh.
class _Pet {
  bool stroking = false;
  Offset? last;
  double lastDx = 0;

  /// How blissful, 0 (not at all) to 1 (in a trance).
  double level = 0;
  bool tranced = false;
  double toNextHeart = 0;
  double side = 0;
  double clock = 0;
  final hearts = <_Heart>[];
  final rng = math.Random(23);
}

extension ParkPet on ParkScreenState {
  /// The top of the friend's head, in global coordinates, for tests that
  /// stroke it.
  @visibleForTesting
  Offset? crownForTest() {
    final c = character;
    final crown = c == null ? null : _crown(c);
    return crown == null ? null : _headerGlobal(crown.$1);
  }

  /// The top of the head on screen (header coordinates) and the head's
  /// radius in pixels.
  (Offset, double)? _crown(LanternCharacter c) {
    final s = c.root.globalTransform.getMaxScaleOnAxis() / c.friend.scale;
    final r = c.headRadius * s;
    final top = camera.worldToScreen(c.headCenter + vm.Vector3(0, r, 0), _headerSize);
    final mid = camera.worldToScreen(c.headCenter, _headerSize);
    if (top == null || mid == null) return null;
    return (top, (top - mid).distance);
  }

  /// Whether a press at [p] (header coordinates) lands on the crown, where
  /// a drag pets rather than squishes.
  bool _onCrown(LanternCharacter c, Offset p) {
    final crown = _crown(c);
    if (crown == null) return false;
    final (top, r) = crown;
    final d = p - top;
    return d.dx.abs() < r * 0.95 && d.dy > -r * 0.6 && d.dy < r * 0.5;
  }

  bool startPet(LanternCharacter c, Offset p) {
    if (!_onCrown(c, p)) return false;
    pet
      ..stroking = true
      ..last = p
      ..lastDx = 0;
    c
      ..shyTarget = 0
      ..canDoze = false;
    if (c.mood == LanternMood.sleepy && pet.level < 0.5) c.wake();
    return true;
  }

  void movePet(LanternCharacter c, Offset p) {
    final last = pet.last ?? p;
    pet.last = p;
    final d = p - last;
    final crown = _crown(c);
    if (crown == null) return;
    final (top, r) = crown;
    pet.side = ((p.dx - top.dx) / r).clamp(-1.0, 1.0);
    final stroke = d.distance;
    // Strokes add up to bliss; a slow, steady hand works best.
    final gentle = (1.2 - (stroke / 40)).clamp(0.4, 1.0);
    pet.level = math.min(1.0, pet.level + stroke / r * 0.05 * gentle);
    c.pet(_onHead(c, p), 0.13 + 0.1 * math.min(1.0, stroke / 10));
    // A soft brush each time the hand turns back.
    if (d.dx.abs() > 0.5) {
      if (pet.lastDx != 0 && d.dx.sign != pet.lastDx.sign) Sfx.sound('pet_stroke', gap: const Duration(milliseconds: 160));
      pet.lastDx = d.dx;
    }
    pet.toNextHeart -= stroke;
    if (pet.toNextHeart <= 0) {
      pet.toNextHeart = 90 + pet.rng.nextDouble() * 60;
      _addHeart(_headerGlobal(p) + Offset((pet.rng.nextDouble() - 0.5) * 20, -10));
    }
  }

  void endPet(LanternCharacter c) {
    if (!pet.stroking) return;
    pet
      ..stroking = false
      ..last = null;
    c.stopPet();
  }

  /// Where the hand at [p] (header coordinates) presses the head: where
  /// its ray meets the head, or the nearest point of the head's upper half.
  vm.Vector3 _onHead(LanternCharacter c, Offset p) {
    final ray = camera.screenPointToRay(p, _headerSize);
    final center = c.headCenter;
    final r = c.headRadius * (c.root.globalTransform.getMaxScaleOnAxis() / c.friend.scale);
    final d = ray.direction.normalized();
    final along = (center - ray.origin).dot(d);
    final nearest = ray.origin + d * along;
    final miss = (nearest - center).length;
    var dir = miss < r ? (nearest - d * math.sqrt(r * r - miss * miss)) - center : nearest - center;
    dir.normalize();
    if (dir.y < 0.3) {
      dir = vm.Vector3(dir.x, 0.3, dir.z)..normalize();
    }
    return center + dir * r;
  }

  // A few shades, so no two hearts look stamped from one mold.
  static const _heartColors = [
    (Color(0xFFFFB3CF), Color(0xFFFF4F8B)),
    (Color(0xFFFFC4D6), Color(0xFFFF6F9A)),
    (Color(0xFFFFD0C2), Color(0xFFFF7A86)),
    (Color(0xFFF2C6FF), Color(0xFFC77DFF)),
    (Color(0xFFFFA8BE), Color(0xFFE83F79)),
  ];

  void _addHeart(Offset at) {
    final rng = pet.rng;
    void one(Offset at, double size) {
      final (top, bottom) = _heartColors[rng.nextInt(_heartColors.length)];
      pet.hearts.add(_Heart(
        at,
        Offset((rng.nextDouble() - 0.5) * 36, -40 - rng.nextDouble() * 30 - size),
        size,
        (rng.nextDouble() - 0.5) * 0.8,
        top,
        bottom,
        life: 1.4 + size / 28,
      ));
    }

    // Mostly small, now and then a big one, sometimes with a tiny friend.
    final size = 9 + 22 * math.pow(rng.nextDouble(), 1.8).toDouble();
    one(at, size);
    if (rng.nextDouble() < 0.3) one(at + Offset((rng.nextBool() ? 1 : -1) * (size * 0.9 + 6), size * 0.3), 6 + rng.nextDouble() * 4);
    Sfx.sound('heart', pitch: [1.0, 1.122, 1.26, 1.498][rng.nextInt(4)], gap: const Duration(milliseconds: 140));
  }

  void tickPet(LanternCharacter c, double dt) {
    pet.clock += dt;
    // Bliss fades once the hand lifts, slowly from a trance.
    if (!pet.stroking) pet.level = math.max(0.0, pet.level - dt * (pet.level > 0.75 ? 0.05 : 0.16));
    final p = pet.level;

    if (p > 0.01 || pet.stroking) {
      c.shyTarget = 0;
      final trance = ((p - 0.7) / 0.3).clamp(0.0, 1.0);
      // Leaning into the hand, then a slow, dreamy sway.
      c.petLean = (pet.stroking ? -pet.side * 0.12 * (1 - trance) : 0) + math.sin(pet.clock * 1.15) * 0.09 * trance;
      c.glowScale = 1 + 0.4 * p;
      if (p > 0.12) {
        // Eyes shut and smiling; in a trance, drowsy, with a slow blink of
        // the happy face now and then.
        final drowsy = trance > 0.3 && (pet.clock % 3.2) < 2.5;
        c.react(drowsy ? LanternFace.sleepy : LanternFace.content, 0.2);
        if (trance > 0) c.lookToward(vm.Vector2(0, -0.25 * trance), curious: false);
      }
      if (trance > 0.95 && !pet.tranced) {
        pet.tranced = true;
        Sfx.sound('yawn', volume: 0.8);
      }
      if (pet.tranced && p < 0.5) {
        // Back from the trance: a blink and a happy little sigh.
        pet.tranced = false;
        c
          ..react(LanternFace.delighted, 0.8)
          ..jolt(0.3)
          ..lookToward(null);
        Sfx.sound('chirp_happy');
      }
      // Hearts drift up on their own while it is blissful.
      if ((p > 0.55 && !pet.stroking) || trance > 0) {
        pet.toNextHeart -= dt * 60 * (0.4 + trance);
        if (pet.toNextHeart <= 0) {
          pet.toNextHeart = 70 + pet.rng.nextDouble() * 50;
          final head = _headGlobal();
          if (head != null) _addHeart(head + Offset((pet.rng.nextDouble() - 0.5) * 70, -40));
        }
      }
    } else {
      c.petLean = 0;
    }
    if (p < 0.01 && !pet.stroking && c.glowScale != 1 && sp.lights <= 0) c.glowScale = 1;
    if (p < 0.01 && !pet.stroking) c.canDoze = !errandActive;

    // Hearts rise, sway, and fade.
    for (final h in pet.hearts) {
      h.age += dt;
      h.velocity = Offset(h.velocity.dx * math.exp(-dt * 1.5) + math.sin(h.age * 4 + h.spin * 9) * 14 * dt * 10, h.velocity.dy * math.exp(-dt * 0.6));
      h.at += h.velocity * dt;
    }
    pet.hearts.removeWhere((h) => h.age >= h.life);
    if (pet.hearts.isNotEmpty || p > 0) _refresh();
  }

  Widget _heartsLayer() {
    if (pet.hearts.isEmpty) return const SizedBox.shrink();
    return Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _HeartsPainter(List.of(pet.hearts)))));
  }
}

class _HeartsPainter extends CustomPainter {
  _HeartsPainter(this.hearts);
  final List<_Heart> hearts;

  static Path _heart(double s) {
    // A heart [s] tall, centered on the origin.
    final w = s * 1.1;
    return Path()
      ..moveTo(0, s * 0.42)
      ..cubicTo(-w * 0.95, -s * 0.05, -w * 0.45, -s * 0.72, 0, -s * 0.28)
      ..cubicTo(w * 0.45, -s * 0.72, w * 0.95, -s * 0.05, 0, s * 0.42)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final h in hearts) {
      final u = h.age / h.life;
      // Pops in with a little overshoot, fades out toward the end.
      final pop = u < 0.12 ? Curves.elasticOut.transform(u / 0.12) : 1.0;
      final fade = u < 0.6 ? 1.0 : 1 - (u - 0.6) / 0.4;
      final s = h.size * pop * (1 + 0.15 * u);
      canvas.save();
      canvas.translate(h.at.dx, h.at.dy);
      canvas.rotate(h.spin + math.sin(h.age * 3 + h.spin * 5) * 0.18);
      final path = _heart(s);
      canvas.drawPath(path, Paint()..color = h.bottom.withValues(alpha: 0.4 * fade)..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.45));
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [h.top.withValues(alpha: fade), h.bottom.withValues(alpha: fade)],
          ).createShader(Rect.fromCenter(center: Offset.zero, width: s * 2.2, height: s)),
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(-s * 0.32, -s * 0.24), width: s * 0.28, height: s * 0.18),
        Paint()..color = Colors.white.withValues(alpha: 0.75 * fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_HeartsPainter old) => true;
}
