import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// How a shell breaks.
enum BurstKind { peony, chrysanthemum, willow, ring, palm, crossette, crackle }

/// The physical character of each kind of break.
class BurstStyle {
  const BurstStyle({
    required this.count,
    required this.speed,
    required this.drag,
    required this.gravity,
    required this.life,
    required this.trail,
    required this.width,
    this.glitter = 0,
    this.strobe = false,
    this.split = 0,
    this.brightness = 1.0,
  });

  /// Stars thrown at the break.
  final int count;

  /// Launch speed of the stars, in meters per second.
  final double speed;

  /// Air drag (per second); higher stops the stars sooner.
  final double drag;

  /// Downward pull, in meters per second squared.
  final double gravity;

  /// How long a star burns, in seconds.
  final double life;

  /// How long a star's trail is, in seconds of its past path.
  final double trail;

  /// Trail width at the head, in meters.
  final double width;

  /// Glints per star that flicker along its trail.
  final int glitter;

  /// Stars strobe on and off instead of burning steadily.
  final bool strobe;

  /// Seconds after the break when each star splits in four (0: never).
  final double split;

  final double brightness;

  static const styles = {
    BurstKind.peony: BurstStyle(count: 150, speed: 30, drag: 1.6, gravity: 4, life: 1.5, trail: 0.12, width: 0.42),
    BurstKind.chrysanthemum: BurstStyle(
      count: 130,
      speed: 31,
      drag: 1.5,
      gravity: 5,
      life: 1.9,
      trail: 0.55,
      width: 0.34,
    ),
    BurstKind.willow: BurstStyle(
      count: 90,
      speed: 19,
      drag: 0.85,
      gravity: 10,
      life: 4.2,
      trail: 1.6,
      width: 0.28,
      glitter: 2,
      brightness: 0.9,
    ),
    BurstKind.ring: BurstStyle(count: 56, speed: 26, drag: 1.4, gravity: 3, life: 1.6, trail: 0.3, width: 0.45),
    BurstKind.palm: BurstStyle(
      count: 11,
      speed: 24,
      drag: 1.0,
      gravity: 8,
      life: 2.6,
      trail: 1.0,
      width: 0.8,
      glitter: 4,
      brightness: 1.2,
    ),
    BurstKind.crossette: BurstStyle(
      count: 16,
      speed: 26,
      drag: 1.2,
      gravity: 6,
      life: 2.0,
      trail: 0.35,
      width: 0.42,
      split: 0.55,
    ),
    BurstKind.crackle: BurstStyle(
      count: 110,
      speed: 14,
      drag: 2.2,
      gravity: 3,
      life: 0.9,
      trail: 0,
      width: 0.16,
      strobe: true,
      brightness: 1.3,
    ),
  };
}

/// One shell in the show.
class Launch {
  Launch({
    required this.time,
    required this.pad,
    required this.breakAt,
    required this.kind,
    required this.color,
    this.pistil,
    this.size = 1.0,
    this.ascent = 2.0,
    this.ringTilt = 0.0,
    this.main = false,
    int? seed,
  }) : seed = seed ?? (time * 1000).round() ^ breakAt.x.round() * 7919;

  /// When the shell leaves the mortar, in show seconds.
  final double time;

  /// Where it launches from, on the water.
  final Vector3 pad;

  /// Where it breaks.
  final Vector3 breakAt;
  final BurstKind kind;

  /// The star color, linear.
  final Vector3 color;

  /// An optional inner sphere of a second color.
  final Vector3? pistil;

  /// Scales star speed (the burst's spread) and width.
  final double size;

  /// Seconds from launch to the top of the climb.
  final double ascent;

  /// Tilt of a ring burst away from facing the audience, in radians.
  final double ringTilt;

  /// A finale main: heavier sound, a little camera shake.
  final bool main;
  final int seed;

  /// The short hang at the top of the climb before the break.
  static const hang = 0.14;

  double get breakTime => time + ascent + hang;
  BurstStyle get style => BurstStyle.styles[kind]!;

  /// When this shell's light is entirely gone.
  double get endTime => breakTime + style.life + style.split + style.trail + 0.2;

  List<_Star>? _stars;
}

