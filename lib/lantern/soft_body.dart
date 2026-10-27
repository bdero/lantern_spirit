import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// A squishy head: twelve control points around a sphere, simulated as a
/// soft body, deform the head mesh and the face cap on it.
///
/// Each control point sits on an icosahedron direction and carries an offset
/// from rest. Springs pull the offsets home, neighbors drag each other along,
/// and a volume term pushes the rest of the head out when one side is pressed
/// in, so it reads as soft rather than dented. Every vertex follows a smooth
/// blend of the control offsets, weighted by how close its direction is to
/// each control point. Normals are rebuilt on the CPU each frame.
///
/// Positions here are in the head mesh's own space (a unit sphere); the face
/// cap lives in the head's parent space, where the sphere has [radius].
class SoftHead {
  SoftHead({required this.radius, required this.faceZ, this.faceK = 1.3, this.capScale = 1.012}) {
    _buildControls();
    _buildHead();
    _buildCap();
  }

  /// The head's radius in the cap's space.
  final double radius;

  /// Which way the face points along Z.
  final double faceZ;
  final double faceK;
  final double capScale;

  late final MeshGeometry headGeometry;
  late final MeshGeometry capGeometry;

  // ---------------------------------------------------------------- tuning
  /// How hard each point springs back to rest.
  double stiffness = 140;

  /// How quickly wobbles die out.
  double damping = 16.5;

  /// How heavy each point is. More weight slows the wobble into a few
  /// unhurried sloshes that roll across the head, rather than a fast jelly
  /// shiver.
  double mass = 2.4;

  /// How strongly neighbors pull each other along.
  double coupling = 55;

  /// How strongly the head keeps its volume.
  double volume = 260;

  // ---------------------------------------------------------------- state
  final List<Vector3> _dirs = [];
  final List<List<int>> _neighbors = [];
  late final Float64List _off; // 12 * 3
  late final Float64List _vel;
  final Float64List _force = Float64List(36);

  // Each vertex blends the controls with fixed weights.
  late final Float32List _headRest, _capRest;
  late final Float32List _headW, _capW; // vertexCount * 12
  late final Float32List _headPos, _headNrm, _capPos;
  late final Uint32List _headIdx, _capIdx;
  late final Float32List _headUv, _capUv, _capNrm;
  late final int _headVerts, _capVerts;
  double _accum = 0;
  bool _dirty = true;

  // Interaction: one press or pull at a time.
  Vector3? _pressDir;
  double _pressDepth = 0;
  Vector3? _pullDir;
  Vector3? _pullTarget;

  /// The largest displacement right now, 0 at rest.
  double get energy {
    var e = 0.0;
    for (var i = 0; i < 36; i++) {
      e = math.max(e, _off[i].abs());
    }
    return e;
  }

  // ---------------------------------------------------------------- input
  /// A quick inward knock at [dir] (head-mesh space), like a poke.
  void impulse(Vector3 dir, double amount) {
    // Scaled so a knock dents the head as deeply whatever the mass; only the
    // pace of the wobble changes.
    amount /= math.sqrt(mass);
    final d = dir.normalized();
    for (var i = 0; i < 12; i++) {
      final w = _falloff(d, _dirs[i], 5.0);
      _vel[i * 3] -= _dirs[i].x * amount * w;
      _vel[i * 3 + 1] -= _dirs[i].y * amount * w;
      _vel[i * 3 + 2] -= _dirs[i].z * amount * w;
    }
  }

  /// Ripples across the whole head, for landings and catches.
  void jiggle(double amount, int seed) {
    amount /= math.sqrt(mass);
    final rng = math.Random(seed);
    for (var i = 0; i < 12; i++) {
      final s = (rng.nextDouble() * 2 - 1) * amount;
      _vel[i * 3] += _dirs[i].x * s;
      _vel[i * 3 + 1] += _dirs[i].y * s;
      _vel[i * 3 + 2] += _dirs[i].z * s;
    }
  }

  /// Inertia: while the head's owner speeds up by [accel] (head-mesh units
  /// per second squared), the surface lags the other way, the crown most.
  void drag(Vector3 accel, double dt) {
    for (var i = 0; i < 12; i++) {
      final k = (0.35 + 0.65 * (_dirs[i].y * 0.5 + 0.5)) * dt;
      _vel[i * 3] -= accel.x * k;
      _vel[i * 3 + 1] -= accel.y * k;
      _vel[i * 3 + 2] -= accel.z * k;
    }
  }

