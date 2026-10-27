import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// The shape a particle draws as (see `assets/vfx.fmat`).
enum VfxShape { streak, dot, ring, flare, puff }

/// Game effects: a CPU particle system drawn as glowing quads and streaks
/// in one additive mesh, so a hundred bursts cost one draw.
///
/// Everything is fire-and-forget: call [burst], [ring], [flare], [streak],
/// [bolt], and friends from game code, and [update] once a frame with the
/// camera. Colors are linear and may go past 1 for bloom.
class Vfx {
  Vfx._(this.node, this._mesh);

  static Future<Vfx> create(Scene scene, {int capacity = 9000}) async {
    final material = await loadFmatMaterial('assets/vfx.fmat');
    final mesh = _GlowMesh(capacity);
    final node = Node(name: 'Vfx', mesh: Mesh(mesh.geometry, material))..raycastable = false;
    scene.add(node);
    return Vfx._(node, mesh);
  }

  final Node node;
  final _GlowMesh _mesh;
  final List<_Particle> _live = [];
  final _rng = math.Random(17);

  static const int _max = 2000;

  int get count => _live.length;

  double _r(double a, double b) => a + _rng.nextDouble() * (b - a);

  Vector3 _randomDir() {
    final z = _r(-1, 1);
    final a = _r(0, math.pi * 2);
    final s = math.sqrt(1 - z * z);
    return Vector3(s * math.cos(a), s * math.sin(a), z);
  }

  void _emitAlong(double dt, _Particle p) {
    final lead = _r(0, dt);
    p
      ..pos.addScaled(p.vel, lead)
      ..age = lead;
    _add(p);
  }

  void _add(_Particle p) {
    if (_live.length >= _max) _live.removeAt(0);
    _live.add(p);
  }

  /// Drops every live particle and empties the mesh, so nothing left over
  /// is drawn the next time this layer shows.
  void clear() {
    _live.clear();
    _mesh
      ..begin()
      ..commit();
  }

  /// A spray of [count] particles flying out from [at].
  void burst(
    Vector3 at, {
    int count = 24,
    double speed = 3,
    double speedJitter = 0.6,
    Vector3? color,
    Vector3? color2,
    double size = 0.08,
    double life = 0.8,
    double gravity = 2,
    double drag = 1.5,
    VfxShape shape = VfxShape.dot,
    bool streaks = false,
    Vector3? bias,
    double flatten = 1,
  }) {
    final c = color ?? Vector3(1.6, 1.25, 0.6);
    for (var i = 0; i < count; i++) {
      final d = _randomDir()..z *= flatten;
      final v = d * (speed * (1 - speedJitter + _r(0, speedJitter * 2)));
      if (bias != null) v.add(bias);
      final col = color2 == null ? c.clone() : (c + (color2 - c) * _rng.nextDouble());
      _add(
        _Particle(
          pos: at.clone(),
          vel: v,
          color: col,
          size: size * _r(0.6, 1.3),
          endSize: size * 0.2,
          life: life * _r(0.6, 1.2),
          gravity: gravity,
          drag: drag,
          shape: streaks ? VfxShape.streak : shape,
          stretch: streaks ? 0.06 : 0,
          twinkle: shape == VfxShape.flare ? _r(10, 30) : 0,
        ),
      );
    }
  }

  /// An expanding shockwave ring. Faces the camera, or lies flat in the plane
  /// with [normal] (a ripple on water, a ring around a landing).
  void ring(Vector3 at, {double radius = 1.2, Vector3? color, double life = 0.5, double start = 0.1, Vector3? normal}) {
    _add(
      _Particle(
        pos: at.clone(),
        vel: Vector3.zero(),
        color: color ?? Vector3(1.4, 1.2, 0.8),
        size: start,
        endSize: radius,
        life: life,
        shape: VfxShape.ring,
        normal: normal?.normalized(),
        easeOut: true,
      ),
    );
  }