class _Star {
  _Star(this.vx, this.vy, this.vz, this.life, this.seed, this.r, this.g, this.b, this.speedScale);
  final double vx, vy, vz, life;
  final int seed;
  final double r, g, b;
  final double speedScale;
  List<_Star>? children;
}

/// A light a burst throws on its surroundings this frame.
class BurstLight {
  BurstLight(this.position, this.color, this.intensity, this.launch);
  final Vector3 position;
  final Vector3 color;

  /// Relative brightness, about 1 at a big break's flash.
  final double intensity;
  final Launch launch;
}

/// Simulates the fireworks in closed form and writes them into two dynamic
/// meshes: additive light (trails, heads, shell tails, glitter) and
/// alpha-blended smoke.
///
/// Every position is a direct function of show time, so evaluating any
/// moment (playing, paused, or scrubbed) costs the same and always matches.
class FireworkRenderer {
  FireworkRenderer({required Material lightMaterial, required Material smokeMaterial, this.trailSamples = 8}) {
    lightNode = Node(name: 'FireworkLight', mesh: Mesh(_light.geometry, lightMaterial))..raycastable = false;
    smokeNode = Node(name: 'FireworkSmoke', mesh: Mesh(_smoke.geometry, smokeMaterial))..raycastable = false;
  }

  late final Node lightNode;
  late final Node smokeNode;
  final _DynamicMesh _light = _DynamicMesh(60000);
  final _DynamicMesh _smoke = _DynamicMesh(4000);

  /// Points sampled along each trail. Fewer is cheaper.
  int trailSamples;

  /// The wind carrying the smoke, in meters per second.
  final Vector3 wind = Vector3(1.4, 0.12, 0.3);

  /// Lights from every burst burning at the last evaluated time.
  final List<BurstLight> lights = [];

  // Camera basis for billboards, refreshed each evaluate.
  double _cx = 0, _cy = 0, _cz = 0;

  /// Builds the frame for show time [t] seen from [camera].
  void evaluate(List<Launch> launches, double t, Vector3 camera) {
    _cx = camera.x;
    _cy = camera.y;
    _cz = camera.z;
    _light.begin();
    _smoke.begin();
    lights.clear();
    for (final l in launches) {
      if (t < l.time) continue;
      if (t < l.breakTime) {
        _shell(l, t);
        continue;
      }
      final a = t - l.breakTime;
      if (a <= l.endTime - l.breakTime) _burst(l, a, t);
    }
    // Smoke outlives the light by a long way.
    for (final l in launches) {
      if (t < l.breakTime || t > l.breakTime + 20) continue;
      _smokeFor(l, t - l.breakTime);
    }
    _light.commit();
    _smoke.commit();
  }

  // ---------------------------------------------------------------- shells
  void _shellPos(Launch l, double tau, List<double> out) {
    final x = (tau / l.ascent).clamp(0.0, 1.0);
    // Fast off the mortar, easing into the hang at the top.
    final e = 1 - (1 - x) * (1 - x) * (1 - x);
    final curl = math.sin(math.pi * x) * (1 - x) * 1.6 * ((l.seed & 1) == 0 ? 1 : -1);
    out[0] = l.pad.x + (l.breakAt.x - l.pad.x) * e + curl;
    out[1] = l.pad.y + (l.breakAt.y - l.pad.y) * e;
    out[2] = l.pad.z + (l.breakAt.z - l.pad.z) * e;
  }

  void _shell(Launch l, double t) {
    final age = t - l.time;
    const tail = 0.45;
    final n = trailSamples;
    final pts = Float64List(n * 3);
    final tmp = [0.0, 0.0, 0.0];
    final cols = Float64List(n * 4);
    for (var j = 0; j < n; j++) {
      final f = j / (n - 1);
      final tau = math.max(0.0, age - tail * (1 - f));
      _shellPos(l, tau, tmp);
      pts[j * 3] = tmp[0];
      pts[j * 3 + 1] = tmp[1];
      pts[j * 3 + 2] = tmp[2];
      cols[j * 4] = 1.0;
      cols[j * 4 + 1] = 0.72;
      cols[j * 4 + 2] = 0.42;
      cols[j * 4 + 3] = 2.2 * f;
    }
    _strip(pts, cols, n, 0.22);
    final hx = pts[(n - 1) * 3], hy = pts[(n - 1) * 3 + 1], hz = pts[(n - 1) * 3 + 2];
    // The shell's own glow fades as it slows into the hang.
    final glow = 1.0 - 0.6 * (age / (l.ascent + Launch.hang)).clamp(0.0, 1.0);
    _quad(hx, hy, hz, 0.7, 1.0, 0.86, 0.62, 3.5 * glow);
  }

