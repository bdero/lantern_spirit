import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';

/// A five-pointed star, extruded into a thin prism facing -Z.
MeshGeometry starGeometry({double radius = 1, double inner = 0.45, double depth = 0.3}) {
  final rim = <List<double>>[];
  for (var i = 0; i < 10; i++) {
    final a = math.pi / 2 + i * math.pi / 5;
    final r = i.isEven ? radius : radius * inner;
    rim.add([r * math.cos(a), r * math.sin(a)]);
  }
  final pos = <double>[];
  final idx = <int>[];
  void tri(List<double> a, List<double> b, List<double> c) {
    final base = pos.length ~/ 3;
    pos.addAll([...a, ...b, ...c]);
    // Both windings: the star is tiny, and this keeps it visible from any
    // side whatever the material culls.
    idx.addAll([base, base + 1, base + 2, base, base + 2, base + 1]);
  }

  final h = depth / 2;
  for (var i = 0; i < 10; i++) {
    final p = rim[i], q = rim[(i + 1) % 10];
    // Front and back faces.
    tri([0, 0, -h], [q[0], q[1], -h * 0.2], [p[0], p[1], -h * 0.2]);
    tri([0, 0, h], [p[0], p[1], h * 0.2], [q[0], q[1], h * 0.2]);
    // The edge between them.
    tri([p[0], p[1], -h * 0.2], [q[0], q[1], -h * 0.2], [q[0], q[1], h * 0.2]);
    tri([p[0], p[1], -h * 0.2], [q[0], q[1], h * 0.2], [p[0], p[1], h * 0.2]);
  }
  return MeshGeometry.fromArrays(positions: Float32List.fromList(pos), indices: idx);
}
