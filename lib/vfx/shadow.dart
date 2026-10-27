import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// A soft pool of shadow under a friend: it tightens and darkens as the
/// friend comes down onto the floor and spreads and fades as it rises.
class ContactShadow {
  ContactShadow._(this.node, this._material);

  static Future<ContactShadow> create(Scene scene, {double opacity = 0.5}) async {
    final material = await loadFmatMaterial('assets/shadow.fmat');
    material.parameters.setFloat('opacity', opacity);
    final node = Node(name: 'ContactShadow', mesh: Mesh(PlaneGeometry(width: 1, depth: 1), material))..raycastable = false;
    scene.add(node);
    return ContactShadow._(node, material)..opacity = opacity;
  }

  final Node node;
  final PreprocessedMaterial _material;

  /// Darkness at rest, on the floor.
  double opacity = 0.5;

  /// Puts the shadow on the floor at [at] (the floor height is `at.y`), for
  /// something [radius] wide hovering [height] above it.
  void place(Vector3 at, {double radius = 0.5, double height = 0}) {
    final lift = (height / 1.2).clamp(0.0, 1.0);
    final size = radius * 2 * (1 + 0.5 * lift);
    node.localTransform = Matrix4.compose(at + Vector3(0, 0.004, 0), Quaternion.identity(), Vector3(size, 1, size));
    _material.parameters.setFloat('opacity', opacity * (1 - 0.7 * lift));
  }
}
