import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Which surface a scenery material draws (see `assets/scenery.fmat`).
enum Finish { plain, planks, cobbles, grass, rug, plaster, stripes, rock, pathStones, plazaStones }

/// One scenery look: colors, a surface, and how it catches light.
class Look {
  const Look(this.surface, this.a, [this.b, this.c, this.scale = 1, this.rim = 0.15, this.gloss = 0, this.emissive = 0]);

  final Finish surface;
  final (double, double, double) a;
  final (double, double, double)? b;
  final (double, double, double)? c;
  final double scale;
  final double rim;
  final double gloss;
  final double emissive;
}

/// A point light for scenery: where it is, how far it reaches, its color
/// times intensity.
class SceneryLamp {
  SceneryLamp(this.position, this.range, this.color);
  Vector3 position;
  double range;
  Vector3 color;
}

/// Makes scenery materials and keeps their lighting in step: the sky, the
/// key light, and up to three lamps shared by every piece of a set.
class Scenery {
  final List<PreprocessedMaterial> _all = [];

  Vector3 keyDir = Vector3(-0.4, 0.8, -0.45);
  Vector3 keyColor = Vector3(0.55, 0.6, 0.85);
  Vector3 sky = Vector3(0.22, 0.26, 0.45);
  Vector3 ground = Vector3(0.12, 0.08, 0.08);

  /// Stylized lighting: a two-tone key and stronger rims, 0 to 1.
  double toon = 0;

  /// How much pieces darken toward the ground they stand on, 0 to 1.
  double ao = 0;
  final List<SceneryLamp> lamps = [];

  static Vector4 _v((double, double, double) c) => Vector4(c.$1, c.$2, c.$3, 1);

  /// Baked shadows on the ground, and the world rect they cover (x0, z0,
  /// 1 / size, strength); none until set.
  Texture2D? shade;
  Vector4 shadeRect = Vector4.zero();

  /// [center] places rings and stripes; [width] is a path strip's width,
  /// for stones laid along it.
  Future<PreprocessedMaterial> make(Look look, {Vector3? center, double width = 0}) async {
    final m = await loadFmatMaterial('assets/scenery.fmat');
    m.parameters
      ..setVec4('color_a', _v(look.a))
      ..setVec4('color_b', _v(look.b ?? look.a))
      ..setVec4('color_c', _v(look.c ?? look.a))
      ..setFloat('pattern', look.surface.index.toDouble())
      ..setFloat('scale', look.scale)
      ..setFloat('rim', look.rim)
      ..setFloat('gloss', look.gloss)
      ..setFloat('emissive', look.emissive)
      ..setVec4('center', Vector4(center?.x ?? 0, center?.y ?? 0, center?.z ?? 0, width));
    _all.add(m);
    _light(m);
    return m;
  }

  /// Makes every look at once.
  Future<List<PreprocessedMaterial>> makeAll(List<Look> looks) => Future.wait([for (final l in looks) make(l)]);

  void _light(PreprocessedMaterial m) {
    m.parameters
      ..setVec4('key_dir', Vector4(keyDir.x, keyDir.y, keyDir.z, 0))
      ..setVec4('key_color', Vector4(keyColor.x, keyColor.y, keyColor.z, 1))
      ..setVec4('sky_color', Vector4(sky.x, sky.y, sky.z, 1))
      ..setVec4('ground_color', Vector4(ground.x, ground.y, ground.z, 1))
      ..setFloat('toon', toon)
      ..setFloat('ao', ao)
      ..setVec4('shade_rect', shadeRect);
    final map = shade;
    if (map != null) m.parameters.setTexture('shade_map', map.gpuTexture, sampler: map.sampledSampler);
    for (var i = 0; i < 3; i++) {
      final l = i < lamps.length ? lamps[i] : null;
      m.parameters
        ..setVec4('lamp${i}_pos', l == null ? Vector4(0, 0, 0, 0) : Vector4(l.position.x, l.position.y, l.position.z, l.range))
        ..setVec4('lamp${i}_color', l == null ? Vector4.zero() : Vector4(l.color.x, l.color.y, l.color.z, 1));
    }
  }

  /// Pushes the current lights to every material (after moving a lamp).
  void relight() {
    for (final m in _all) {
      _light(m);
    }
  }
}
