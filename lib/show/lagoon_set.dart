import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Where Lumi sits: the end of the pier, in world space.
final Vector3 kPierEnd = Vector3(0.3, 0.95, 4.0);

/// The lagoon at night: water, sky, the far shore with its towers, dome,
/// Ferris wheel, and coaster hill, a wooden pier, and every small light.
///
/// The audience looks along +Z, across the water toward the far shore about
/// 180 m away. Built from primitives so it stays easy to tune.
class LagoonSet {
  LagoonSet._(this.root, this.sky, this.water, this.dots, this.wheel, this.reflector);

  static Future<LagoonSet> build({double reflectionScale = 0.5}) async {
    final results = await Future.wait([
      loadFmatSky('assets/show/lagoon_sky.fmat'),
      loadFmatMaterial('assets/show/water.fmat'),
      loadFmatMaterial('assets/show/glow_dot.fmat'),
      loadFmatMaterial('assets/show/glow_dot.fmat'),
    ]);
    final sky = results[0] as PreprocessedSky;
    final water = results[1] as PreprocessedMaterial;
    final dotMat = results[2] as PreprocessedMaterial;
    final wheelDotMat = results[3] as PreprocessedMaterial;

    final root = Node(name: 'Lagoon');
    final rng = math.Random(21);

    // ---------------------------------------------------------------- water
    final reflector = reflectionScale > 0 ? PlanarReflectorComponent(resolutionScale: reflectionScale) : null;
    final waterNode = Node(
      name: 'Water',
      mesh: Mesh(PlaneGeometry(width: 900, depth: 900), water),
      localTransform: Matrix4.translation(Vector3(0, 0, 200)),
    )..raycastable = false;
    if (reflector != null) waterNode.addComponent(reflector);
    root.add(waterNode);

    // ---------------------------------------------------------------- shore
    final silhouette = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(0.012, 0.014, 0.03, 1)
      ..roughnessFactor = 0.9
      ..metallicFactor = 0;
    void solid(Geometry g, Matrix4 m) => root.add(Node(mesh: Mesh(g, silhouette), localTransform: m)..raycastable = false);

    solid(CuboidGeometry(Vector3(800, 2.8, 24)), Matrix4.translation(Vector3(0, 1.0, 186)));
    final dots = _DotBatch(dotMat);
    for (final (x, r, h) in const [(-28.0, 2.6, 22.0), (-21.0, 1.8, 15.0), (14.0, 3.2, 26.0), (22.0, 2.0, 17.0), (38.0, 2.4, 12.0), (-40.0, 2.2, 10.0), (55.0, 1.6, 9.0), (-62.0, 3.0, 8.0)]) {
      solid(CylinderGeometry(bottomRadius: r, topRadius: r, height: h, radialSegments: 20), Matrix4.translation(Vector3(x, h / 2, 182)));
      solid(
        CylinderGeometry(bottomRadius: r * 1.25, topRadius: 0, height: r * 2.6, radialSegments: 20),
        Matrix4.translation(Vector3(x, h + r * 1.3, 182)),
      );
      // Lit windows on the side facing the water.
      for (var k = 0; k < (h / 3).floor(); k++) {
        if (rng.nextDouble() < 0.5) continue;
        final a = rng.nextDouble() * 2 - 1;
        dots.add(
          Vector3(x + math.sin(a) * r, 2 + k * 3.0, 182 - math.cos(a) * r),
          0.24,
          Vector3(1.0, 0.72, 0.4),
          5.0,
          twinkle: 0.15,
        );
      }
    }
    solid(SphereGeometry(radius: 9, segments: 40, rings: 20), Matrix4.compose(Vector3(2, 0, 186), Quaternion.identity(), Vector3(1.4, 0.75, 1)));

    // Coaster lift hill: short tubes along the curve.
    Vector3 coaster(double t) =>
        Vector3(55 + t * 1.2, 2 + 22 * math.sin(math.min(t / 12, 1) * math.pi / 2) - math.pow(math.max(0, t - 12), 1.6) * 0.9, 179);
    for (var i = 0; i < 25; i++) {
      final a = coaster(i.toDouble()), b = coaster(i + 1.0);
      final mid = (a + b) * 0.5;
      final d = b - a;
      final q = Quaternion.fromTwoVectors(Vector3(0, 1, 0), d.normalized());
      solid(CylinderGeometry(bottomRadius: 0.35, topRadius: 0.35, height: d.length, radialSegments: 8), Matrix4.compose(mid, q, Vector3.all(1)));
    }

    // String lights along the shore and on the far boardwalk.
    for (var i = 0; i < 140; i++) {
      final x = -120 + i * 1.75;
      dots.add(Vector3(x, 2.6 + 0.6 * math.pow(math.sin(i * 0.45), 2), 176), 0.2, Vector3(1.0, 0.72, 0.42), 6.0, twinkle: 0.2);
    }
    // Lights behind the audience, which become soft bokeh in the close-up.
    for (var i = 0; i < 60; i++) {
      final x = -40 + i * 1.4;
      final warm = i % 3 != 0;
      dots.add(
        Vector3(x, 2.2 + 0.5 * math.sin(i * 0.7), -38 - (i % 4) * 0.8),
        0.18,
        warm ? Vector3(1.0, 0.7, 0.4) : Vector3(0.6, 0.75, 1.0),
        5.0,
        twinkle: 0.15,
      );
    }

    // ---------------------------------------------------------------- wheel
    final wheel = Node(name: 'FerrisWheel', localTransform: Matrix4.translation(Vector3(-58, 18, 180)));
    final wheelSpin = Node(name: 'WheelSpin');
    wheel.add(wheelSpin);
    root.add(wheel);
    wheelSpin.add(
      Node(
        mesh: Mesh(TorusGeometry(radius: 13, tubeRadius: 0.35, radialSegments: 64, tubularSegments: 8), silhouette),
        localTransform: Matrix4.rotationX(math.pi / 2),
      )..raycastable = false,
    );
    for (var i = 0; i < 8; i++) {
      wheelSpin.add(
        Node(
          mesh: Mesh(CylinderGeometry(bottomRadius: 0.12, topRadius: 0.12, height: 26, radialSegments: 6), silhouette),
          localTransform: Matrix4.rotationZ(i / 8 * math.pi),
        )..raycastable = false,
      );
    }
    for (final s in const [-1.0, 1.0]) {
      wheel.add(
        Node(
          mesh: Mesh(CylinderGeometry(bottomRadius: 0.4, topRadius: 0.4, height: 21, radialSegments: 8), silhouette),
          localTransform: Matrix4.compose(Vector3(s * 5, -9, 0.6), Quaternion.axisAngle(Vector3(0, 0, 1), s * 0.25), Vector3.all(1)),
        )..raycastable = false,
      );
    }
    final wheelDots = _DotBatch(wheelDotMat);
    const beadColors = [(1.0, 0.45, 0.6), (0.5, 0.75, 1.0), (1.0, 0.8, 0.4)];
    for (var i = 0; i < 32; i++) {
      final a = i / 32 * math.pi * 2;
      final c = beadColors[i % 3];
      wheelDots.add(Vector3(math.cos(a) * 13, math.sin(a) * 13, -0.4), 0.32, Vector3(c.$1, c.$2, c.$3), 8.0, twinkle: 0.1);
    }
    wheelSpin.add(wheelDots.build('WheelBeads'));

    // ---------------------------------------------------------------- pier
    final wood = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(0.09, 0.055, 0.035, 1)
      ..roughnessFactor = 0.75
      ..metallicFactor = 0;
    void woodPiece(Geometry g, Matrix4 m) => root.add(Node(mesh: Mesh(g, wood), localTransform: m)..raycastable = false);
    final plank = CuboidGeometry(Vector3(3.2, 0.1, 0.44));
    for (var i = 0; i < 30; i++) {
      woodPiece(plank, Matrix4.translation(Vector3(0.3, 0.86, -10 + i * 0.5)));
    }
    final post = CylinderGeometry(bottomRadius: 0.14, topRadius: 0.14, height: 3.2, radialSegments: 10);
    final railPost = CylinderGeometry(bottomRadius: 0.08, topRadius: 0.08, height: 1.1, radialSegments: 8);
    for (var z = -10.0; z <= 5; z += 3) {
      for (final x in const [-1.25, 1.85]) {
        woodPiece(post, Matrix4.translation(Vector3(x, -0.6, z)));
        woodPiece(railPost, Matrix4.translation(Vector3(x, 1.35, z)));
      }
    }
    for (final x in const [-1.25, 1.85]) {
      woodPiece(CuboidGeometry(Vector3(0.12, 0.1, 15.2)), Matrix4.translation(Vector3(x, 1.88, -2.5)));
      for (var k = 0; k < 12; k++) {
        dots.add(Vector3(x, 1.98, -9.5 + k * 1.25), 0.03, Vector3(1.0, 0.7, 0.4), 2.2, twinkle: 0.25);
      }
    }
    root.add(dots.build('SetLights'));

    // A faint warm light from the rail lanterns so the wood reads.
    root.add(
      Node(name: 'PierGlow', localTransform: Matrix4.translation(Vector3(0.3, 2.6, 2.0)))
        ..addComponent(PointLightComponent(PointLight(color: Vector3(1.0, 0.65, 0.35), intensity: 6, range: 12))),
    );

    return LagoonSet._(root, sky, water, [dotMat, wheelDotMat], wheelSpin, reflector);
  }