  // ---------------------------------------------------------------- bursts
  List<_Star> _starsOf(Launch l) {
    final cached = l._stars;
    if (cached != null) return cached;
    final s = l.style;
    final rng = math.Random(l.seed);
    final stars = <_Star>[];
    void add(Vector3 dir, double speed, Vector3 col, double lifeScale) {
      final v = speed * (0.9 + 0.2 * rng.nextDouble());
      stars.add(
        _Star(
          dir.x * v,
          dir.y * v,
          dir.z * v,
          s.life * lifeScale * (0.85 + 0.3 * rng.nextDouble()),
          rng.nextInt(1 << 30),
          col.x,
          col.y,
          col.z,
          v / s.speed,
        ),
      );
    }

    final speed = s.speed * l.size;
    if (l.kind == BurstKind.ring) {
      // A circle facing the audience (the camera looks along +Z), tilted.
      final n = Vector3(0, math.sin(l.ringTilt), -math.cos(l.ringTilt)).normalized();
      final u = Vector3(1, 0, 0);
      final w = n.cross(u).normalized();
      for (var i = 0; i < s.count; i++) {
        final a = i / s.count * math.pi * 2;
        add((u * math.cos(a) + w * math.sin(a)).normalized(), speed, l.color, 1);
      }
    } else if (l.kind == BurstKind.crackle) {
      for (var i = 0; i < s.count; i++) {
        final d = _randomDir(rng);
        add(d, speed * (0.25 + 0.75 * math.pow(rng.nextDouble(), 0.5)), l.color, 0.6 + 0.6 * rng.nextDouble());
      }
    } else {
      final dirs = _fibonacciSphere(s.count, rng, 0.07);
      for (final d in dirs) {
        add(d, speed, l.color, 1);
      }
    }
    final pistil = l.pistil;
    if (pistil != null) {
      final dirs = _fibonacciSphere((s.count * 0.4).round(), rng, 0.08);
      for (final d in dirs) {
        add(d, speed * 0.45, pistil, 0.8);
      }
    }
    if (s.split > 0) {
      for (final star in stars) {
        // Four children thrown sideways from the split point.
        final v = Vector3(star.vx, star.vy, star.vz)..normalize();
        final side = v.cross(Vector3(0, 1, 0.3)).normalized();
        final up = v.cross(side).normalized();
        star.children = [
          for (var k = 0; k < 4; k++)
            _Star(
              ((side * math.cos(k * math.pi / 2) + up * math.sin(k * math.pi / 2)) * (speed * 0.35)).x,
              ((side * math.cos(k * math.pi / 2) + up * math.sin(k * math.pi / 2)) * (speed * 0.35)).y,
              ((side * math.cos(k * math.pi / 2) + up * math.sin(k * math.pi / 2)) * (speed * 0.35)).z,
              s.life * 0.7,
              star.seed + k,
              star.r,
              star.g,
              star.b,
              0.6,
            ),
        ];
      }
    }
    l._stars = stars;
    return stars;
  }

  /// Position of a star [a] seconds after its break, from [ox, oy, oz] with
  /// initial velocity v, under linear drag and gravity.
  static void _starPos(
    double ox,
    double oy,
    double oz,
    double vx,
    double vy,
    double vz,
    double k,
    double g,
    double a,
    List<double> out,
  ) {
    final e = (1 - math.exp(-k * a)) / k;
    out[0] = ox + vx * e;
    out[1] = oy + vy * e - g * (a - e) / k;
    out[2] = oz + vz * e;
  }

  static void _starVel(double vx, double vy, double vz, double k, double g, double a, List<double> out) {
    final d = math.exp(-k * a);
    out[0] = vx * d;
    out[1] = vy * d - g * (1 - d) / k;
    out[2] = vz * d;
  }