  /// A soap bubble with a lantern glow inside, drifting at [velocity].
  void bubble(Vector3 at, Vector3 velocity, {double size = 0.35, double life = 3.0, Vector3? color}) {
    final c = color ?? Vector3(0.9, 1.1, 1.5);
    _add(_Particle(pos: at.clone(), vel: velocity.clone(), color: c * 0.9, size: size, endSize: size * 1.05, life: life, shape: VfxShape.ring, keepBright: true));
    _add(_Particle(pos: at.clone(), vel: velocity.clone(), color: Vector3(1.6, 1.1, 0.5), size: size * 0.5, endSize: size * 0.45, life: life, shape: VfxShape.dot, keepBright: true));
    _add(_Particle(pos: at + Vector3(-size * 0.35, size * 0.35, -0.05), vel: velocity.clone(), color: Vector3.all(1.4), size: size * 0.16, endSize: size * 0.16, life: life, shape: VfxShape.dot, keepBright: true));
  }

  /// A star flare that pops and fades.
  void flare(Vector3 at, {double size = 0.9, Vector3? color, double life = 0.35}) {
    _add(
      _Particle(
        pos: at.clone(),
        vel: Vector3.zero(),
        color: color ?? Vector3(2, 1.7, 1.1),
        size: size,
        endSize: size * 0.3,
        life: life,
        shape: VfxShape.flare,
        spin: _r(-1, 1),
      ),
    );
  }

  /// A soft glow that swells and fades (a flash of light in the world).
  void glow(Vector3 at, {double size = 1.5, Vector3? color, double life = 0.4}) {
    _add(
      _Particle(
        pos: at.clone(),
        vel: Vector3.zero(),
        color: color ?? Vector3(1.2, 1.0, 0.7),
        size: size * 0.5,
        endSize: size,
        life: life,
        shape: VfxShape.dot,
        easeOut: true,
      ),
    );
  }

  /// Soft cloud puffs bursting outward.
  void puffs(Vector3 at, {int count = 10, double speed = 1.6, Vector3? color, double size = 0.45, double life = 0.9, double flatten = 0.4}) {
    for (var i = 0; i < count; i++) {
      final d = _randomDir()..y *= flatten;
      _add(
        _Particle(
          pos: at.clone(),
          vel: d * (speed * _r(0.5, 1.2)),
          color: color ?? Vector3(0.5, 0.45, 0.5),
          size: size * _r(0.5, 1),
          endSize: size * _r(1.4, 2.2),
          life: life * _r(0.7, 1.2),
          drag: 3,
          shape: VfxShape.puff,
        ),
      );
    }
  }

  /// One frame's worth of a jet of fire from [at] along [dir] (normalized),
  /// for [dt] seconds of burn: a white-hot core, flame that cools from
  /// yellow through orange to red as it slows and spreads, and a little
  /// smoke. [inherit] is the emitter's own velocity, part of which the
  /// exhaust keeps so the plume trails behind a moving body.
  void jet(Vector3 at, Vector3 dir, double dt, {double scale = 1, double power = 1, Vector3? inherit}) {
    final carry = (inherit ?? Vector3.zero()) * 0.35;
    final side = dir.cross(dir.y.abs() > 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0))..normalize();
    final side2 = dir.cross(side)..normalize();
    Vector3 spread(double amount) => side * _r(-amount, amount) + side2 * _r(-amount, amount);
    // Spread each frame's particles back along their path by a random slice
    // of the frame, so the plume stays continuous at any frame rate.
    int n(double rate) {
      final x = rate * dt * power;
      return x.floor() + (_rng.nextDouble() < x - x.floor() ? 1 : 0);
    }

