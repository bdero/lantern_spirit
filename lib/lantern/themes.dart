import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show HSVColor;

import 'package:vector_math/vector_math.dart';

/// A color skin for the character. Every value is a material parameter, so a
/// theme change is a parameter ease, not a new asset.
class LanternTheme {
  const LanternTheme({
    required this.name,
    required this.skin,
    required this.rim,
    required this.inner,
    required this.emberColor,
    required this.translucency,
    required this.swatch,
    required this.sky,
  });

  final String name;
  final Color skin;
  final Color rim;
  final Color inner;
  final Color emberColor;
  final double translucency;

  /// The chip shown in the theme picker.
  final Color swatch;

  /// Top and bottom of the header behind the character.
  final List<Color> sky;

  static const aurora = LanternTheme(
    name: 'Aurora',
    skin: Color(0xFF6FB8FF),
    rim: Color(0xFF8FD9FF),
    inner: Color(0xFFB59BFF),
    emberColor: Color(0xFFFF9A3D),
    translucency: 0.0,
    swatch: Color(0xFF73C7FF),
    sky: [Color(0xFF0B1433), Color(0xFF1B2552)],
  );

  static const ember = LanternTheme(
    name: 'Ember',
    skin: Color(0xFFFF7A4D),
    rim: Color(0xFFFFB070),
    inner: Color(0xFFFF5C8A),
    emberColor: Color(0xFFFF4F9A),
    translucency: 0.0,
    swatch: Color(0xFFFF8A5C),
    sky: [Color(0xFF240C1A), Color(0xFF3D1426)],
  );

  static const ghost = LanternTheme(
    name: 'Ghost',
    skin: Color(0xFFBDF2E4),
    rim: Color(0xFF9DFFDB),
    inner: Color(0xFF7DE8FF),
    emberColor: Color(0xFF7DFFC4),
    translucency: 0.45,
    swatch: Color(0xFFC6F5EA),
    sky: [Color(0xFF06201F), Color(0xFF0C3434)],
  );

  static const all = [aurora, ember, ghost];
}

/// The theme's colors as linear vectors, eased toward a target each frame.
class ThemeColors {
  /// The theme's colors, with every hue turned by [hueShift] degrees.
  ThemeColors.from(LanternTheme t, {double hueShift = 0})
    : skin = linear(_turn(t.skin, hueShift)),
      rim = linear(_turn(t.rim, hueShift)),
      inner = linear(_turn(t.inner, hueShift)),
      ember = linear(_turn(t.emberColor, hueShift)),
      translucency = t.translucency;

  static Color _turn(Color c, double degrees) {
    if (degrees == 0) return c;
    final hsv = HSVColor.fromColor(c);
    return hsv.withHue((hsv.hue + degrees) % 360).toColor();
  }

  final Vector4 skin;
  final Vector4 rim;
  final Vector4 inner;
  final Vector4 ember;
  double translucency;

  /// Moves every channel a fraction [k] of the way toward [target].
  void approach(ThemeColors target, double k) {
    skin.add((target.skin - skin)..scale(k));
    rim.add((target.rim - rim)..scale(k));
    inner.add((target.inner - inner)..scale(k));
    ember.add((target.ember - ember)..scale(k));
    translucency += (target.translucency - translucency) * k;
  }

  static Vector4 linear(Color c) {
    double lin(double v) => v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return Vector4(lin(c.r), lin(c.g), lin(c.b), 1.0);
  }
}
