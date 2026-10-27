import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Small glowing orbs around the character: a few that drift ambiently, plus
/// short-lived bursts (a celebration ring, flecks off a poke, stars circling
/// a dizzy head). All are plain sphere nodes sharing two ember materials.
class SparkField {
  SparkField({
    required this.parent,
    required Material ambientMaterial,
    required Material goldMaterial,
    int ambientCount = 14,
  }) {
    final geometry = SphereGeometry(radius: 1, segments: 12, rings: 8);
    for (var i = 0; i < ambientCount; i++) {
      // Hidden until the first update places it (a unit sphere otherwise).
      final node = Node(name: 'Spark$i', mesh: Mesh(geometry, ambientMaterial))
        ..raycastable = false
        ..visible = false;
      parent.add(node);
      _ambient.add(
        _Ambient(
          node: node,
          radius: 1.0 + _rng.nextDouble() * 0.7,
          height: 0.7 + _rng.nextDouble() * 1.9,
          phase: _rng.nextDouble() * math.pi * 2,
          speed: 0.08 + _rng.nextDouble() * 0.16,
          size: 0.012 + _rng.nextDouble() * 0.02,
          twinkle: 1.5 + _rng.nextDouble() * 2.5,
        ),
      );
    }
    for (var i = 0; i < 5; i++) {
      final node = Node(name: 'Star$i', mesh: Mesh(geometry, goldMaterial))
        ..raycastable = false
        ..visible = false;
      parent.add(node);
      _stars.add(node);
    }
    for (var i = 0; i < 48; i++) {
      final node = Node(name: 'Burst$i', mesh: Mesh(geometry, goldMaterial))
        ..raycastable = false
        ..visible = false;
      parent.add(node);
      _pool.add(_Particle(node));
    }
  }

  final Node parent;
  final _rng = math.Random(7);
  final _ambient = <_Ambient>[];
  final _pool = <_Particle>[];
  final _stars = <Node>[];

  /// 0 hides the ambient sparks, 1 shows all of them.
  double ambientAmount = 1.0;

  /// Orbiting stars over the head while above zero.
  double starAmount = 0.0;

  /// Shows every spark and star (or hides them again), so a pipeline warm-up
  /// sees the materials they draw with before their first real appearance.
  void showAllForWarmUp(bool show) {
    for (final p in _pool) {
      p.node.visible = show;
    }
    for (final star in _stars) {
      star.visible = show;
    }
  }

  /// A ring of sparks thrown outward from [center].
  void burst(Vector3 center, {int count = 30}) {
    for (var i = 0; i < count; i++) {
      final a = i / count * math.pi * 2 + _rng.nextDouble() * 0.2;
      final dir = Vector3(math.cos(a), math.sin(a) * 0.9, (_rng.nextDouble() - 0.5) * 0.6);
      _emit(
        center + dir * 0.55,
        dir * (1.6 + _rng.nextDouble() * 1.4),
        life: 0.9 + _rng.nextDouble() * 0.5,
        size: 0.02 + _rng.nextDouble() * 0.028,
      );
    }
  }

  /// A few flecks knocked off a poke at [point], flying along [normal].
  void flecks(Vector3 point, Vector3 normal) {
    for (var i = 0; i < 8; i++) {
      final jitter = Vector3(
        _rng.nextDouble() - 0.5,
        _rng.nextDouble() - 0.3,
        _rng.nextDouble() - 0.5,
      );
      _emit(
        point + normal * 0.05,
        (normal + jitter * 0.9).normalized() * (1.2 + _rng.nextDouble() * 1.2),
        life: 0.45 + _rng.nextDouble() * 0.25,
        size: 0.014 + _rng.nextDouble() * 0.014,
      );
    }
  }

  void _emit(Vector3 p, Vector3 v, {required double life, required double size}) {
    for (final particle in _pool) {
      if (particle.age < particle.life) continue;
      particle
        ..position.setFrom(p)
        ..velocity.setFrom(v)
        ..age = 0
        ..life = life
        ..size = size
        ..node.visible = true;
      return;
    }
  }

  void update(double dt, double time, Vector3 headCenter) {
    for (final s in _ambient) {
      final a = s.phase + time * s.speed * math.pi * 2;
      final bob = math.sin(time * 0.7 + s.phase * 3) * 0.12;
      final p = Vector3(
        math.cos(a) * s.radius,
        s.height + bob,
        math.sin(a) * s.radius * 0.6,
      );
      final tw = 0.55 + 0.45 * math.sin(time * s.twinkle + s.phase * 5);
      final scale = s.size * tw * ambientAmount;
      s.node.visible = scale > 1e-4;
      s.node.localTransform = Matrix4.compose(p, Quaternion.identity(), Vector3.all(scale));
    }

    for (final particle in _pool) {
      if (particle.age >= particle.life) continue;
      particle.age += dt;
      if (particle.age >= particle.life) {
        particle.node.visible = false;
        continue;
      }
      // Quick drag so the ring opens fast and then hangs in the air.
      particle.velocity.scale(math.exp(-3.2 * dt));
      particle.velocity.y -= 0.6 * dt;
      particle.position.addScaled(particle.velocity, dt);
      final k = 1 - particle.age / particle.life;
      final scale = particle.size * (k < 0.3 ? k / 0.3 : 1.0);
      particle.node.localTransform = Matrix4.compose(
        particle.position,
        Quaternion.identity(),
        Vector3.all(scale),
      );
    }

    // Stars circling above a dizzy head.
    for (var i = 0; i < _stars.length; i++) {
      final star = _stars[i];
      star.visible = starAmount > 0.01;
      if (!star.visible) continue;
      final a = time * 3.2 + i / _stars.length * math.pi * 2;
      final p =
          headCenter +
          Vector3(math.cos(a) * 0.6, 0.68 + 0.05 * math.sin(a * 2), math.sin(a) * 0.3);
      star.localTransform = Matrix4.compose(
        p,
        Quaternion.identity(),
        Vector3.all(0.05 * starAmount),
      );
    }
  }
}

class _Ambient {
  _Ambient({
    required this.node,
    required this.radius,
    required this.height,
    required this.phase,
    required this.speed,
    required this.size,
    required this.twinkle,
  });
  final Node node;
  final double radius, height, phase, speed, size, twinkle;
}

class _Particle {
  _Particle(this.node);
  final Node node;
  final position = Vector3.zero();
  final velocity = Vector3.zero();
  double age = 1, life = 0, size = 0.02;
}