    // The core: tight, fast, nearly white, gone almost at once.
    for (var i = n(150); i > 0; i--) {
      _emitAlong(dt, _Particle(
        pos: at + spread(0.03 * scale),
        vel: (dir * _r(5.5, 7.5) + spread(0.5)) * scale + carry,
        color: Vector3(3.4, 3.1, 2.6),
        endColor: Vector3(3.0, 1.9, 0.6),
        size: 0.07 * scale,
        endSize: 0.03 * scale,
        life: _r(0.06, 0.1),
        drag: 4,
        shape: VfxShape.flare,
      ));
    }
    // The flame: widening, slowing, cooling.
    for (var i = n(170); i > 0; i--) {
      _emitAlong(dt, _Particle(
        pos: at + dir * (0.05 * scale) + spread(0.05 * scale),
        vel: (dir * _r(3.0, 4.6) + spread(0.9)) * scale + carry,
        color: Vector3(3.2, 2.0, 0.55),
        endColor: Vector3(1.5, 0.3, 0.06),
        colorCurve: 1.6,
        size: 0.09 * scale,
        endSize: 0.22 * scale,
        life: _r(0.2, 0.36),
        drag: 5,
        gravity: -1.5,
        easeOut: true,
        shape: VfxShape.puff,
      ));
    }
    // Embers flicking out of the plume.
    for (var i = n(18); i > 0; i--) {
      _emitAlong(dt, _Particle(
        pos: at + dir * (0.15 * scale),
        vel: (dir * _r(2, 4) + spread(2.2)) * scale + carry,
        color: Vector3(2.4, 1.3, 0.4),
        endColor: Vector3(1.0, 0.25, 0.05),
        size: 0.025 * scale,
        endSize: 0.01 * scale,
        life: _r(0.3, 0.6),
        drag: 1.5,
        gravity: 2,
        shape: VfxShape.streak,
        stretch: 0.03,
      ));
    }
    // A soft haze of smoke where the flame dies.
    for (var i = n(16); i > 0; i--) {
      _emitAlong(dt, _Particle(
        pos: at + dir * (0.5 * scale) + spread(0.1 * scale),
        vel: (dir * _r(1.2, 2.0) + spread(0.6)) * scale + carry * 0.5,
        color: Vector3(0.22, 0.17, 0.22),
        endColor: Vector3(0.08, 0.08, 0.12),
        size: 0.18 * scale,
        endSize: 0.5 * scale,
        life: _r(0.6, 0.9),
        drag: 2.5,
        gravity: -0.6,
        easeOut: true,
        shape: VfxShape.puff,
      ));
    }
  }

  /// One moving streak (a speed line, a shooting star, a trail mote).
  void streak(Vector3 at, Vector3 velocity, {Vector3? color, double width = 0.03, double length = 0.12, double life = 0.5, double gravity = 0}) {
    _add(
      _Particle(
        pos: at.clone(),
        vel: velocity.clone(),
        color: color ?? Vector3(1, 1, 1),
        size: width,
        endSize: width * 0.4,
        life: life,
        gravity: gravity,
        shape: VfxShape.streak,
        stretch: length,
      ),
    );
  }

  /// A fixed glowing segment that fades: lightning strokes, lines.
  void segment(Vector3 a, Vector3 b, {Vector3? color, double width = 0.05, double life = 0.2}) {
    _add(
      _Particle(
        pos: b.clone(),
        vel: Vector3.zero(),
        tail: a.clone(),
        color: color ?? Vector3(1.6, 1.8, 2.4),
        size: width,
        endSize: width * 0.6,
        life: life,
        shape: VfxShape.streak,
      ),
    );
  }

  /// A forked lightning bolt from [from] to [to].
  void bolt(Vector3 from, Vector3 to, {Vector3? color, double life = 0.22, int depth = 2}) {
    final c = color ?? Vector3(1.8, 2.0, 3.0);
    void strike(Vector3 a, Vector3 b, double width, int level) {
      const steps = 7;
      var p = a;
      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        final base = a + (b - a) * t;
        final jag = i == steps ? Vector3.zero() : Vector3(_r(-1, 1), _r(-0.3, 0.3), 0) * ((b - a).length * 0.09);
        final next = base + jag;
        segment(p, next, color: c, width: width, life: life);
        segment(p, next, color: c * 0.25, width: width * 5, life: life * 0.8);
        if (level > 0 && _rng.nextDouble() < 0.28) {
          final branch = next + Vector3(_r(-1, 1), _r(-0.9, -0.2), 0) * ((b - a).length * 0.25);
          strike(next, branch, width * 0.55, level - 1);
        }
        p = next;
      }
    }

    strike(from, to, 0.05, depth);
    glow(to, size: 1.6, color: c * 0.5, life: life * 1.4);
  }

  void update(double dt, PerspectiveCamera camera) {
    final eye = camera.position;
    final fwd = (camera.target - eye)..normalize();
    final right = fwd.cross(Vector3(0, 1, 0))..normalize();
    final up = right.cross(fwd)..normalize();
    _mesh.begin();
    final keep = <_Particle>[];
    for (final p in _live) {
      p.age += dt;
      if (p.age >= p.life) continue;
      keep.add(p);
      p.vel.y -= p.gravity * dt;
      p.vel.scale(math.exp(-p.drag * dt));
      p.pos.addScaled(p.vel, dt);
      final t = p.age / p.life;
      final k = p.easeOut ? 1 - (1 - t) * (1 - t) : t;
      final size = p.size + (p.endSize - p.size) * k;
      var fade = (1 - t) * (1 - t);
      if (p.shape == VfxShape.ring || p.shape == VfxShape.puff) fade = 1 - t;
      if (p.keepBright) fade = t < 0.9 ? 1 : (1 - t) * 10;
      if (p.twinkle > 0) fade *= 0.55 + 0.45 * math.sin(p.age * p.twinkle);
      final end = p.endColor;
      final base = end == null ? p.color : p.color + (end - p.color) * math.pow(t, 1 / p.colorCurve).toDouble();
      final c = base * fade;
      switch (p.shape) {
        case VfxShape.streak:
          final tail = p.tail ?? p.pos - p.vel * p.stretch;
          _quadStreak(tail, p.pos, size, fwd, c);
        default:
          final band = switch (p.shape) {
            VfxShape.dot => 2.0,
            VfxShape.ring => 4.0,
            VfxShape.flare => 6.0,
            _ => 8.0,
          };
          Vector3 a, b;
          if (p.normal case final n?) {
            a = n.cross(n.y.abs() > 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0))..normalize();
            b = n.cross(a);
          } else if (p.spin != 0) {
            final ang = p.spin * p.age * 3;
            a = right * math.cos(ang) + up * math.sin(ang);
            b = up * math.cos(ang) - right * math.sin(ang);
          } else {
            a = right;
            b = up;
          }
          _quad(p.pos, a * size, b * size, band, c);
      }
    }
    _live
      ..clear()
      ..addAll(keep);
    _mesh.commit();
  }

  void _quad(Vector3 c, Vector3 a, Vector3 b, double band, Vector3 col) {
    if (!_mesh.reserve(4, 6)) return;
    final i = _mesh.vertexCount;
    void v(Vector3 p, double u, double w) => _mesh.vertex(p.x, p.y, p.z, u, band + w, col.x, col.y, col.z, 1);
    v(c - a - b, 0, 0);
    v(c + a - b, 1, 0);
    v(c + a + b, 1, 1);
    v(c - a + b, 0, 1);
    _mesh.tri(i, i + 1, i + 2);
    _mesh.tri(i, i + 2, i + 3);
  }

  void _quadStreak(Vector3 tail, Vector3 head, double width, Vector3 fwd, Vector3 col) {
    if (!_mesh.reserve(4, 6)) return;
    final d = head - tail;
    var side = d.cross(fwd);
    if (side.length2 < 1e-10) side = Vector3(width, 0, 0);
    side
      ..normalize()
      ..scale(width);
    final i = _mesh.vertexCount;
    void v(Vector3 p, double u, double w) => _mesh.vertex(p.x, p.y, p.z, u, w, col.x, col.y, col.z, 1);
    v(tail - side, 0, 0);
    v(tail + side, 1, 0);
    v(head + side, 1, 1);
    v(head - side, 0, 1);
    _mesh.tri(i, i + 1, i + 2);
    _mesh.tri(i, i + 2, i + 3);
  }
}