  /// Holds a finger pressed into the head at [dir], [depth] deep (0 to 0.5).
  void press(Vector3 dir, double depth) {
    _pressDir = dir.normalized();
    _pressDepth = depth;
  }

  /// Pulls the head toward [target] from the point at [dir] (both in
  /// head-mesh space; target may be outside the sphere).
  void pull(Vector3 dir, Vector3 target) {
    _pullDir = dir.normalized();
    _pullTarget = target.clone();
  }

  /// Lets go of any press or pull; the head springs back.
  void release() {
    _pressDir = null;
    _pullDir = null;
    _pullTarget = null;
  }

  // ---------------------------------------------------------------- sim
  /// Stops simulating and writing the mesh (for render checks).
  bool frozen = false;

  void update(double dt) {
    if (frozen) return;
    _accum += dt.clamp(0.0, 0.1);
    const step = 1 / 120;
    var steps = 0;
    while (_accum >= step && steps < 8) {
      _step(step);
      _accum -= step;
      steps++;
    }
    if (steps > 0 || _dirty) _write();
  }

  void _step(double h) {
    // Mean inward push, for volume preservation.
    var radial = 0.0;
    for (var i = 0; i < 12; i++) {
      radial += _off[i * 3] * _dirs[i].x + _off[i * 3 + 1] * _dirs[i].y + _off[i * 3 + 2] * _dirs[i].z;
    }
    radial /= 12;
    for (var i = 0; i < 12; i++) {
      final ox = _off[i * 3], oy = _off[i * 3 + 1], oz = _off[i * 3 + 2];
      var fx = -stiffness * ox - damping * _vel[i * 3];
      var fy = -stiffness * oy - damping * _vel[i * 3 + 1];
      var fz = -stiffness * oz - damping * _vel[i * 3 + 2];
      // Neighbors.
      var nx = 0.0, ny = 0.0, nz = 0.0;
      for (final j in _neighbors[i]) {
        nx += _off[j * 3];
        ny += _off[j * 3 + 1];
        nz += _off[j * 3 + 2];
      }
      final n = _neighbors[i].length;
      fx += coupling * (nx / n - ox);
      fy += coupling * (ny / n - oy);
      fz += coupling * (nz / n - oz);
      // Volume: when the head is pushed in overall, push every point out.
      fx -= volume * radial * _dirs[i].x;
      fy -= volume * radial * _dirs[i].y;
      fz -= volume * radial * _dirs[i].z;
      _force[i * 3] = fx;
      _force[i * 3 + 1] = fy;
      _force[i * 3 + 2] = fz;
    }
    // Hard constraints from a press or pull, applied as stiff springs.
    final pd = _pressDir;
    if (pd != null) {
      for (var i = 0; i < 12; i++) {
        final w = _falloff(pd, _dirs[i], 4.0);
        if (w < 0.02) continue;
        final tx = -_dirs[i].x * _pressDepth * w, ty = -_dirs[i].y * _pressDepth * w, tz = -_dirs[i].z * _pressDepth * w;
        _force[i * 3] += 1200 * w * (tx - _off[i * 3]);
        _force[i * 3 + 1] += 1200 * w * (ty - _off[i * 3 + 1]);
        _force[i * 3 + 2] += 1200 * w * (tz - _off[i * 3 + 2]);
      }
    }
    final ud = _pullDir, ut = _pullTarget;
    if (ud != null && ut != null) {
      // Stretch toward the target, capped so it reads as taffy, not a tear.
      final want = ut - ud;
      final len = want.length;
      if (len > 1.9) want.scale(1.9 / len);
      for (var i = 0; i < 12; i++) {
        final w = _falloff(ud, _dirs[i], 1.3);
        if (w < 0.02) continue;
        _force[i * 3] += 2400 * w * (want.x * w - _off[i * 3]);
        _force[i * 3 + 1] += 2400 * w * (want.y * w - _off[i * 3 + 1]);
        _force[i * 3 + 2] += 2400 * w * (want.z * w - _off[i * 3 + 2]);
      }
    }
    for (var i = 0; i < 36; i++) {
      _vel[i] += _force[i] * h / mass;
      _off[i] += _vel[i] * h;
    }
    _dirty = true;
  }