  final Node root;
  final PreprocessedSky sky;
  final PreprocessedMaterial water;
  final List<PreprocessedMaterial> dots;
  final Node wheel;
  final PlanarReflectorComponent? reflector;

  /// Advances the set's own motion: twinkles, the turning wheel, ripples.
  void update(double t) {
    sky.parameters.setFloat('time', t);
    water.parameters.setFloat('time', t);
    for (final d in dots) {
      d.parameters.setFloat('time', t);
    }
    wheel.localTransform = Matrix4.rotationZ(t * 0.05);
  }

  /// Lights the sky around the brightest burst.
  void setFlash(Vector3 direction, Vector3 color, double strength) {
    sky.parameters
      ..setVec4('flash_dir', Vector4(direction.x, direction.y, direction.z, strength))
      ..setVec4('flash_color', Vector4(color.x, color.y, color.z, 0));
  }

  /// Dims the town lights (during the finale the sky should win).
  set townLights(double v) {
    for (final d in dots) {
      d.parameters.setFloat('master', v);
    }
  }
}

/// Collects small glowing spheres into one instanced draw.
class _DotBatch {
  _DotBatch(this.material);
  final PreprocessedMaterial material;
  final List<(Vector3, double, Vector3, double, double)> _dots = [];
  final _rng = math.Random(5);

  void add(Vector3 p, double radius, Vector3 color, double brightness, {double twinkle = 0}) {
    _dots.add((p, radius, color, brightness, twinkle));
  }

  Node build(String name) {
    final mesh = InstancedMesh(geometry: SphereGeometry(radius: 1, segments: 10, rings: 6), material: material);
    for (var i = 0; i < _dots.length; i++) {
      final (p, r, c, b, tw) = _dots[i];
      mesh.addInstance(Matrix4.compose(p, Quaternion.identity(), Vector3.all(r)));
      mesh.setInstanceAttribute(i, 'tint', Vector4(c.x, c.y, c.z, b));
      mesh.setInstanceAttribute(i, 'twinkle', Vector4(1.5 + _rng.nextDouble() * 3, tw, _rng.nextDouble() * 6.28, 0));
    }
    return Node(name: name)
      ..raycastable = false
      ..addComponent(InstancedMeshComponent(mesh));
  }
}
