import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'palette.dart';

/// A notification as a real object: a slab with a little thickness, the
/// notification drawn on its face, that can have bites taken out of it.
///
/// The outline is a signed distance field (a rounded rectangle, minus each
/// bite) and the mesh is rebuilt from it after every bite: marching squares
/// fill the face and the back, and the outline is extruded into side walls.
/// The walls along a bite glow gold, the light inside showing through.
///
/// Local space: x along the width (+x toward the screen's right), y up, the
/// face toward the camera at -z.
class NotificationSnack {
  NotificationSnack._(this.node, this._face, this._edge, this.width, this.height, this.thickness);

  /// Draws [title] and [body] onto a face texture and builds the slab.
  static Future<NotificationSnack> create(String title, String body, {double width = 1.7}) async {
    const logical = Size(210, 58);
    final height = width * logical.height / logical.width;
    final image = await _drawFace(title, body, logical, 5);
    final texture = await Texture2D.fromImage(image);
    final face = UnlitMaterial(colorTexture: texture)..doubleSided = true;
    final edge = UnlitMaterial()..doubleSided = true;
    final node = Node(name: 'NotificationSnack')..raycastable = false;
    final snack = NotificationSnack._(node, face, edge, width, height, width * 0.045);
    snack._rebuild();
    return snack;
  }

  final Node node;
  final UnlitMaterial _face;
  final UnlitMaterial _edge;
  final double width;
  final double height;
  final double thickness;

  final List<_Bite> _bites = [];

  /// How many bites have been taken.
  int get bites => _bites.length;

  /// Takes a bite centered at [at] (local x, y) with radius [radius]: a ring
  /// of tooth marks around a round hole, facing back toward the middle.
  void bite(vm.Vector2 at, double radius) {
    final inward = (-at).normalized();
    final teeth = <(vm.Vector2, double)>[(at.clone(), radius * 0.74)];
    // Teeth along the inner side of the bite leave a scalloped edge.
    for (var i = 0; i < 5; i++) {
      final a = math.atan2(inward.y, inward.x) + (i / 4 - 0.5) * 2.3;
      teeth.add((at + vm.Vector2(math.cos(a), math.sin(a)) * (radius * 0.7), radius * 0.3));
    }
    _bites.add(_Bite(teeth));
    _rebuild();
  }

  /// Signed distance to the remaining outline (negative inside).
  double distance(double x, double y) {
    final d = _rect(x, y);
    final b = _biteDistance(x, y);
    return math.max(d, -b);
  }

  /// The leftmost and rightmost solid points along the row at [y], or null
  /// if the row is all eaten: where the hands can still hold on.
  (double, double)? span(double y) {
    double? lo, hi;
    const steps = 120;
    for (var i = 0; i <= steps; i++) {
      final x = -width / 2 + width * i / steps;
      if (distance(x, y) < -0.01) {
        lo ??= x;
        hi = x;
      }
    }
    return lo == null ? null : (lo, hi!);
  }

  /// Where it is still solid, the point nearest [p] (local x, y).
  vm.Vector2 nearestSolid(vm.Vector2 p) {
    var best = vm.Vector2.zero();
    var bestD = double.infinity;
    for (var i = 0; i <= 40; i++) {
      for (var j = 0; j <= 12; j++) {
        final x = -width / 2 + width * i / 40;
        final y = -height / 2 + height * j / 12;
        if (distance(x, y) > -0.02) continue;
        final d = (vm.Vector2(x, y) - p).length2;
        if (d < bestD) {
          bestD = d;
          best = vm.Vector2(x, y);
        }
      }
    }
    return best;
  }

  double _rect(double x, double y) {
    final r = height * 0.26;
    final qx = x.abs() - (width / 2 - r);
    final qy = y.abs() - (height / 2 - r);
    final ox = math.max(qx, 0.0), oy = math.max(qy, 0.0);
    return math.sqrt(ox * ox + oy * oy) + math.min(math.max(qx, qy), 0.0) - r;
  }

  double _biteDistance(double x, double y) {
    var d = double.infinity;
    for (final b in _bites) {
      for (final (c, r) in b.circles) {
        final dx = x - c.x, dy = y - c.y;
        d = math.min(d, math.sqrt(dx * dx + dy * dy) - r);
      }
    }
    return d;
  }