  /// How far the surface at unit direction [dir] has moved from rest, in
  /// the head mesh's unit-sphere space: the same blend the vertices use.
  Vector3 displacementAt(Vector3 dir) {
    var sum = 0.0;
    var dx = 0.0, dy = 0.0, dz = 0.0;
    for (var i = 0; i < 12; i++) {
      final w = _falloff(dir, _dirs[i], 5.0);
      sum += w;
      dx += _off[i * 3] * w;
      dy += _off[i * 3 + 1] * w;
      dz += _off[i * 3 + 2] * w;
    }
    return Vector3(dx, dy, dz) / sum;
  }

  static double _falloff(Vector3 a, Vector3 b, double sharpness) =>
      math.exp(sharpness * (a.x * b.x + a.y * b.y + a.z * b.z - 1));

  // ---------------------------------------------------------------- mesh
  void _write() {
    _dirty = false;
    _deform(_headRest, _headW, _headVerts, _headPos, 1.0);
    _deform(_capRest, _capW, _capVerts, _capPos, radius * capScale);
    _normals();
    // Fresh views each time: the geometry keeps the lists it is given and
    // treats the same list object as unchanged.
    headGeometry.rebuild(
      positions: Float32List.sublistView(_headPos),
      normals: Float32List.sublistView(_headNrm),
      texCoords: _headUv,
      indices: _headIdx,
    );
    capGeometry.rebuild(
      positions: Float32List.sublistView(_capPos),
      normals: _capNrm,
      texCoords: _capUv,
      indices: _capIdx,
    );
  }

  void _deform(Float32List rest, Float32List weights, int count, Float32List out, double scale) {
    for (var v = 0; v < count; v++) {
      var dx = 0.0, dy = 0.0, dz = 0.0;
      final wo = v * 12;
      for (var i = 0; i < 12; i++) {
        final w = weights[wo + i];
        dx += _off[i * 3] * w;
        dy += _off[i * 3 + 1] * w;
        dz += _off[i * 3 + 2] * w;
      }
      out[v * 3] = (rest[v * 3] + dx) * scale;
      out[v * 3 + 1] = (rest[v * 3 + 1] + dy) * scale;
      out[v * 3 + 2] = (rest[v * 3 + 2] + dz) * scale;
    }
  }

  void _normals() {
    final n = _headNrm..fillRange(0, _headNrm.length, 0);
    final p = _headPos;
    for (var t = 0; t < _headIdx.length; t += 3) {
      final a = _headIdx[t] * 3, b = _headIdx[t + 1] * 3, c = _headIdx[t + 2] * 3;
      final ux = p[b] - p[a], uy = p[b + 1] - p[a + 1], uz = p[b + 2] - p[a + 2];
      final vx = p[c] - p[a], vy = p[c + 1] - p[a + 1], vz = p[c + 2] - p[a + 2];
      final nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
      for (final k in [a, b, c]) {
        n[k] += nx;
        n[k + 1] += ny;
        n[k + 2] += nz;
      }
    }
    for (var v = 0; v < _headVerts; v++) {
      final x = n[v * 3], y = n[v * 3 + 1], z = n[v * 3 + 2];
      final l = math.sqrt(x * x + y * y + z * z) + 1e-9;
      n[v * 3] = x / l;
      n[v * 3 + 1] = y / l;
      n[v * 3 + 2] = z / l;
    }
  }

  Float32List _weightsFor(Float32List rest, int count) {
    final w = Float32List(count * 12);
    for (var v = 0; v < count; v++) {
      final d = Vector3(rest[v * 3], rest[v * 3 + 1], rest[v * 3 + 2])..normalize();
      var sum = 0.0;
      for (var i = 0; i < 12; i++) {
        final x = _falloff(d, _dirs[i], 5.0);
        w[v * 12 + i] = x;
        sum += x;
      }
      for (var i = 0; i < 12; i++) {
        w[v * 12 + i] /= sum;
      }
    }
    return w;
  }

  void _buildControls() {
    final t = (1 + math.sqrt(5)) / 2;
    for (final v in [
      [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], //
      [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t], //
      [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1],
    ]) {
      _dirs.add(Vector3(v[0].toDouble(), v[1].toDouble(), v[2].toDouble())..normalize());
    }
    for (var i = 0; i < 12; i++) {
      final near = <int>[];
      for (var j = 0; j < 12; j++) {
        if (i != j && _dirs[i].dot(_dirs[j]) > 0.4) near.add(j);
      }
      _neighbors.add(near);
    }
    _off = Float64List(36);
    _vel = Float64List(36);
  }