class _Particle {
  _Particle({
    required this.pos,
    required this.vel,
    required this.color,
    required this.size,
    required this.endSize,
    required this.life,
    required this.shape,
    this.gravity = 0,
    this.drag = 0,
    this.stretch = 0,
    this.twinkle = 0,
    this.spin = 0,
    this.normal,
    this.tail,
    this.easeOut = false,
    this.keepBright = false,
    this.endColor,
    this.colorCurve = 1,
  });

  final Vector3 pos;
  final Vector3 vel;
  final Vector3 color;
  final double size;
  final double endSize;
  final double life;
  final VfxShape shape;
  final double gravity;
  final double drag;
  final double stretch;
  final double twinkle;
  final double spin;
  final Vector3? normal;
  final Vector3? tail;
  final bool easeOut;

  /// Stays at full strength until the last moment (a bubble until it pops).
  final bool keepBright;

  /// When set, the color cools toward this over the particle's life (fire
  /// going from white-hot to red); [colorCurve] above 1 holds the start
  /// color longer.
  final Vector3? endColor;
  final double colorCurve;
  double age = 0;
}

/// A mesh rebuilt from scratch every frame.
class _GlowMesh {
  _GlowMesh(this.capacity)
    : _pos = Float32List(capacity * 3),
      _nrm = Float32List(capacity * 3),
      _uv = Float32List(capacity * 2),
      _col = Float32List(capacity * 4),
      _idx = Uint32List(capacity * 2) {
    for (var i = 0; i < capacity; i++) {
      _nrm[i * 3 + 1] = 1;
    }
    geometry = MeshGeometry.fromArrays(
      positions: Float32List(9),
      normals: Float32List.fromList([0, 1, 0, 0, 1, 0, 0, 1, 0]),
      texCoords: Float32List(6),
      colors: Float32List(12),
      indices: const [0, 1, 2],
      storage: GeometryStorage.updatable,
      bounds: Aabb3.minMax(Vector3.all(-1000), Vector3.all(1000)),
    );
  }