  void _burst(Launch l, double a, double t) {
    final s = l.style;
    final stars = _starsOf(l);
    final n = s.trail > 0 ? trailSamples : 1;
    final pts = Float64List(n * 3);
    final cols = Float64List(n * 4);
    final tmp = [0.0, 0.0, 0.0];
    final vtmp = [0.0, 0.0, 0.0];
    final width = s.width * math.sqrt(l.size);
    final bx = l.breakAt.x, by = l.breakAt.y, bz = l.breakAt.z;

    void drawStar(_Star st, double ox, double oy, double oz, double age, double w) {
      if (age <= 0 || age > st.life + s.trail) return;
      final strobeOn = !s.strobe || _hash(st.seed, (t * 22).floor()) > 0.45;
      if (n > 1) {
        for (var j = 0; j < n; j++) {
          final f = j / (n - 1);
          final aj = math.max(0.0, age - s.trail * (1 - f));
          _starPos(ox, oy, oz, st.vx, st.vy, st.vz, s.drag, s.gravity, aj, tmp);
          pts[j * 3] = tmp[0];
          pts[j * 3 + 1] = tmp[1];
          pts[j * 3 + 2] = tmp[2];
          _burnColor(st, aj, f, cols, j * 4);
        }
        if (age < st.life + s.trail) _strip(pts, cols, n, w);
      }
      if (age <= st.life && strobeOn) {
        _starPos(ox, oy, oz, st.vx, st.vy, st.vz, s.drag, s.gravity, age, tmp);
        final u = age / st.life;
        final hot = u < 0.12 ? 1.0 - u / 0.12 : 0.0;
        final fade = 1.0 - _smooth(0.75, 1.0, u);
        final r = st.r + (1 - st.r) * hot;
        final g = st.g + (1 - st.g) * hot;
        final b = st.b + (1 - st.b) * hot;
        _quad(tmp[0], tmp[1], tmp[2], w * 2.6, r, g, b, 2.8 * s.brightness * fade * (s.strobe ? 1.6 : 1));
      }
      // Glitter: glints that flicker in the trail behind the star.
      for (var gi = 0; gi < s.glitter; gi++) {
        final back = 0.25 + gi * 0.35 + _hash(st.seed, gi * 31) * 0.3;
        final ag = age - back;
        if (ag <= 0 || ag > st.life) continue;
        if (_hash(st.seed + gi * 977, (t * 18).floor()) < 0.55) continue;
        _starPos(ox, oy, oz, st.vx, st.vy, st.vz, s.drag, s.gravity, ag, tmp);
        _quad(tmp[0], tmp[1] - 0.6 * back, tmp[2], w * 1.3, 1.0, 0.92, 0.75, 3.2);
      }
    }

    for (final st in stars) {
      final children = st.children;
      if (children != null && a > s.split) {
        // Past the split the parent is gone; its four children carry on from
        // where it was, with its velocity plus their own sideways throw.
        _starPos(bx, by, bz, st.vx, st.vy, st.vz, s.drag, s.gravity, s.split, tmp);
        _starVel(st.vx, st.vy, st.vz, s.drag, s.gravity, s.split, vtmp);
        final sx = tmp[0], sy = tmp[1], sz = tmp[2];
        for (final c in children) {
          final child = _Star(
            c.vx + vtmp[0],
            c.vy + vtmp[1],
            c.vz + vtmp[2],
            c.life,
            c.seed,
            c.r,
            c.g,
            c.b,
            c.speedScale,
          );
          drawStar(child, sx, sy, sz, a - s.split, width * 0.75);
        }
      } else {
        drawStar(st, bx, by, bz, a, width * (0.7 + 0.3 * st.speedScale));
      }
    }

    // The light this break throws: a sharp flash, then a decay that follows
    // the stars burning down.
    final flash = math.exp(-a / 0.09) * 1.4;
    final burn = math.exp(-a / (s.life * 0.45)) * (1 - _smooth(s.life * 0.8, s.life * 1.2, a));
    final intensity = (flash + burn * 0.7) * s.brightness * l.size * (l.main ? 1.3 : 1.0);
    if (intensity > 0.01) {
      lights.add(BurstLight(l.breakAt.clone(), l.color.clone(), intensity, l));
    }
  }