  // ------------------------------------------------------------- meshing
  void _rebuild() {
    const nx = 150, ny = 44;
    final x0 = -width / 2 - 0.02, y0 = -height / 2 - 0.02;
    final dx = (width + 0.04) / nx, dy = (height + 0.04) / ny;
    final sdf = Float64List((nx + 1) * (ny + 1));
    for (var j = 0; j <= ny; j++) {
      for (var i = 0; i <= nx; i++) {
        sdf[j * (nx + 1) + i] = distance(x0 + i * dx, y0 + j * dy);
      }
    }

    final facePos = <double>[], faceUv = <double>[];
    final edgePos = <double>[], edgeCol = <double>[];
    final zf = -thickness / 2, zb = thickness / 2;
    // Fake light for the unlit walls: brighter facing up and to the left.
    final light = vm.Vector2(0.35, 0.94).normalized();
    final rim = vm.Vector3(0.24, 0.29, 0.52);
    final glow = vm.Vector3(2.1, 1.55, 0.6);
    final back = vm.Vector3(0.05, 0.06, 0.14);

    void facePoint(double x, double y) {
      facePos.addAll([x, y, zf]);
      faceUv.addAll([0.5 + x / width, 0.5 - y / height]);
    }

    void edgePoint(double x, double y, double z, vm.Vector3 c) {
      edgePos.addAll([x, y, z]);
      edgeCol.addAll([c.x, c.y, c.z, 1]);
    }

    for (var j = 0; j < ny; j++) {
      for (var i = 0; i < nx; i++) {
        // Corners counterclockwise, with the edge crossings between them.
        final cx = [i, i + 1, i + 1, i], cy = [j, j, j + 1, j + 1];
        final v = [for (var k = 0; k < 4; k++) sdf[cy[k] * (nx + 1) + cx[k]]];
        if (v.every((d) => d >= 0)) continue;
        final poly = <(double, double, bool)>[];
        for (var k = 0; k < 4; k++) {
          final ax = x0 + cx[k] * dx, ay = y0 + cy[k] * dy;
          if (v[k] < 0) poly.add((ax, ay, false));
          final n = (k + 1) % 4;
          if ((v[k] < 0) != (v[n] < 0)) {
            final t = v[k] / (v[k] - v[n]);
            final bx = x0 + cx[n] * dx, by = y0 + cy[n] * dy;
            poly.add((ax + (bx - ax) * t, ay + (by - ay) * t, true));
          }
        }
        // Face and back: a fan over the cell's solid part.
        for (var k = 1; k + 1 < poly.length; k++) {
          for (final p in [poly[0], poly[k], poly[k + 1]]) {
            facePoint(p.$1, p.$2);
          }
          for (final p in [poly[0], poly[k + 1], poly[k]]) {
            edgePoint(p.$1, p.$2, zb, back);
          }
        }
        // Walls: wherever two crossings sit next to each other on the
        // polygon, the outline runs between them.
        for (var k = 0; k < poly.length; k++) {
          final a = poly[k], b = poly[(k + 1) % poly.length];
          if (!a.$3 || !b.$3) continue;
          final mx = (a.$1 + b.$1) / 2, my = (a.$2 + b.$2) / 2;
          final gx = distance(mx + 1e-3, my) - distance(mx - 1e-3, my);
          final gy = distance(mx, my + 1e-3) - distance(mx, my - 1e-3);
          final normal = vm.Vector2(gx, gy)..normalize();
          final bitten = _biteDistance(mx, my).abs() < dx * 1.5;
          final shade = 0.55 + 0.45 * math.max(0.0, normal.dot(light));
          final c = bitten ? glow * (0.75 + 0.25 * shade) : rim * shade;
          edgePoint(a.$1, a.$2, zf, c);
          edgePoint(b.$1, b.$2, zf, c);
          edgePoint(b.$1, b.$2, zb, c * 0.8);
          edgePoint(a.$1, a.$2, zf, c);
          edgePoint(b.$1, b.$2, zb, c * 0.8);
          edgePoint(a.$1, a.$2, zb, c * 0.8);
          if (bitten) {
            // A thin glowing lip on the face along the bite, so it reads
            // even straight on.
            final ix = -normal.x * 0.022, iy = -normal.y * 0.022;
            final z = zf - 0.002;
            final lip = glow * 0.9;
            edgePoint(a.$1, a.$2, z, lip);
            edgePoint(b.$1, b.$2, z, lip);
            edgePoint(b.$1 + ix, b.$2 + iy, z, lip * 0.15);
            edgePoint(a.$1, a.$2, z, lip);
            edgePoint(b.$1 + ix, b.$2 + iy, z, lip * 0.15);
            edgePoint(a.$1 + ix, a.$2 + iy, z, lip * 0.15);
          }
        }
      }
    }

    node.children.toList().forEach(node.remove);
    if (facePos.isEmpty) return;
    final faceN = Float32List(facePos.length);
    for (var k = 2; k < faceN.length; k += 3) {
      faceN[k] = -1;
    }
    node.add(Node(
      mesh: Mesh(
        MeshGeometry.fromArrays(positions: Float32List.fromList(facePos), normals: faceN, texCoords: Float32List.fromList(faceUv)),
        _face,
      ),
    )..raycastable = false);
    final edgeN = Float32List(edgePos.length);
    for (var k = 2; k < edgeN.length; k += 3) {
      edgeN[k] = 1;
    }
    node.add(Node(
      mesh: Mesh(
        MeshGeometry.fromArrays(positions: Float32List.fromList(edgePos), normals: edgeN, colors: Float32List.fromList(edgeCol)),
        _edge,
      ),
    )..raycastable = false);
  }

  // ------------------------------------------------------------- texture
  static Future<ui.Image> _drawFace(String title, String body, Size size, double scale) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF182041));
    // A soft top sheen and a hairline border, like the toast in the app.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [const Color(0x223A4A80), const Color(0x00000000)]),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(14)),
      Paint()
        ..color = const Color(0x803A4A80)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    void text(String s, Offset at, TextStyle style, double maxWidth) {
      final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, maxLines: 2)..layout(maxWidth: maxWidth);
      tp.paint(canvas, at);
    }

    const icon = Icons.notifications_rounded;
    text(
      String.fromCharCode(icon.codePoint),
      const Offset(12, 19),
      TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: 18, color: Park.gold),
      30,
    );
    text(title, const Offset(38, 9), const TextStyle(color: Park.ink, fontWeight: FontWeight.w800, fontSize: 13), size.width - 50);
    text(body, const Offset(38, 26), const TextStyle(color: Park.inkMuted, fontSize: 12, height: 1.2), size.width - 50);
    final picture = recorder.endRecording();
    return picture.toImage((size.width * scale).round(), (size.height * scale).round());
  }
}

class _Bite {
  _Bite(this.circles);
  final List<(vm.Vector2, double)> circles;
}