  final int capacity;
  final Float32List _pos, _nrm, _uv, _col;
  final Uint32List _idx;
  late final MeshGeometry geometry;
  int vertexCount = 0;
  int _indexCount = 0;

  void begin() {
    vertexCount = 0;
    _indexCount = 0;
  }

  bool reserve(int vertices, int indices) => vertexCount + vertices <= capacity && _indexCount + indices <= _idx.length;

  void vertex(double x, double y, double z, double u, double v, double r, double g, double b, double a) {
    final i = vertexCount++;
    _pos[i * 3] = x;
    _pos[i * 3 + 1] = y;
    _pos[i * 3 + 2] = z;
    _uv[i * 2] = u;
    _uv[i * 2 + 1] = v;
    _col[i * 4] = r;
    _col[i * 4 + 1] = g;
    _col[i * 4 + 2] = b;
    _col[i * 4 + 3] = a;
  }

  void tri(int a, int b, int c) {
    _idx[_indexCount++] = a;
    _idx[_indexCount++] = b;
    _idx[_indexCount++] = c;
  }

  void commit() {
    if (vertexCount == 0) {
      geometry.rebuild(
        positions: Float32List(9),
        normals: Float32List.fromList([0, 1, 0, 0, 1, 0, 0, 1, 0]),
        texCoords: Float32List(6),
        colors: Float32List(12),
        indices: const [0, 1, 2],
      );
      return;
    }
    geometry.rebuild(
      positions: Float32List.sublistView(_pos, 0, vertexCount * 3),
      normals: Float32List.sublistView(_nrm, 0, vertexCount * 3),
      texCoords: Float32List.sublistView(_uv, 0, vertexCount * 2),
      colors: Float32List.sublistView(_col, 0, vertexCount * 4),
      indices: Uint32List.sublistView(_idx, 0, _indexCount),
    );
  }
}