  void _burnColor(_Star st, double age, double along, Float64List out, int o) {
    final u = (age / st.life).clamp(0.0, 1.2);
    double r = st.r, g = st.g, b = st.b;
    if (u < 0.1) {
      // White-hot at first.
      final h = 1 - u / 0.1;
      r += (1 - r) * h;
      g += (1 - g) * h;
      b += (1 - b) * h;
    } else if (u > 0.72) {
      // Cooling toward amber as it burns out.
      final c = ((u - 0.72) / 0.28).clamp(0.0, 1.0);
      r += (1.0 - r) * c * 0.7;
      g += (0.42 - g) * c * 0.7;
      b += (0.12 - b) * c * 0.7;
    }
    final fade = 1.0 - _smooth(0.8, 1.1, u);
    out[o] = r;
    out[o + 1] = g;
    out[o + 2] = b;
    out[o + 3] = 1.6 * fade * (0.15 + 0.85 * along);
  }

  // ---------------------------------------------------------------- smoke
  void _smokeFor(Launch l, double age) {
    final rng = math.Random(l.seed ^ 0x5bd1e995);
    final puffs = l.kind == BurstKind.crackle ? 2 : 4;
    for (var i = 0; i < puffs; i++) {
      final ox = (rng.nextDouble() - 0.5) * 10 * l.size;
      final oy = (rng.nextDouble() - 0.5) * 7 * l.size;
      final oz = (rng.nextDouble() - 0.5) * 8;
      final px = l.breakAt.x + ox + wind.x * age;
      final py = l.breakAt.y + oy + wind.y * age - 0.15 * age;
      final pz = l.breakAt.z + oz + wind.z * age;
      final radius = (4 + 10 * (1 - math.exp(-age / 3.5))) * l.size;
      final alpha = 0.22 * (1 - math.exp(-age * 3)) * math.exp(-age / 9) * (l.kind == BurstKind.crackle ? 0.6 : 1);
      if (alpha < 0.003) continue;
      // Lit by everything burning now, falling off with distance.
      double lr = 0.03, lg = 0.03, lb = 0.045;
      for (final light in lights) {
        final dx = light.position.x - px, dy = light.position.y - py, dz = light.position.z - pz;
        final d2 = dx * dx + dy * dy + dz * dz;
        final k = light.intensity * 900 / (900 + d2);
        lr += light.color.x * k * 0.55;
        lg += light.color.y * k * 0.55;
        lb += light.color.z * k * 0.55;
      }
      _smokeQuad(px, py, pz, radius, lr, lg, lb, alpha);
    }
  }

  // ---------------------------------------------------------------- geometry
  /// A camera-facing strip through [n] points with per-point color.
  void _strip(Float64List p, Float64List c, int n, double width) {
    final m = _light;
    if (!m.reserve(n * 2, (n - 1) * 6)) return;
    final base = m.vertexCount;
    for (var j = 0; j < n; j++) {
      final x = p[j * 3], y = p[j * 3 + 1], z = p[j * 3 + 2];
      // Tangent from neighbors.
      final j0 = j > 0 ? j - 1 : j, j1 = j < n - 1 ? j + 1 : j;
      var tx = p[j1 * 3] - p[j0 * 3], ty = p[j1 * 3 + 1] - p[j0 * 3 + 1], tz = p[j1 * 3 + 2] - p[j0 * 3 + 2];
      final vx = x - _cx, vy = y - _cy, vz = z - _cz;
      var sx = ty * vz - tz * vy, sy = tz * vx - tx * vz, sz = tx * vy - ty * vx;
      var sl = math.sqrt(sx * sx + sy * sy + sz * sz);
      if (sl < 1e-6) {
        // Degenerate (a star at the very start): use the screen's horizontal.
        sx = vz;
        sy = 0;
        sz = -vx;
        sl = math.sqrt(sx * sx + sz * sz) + 1e-6;
        tx = ty = tz = 0;
      }
      final f = j / (n - 1);
      // Keep at least a pixel or so wide far away, to avoid shimmer.
      final dist = math.sqrt(vx * vx + vy * vy + vz * vz);
      final w = math.max(width * (0.18 + 0.82 * f), dist * 0.0011) * 0.5 / sl;
      m.vertex(x + sx * w, y + sy * w, z + sz * w, 0, f, c[j * 4], c[j * 4 + 1], c[j * 4 + 2], c[j * 4 + 3]);
      m.vertex(x - sx * w, y - sy * w, z - sz * w, 1, f, c[j * 4], c[j * 4 + 1], c[j * 4 + 2], c[j * 4 + 3]);
    }
    for (var j = 0; j < n - 1; j++) {
      final a = base + j * 2;
      m.tri(a, a + 1, a + 2);
      m.tri(a + 1, a + 3, a + 2);
    }
  }

