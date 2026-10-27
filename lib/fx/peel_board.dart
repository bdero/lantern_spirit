import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// One card of the app as a thick 3D slab: its snapshot on the face, solid
/// rounded sides, and a dark back. Built at unit thickness so its depth can
/// be animated by scaling z.
///
/// Local space: x right, y up, the face at z = 0 looking toward -z (the
/// camera), the body extending to z = +1.
class Slab {
  Slab._(this.node, this.size);

  static Future<Slab> create(ui.Image image, {required Vector2 size, required double radius, Vector3? side}) async {
    final texture = await Texture2D.fromImage(image);
    // Display-referred, so the snapshot shows exactly as the flat app did
    // (scene-referred, the tone curve would darken its deep blues).
    final face = UnlitMaterial(colorTexture: texture)
      ..doubleSided = true
      ..displayReferred = true;
    final body = UnlitMaterial()
      ..doubleSided = true
      ..displayReferred = true;
    final node = Node(name: 'Slab')..raycastable = false;
    final outline = _outline(size.x / 2, size.y / 2, math.min(radius, math.min(size.x, size.y) / 2), 8);

    // The face: a fan from the middle (the outline is convex).
    final fp = <double>[], fu = <double>[];
    void fv(Vector2 p) {
      fp.addAll([p.x, p.y, 0]);
      fu.addAll([0.5 + p.x / size.x, 0.5 - p.y / size.y]);
    }

    for (var i = 0; i < outline.length; i++) {
      fv(Vector2.zero());
      fv(outline[i]);
      fv(outline[(i + 1) % outline.length]);
    }
    // The sides and back, shaded by which way each wall faces.
    final c = side ?? Vector3(0.13, 0.16, 0.3);
    final bp = <double>[], bc = <double>[];
    void bv(Vector2 p, double z, Vector3 col) {
      bp.addAll([p.x, p.y, z]);
      bc.addAll([col.x, col.y, col.z, 1]);
    }

    final light = Vector2(-0.35, 0.94).normalized();
    for (var i = 0; i < outline.length; i++) {
      final a = outline[i], b = outline[(i + 1) % outline.length];
      final n = Vector2(b.y - a.y, -(b.x - a.x))..normalize();
      final shade = c * (0.55 + 0.6 * math.max(0.0, n.dot(light)));
      final deep = shade * 0.6;
      bv(a, 0, shade);
      bv(b, 0, shade);
      bv(b, 1, deep);
      bv(a, 0, shade);
      bv(b, 1, deep);
      bv(a, 1, deep);
      // Back.
      final back = c * 0.35;
      bv(Vector2.zero(), 1, back);
      bv(b, 1, back);
      bv(a, 1, back);
    }
    Float32List normals(int n) {
      final out = Float32List(n);
      for (var k = 2; k < n; k += 3) {
        out[k] = -1;
      }
      return out;
    }

    node
      ..add(Node(
        mesh: Mesh(MeshGeometry.fromArrays(positions: Float32List.fromList(fp), normals: normals(fp.length), texCoords: Float32List.fromList(fu)), face),
      )..raycastable = false)
      ..add(Node(
        mesh: Mesh(MeshGeometry.fromArrays(positions: Float32List.fromList(bp), normals: normals(bp.length), colors: Float32List.fromList(bc)), body),
      )..raycastable = false);
    return Slab._(node, size);
  }

  final Node node;
  final Vector2 size;

  /// The rounded outline, counterclockwise, with [steps] segments per corner.
  static List<Vector2> _outline(double hx, double hy, double r, int steps) {
    final out = <Vector2>[];
    final corners = [(hx - r, hy - r, 0.0), (-hx + r, hy - r, math.pi / 2), (-hx + r, -hy + r, math.pi), (hx - r, -hy + r, math.pi * 1.5)];
    for (final (cx, cy, a0) in corners) {
      for (var k = 0; k <= steps; k++) {
        final a = a0 + k / steps * math.pi / 2;
        out.add(Vector2(cx + math.cos(a) * r, cy + math.sin(a) * r));
      }
    }
    return out;
  }
}