  void _buildHead() {
    const seg = 48, rings = 24;
    final pos = <double>[], idx = <int>[];
    for (var r = 0; r <= rings; r++) {
      final phi = r / rings * math.pi;
      for (var s = 0; s <= seg; s++) {
        final th = s / seg * math.pi * 2;
        pos.addAll([math.sin(phi) * math.sin(th), math.cos(phi), math.sin(phi) * math.cos(th)]);
      }
    }
    for (var r = 0; r < rings; r++) {
      for (var s = 0; s < seg; s++) {
        final a = r * (seg + 1) + s, b = a + seg + 1;
        _addOutward(idx, pos, a, b, a + 1);
        _addOutward(idx, pos, a + 1, b, b + 1);
      }
    }
    _headVerts = pos.length ~/ 3;
    _headRest = Float32List.fromList(pos);
    _headPos = Float32List.fromList(pos);
    _headNrm = Float32List.fromList(pos);
    _headIdx = Uint32List.fromList(idx);
    _headUv = Float32List(_headVerts * 2);
    _headW = _weightsFor(_headRest, _headVerts);
    headGeometry = MeshGeometry.fromArrays(
      positions: Float32List.fromList(_headPos),
      normals: Float32List.fromList(_headNrm),
      texCoords: Float32List(_headVerts * 2),
      indices: idx,
      storage: GeometryStorage.updatable,
      bounds: Aabb3.minMax(Vector3.all(-1.6), Vector3.all(1.6)),
    );
  }

  void _buildCap() {
    // A cap of the sphere around the face direction, UV-mapped by projection
    // from the front, matching the face atlas's layout.
    const seg = 64, rings = 24;
    final cmax = 70 * math.pi / 180;
    final pos = <double>[], uv = <double>[], idx = <int>[];
    for (var r = 0; r <= rings; r++) {
      final a = cmax * r / rings;
      for (var s = 0; s <= seg; s++) {
        final th = s / seg * math.pi * 2;
        final dx = math.sin(a) * math.cos(th), dy = math.sin(a) * math.sin(th), dz = math.cos(a) * faceZ;
        pos.addAll([dx, dy, dz]);
        uv.addAll([dx / (2 * faceK) + 0.5, 0.5 - dy / (2 * faceK)]);
      }
    }
    for (var r = 0; r < rings; r++) {
      for (var s = 0; s < seg; s++) {
        final a = r * (seg + 1) + s, b = a + seg + 1;
        _addOutward(idx, pos, a, b, a + 1);
        _addOutward(idx, pos, a + 1, b, b + 1);
      }
    }
    _capVerts = pos.length ~/ 3;
    _capRest = Float32List.fromList(pos);
    _capPos = Float32List(pos.length);
    for (var i = 0; i < pos.length; i++) {
      _capPos[i] = pos[i] * radius * capScale;
    }
    _capW = _weightsFor(_capRest, _capVerts);
    _capIdx = Uint32List.fromList(idx);
    _capUv = Float32List.fromList(uv);
    _capNrm = Float32List.fromList(pos);
    capGeometry = MeshGeometry.fromArrays(
      positions: Float32List.fromList(_capPos),
      normals: Float32List.fromList(pos),
      texCoords: Float32List.fromList(uv),
      indices: idx,
      storage: GeometryStorage.updatable,
      bounds: Aabb3.minMax(Vector3.all(-1.2), Vector3.all(1.2)),
    );
  }

  /// Adds a triangle wound counter-clockwise as seen from outside the sphere
  /// (the engine's front face), skipping degenerate ones at the poles.
  static void _addOutward(List<int> idx, List<double> p, int a, int b, int c) {
    final ax = p[a * 3], ay = p[a * 3 + 1], az = p[a * 3 + 2];
    final ux = p[b * 3] - ax, uy = p[b * 3 + 1] - ay, uz = p[b * 3 + 2] - az;
    final vx = p[c * 3] - ax, vy = p[c * 3 + 1] - ay, vz = p[c * 3 + 2] - az;
    final nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    final area = nx * nx + ny * ny + nz * nz;
    if (area < 1e-14) return;
    final outward = nx * ax + ny * ay + nz * az;
    if (outward >= 0) {
      idx.addAll([a, b, c]);
    } else {
      idx.addAll([a, c, b]);
    }
  }
}