  /// A camera-facing square glow centered at (x, y, z).
  void _quad(double x, double y, double z, double size, double r, double g, double b, double a) {
    _billboard(_light, x, y, z, size, r, g, b, a, 2.0);
  }

  void _smokeQuad(double x, double y, double z, double size, double r, double g, double b, double a) {
    _billboard(_smoke, x, y, z, size, r, g, b, a, 0.0);
  }

  void _billboard(
    _DynamicMesh m,
    double x,
    double y,
    double z,
    double size,
    double r,
    double g,
    double b,
    double a,
    double vOffset,
  ) {
    if (!m.reserve(4, 6)) return;
    final vx = x - _cx, vy = y - _cy, vz = z - _cz;
    final vl = math.sqrt(vx * vx + vy * vy + vz * vz) + 1e-6;
    // right = normalize(view x up), up = right x view.
    var rx = vz, rz = -vx;
    final rl = math.sqrt(rx * rx + rz * rz) + 1e-6;
    rx /= rl;
    rz /= rl;
    final ux = (rz * vy) / vl, uy = (rx * vz - rz * vx) / vl, uz = (-rx * vy) / vl;
    final h = math.max(size, vl * 0.0024) * 0.5;
    final base = m.vertexCount;
    m.vertex(x - rx * h - ux * h, y - uy * h, z - rz * h - uz * h, 0, vOffset, r, g, b, a);
    m.vertex(x + rx * h - ux * h, y - uy * h, z + rz * h - uz * h, 1, vOffset, r, g, b, a);
    m.vertex(x + rx * h + ux * h, y + uy * h, z + rz * h + uz * h, 1, vOffset + 1, r, g, b, a);
    m.vertex(x - rx * h + ux * h, y + uy * h, z - rz * h + uz * h, 0, vOffset + 1, r, g, b, a);
    m.tri(base, base + 1, base + 2);
    m.tri(base, base + 2, base + 3);
  }

  // ---------------------------------------------------------------- helpers
  static double _smooth(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static double _hash(int a, int b) {
    var h = (a * 374761393 + b * 668265263) & 0x7fffffff;
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
    return (h & 0xffff) / 0xffff;
  }

  static Vector3 _randomDir(math.Random rng) {
    final z = rng.nextDouble() * 2 - 1;
    final a = rng.nextDouble() * math.pi * 2;
    final r = math.sqrt(1 - z * z);
    return Vector3(r * math.cos(a), z, r * math.sin(a));
  }

  static List<Vector3> _fibonacciSphere(int n, math.Random rng, double jitter) {
    final out = <Vector3>[];
    final g = math.pi * (3 - math.sqrt(5));
    for (var i = 0; i < n; i++) {
      final z = 1 - 2 * (i + 0.5) / n;
      final r = math.sqrt(1 - z * z);
      final a = i * g;
      final d = Vector3(math.cos(a) * r, z, math.sin(a) * r)
        ..add(
          Vector3(rng.nextDouble() - 0.5, rng.nextDouble() - 0.5, rng.nextDouble() - 0.5)..scale(jitter * 2),
        );
      out.add(d.normalized());
    }
    return out;
  }
}

/// A mesh rebuilt from scratch every frame, with fixed capacity.
class _DynamicMesh {
  _DynamicMesh(this.capacity)
    : _pos = Float32List(capacity * 3),
      _nrm = Float32List(capacity * 3),
      _uv = Float32List(capacity * 2),
      _col = Float32List(capacity * 4),
      _idx = Uint32List(capacity * 2) {
    for (var i = 0; i < capacity; i++) {
      _nrm[i * 3 + 1] = 1;
    }
    // Start with one degenerate triangle so the mesh is valid when empty.
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

  bool reserve(int vertices, int indices) =>
      vertexCount + vertices <= capacity && _indexCount + indices <= _idx.length;

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
