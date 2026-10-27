import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';

import '../app/clock.dart';
import '../app/sfx.dart';
import 'package:vector_math/vector_math.dart';

import 'friends.dart';
import 'moods.dart';
import 'soft_body.dart';
import 'sparks.dart';
import 'themes.dart';
import 'wardrobe.dart';

/// Which way the face points in world space, along Z. The GLB faces glTF +Z,
/// which the importer brings in as -Z; the camera sits on this side.
const double kFaceZ = -1.0;

/// The Lantern Spirit: the GLB rig, its state clips, and everything layered
/// on top at runtime.
///
/// Two layers drive every part. The clips (one per [LanternMood]) key the
/// `<Part>Ctrl` nodes, the way an animator's timeline would. This class owns
/// the `<Part>Fx` nodes under them for interactive motion (look-at, springs,
/// follow-through, explode), so the two never fight over a transform.
class LanternCharacter extends ChangeNotifier {
  LanternCharacter._(
    this.friend,
    this.root,
    this._skin,
    this._bodySkin,
    this._face,
    this._ember,
    this._sparkAmbient,
    this._sparkGold,
    this._accent,
  );

  /// Loads the rig and materials for [friend] and adds it to [scene].
  /// Loads [friend] and adds it to [scene], unless [addToScene] is false (for
  /// a caller that places and updates it first, so it never shows unposed).
  static Future<LanternCharacter> load(Scene scene, {Friend friend = Friends.lumi, bool addToScene = true}) async {
    final toy = !friend.isLantern;
    final results = await Future.wait([
      loadScene('assets/lantern.glb'),
      loadFmatMaterial(toy ? 'assets/toy.fmat' : 'assets/skin.fmat'),
      loadFmatMaterial(toy ? 'assets/toy.fmat' : 'assets/skin.fmat'),
      loadFmatMaterial('assets/face.fmat'),
      loadFmatMaterial(toy ? 'assets/toy.fmat' : 'assets/ember.fmat'),
      loadFmatMaterial('assets/ember.fmat'),
      loadFmatMaterial('assets/ember.fmat'),
      Texture2D.fromAsset(friend.atlas),
      if (toy) loadFmatMaterial('assets/toy.fmat'),
    ]);
    final c = LanternCharacter._(
      friend,
      results[0] as Node,
      results[1] as PreprocessedMaterial,
      results[2] as PreprocessedMaterial,
      results[3] as PreprocessedMaterial,
      results[4] as PreprocessedMaterial,
      results[5] as PreprocessedMaterial,
      results[6] as PreprocessedMaterial,
      toy ? results[8] as PreprocessedMaterial : null,
    );
    final atlas = results[7] as Texture2D;
    c._face.parameters.setTexture(
      'atlas',
      atlas.gpuTexture,
      sampler: atlas.sampledSampler,
    );
    c._bind();
    if (addToScene) scene.add(c.root);
    return c;
  }

  /// Who this is: Lumi, or one of the other friends on the same rig.
  final Friend friend;

  final Node root;

  /// The head's material (Lumi's skin, or a friend's toy material).
  final PreprocessedMaterial _skin;

  /// A friend's sprout leaves or ring and moon.
  final PreprocessedMaterial? _accent;

  /// The body's own copy of the skin, so a head dent never touches it.
  final PreprocessedMaterial _bodySkin;
  final PreprocessedMaterial _face;
  final PreprocessedMaterial _ember;
  final PreprocessedMaterial _sparkAmbient;
  final PreprocessedMaterial _sparkGold;

  late final Node _head; // the head sphere mesh node
  late final Node _faceNode;
  late final Map<String, Node> _fx;
  late final Map<LanternMood, AnimationClip> _clips;
  late final SparkField sparks;

  // ---------------------------------------------------------------- tuning
  /// Crossfade length between states, in seconds.
  double fadeSeconds = 0.35;

  /// Scales the whole glow on top of each mood's own level.
  double glowScale = 1.0;

  /// How soft the head is: 1 is the default jelly, lower is firmer.
  double get softness => 140 / soft.stiffness;
  set softness(double v) {
    soft
      ..stiffness = 140 / v
      ..volume = 90 / v;
  }

  /// How far the head squashes on a poke or a landing (1 is none).
  double squash = 0.9;

  /// Pulls the parts apart to show how the character is built, 0 to 1.
  double explodeTarget = 0;

  /// Light reaching Lumi from the world (color times intensity) and the
  /// direction it comes from. The materials are unlit, so scene lights do not
  /// touch them; the fireworks drive this instead.
  final Vector3 ambientColor = Vector3.zero();
  final Vector3 ambientDirection = Vector3(0, 1, 0);

  /// The mood one-shots hand back to when they finish.
  LanternMood restMood = LanternMood.awake;

  /// Whether Lumi dozes off after a while without attention, and how soon.
  bool canDoze = true;
  double dozeAfter = 25;

  /// Seconds since anything paid attention to the friend.
  double get idleSeconds => _idle;

  // ---------------------------------------------------------------- state
  LanternMood _mood = LanternMood.sleepy;
  LanternMood get mood => _mood;

  final Map<LanternMood, double> _weights = {
    for (final m in LanternMood.values) m: m == LanternMood.sleepy ? 1.0 : 0.0,
  };
  Map<LanternMood, double> get weights => Map.unmodifiable(_weights);
  Map<LanternMood, double> _fadeFrom = {};
  double _fadeT = 1;

  double _faceFrame = LanternFace.sleepy.cell;
  double _prevFaceFrame = LanternFace.sleepy.cell;
  double _faceMix = 1;
  LanternFace? _faceOverride;
  double _faceOverrideTimer = 0;
  double _blinkTimer = 3;
  double _blinkLeft = 0;

  double _glow = LanternMood.sleepy.glow;
  double _moodTimer = 0;
  double _idle = 0;

  final ThemeColors _colors = ThemeColors.from(LanternTheme.aurora);
  ThemeColors _targetColors = ThemeColors.from(LanternTheme.aurora);
  LanternTheme _theme = LanternTheme.aurora;
  LanternTheme get theme => _theme;

  // Look-at, in -1..1 screen terms (x right, y up), and whether it is active.
  final Vector2 _lookTarget = Vector2.zero();
  final Vector2 _look = Vector2.zero();
  bool _looking = false;

  // Where the attention system wants the eyes and head, when nothing is
  // being followed explicitly. Eyes jump; the head trails behind on a spring.
  final Vector2 _gaze = Vector2.zero();
  final Vector2 _eyes = Vector2.zero();

  /// The emotion pad point: x from bad (-1) to good (1) mood, y from low
  /// (-1) to high (1) energy. When set, Lumi's resting pose is a continuous
  /// blend of the four corner moods instead of the Awake loop.
  Vector2? moodPoint;
  static const _corners = [LanternMood.grumpy, LanternMood.happy, LanternMood.glum, LanternMood.content];

  // Springs.
  final _bob = _Spring(stiffness: 70, damping: 10);
  final _handLag = _Spring(stiffness: 40, damping: 6);
  final _squash = _Spring(stiffness: 180, damping: 9);
  double _explode = 0;

  // What Lumi is wearing, by socket, and the parts that sway.
  final Map<Socket, (String, Node)> _worn = {};
  final List<_Sway> _sway = [];
  final Vector3 _lastHead = Vector3.zero();
  final Vector3 _headVelocity = Vector3.zero();

  /// The id of the accessory on the head socket, or null.
  String? get hat => _worn[Socket.head]?.$1;

  /// Whether the scarf is on.
  bool get scarf => _worn.containsKey(Socket.neck);

  /// Puts on [hat] (an accessory id, or null for none) and the scarf.
  Future<void> wear({String? hat, bool scarf = false}) async {
    await _wearOn(Socket.head, hat);
    await _wearOn(Socket.neck, scarf ? Wardrobe.scarf.id : null);
  }

  Future<void> _wearOn(Socket socket, String? id) async {
    if (_worn[socket]?.$1 == id) return;
    if (socket == Socket.head && id == null) _sprout?.visible = true;
    final old = _worn.remove(socket);
    if (old != null) {
      old.$2.detach();
      _sway.removeWhere((s) => s.owner == old.$2);
    }
    final accessory = Wardrobe.byId(id);
    if (accessory == null) return;
    final node = await loadScene(accessory.asset);
    // Another wear() may have won the race while this one loaded.
    if (_worn.containsKey(socket)) return;
    void untouchable(Node n) {
      n.raycastable = false;
      n.children.forEach(untouchable);
    }

    untouchable(node);
    final parent = socket == Socket.head ? _hatRide : root.getChildByName('NeckFx')!;
    // The sprout makes room for a hat.
    _sprout?.visible = socket != Socket.head ? (_sprout?.visible ?? true) : false;
    parent.add(node);
    _worn[socket] = (accessory.id, node);
    void findSway(Node n) {
      final name = n.name;
      final k = switch (name) {
        'Pom' || 'HatPom' => 1.0,
        'ScarfTail' => 1.4,
        'Star' => 0.8,
        _ when name.startsWith('Flower') && !name.contains('.') => 0.35,
        _ => 0.0,
      };
      if (k > 0) _sway.add(_Sway(node, n, k));
      n.children.forEach(findSway);
    }

    findSway(node);
  }

  /// The squishy head: pokes, presses, pulls, and jiggles.
  late final SoftHead soft;
  Vector3? _grabDir;
  Vector3? _grabWorld;
  int _jiggleSeed = 1;

  void _bind() {
    _head = root.getChildByName('Head')!;
    _faceNode = root.getChildByName('Face')!;
    _fx = {
      for (final p in const ['Head', 'Body', 'HandL', 'HandR', 'Wisp'])
        p: root.getChildByName('${p}Fx')!,
    };
    void setMaterial(String node, Material m) {
      for (final p in root.getChildByName(node)!.mesh!.primitives) {
        p.material = m;
      }
    }

    setMaterial('Head', _skin);
    setMaterial('Body', _bodySkin);
    setMaterial('HandL', _ember);
    setMaterial('HandR', _ember);
    setMaterial('Wisp', _ember);
    setMaterial('Face', _face);
    _hatMount = Node(name: 'HatMount');
    _fx['Head']!.add(_hatMount);
    _hatRide = Node(name: 'HatRide');
    _hatMount.add(_hatRide);
    // Swap the imported head and face cap for deformable ones.
    soft = SoftHead(radius: _head.localTransform.getMaxScaleOnAxis(), faceZ: kFaceZ);
    // Swap geometry inside the existing primitives: the imported scene has
    // already registered these meshes for drawing.
    for (final p in _head.mesh!.primitives) {
      p.geometry = soft.headGeometry;
    }
    for (final p in _faceNode.mesh!.primitives) {
      p.geometry = soft.capGeometry;
    }
    if (!friend.isLantern) _shapeFriend();
    // Juju is gummy: softer and wobblier than anyone.
    if (friend.id == 'juju') softness = 1.6;
    root.getChildByName('Face')!.raycastable = false;
    for (final n in const ['Body', 'HandL', 'HandR', 'Wisp']) {
      root.getChildByName(n)!.raycastable = false;
    }

    _clips = {
      for (final m in LanternMood.values)
        m: root.createAnimationClip(root.findAnimationByName(m.clip)!)
          ..loop = m.loops
          ..weight = _weights[m]!,
    };
    for (final m in LanternMood.values) {
      if (m.loops) _clips[m]!.play();
    }

    _sparkGold.parameters
      ..setVec4('ember_color', Vector4(1.0, 0.72, 0.28, 1))
      ..setFloat('intensity', 3.2);
    sparks = SparkField(
      parent: root,
      ambientMaterial: _sparkAmbient,
      goldMaterial: _sparkGold,
    );
  }

  // ---------------------------------------------------------------- friends
  late final Node _hatMount;

  /// Under the hat mount: follows the soft head's crown so a hat rides every
  /// squish and stretch instead of clipping or floating off.
  late final Node _hatRide;
  static final _brim = [
    for (var i = 0; i < 8; i++)
      Vector3(math.cos(i * math.pi / 4) * 0.77, 0.64, math.sin(i * math.pi / 4) * 0.77),
  ];

  void _rideHat() {
    if (_worn[Socket.head] == null) return;
    // In the mount's space the head is a 0.62 sphere; soft offsets are in
    // unit-sphere space.
    const r = 0.62;
    final crown = soft.displacementAt(Vector3(0, 1, 0)) * r;
    final side = Vector3(crown.x, 0, crown.z);
    final shift = Vector3(0, crown.y, 0) + side * 0.5;
    // Under the brim the head may bulge outward past where the hat moved to:
    // widen the hat just enough to cover it.
    var bulge = 0.0;
    for (final d in _brim) {
      final out = Vector3(d.x, 0, d.z)..normalize();
      bulge = math.max(bulge, (soft.displacementAt(d) * r - shift).dot(out));
    }
    final inflate = 1 + (math.max(0.0, bulge) / r * 1.1).clamp(0.0, 0.18);
    // Lean the hat the way the crown slid.
    final lean = (side.length / r * 0.4).clamp(0.0, 0.35);
    final q = side.length < 1e-5 ? Quaternion.identity() : Quaternion.axisAngle(Vector3(0, 1, 0).cross(side).normalized(), lean);
    // A sneeze can send the hat flying; it lands back on, crooked, and
    // slowly settles straight.
    var fly = Vector3.zero();
    var spin = Quaternion.identity();
    var squashY = 1.0;
    if (_hatFly >= 0) {
      _hatFly += _lastDt;
      final u = (_hatFly / 1.1).clamp(0.0, 1.0);
      fly = Vector3(0.32 * u, 1.25 * 4 * u * (1 - u), -0.18 * u);
      spin = Quaternion.axisAngle(Vector3(1, 0, 0.4).normalized(), u * math.pi * 2.5);
      if (u >= 1) {
        if (_hatFly - _lastDt < 1.1) onSound?.call('hat_land');
        final settle = (_hatFly - 1.1).clamp(0.0, 4.0);
        final k = math.exp(-settle * 0.9);
        fly = Vector3(0.32 * k * 0.6, 0, -0.18 * k * 0.6);
        spin = Quaternion.axisAngle(Vector3(0, 0, 1), -0.42 * k + 0.06 * math.sin(settle * 9) * math.exp(-settle * 3));
        squashY = 1 - 0.18 * math.exp(-settle * 7) * math.cos(settle * 22).abs();
        if (settle >= 4) _hatFly = -1;
      }
    }
    _hatRide.localTransform = Matrix4.compose(shift + fly, q * spin, Vector3(inflate, squashY, inflate));
  }

  // ---------------------------------------------------------------- antics
  double _hatFly = -1;
  double _sneezeT = -1;

  /// Called the moment of a sneeze, with where the head is, for effects.
  void Function(Vector3 head)? onSneeze;

  /// Called with a sound's name when something audible happens to the
  /// friend itself (a sneeze, the hat landing, a tumble, dozing off), for
  /// whoever owns the speakers.
  void Function(String sound)? onSound = Sfx.sound;

  bool get sneezing => _sneezeT >= 0;

  /// A big inhale, then a sneeze that knocks the hat off. It flies up,
  /// spins, and drops back on crooked.
  void sneeze() {
    if (_sneezeT >= 0) return;
    _idle = 0;
    if (_mood == LanternMood.sleepy) wake();
    _sneezeT = 0;
  }

  void _stepSneeze(double dt) {
    if (_sneezeT < 0) return;
    final before = _sneezeT;
    _sneezeT += dt;
    if (_sneezeT < 0.75) {
      // Inhale: tip back, stretch tall, eyes going wide.
      _squash.target = -0.12 * (_sneezeT / 0.75);
      if (before == 0) {
        _showFace(LanternFace.surprised, 0.75);
        onSound?.call('sneeze_in');
      }
    } else if (before < 0.75) {
      onSound?.call('sneeze_out');
      _squash
        ..target = 0
        ..velocity -= 4.5;
      soft.jiggle(0.9, _jiggleSeed++);
      _showFace(LanternFace.poked, 0.5);
      if (_worn[Socket.head] != null) {
        _hatFly = 0;
        onSound?.call('hat_pop');
      }
      onSneeze?.call(headCenter);
    }
    if (_sneezeT > 1.6) _sneezeT = -1;
  }

  // Shy: both hands come up over the face, with a peek now and then.
  double shyTarget = 0;
  double _shy = 0;
  double _shyClock = 0;

  /// How much the hands cover the face right now, 0 to 1.
  double get shy => _shy;

  // Mochi's sprout blooms into a flower.
  double _bloom = -1;
  final List<Node> _petals = [];

  /// Mochi only: the sprout grows a flower, holds it, and closes again.
  void bloom() {
    if (friend.extras != FriendExtras.sprout || _bloom >= 0 || _sproutTwirl == null) return;
    _idle = 0;
    if (_petals.isEmpty) {
      final geo = SphereGeometry(radius: 1, segments: 16, rings: 8);
      for (var i = 0; i < 6; i++) {
        final p = Node(name: 'Petal', mesh: Mesh(geo, _petalMaterial!))..raycastable = false;
        _sproutTwirl!.add(p);
        _petals.add(p);
      }
      final heart = Node(name: 'Heart', mesh: Mesh(geo, _flat(1.0, 0.85, 0.3)))..raycastable = false;
      _sproutTwirl!.add(heart);
      _petals.add(heart);
    }
    _bloom = 0;
    _sprout?.visible = true;
    react(LanternFace.wow, 1.0);
  }

  // Simple flat colors for the flower and the umbrella canopy.
  static UnlitMaterial _flat(double r, double g, double b) => UnlitMaterial()..baseColorFactor = Vector4(r, g, b, 1);
  final Material? _petalMaterial = _flat(1.0, 0.55, 0.7);
  final Material _canopy = _flat(0.95, 0.35, 0.4);

  void _stepBloom(double dt) {
    if (_bloom < 0) return;
    _bloom += dt;
    final open = _bloom < 1.4 ? _easeOutBack(_bloom / 1.4) : (_bloom < 7 ? 1.0 : (1 - (_bloom - 7) / 0.8).clamp(0.0, 1.0));
    for (var i = 0; i < 6; i++) {
      final a = i / 6 * math.pi * 2 + _bloom * 0.3;
      _petals[i].localTransform = Matrix4.compose(
        Vector3(math.cos(a) * 0.14 * open, 0.17 + 0.03 * open, math.sin(a) * 0.14 * open),
        Quaternion.axisAngle(Vector3(-math.sin(a), 0, math.cos(a)), 0.9 - 0.6 * open),
        Vector3(0.15, 0.045, 0.09) * open,
      );
    }
    _petals[6].localTransform = Matrix4.compose(Vector3(0, 0.2, 0), Quaternion.identity(), Vector3.all(0.07 * open));
    // Over a hat, the flower pokes up through the top of it.
    final lift = _worn[Socket.head] != null ? 0.32 * open : 0.0;
    _sproutTwirl!.localTransform = Matrix4.translation(Vector3(0, lift, 0)) * Matrix4.rotationY(_sproutSpin);
    if (_bloom >= 7.8) {
      _bloom = -1;
      if (_worn[Socket.head] != null) _sprout?.visible = false;
    }
  }

  // A tumble: the window moved under it.
  double _tumbleT = -1;
  Matrix4? _tumbleBase;

  /// Rolls head over heels (the layout changed) and lands with a bounce.
  void tumble() {
    if (_tumbleT >= 0) return;
    _tumbleT = 0;
    _tumbleBase = root.localTransform.clone();
    _idle = 0;
    onSound?.call('tumble');
  }

  void _stepTumble(double dt) {
    if (_tumbleT < 0) return;
    _tumbleT += dt;
    final t = (_tumbleT / 0.85).clamp(0.0, 1.0);
    final e = t * t * (3 - 2 * t);
    final lift = 4 * 0.35 * t * (1 - t);
    root.localTransform = _tumbleBase! * Matrix4.translation(Vector3(0, 1.3 + lift, 0)) * Matrix4.rotationZ(e * math.pi * 2) * Matrix4.translation(Vector3(0, -1.3, 0));
    if (t >= 1) {
      root.localTransform = _tumbleBase!;
      _tumbleT = -1;
      jolt(1.0);
      setMood(LanternMood.dizzy);
      onSound?.call('land');
      onSound?.call('dizzy');
    }
  }

  // Weather gear: an umbrella in hand, or sunglasses.
  Node? _umbrella;
  double _umbrellaPose = 0;

  /// The top of the umbrella's canopy in the world, while one is up.
  Vector3? get umbrellaTop => _umbrella?.children.first.globalTransform.getTranslation();

  /// The umbrella in the rig's own space: where the hand holds it (out
  /// beside the head, a little low), where its canopy sits (above the
  /// crown, to that side), and the head's radius.
  (Vector3, Vector3, double) get _umbrellaFrame {
    final r = friend.isLantern ? 0.62 : friend.head.$2;
    final center = Vector3(friend.headOffset.$1, 1.8 + friend.headOffset.$2, 0);
    return (center + Vector3(r * 1.55, -r * 0.5, 0.1 * kFaceZ), center + Vector3(r * 0.5, r * 1.75, 0), r);
  }
  Node? _shades;

  /// Opens a little umbrella (rain), puts on sunglasses (heat), or neither.
  void weather({bool umbrella = false, bool shades = false}) {
    if (umbrella && _umbrella == null) {
      // Sized from the head: held out beside it, leaning in so the canopy
      // rests above the crown and the stick never passes through the head.
      final (hand, top, r) = _umbrellaFrame;
      final along = top - hand;
      final n = Node(name: 'Umbrella');
      final canopy = Node(mesh: Mesh(CylinderGeometry(bottomRadius: 1, topRadius: 0.05, height: 1, radialSegments: 10), _canopy),
          localTransform: Matrix4.compose(Vector3(0, along.length, 0), Quaternion.identity(), Vector3(r * 1.25, r * 0.42, r * 1.25)));
      final stick = Node(mesh: Mesh(CylinderGeometry(bottomRadius: 1, topRadius: 1, height: 1, radialSegments: 8), _ember),
          localTransform: Matrix4.compose(Vector3(0, along.length * 0.5, 0), Quaternion.identity(), Vector3(0.018, along.length, 0.018)));
      n
        ..add(canopy)
        ..add(stick);
      _umbrella = n;
      (_lean ?? root).add(n);
    } else if (!umbrella && _umbrella != null) {
      _umbrella!.detach();
      _umbrella = null;
    }
    if (shades && _shades == null) {
      final n = Node(name: 'Shades');
      final dark = _shadesMaterial;
      for (final x in const [-0.2, 0.2]) {
        n.add(Node(mesh: Mesh(SphereGeometry(radius: 1, segments: 20, rings: 10), dark),
            localTransform: Matrix4.compose(Vector3(x, 0.1, 0.6 * kFaceZ), Quaternion.identity(), Vector3(0.15, 0.1, 0.04))));
      }
      n.add(Node(mesh: Mesh(CylinderGeometry(bottomRadius: 1, topRadius: 1, height: 1, radialSegments: 6), dark),
          localTransform: Matrix4.compose(Vector3(0, 0.13, 0.62 * kFaceZ), Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2), Vector3(0.012, 0.16, 0.012))));
      _shades = n;
      _hatRide.add(n);
    } else if (!shades && _shades != null) {
      _shades!.detach();
      _shades = null;
    }
    for (final n in [?_umbrella, ?_shades]) {
      void off(Node m) {
        m.raycastable = false;
        m.children.forEach(off);
      }

      off(n);
    }
  }

  static final _shadesMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = Vector4(0.02, 0.02, 0.03, 1)
    ..metallicFactor = 0.2
    ..roughnessFactor = 0.15;
  Matrix4 _faceBase = Matrix4.identity();
  Node? _sprout;
  Node? _ring;
  Node? _moon;
  final List<Node> _feet = [];

  /// Reshapes Lumi's parts into [friend]: the same rig, clips, and soft
  /// head, with new proportions, feet, and extras.
  void _shapeFriend() {
    final f = friend;
    Matrix4 shape(V3 size, V3 offset) =>
        Matrix4.compose(Vector3(offset.$1, offset.$2, offset.$3), Quaternion.identity(), Vector3(size.$1, size.$2, size.$3));
    // The face cap lives in the head socket's space around a 0.62 sphere, so
    // the same mapping that stretches the head stretches the face with it.
    _head.localTransform = shape(f.head, f.headOffset);
    _faceBase = f.headMount;
    _hatMount.localTransform = f.hatMount;
    place(Vector3.zero(), 0);
    final body = root.getChildByName('Body')!;
    if (f.body case final b?) {
      body.localTransform = shape(b, f.bodyOffset);
    } else {
      body.visible = false;
    }
    for (final (name, side) in const [('HandL', -1.0), ('HandR', 1.0)]) {
      root.getChildByName(name)!.localTransform = shape(
        (f.hand, f.hand, f.hand),
        (f.handOffset.$1 * side, f.handOffset.$2, f.handOffset.$3),
      );
    }
    final wisp = root.getChildByName('Wisp')!;
    if (f.foot case final foot?) {
      wisp.visible = false;
      final geo = SphereGeometry(radius: 1, segments: 32, rings: 16);
      for (final side in const [-1.0, 1.0]) {
        final n = Node(
          name: side < 0 ? 'FootL' : 'FootR',
          mesh: Mesh(geo, _ember),
          localTransform: shape(foot, (f.footOffset.$1 * side, f.footOffset.$2, f.footOffset.$3)),
        )..raycastable = false;
        _fx['Wisp']!.add(n);
        _feet.add(n);
        _footBase.add((Vector3(foot.$1, foot.$2, foot.$3), Vector3(f.footOffset.$1 * side, f.footOffset.$2, f.footOffset.$3), side));
      }
    }
    root.getChildByName('NeckFx')!.localTransform = Matrix4.compose(
      Vector3(f.neckOffset.$1, 0.26 + f.neckOffset.$2, f.neckOffset.$3),
      Quaternion.identity(),
      Vector3.all(f.neckScale),
    );
    final accent = _accent!;
    switch (f.extras) {
      case FriendExtras.sprout:
        // A bud and two leaves on top of the head.
        final top = f.headOffset.$2 + f.head.$2;
        final sprout = Node(name: 'Sprout', localTransform: Matrix4.translation(Vector3(0, top - 0.06, 0)));
        final ball = SphereGeometry(radius: 1, segments: 24, rings: 12);
        final twirl = Node(name: 'SproutTwirl');
        sprout.add(twirl);
        twirl.add(Node(name: 'Stem', mesh: Mesh(ball, accent), localTransform: shape((0.035, 0.09, 0.035), (0, 0.02, 0))));
        twirl.add(Node(name: 'Bud', mesh: Mesh(ball, accent), localTransform: shape((0.065, 0.065, 0.065), (0, 0.1, 0))));
        for (final side in const [-1.0, 1.0]) {
          final leaf = Node(name: 'SproutLeaf', mesh: Mesh(ball, accent));
          twirl.add(leaf);
          _leaves.add((leaf, side));
        }
        _sproutTwirl = twirl;
        _fx['Head']!.add(sprout);
        _sprout = sprout;
        _sway.add(_Sway(sprout, sprout, 0.6));
      case FriendExtras.orbit:
        final c = Vector3(f.headOffset.$1, f.headOffset.$2, f.headOffset.$3);
        _ring = Node(
          name: 'Ring',
          mesh: Mesh(TorusGeometry(radius: 0.68, tubeRadius: 0.012, radialSegments: 96, tubularSegments: 10), accent),
          localTransform: Matrix4.compose(
            c,
            Quaternion.axisAngle(Vector3(0, 1, 0), -0.2) * Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2 - 0.28),
            Vector3.all(1),
          ),
        );
        _moon = Node(name: 'Moon', mesh: Mesh(SphereGeometry(radius: 0.07, segments: 24, rings: 12), accent));
        _fx['Head']!.add(_ring!);
        _fx['Head']!.add(_moon!);
      case FriendExtras.none:
        break;
    }
    void untouchable(Node n) {
      if (n != _head) n.raycastable = false;
      n.children.forEach(untouchable);
    }

    for (final n in [_sprout, _ring, _moon]) {
      if (n != null) untouchable(n);
    }
  }

  /// Idle antics and personality: Juju hops, Mochi's sprout perks up, droops,
  /// and spins, Nova's ring turns. Games switch the hops off.
  bool idleAntics = true;
  double _hopT = -1;
  double _hopTimer = 3;
  double _leafAngle = 0.5;
  double _sproutSpin = 0;
  double _ringSpin = 0;
  Node? _sproutTwirl;
  final List<(Node, double)> _leaves = [];
  final _rng = math.Random(5);

  /// Advances the friend's antics and returns how high it is hopping.
  double _antics(double dt, double time) {
    var hop = 0.0;
    switch (friend.extras) {
      case FriendExtras.none when friend.id == 'juju':
        final calm = _mood == LanternMood.awake || _mood == LanternMood.curious || _mood == LanternMood.happy;
        if (_hopT < 0) {
          _hopTimer -= dt;
          if (_hopTimer <= 0 && calm && idleAntics && !grabbing) {
            _hopT = 0;
            _squash.velocity += 1.4;
          }
        }
        if (_hopT >= 0) {
          _hopT += dt;
          const air = 0.42;
          final t = (_hopT / air).clamp(0.0, 1.0);
          hop = 4 * 0.24 * t * (1 - t);
          if (_hopT >= air) {
            _hopT = -1;
            _hopTimer = 2.5 + _rng.nextDouble() * 3.5;
            // Land with a jelly wobble.
            _squash.velocity -= 2.4;
            soft.jiggle(0.5, _jiggleSeed++);
          }
        }
      case FriendExtras.sprout:
        // Leaves perk up when happy, droop when tired or sad.
        final target = switch (_mood) {
          LanternMood.sleepy || LanternMood.glum => -0.25,
          LanternMood.delighted || LanternMood.happy || LanternMood.cheer => 0.85,
          LanternMood.poked || LanternMood.flinch => 1.0,
          _ => 0.5,
        };
        _leafAngle = _approach(_leafAngle, target + math.sin(time * 2.2) * 0.05, dt * 6);
        for (final (leaf, side) in _leaves) {
          leaf.localTransform = Matrix4.compose(
            Vector3(0.16 * side, 0.12 + 0.05 * _leafAngle, 0),
            Quaternion.axisAngle(Vector3(0, 0, 1), _leafAngle * side),
            Vector3(0.22, 0.05, 0.1),
          );
        }
        // Delighted: the sprout spins like a propeller.
        final spinning = _mood == LanternMood.delighted || _mood == LanternMood.cheer;
        _sproutSpin += dt * (spinning ? 18 : 0);
        if (!spinning) _sproutSpin = _approach(_sproutSpin, (_sproutSpin / math.pi).roundToDouble() * math.pi, dt * 5);
        if (_bloom < 0) _sproutTwirl?.localTransform = Matrix4.rotationY(_sproutSpin);
      case FriendExtras.orbit:
        final speed = switch (_mood) {
          LanternMood.delighted || LanternMood.cheer || LanternMood.happy => 7.0,
          LanternMood.dizzy => -5.0,
          LanternMood.sleepy => 0.2,
          _ => 0.8,
        };
        _ringSpin += dt * speed;
        final c = Vector3(friend.headOffset.$1, friend.headOffset.$2, friend.headOffset.$3);
        _ring?.localTransform = Matrix4.compose(
          c,
          Quaternion.axisAngle(Vector3(0, 1, 0), -0.2) *
              Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2 - 0.28) *
              Quaternion.axisAngle(Vector3(0, 1, 0), _ringSpin),
          Vector3.all(1),
        );
      default:
        break;
    }
    return hop;
  }

  /// The friend's colors for the current color slot, hue turned.
  FriendPalette get _palette {
    final i = LanternTheme.all.indexOf(_theme).clamp(0, friend.palettes.length - 1);
    return friend.palettes[i];
  }

  final Map<PreprocessedMaterial, _ToyState> _toyState = {};

  void _applyToy(PreprocessedMaterial m, ToyLook look, double k, double glow) {
    final t = look.turned(_hueShift);
    final st = _toyState.putIfAbsent(m, () => _ToyState.from(t));
    st.approach(t, k);
    m.parameters
      ..setVec4('base_color', st.base)
      ..setVec4('shade_color', st.shade)
      ..setVec4('rim_color', st.rim)
      ..setFloat('sss', t.sss)
      ..setFloat('spec', t.spec)
      ..setFloat('gloss', t.gloss)
      ..setFloat('rim', t.rimAmount)
      ..setFloat('core', t.core)
      ..setFloat('film', t.film)
      ..setFloat('emissive', t.emissive)
      ..setFloat('coat', t.coat)
      ..setVec4('sss_color', Vector4(t.sssColor.$1, t.sssColor.$2, t.sssColor.$3, 1))
      ..setFloat('sss_edge', t.sssEdge)
      ..setFloat('sparkle', t.sparkle)
      ..setFloat('fuzz', t.fuzz)
      ..setFloat('time', _time)
      ..setFloat('glow', glow);
  }

  // ---------------------------------------------------------------- moods
  /// Crossfades to [next]. One-shot moods restart from their first frame.
  void setMood(LanternMood next) {
    if (next == _mood && next.loops) return;
    _fadeFrom = Map.of(_weights);
    _fadeT = 0;
    if (!next.loops) {
      _clips[next]!
        ..seek(0)
        ..play();
    }
    _prevFaceFrame = _currentFaceCell();
    _faceFrame = next.face.cell;
    _faceMix = 0;
    // Dizziness shows over everything: no passing reaction covers it.
    if (next == LanternMood.dizzy) {
      _faceOverride = null;
      _faceOverrideTimer = 0;
    }
    if (next == LanternMood.sleepy && _mood != LanternMood.sleepy) onSound?.call('yawn');
    _mood = next;
    _moodTimer = 0;
    notifyListeners();
  }

  /// Wakes from sleep with a quick surprised look. Returns whether it woke.
  bool wake() {
    _idle = 0;
    if (_mood != LanternMood.sleepy) return false;
    setMood(LanternMood.awake);
    _showFace(LanternFace.surprised, 0.45);
    _squash.velocity -= 2.2;
    onSound?.call('wake');
    return true;
  }

  /// Tests a tap's [ray] against the head. On a hit the head dents at the
  /// contact point and plays the poke reaction. Returns whether it hit.
  bool poke(Scene scene, Ray ray) {
    _idle = 0;
    final hit = scene.raycast(ray, where: (n) => n == _head);
    if (hit == null) return false;
    if (_mood == LanternMood.sleepy) {
      wake();
      return true;
    }
    soft.impulse(_toHead(hit.worldPoint), 3.4);
    setMood(LanternMood.poked);
    onSound?.call('poke');
    final toRoot = Matrix4.inverted(root.globalTransform);
    sparks.flecks(toRoot.transformed3(hit.worldPoint.clone()), toRoot.rotated3(hit.worldNormal.clone()));
    return true;
  }

  Vector3 _toHead(Vector3 world) => Matrix4.inverted(_head.globalTransform).transformed3(world.clone());

  /// Starts a press or pull if [ray] hits the head. Returns whether it hit.
  bool grab(Scene scene, Ray ray) {
    final hit = scene.raycast(ray, where: (n) => n == _head);
    if (hit == null) return false;
    _idle = 0;
    if (_mood == LanternMood.sleepy) wake();
    _grabWorld = hit.worldPoint.clone();
    _grabDir = _toHead(hit.worldPoint)..normalize();
    soft.press(_grabDir!, 0.22);
    _showFace(LanternFace.poked, 0.3);
    onSound?.call('squish');
    return true;
  }

  /// Whether a press or pull is in progress.
  bool get grabbing => _grabDir != null;

  /// How far the head is stretched right now, in head radii (0 at rest).
  double get grabStretch => soft.energy;

  /// Moves the held finger along [ray]: near the head it presses deeper,
  /// away from it the head stretches toward the finger like taffy.
  void drag(Ray ray) {
    final dir = _grabDir;
    if (dir == null) return;
    // Where the finger is now, on the plane through the grabbed point that
    // faces the camera, so a drag stretches across the screen, not into it.
    final anchor = _grabWorld!;
    final dirN = ray.direction.normalized();
    final t = (anchor - ray.origin).dot(dirN);
    final world = ray.origin + dirN * t;
    final target = _toHead(world);
    final grabbed = _toHead(anchor);
    final reach = (target - grabbed).length;
    if (reach < 0.35) {
      final depth = 0.22 + 0.3 * (1 - reach / 0.35);
      soft.press(dir, depth);
      // Seen from the front a press reads as the whole head giving way.
      _squash.target = depth * 0.55;
    } else {
      _squash.target = 0;
      soft.pull(dir, dir + (target - grabbed));
      _showFace(LanternFace.surprised, 0.2);
      if (!_stretching) onSound?.call('stretch');
    }
    _stretching = reach >= 0.35;
  }

  /// Lets go: the head snaps back, overshoots, and settles.
  bool _stretching = false;

  // A dizzy spin about the vertical after a hard snap back.
  double _spinT = -1;
  double _spinTurns = 0;
  double _spinAngle = 0;

  /// The head was stretched hard and let go: it snaps back so violently the
  /// friend spins round [direction] (1 turns the face toward the screen's
  /// left first, -1 toward its right), [strength] 0 to 1 setting how far,
  /// then comes to a wobbly stop, dizzy.
  void snapSpin(double direction, double strength) {
    _spinT = 0;
    // Whole turns, so it comes to rest facing front again.
    _spinTurns = direction.sign * (1 + strength.clamp(0.0, 1.0)).roundToDouble();
    soft.jiggle(1.4 + strength, _jiggleSeed++);
    _squash.velocity -= 6 * (0.5 + strength);
    _showFace(LanternFace.surprised, 0.4);
    onSound?.call('tumble');
  }

  void _stepSpin(double dt) {
    if (_spinT < 0) return;
    _spinT += dt;
    const length = 1.25;
    final u = (_spinT / length).clamp(0.0, 1.0);
    // Flung round fast, slowing to a stop with a little wobble back.
    final ease = 1 - math.pow(1 - u, 3).toDouble();
    _spinAngle = _spinTurns * math.pi * 2 * ease + math.sin(u * math.pi * 3) * 0.12 * u * (1 - u) * 4 * _spinTurns.sign;
    if (u >= 1) {
      _spinT = -1;
      _spinAngle = 0;
      setMood(LanternMood.dizzy);
      onSound?.call('dizzy');
    }
  }

  /// A lean into whatever is stroking the head, in radians (positive leans
  /// toward the screen's left); eased.
  double petLean = 0;
  double _petLean = 0;

  /// A tip about the feet (or the middle, for a floater), in radians,
  /// applied as is: positive tips toward the screen's left. For
  /// hand-animated moments like falling over.
  double tip = 0;

  /// Petting: a hand pressing the head at the world point [at] (on its
  /// surface), [depth] deep (about 0.1 to 0.25). The head dents under the
  /// hand, follows it as it moves, and gives a little all over.
  void pet(Vector3 at, double depth) {
    _idle = 0;
    soft.press(_toHead(at)..normalize(), depth);
    _squash.target = depth * 0.45;
  }

  /// The hand lifts off; the head rounds out again.
  void stopPet() {
    if (_grabDir != null) return;
    soft.release();
    _squash.target = 0;
  }

  void releaseGrab() {
    if (_grabDir == null) return;
    onSound?.call(_stretching ? 'snap_back' : 'squish');
    _stretching = false;
    _grabDir = null;
    _grabWorld = null;
    _squash.target = 0;
    soft
      ..release()
      ..jiggle(0.6, _jiggleSeed++);
    _squash.velocity -= 1.2;
  }

  /// Plays the celebration: a jump, a burst of sparks, a flash of glow.
  void celebrate() {
    _idle = 0;
    setMood(LanternMood.delighted);
    AppClock.delayed(const Duration(milliseconds: 380), () {
      burstAt(headCenter);
    });
  }

  /// Points the head and eyes toward a screen position, in -1..1 with y up,
  /// or stops following when [target] is null.
  void lookToward(Vector2? target, {bool curious = true}) {
    _idle = 0;
    if (target == null) {
      _looking = false;
      if (_mood == LanternMood.curious) setMood(LanternMood.awake);
      return;
    }
    _looking = true;
    _lookTarget.setFrom(target);
    if (curious && (_mood == LanternMood.awake)) setMood(LanternMood.curious);
  }

  /// Feeds the list's scroll velocity (logical px/s) into the float bob.
  void scrollVelocity(double pxPerSecond) {
    _idle = 0;
    _bob.target = (-pxPerSecond * 0.00012).clamp(-0.32, 0.32);
  }

  /// A hard fling makes the character dizzy for a moment.
  void fling(double pxPerSecond) {
    _idle = 0;
    _bob.target = 0;
    _bob.velocity += (-pxPerSecond * 0.0006).clamp(-3.0, 3.0);
    if (pxPerSecond.abs() > 2200 && _mood != LanternMood.sleepy) {
      setMood(LanternMood.dizzy);
    }
  }

  /// Turns every color of the theme around the hue wheel, in degrees.
  double get hueShift => _hueShift;
  double _hueShift = 0;
  set hueShift(double v) {
    _hueShift = v;
    _targetColors = ThemeColors.from(_theme, hueShift: v);
  }

  void setTheme(LanternTheme theme) {
    _theme = theme;
    _targetColors = ThemeColors.from(theme, hueShift: _hueShift);
    notifyListeners();
  }

  /// Finishes any crossfade at once, for jumps in time (scrubbing a show).
  void settle() {
    _fadeT = 1;
    for (final m in LanternMood.values) {
      _weights[m] = m == _mood ? 1.0 : 0.0;
    }
    _prevFaceFrame = _faceFrame;
    _faceMix = 1;
    _faceOverride = null;
    _faceOverrideTimer = 0;
    _glow = _mood.glow;
  }

  Vector3 _toRoot(Vector3 world) => Matrix4.inverted(root.globalTransform).transformed3(world.clone());

  /// Throws a ring of sparks from a point in world space.
  void burstAt(Vector3 world, {int count = 30}) => sparks.burst(_toRoot(world), count: count);

  /// Shows [face] for [seconds], then returns to the mood's own expression.
  void react(LanternFace face, double seconds) => _showFace(face, seconds);

  /// A physical jolt: the head squashes and springs back, scaled by
  /// [amount] (about 1 for a firework thump).
  void jolt(double amount) {
    _squash.velocity -= 1.6 * amount;
    soft.jiggle(0.5 * amount, _jiggleSeed++);
  }

  /// Places Lumi at [position], turned [yaw] radians about the vertical, at
  /// [scale].
  void place(Vector3 position, double yaw, {double scale = 1}) {
    root.localTransform =
        Matrix4.compose(position, Quaternion.axisAngle(Vector3(0, 1, 0), yaw), Vector3.all(scale)) *
        Matrix4.compose(Vector3(0, friend.lift, 0), Quaternion.identity(), Vector3.all(friend.scale));
  }

  /// Set while the friend is off the ground (flying in a game, out on an
  /// errand): feet dangle and paddle instead of standing.
  bool airborne = false;

  /// Set while the friend stands on something (the map, a lily pad, the
  /// floor Juju's little ones land on): the feet stay planted while the body
  /// bobs. Otherwise a friend with feet is floating, and they swim gently,
  /// each at its own pace.
  bool grounded = false;
  double _ground = 0;

  /// Running, standing: how hard (0 to 1), and which way along the friend's
  /// own x (the sign). The feet take turns striding.
  double run = 0;

  // Walking on something (see [grounded]): each foot plants on the ground
  // and stays put while the body moves over it, then steps, in turn, when the
  // body has moved a stride on. The body rises through each step and squashes
  // as the foot lands. A jump lifts both feet; they plant again on landing.
  final List<_Footing> _footings = [];
  bool _onGround = false;
  double _groundY = 0;
  double _plantBlend = 0;
  double _gaitLift = 0;
  final Vector3 _lastRootWorld = Vector3.zero();
  final Vector3 _rootVelocity = Vector3.zero();
  bool _rootWorldKnown = false;

  /// Called as each foot lands while walking (for a footstep sound).
  void Function()? onStep;

  /// The swing of the walk, -1 to 1: which foot is stepping and how far
  /// through, for arms that pump in time.
  double get stride {
    for (var i = 0; i < _footings.length && i < _footBase.length; i++) {
      final f = _footings[i];
      if (f.step >= 0) return _footBase[i].$3 * math.sin(math.pi * f.step);
    }
    return 0;
  }
  double _runPhase = 0;
  double _air = 0;

  // Secondary motion from being moved around: the root's velocity in the
  // rig's own units, springs that trail it, and the rig node they lean.
  final Vector3 _lastRoot = Vector3.zero();
  bool _rootKnown = false;
  final Vector3 _motion = Vector3.zero();
  final _trailX = _Spring(stiffness: 38, damping: 7);
  final _trailY = _Spring(stiffness: 38, damping: 7);
  final _trailZ = _Spring(stiffness: 38, damping: 7);
  Node? _lean;
  final List<(Vector3, Vector3, double)> _footBase = [];

  /// A world point the reaching hand (the one on the screen's right) goes
  /// for, or null to keep it home.
  Vector3? reachTarget;
  double _reach = 0;
  // The last point reached for, so the hand eases home from there after the
  // target clears instead of snapping back.
  final Vector3 _reachAt = Vector3.zero();

  /// The same for the other hand (on the screen's left), for holding
  /// something with both.
  Vector3? reachTargetR;
  double _reachR = 0;
  final Vector3 _reachAtR = Vector3.zero();

  /// World-space position of the other hand.
  Vector3 get handWorldR => root.getChildByName('HandR')!.globalTransform.getTranslation();

  /// How high the soles of the feet sit above the root right now, or null
  /// for Lumi, who floats.
  double? get footing {
    if (_feet.isEmpty) return null;
    final g = root.globalTransform;
    final s = g.getMaxScaleOnAxis();
    final low = _feet.map((n) => n.globalTransform.getTranslation().y).reduce(math.min);
    return low - friend.foot!.$2 * s - g.getTranslation().y;
  }

  /// The head's resting center relative to the root, at the root's own
  /// scale, and its radius: where to aim when placing the friend by its head.
  Vector3 get restHead => Vector3(0, friend.lift + (1.8 + friend.headOffset.$2) * friend.scale, 0);
  double get headRadius => (friend.isLantern ? 0.62 : friend.head.$2) * friend.scale;

  /// Where its lowest point rests relative to the root (feet, or Lumi's wisp).
  double get restFeet => friend.foot == null
      ? friend.lift + 0.47 * friend.scale
      : friend.lift + (0.6 + friend.footOffset.$2 - friend.foot!.$2) * friend.scale;

  /// The mouth, in world space: low on the front of the head.
  /// (Turned with the friend, so it stays on its face when it faces away
  /// from the camera.)
  Vector3 get mouthWorld {
    final r = headRadius / friend.scale;
    return headCenter + root.globalTransform.rotated3(Vector3(0, -r * 0.3, r * 0.92 * kFaceZ));
  }

  /// The way the friend faces, in the world, level.
  Vector3 get facing {
    final f = root.globalTransform.rotated3(Vector3(0, 0, kFaceZ))..y = 0;
    return f.normalized();
  }

  /// The front of the tummy, in world space, and roughly how round it is.
  Vector3 get bellyWorld {
    final body = root.getChildByName('Body')!.globalTransform.getTranslation();
    return body + root.globalTransform.rotated3(Vector3(0, 0, bellyRadius / friend.scale * 0.85 * kFaceZ));
  }

  double get bellyRadius => (friend.body?.$1 ?? 0.38) * friend.scale;

  /// Where a jet of thrust leaves the friend, in world space: each foot's
  /// sole, or the tip of Lumi's wisp.
  List<Vector3> get jetPoints {
    final g = root.globalTransform;
    final s = g.getMaxScaleOnAxis();
    if (_feet.isEmpty) {
      return [root.getChildByName('Wisp')!.globalTransform.getTranslation() - Vector3(0, 0.12 * s, 0)];
    }
    return [for (final f in _feet) f.globalTransform.getTranslation() - Vector3(0, friend.foot!.$2 * s, 0)];
  }

  /// World-space position of the reaching hand.
  Vector3 get handWorld => root.getChildByName('HandL')!.globalTransform.getTranslation();

  /// Turns the head and eyes toward a world point, or back to rest when
  /// [target] is null. Unlike [lookToward], this never changes the mood.
  void lookAtWorld(Vector3? target) {
    if (target == null) {
      _looking = false;
      return;
    }
    final local = Matrix4.inverted(root.globalTransform).transformed3(target.clone());
    final d = local - Vector3(0, 1.8, 0);
    final yaw = math.atan2(-d.x * -kFaceZ, -d.z * -kFaceZ);
    final pitch = math.atan2(d.y, math.sqrt(d.x * d.x + d.z * d.z));
    _looking = true;
    _lookTarget.setValues(
      (yaw / (0.42 * kFaceZ)).clamp(-1.4, 1.4),
      (pitch / 0.3 - 0.9).clamp(-1.0, 1.4),
    );
  }

  /// Points the eyes (and, more slowly, the head) at a screen position in
  /// -1..1 with y up, or back at the guest when null. Used by the attention
  /// system; an explicit [lookToward] or [lookAtWorld] takes priority.
  void gaze(Vector2? target, {bool blink = false}) {
    final next = target ?? Vector2.zero();
    if (blink && _blinkLeft <= 0 && (_mood == LanternMood.awake || _mood == LanternMood.curious)) {
      _blinkTimer = 0.05;
    }
    _gaze.setFrom(next);
  }

  /// The four corner weights for the current [moodPoint], in [_corners] order.
  List<double> get moodWeights {
    final p = moodPoint ?? Vector2(0.6, 0.2);
    final u = ((p.x + 1) / 2).clamp(0.0, 1.0), v = ((p.y + 1) / 2).clamp(0.0, 1.0);
    return [(1 - u) * v, u * v, (1 - u) * (1 - v), u * (1 - v)];
  }

  bool get _padActive => moodPoint != null && _mood == LanternMood.awake && _fadeT >= 1;

  /// Glowing parts in world space with their color and strength: the two
  /// hands and the head, for light painted onto the screen around Lumi.
  Iterable<(Vector3, Vector3, double)> get glowSources sync* {
    final g = _glow * glowScale * friend.glow;
    if (!friend.isLantern) {
      final pal = _palette;
      final c = (pal.accent?.emissive ?? 0) > 0 ? pal.accent!.base : pal.head.base;
      final color = Vector3(c.$1, c.$2, c.$3);
      for (final n in const ['HandL', 'HandR']) {
        yield (root.getChildByName(n)!.globalTransform.getTranslation(), color, g * 0.6);
      }
      yield (headCenter, color, g);
      return;
    }
    final ember = Vector3(_colors.ember.x, _colors.ember.y, _colors.ember.z);
    for (final n in const ['HandL', 'HandR']) {
      yield (root.getChildByName(n)!.globalTransform.getTranslation(), ember, g);
    }
    yield (headCenter, Vector3(_colors.rim.x, _colors.rim.y, _colors.rim.z), g * 0.6);
  }

  /// World-space center of the head.
  Vector3 get headCenter => _head.globalTransform.getTranslation();

  // ---------------------------------------------------------------- frame
  double _time = 0;
  double _lastDt = 0;

  void update(double dt, double time) {
    dt = dt.clamp(0.0, 1 / 20);
    _lastDt = dt;
    _time = time;
    _moodTimer += dt;
    _idle += dt;

    // Hand one-shots back once they finish; time out the dizzy spell; doze
    // off after a while with no attention.
    if (!_mood.loops) {
      final clip = _clips[_mood]!;
      final duration = root.findAnimationByName(_mood.clip)!.endTime;
      if (clip.playbackTime >= duration - fadeSeconds * 0.4) {
        setMood(_looking && restMood == LanternMood.awake ? LanternMood.curious : restMood);
      }
    } else if (_mood == LanternMood.dizzy && _moodTimer > 1.9) {
      setMood(restMood);
    } else if (canDoze && _idle > dozeAfter && _mood == LanternMood.awake) {
      setMood(LanternMood.sleepy);
    }

    _stepSneeze(dt);
    _stepBloom(dt);
    _updateWeights(dt);
    _updateFace(dt);
    _updateMotion(dt, time);
    _updateMaterials(dt, time);
    _stepTumble(dt);
    sparks
      ..ambientAmount = !friend.ambientSparks ? 0.0 : (_mood == LanternMood.sleepy ? 0.45 : 1.0)
      ..starAmount = _approach(sparks.starAmount, _mood == LanternMood.dizzy ? 1 : 0, dt * 6)
      ..update(dt, time, _toRoot(headCenter));
  }

  void _updateWeights(double dt) {
    if (_fadeT < 1) {
      _fadeT = math.min(1, _fadeT + dt / math.max(fadeSeconds, 1e-3));
      final e = _smooth(_fadeT);
      for (final m in LanternMood.values) {
        final from = _fadeFrom[m] ?? 0;
        final to = m == _mood ? 1.0 : 0.0;
        _weights[m] = from + (to - from) * e;
      }
    }
    if (_padActive) {
      // The emotion pad: four corner clips blended continuously.
      final w = moodWeights;
      final k = 1 - math.exp(-dt * 6);
      for (final m in LanternMood.values) {
        final i = _corners.indexOf(m);
        final to = i >= 0 ? w[i] : 0.0;
        _weights[m] = _weights[m]! + (to - _weights[m]!) * k;
      }
    } else if (_fadeT >= 1 && _mood == LanternMood.awake) {
      // Leaving the pad: ease the corners out.
      final k = 1 - math.exp(-dt * 6);
      for (final m in LanternMood.values) {
        final to = m == _mood ? 1.0 : 0.0;
        _weights[m] = _weights[m]! + (to - _weights[m]!) * k;
      }
    }
    for (final m in LanternMood.values) {
      _clips[m]!.weight = _weights[m]!;
      if (_corners.contains(m) && !_clips[m]!.playing && _weights[m]! > 0) _clips[m]!.play();
    }
  }

  void _updateFace(double dt) {
    if (_padActive) {
      // Cross-dissolve between the two strongest corners' expressions.
      final w = moodWeights;
      final order = [0, 1, 2, 3]..sort((a, b) => w[b].compareTo(w[a]));
      final a = order[0], b = order[1];
      _faceFrame = _corners[a].face.cell;
      _prevFaceFrame = _corners[b].face.cell;
      _faceMix = (0.5 + (w[a] - w[b]) / math.max(w[a] + w[b], 1e-3)).clamp(0.5, 1.0);
    }
    _faceMix = math.min(1, _faceMix + dt / math.max(fadeSeconds * 0.6, 1e-3));
    if (_faceOverrideTimer > 0) {
      _faceOverrideTimer -= dt;
      if (_faceOverrideTimer <= 0) {
        _prevFaceFrame = _faceOverride!.cell;
        _faceOverride = null;
        _faceMix = 0;
      }
    }

    // Blink now and then while awake.
    final canBlink =
        _mood == LanternMood.awake || _mood == LanternMood.curious;
    if (_blinkLeft > 0) {
      _blinkLeft -= dt;
    } else if (canBlink) {
      _blinkTimer -= dt;
      if (_blinkTimer <= 0) {
        _blinkLeft = 0.13;
        _blinkTimer = 2.4 + math.Random().nextDouble() * 3.2;
      }
    }
  }

  double _currentFaceCell() {
    if (_faceOverride != null) return _faceOverride!.cell;
    return _faceMix >= 0.5 ? _faceFrame : _prevFaceFrame;
  }

  void _showFace(LanternFace face, double seconds) {
    if (_mood == LanternMood.dizzy) return;
    _faceOverride = face;
    _faceOverrideTimer = seconds;
  }

  /// Follow-through from being moved: the whole friend leans into its
  /// travel, the soft head sloshes against changes of speed, and (in
  /// [_updateMotion]) the hands, wisp, and feet trail behind.
  void _stepSecondary(double dt, double time) {
    if (dt <= 0) return;
    final g = root.globalTransform;
    final p = g.getTranslation();
    final world = (p - _lastRoot)..scale(1 / dt);
    _lastRoot.setFrom(p);
    final scale = math.max(g.getMaxScaleOnAxis(), 1e-3);
    // Ignore jumps (placed somewhere new) and the tumble's own spin.
    final jump = !_rootKnown || _tumbleT >= 0 || world.length / scale > 40;
    _rootKnown = true;
    final local = jump ? Vector3.zero() : (Matrix4.inverted(g)..setTranslation(Vector3.zero())).transformed3(world);
    final before = _motion.clone();
    _motion.add((local - _motion)..scale(1 - math.exp(-dt * 12)));
    final accel = (_motion - before)..scale(1 / dt);
    _trailX
      ..target = _motion.x
      ..step(dt);
    _trailY
      ..target = _motion.y
      ..step(dt);
    _trailZ
      ..target = _motion.z
      ..step(dt);
    _air = _approach(_air, airborne ? 1 : 0, dt * 3);

    // Roll into sideways travel, pitch into forward travel, about the
    // middle of the body. The trailing springs overshoot a little when the
    // motion stops, so it settles back with a sway.
    if (_lean == null) {
      _lean = root.getChildByName('Lantern');
      if (_lean == null) {
        final lean = Node(name: 'Lean');
        for (final c in List.of(root.children)) {
          root.remove(c);
          lean.add(c);
        }
        root.add(lean);
        _lean = lean;
      }
    }
    // Standing, the lean pivots at the feet so they stay planted; flying,
    // about the middle.
    final grounded = _feet.isEmpty ? 0.0 : 1 - _air;
    final pivot = 1.1 - 0.65 * grounded;
    final amount = 1 - 0.35 * grounded;
    _petLean += (petLean - _petLean) * (1 - math.exp(-dt * 4));
    final roll = (-_trailX.position * 0.05 * amount).clamp(-0.3, 0.3) + _petLean + tip;
    final pitch = (_trailZ.position * 0.035 * amount).clamp(-0.22, 0.22);
    _stepSpin(dt);
    _lean!.localTransform = Matrix4.translation(Vector3(0, _gaitLift, 0)) *
        Matrix4.rotationY(_spinAngle) *
        Matrix4.translation(Vector3(0, pivot, 0)) *
        Matrix4.rotationZ(roll) *
        Matrix4.rotationX(pitch) *
        Matrix4.translation(Vector3(0, -pivot, 0));

    // The soft head lags behind changes of speed, the top most of all.
    final a = Vector3(accel.x, accel.y * 0.5, accel.z)..scale(0.06 / 0.62);
    if (a.length > 3.5) a.scale(3.5 / a.length);
    if (!jump) soft.drag(a, dt);
  }

  /// Advances the planted feet for this frame (see [_footings]).
  void _stepGait(double dt, bool standing) {
    final g = root.globalTransform;
    final unit = g.getMaxScaleOnAxis();
    final rootWorld = g.getTranslation();
    if (_rootWorldKnown && dt > 0) {
      final v = (rootWorld - _lastRootWorld)..scale(1 / dt);
      // A teleport (placed somewhere new) is not a velocity.
      if (v.length < 40 * math.max(unit, 0.05)) _rootVelocity.setFrom(v);
    }
    _lastRootWorld.setFrom(rootWorld);
    _rootWorldKnown = true;
    while (_footings.length < _footBase.length) {
      _footings.add(_Footing());
    }
    if (_feet.isEmpty || !standing || unit < 0.05) {
      _onGround = false;
      _plantBlend = _approach(_plantBlend, 0, dt * 6);
      _gaitLift *= math.exp(-dt * 10);
      for (final f in _footings) {
        f
          ..planted = false
          ..step = -1;
      }
      return;
    }
    // Where the ground is under the body now: the soles at rest.
    final sole = rootWorld.y + restFeet * unit / friend.scale;
    Vector3 home(int i) {
      final (size, offset, _) = _footBase[i];
      return g.transformed3(Vector3(offset.x, 0, offset.z))..y = _groundY + size.y * unit;
    }

    if (!_onGround) {
      // Landing (or starting to stand): plant both feet where they are.
      if (_plantBlend > 0.5 && sole > _groundY + 0.04 * unit) return;
      if (_rootVelocity.y > 0.05 * unit && _plantBlend > 0.5) return;
      _onGround = true;
      _groundY = sole;
      for (var i = 0; i < _footings.length; i++) {
        _footings[i]
          ..plant.setFrom(home(i))
          ..planted = true
          ..step = -1;
      }
      if (_plantBlend > 0.5) _squash.velocity -= 0.6;
    } else if (sole > _groundY + 0.1 * unit) {
      // Off the ground: a jump. The feet go with the body.
      _onGround = false;
      _squash.velocity += 0.5;
      return;
    } else {
      // Following gentle rises and falls in the ground.
      _groundY += (sole - _groundY) * (1 - math.exp(-dt * 3));
    }
    _plantBlend = _approach(_plantBlend, 1, dt * 8);

    final speed = Vector2(_rootVelocity.x, _rootVelocity.z).length / math.max(unit, 1e-3);
    final duration = (0.24 - 0.025 * speed).clamp(0.13, 0.24);
    final lead = Vector3(_rootVelocity.x, 0, _rootVelocity.z)..scale(duration * 0.6);
    final stride = 0.12 * unit;
    var stepping = false;
    var lift = 0.0;
    for (var i = 0; i < _footings.length; i++) {
      final f = _footings[i];
      if (f.step < 0) continue;
      stepping = true;
      f.step += dt / f.duration;
      f.to.setFrom(home(i) + lead);
      if (f.step >= 1) {
        f
          ..plant.setFrom(f.to)
          ..step = -1;
        // The foot lands: a little squash through the body.
        _squash.velocity -= 0.35 + 0.1 * math.min(speed, 3);
        onStep?.call();
      } else {
        lift = math.max(lift, math.sin(math.pi * f.step));
      }
    }
    if (!stepping) {
      // The foot that has fallen furthest behind steps next, once the body
      // is a stride past it (or, standing still, to tidy up where it is).
      var best = -1;
      var far = 0.0;
      for (var i = 0; i < _footings.length; i++) {
        final d = home(i) - _footings[i].plant;
        final reach = Vector2(d.x, d.z).length;
        if (reach > far) {
          far = reach;
          best = i;
        }
      }
      final settle = speed < 0.3 && far > 0.035 * unit;
      if (best >= 0 && (far > stride || settle)) {
        _footings[best]
          ..from.setFrom(_footings[best].plant)
          ..to.setFrom(home(best) + lead)
          ..duration = settle ? 0.2 : duration
          ..step = 0;
        // Lifting off: a stretch.
        _squash.velocity += 0.2;
      }
    }
    // The body rises as a foot swings through, and settles as it lands.
    _gaitLift += (0.07 * lift - _gaitLift) * (1 - math.exp(-dt * 18));
  }

  /// Foot [i] planted (or mid-step), as a transform under its parent.
  Matrix4 _plantedFoot(int i, Vector3 size) {
    final f = _footings[i];
    final unit = root.globalTransform.getMaxScaleOnAxis();
    var at = f.plant.clone();
    var pitch = 0.0;
    if (f.step >= 0) {
      final u = 0.5 - 0.5 * math.cos(math.pi * f.step.clamp(0.0, 1.0));
      at = f.from + (f.to - f.from) * u;
      at.y += 0.12 * unit * math.sin(math.pi * f.step);
      // Toes up on the way, down to land.
      pitch = -0.5 * math.sin(math.pi * f.step) * kFaceZ;
    }
    final parent = _feet[i].parent!.globalTransform;
    final local = Matrix4.inverted(parent).transformed3(at);
    return Matrix4.compose(local, Quaternion.axisAngle(Vector3(1, 0, 0), pitch), size);
  }

  void _updateMotion(double dt, double time) {
    _stepSecondary(dt, time);
    // Look: ease toward the finger, or back to center.
    final target = _looking ? _lookTarget : _gaze;
    // The eyes snap to their target; the head follows only part of the way
    // unless the target is far off to the side, and it trails behind.
    _eyes.add((target - _eyes)..scale(1 - math.exp(-dt * 28)));
    final headTarget = _looking ? target : (target.length > 0.6 ? target : target * 0.45);
    _look.add((headTarget - _look)..scale(1 - math.exp(-dt * 5.5)));

    _bob.step(dt);
    if (!_looking) _bob.target *= math.exp(-dt * 3);
    _handLag.target = _bob.position;
    _handLag.step(dt);
    _squash.step(dt);
    _explode = _approach(_explode, explodeTarget, dt * 3.5);
    final ex = _smooth(_explode);

    final lag = _handLag.position - _bob.position;
    final squashAmount = (1 - squash) * 2.2;
    final sq = (_squash.position * squashAmount).clamp(-0.25, 0.25);

    final hop = _antics(dt, time);
    final breathe = friend.extras == FriendExtras.sprout ? math.sin(time * 1.5) * 0.022 : 0.0;
    _fx['Head']!.localTransform = Matrix4.compose(
      Vector3(0, _bob.position + hop + 0.42 * ex, 0),
      Quaternion.axisAngle(Vector3(0, 1, 0), _look.x * 0.42 * kFaceZ) *
          Quaternion.axisAngle(Vector3(1, 0, 0), -_look.y * 0.3 * kFaceZ),
      Vector3(1 + sq - breathe * 0.5, 1 - sq + breathe, 1 + sq - breathe * 0.5),
    );
    _fx['Body']!.localTransform = Matrix4.translation(
      Vector3(0, _bob.position * 0.85 + hop + 0.08 * ex, 0),
    );
    // The left hand (on the right of the screen) can leave its spot to
    // reach for something.
    // Follow a moving target with a little lag, so the hand glides, and
    // ease back home from the last point once the target clears.
    double track(Vector3? target, double amount, Vector3 at) {
      if (target != null) {
        if (amount < 1e-3) {
          at.setFrom(target);
        } else {
          at.add((target - at)..scale(1 - math.exp(-dt * 14)));
        }
      }
      return _approach(amount, target == null ? 0 : 1, dt * (target == null ? 3.2 : 5));
    }

    Vector3 reachToward(String part, Vector3 home, double amount, Vector3 at) {
      if (amount <= 1e-3) return home;
      final ctrl = _fx[part]!.parent!.globalTransform;
      final mesh = root.getChildByName(part)!.localTransform.getTranslation();
      final want = Matrix4.inverted(ctrl).transformed3(at.clone()) - mesh;
      return home + (want - home) * _smooth(amount);
    }

    _reach = track(reachTarget, _reach, _reachAt);
    _reachR = track(reachTargetR, _reachR, _reachAtR);
    // Hands trail the travel and lift a little with speed; flying, they
    // flap.
    final trailX = (-_trailX.position * 0.035).clamp(-0.2, 0.2);
    final trailY = (-_trailY.position * 0.025).clamp(-0.15, 0.15);
    final speed = math.min(1.0, _motion.length / 6);
    final flap = math.sin(time * 9) * 0.05 * _air * (0.35 + speed);
    var hand = Vector3(-0.45 * ex + trailX, _bob.position + hop + lag * 1.6 + 0.18 * ex + trailY + speed * 0.06 + flap, 0);
    hand = reachToward('HandL', hand, _reach, _reachAt);
    _fx['HandL']!.localTransform = Matrix4.translation(hand);
    var handR = Vector3(0.45 * ex + trailX, _bob.position + hop + lag * 1.9 + 0.18 * ex + trailY + speed * 0.06 + flap, 0);
    handR = reachToward('HandR', handR, _reachR, _reachAtR);
    // Holding the umbrella up beside the head (unless reaching elsewhere).
    _umbrellaPose = _approach(_umbrellaPose, _umbrella != null && reachTargetR == null ? 1 : 0, dt * 3);
    if (_umbrellaPose > 1e-3) {
      final (grip, _, _) = _umbrellaFrame;
      handR = reachToward('HandR', handR, _umbrellaPose, (_lean ?? root).globalTransform.transformed3(grip.clone()));
    }
    // Shy: both hands come up over the face; every so often they part a
    // little for a peek.
    _shyClock += dt;
    final peeking = _shy > 0.5 && (_shyClock % 1.8) > 1.35;
    _shy = _approach(_shy, shyTarget * (peeking ? 0.55 : 1), dt * 6);
    if (_shy > 1e-3) {
      Vector3 cover(String part, double side) {
        final ctrl = _fx[part]!.parent!.globalTransform;
        final mesh = root.getChildByName(part)!.localTransform.getTranslation();
        final r = headRadius;
        final target = headCenter + Vector3(side * r * 0.42, -r * 0.08, r * 1.05 * kFaceZ) * (root.globalTransform.getMaxScaleOnAxis() / friend.scale);
        return Matrix4.inverted(ctrl).transformed3(target) - mesh;
      }

      final k = _smooth(_shy);
      hand += (cover('HandL', -1) - hand) * k;
      handR += (cover('HandR', 1) - handR) * k;
      _fx['HandL']!.localTransform = Matrix4.translation(hand);
      if (_shy > 0.5 && !peeking) _showFace(LanternFace.content, 0.1);
      if (peeking) _showFace(LanternFace.curious, 0.1);
    }
    _fx['HandR']!.localTransform = Matrix4.translation(handR);
    final umbrella = _umbrella;
    if (umbrella != null) {
      // In the hand, leaning in over the head.
      final parent = umbrella.parent!;
      final hand = root.getChildByName('HandR')!.globalTransform.getTranslation();
      final at = Matrix4.inverted(parent.globalTransform).transformed3(hand);
      final (grip, top, r) = _umbrellaFrame;
      final along = top - grip;
      final lean = math.atan2(-along.x, along.y);
      umbrella.localTransform = Matrix4.compose(at, Quaternion.axisAngle(Vector3(0, 0, 1), lean), Vector3.all(1));
      // The canopy sits closer to level than the stick leans.
      umbrella.children.first.localTransform =
          Matrix4.compose(Vector3(0, along.length, 0), Quaternion.axisAngle(Vector3(0, 0, 1), -lean * 0.6), Vector3(r * 1.25, r * 0.42, r * 1.25));
    }
    final wisp = Vector3(trailX * 1.3, _bob.position * 0.7 + hop * (_feet.isEmpty ? 1 : 0.92) + lag * 2.4 - 0.24 * ex + trailY * 1.2, 0);
    _fx['Wisp']!.localTransform = Matrix4.translation(wisp);
    // Feet: planted when standing (they keep still while the body bobs, and
    // stride in turn when running); swimming when floating, each foot on its
    // own slow cycle; and in flight, hanging loose with the toes dropped,
    // trailing the travel and paddling in turn.
    _ground = _approach(_ground, grounded ? 1 : 0, dt * 6);
    final ground = _ground * (1 - _air);
    _stepGait(dt, ground > 0.5);
    final swim = (1 - _ground) * (1 - _air);
    _runPhase += dt * (8 + 6 * run.abs());
    for (var i = 0; i < _feet.length && i < _footBase.length; i++) {
      final (size, offset, side) = _footBase[i];
      final paddle = math.sin(time * (6 + 5 * speed) + (side < 0 ? 0 : math.pi));
      final step = _runPhase + (side < 0 ? 0 : math.pi);
      final f = side < 0 ? 0.0 : 1.0;
      final swimA = time * (1.55 + 0.4 * f) + f * 2.1;
      final swimB = time * (1.15 + 0.3 * f) + f * 0.9;
      final dangle = Vector3(
        trailX * 0.8 * _air + math.cos(step) * 0.08 * run * ground + math.sin(swimB) * 0.015 * swim,
        (-0.09 + 0.05 * paddle * (0.5 + speed) + trailY * 0.8) * _air +
            (math.max(0.0, math.sin(step)) * 0.1 * run.abs() - (wisp.y - hop)) * ground +
            (-0.03 + 0.03 * math.sin(swimA)) * swim,
        0.04 * paddle * _air * kFaceZ + 0.025 * math.cos(swimA * 0.9 + f) * swim * kFaceZ,
      );
      final rot = Quaternion.axisAngle(Vector3(1, 0, 0), ((0.45 + 0.15 * paddle) * _air + (0.12 + 0.12 * math.sin(swimA + 0.7)) * swim) * kFaceZ) *
          Quaternion.axisAngle(Vector3(0, 0, 1), (-_trailX.position * 0.03).clamp(-0.3, 0.3) * _air + 0.08 * math.sin(swimB + f) * swim);
      final free = Matrix4.compose(offset + dangle, rot, size);
      final planted = _plantBlend > 1e-3 && i < _footings.length ? _plantedFoot(i, size) : null;
      _feet[i].localTransform = planted == null ? free : _mixTransforms(free, planted, _smooth(_plantBlend));
    }
    // Accessories sway against the head's motion.
    final head = headCenter;
    if (dt > 0) {
      _headVelocity.setFrom((head - _lastHead) / dt);
      if (_headVelocity.length > 20) _headVelocity.setZero();
    }
    _lastHead.setFrom(head);
    for (final s in _sway) {
      s.step(dt, _headVelocity);
    }

    // The face cap slides off the head in the exploded view, forward and to
    // the side so it reads as its own piece from the front.
    _faceNode.localTransform = Matrix4.translation(
      Vector3(0.62 * ex, 0.12 * ex, 0.5 * ex * kFaceZ),
    ) * _faceBase;
    // Nova's moon circles its head on a tilted orbit; the ring breathes.
    if (_moon case final moon?) {
      final a = time * 0.9;
      final c = Vector3(friend.headOffset.$1, friend.headOffset.$2, friend.headOffset.$3);
      moon.localTransform = Matrix4.translation(c + Vector3(math.cos(a) * 0.78, 0.5 + math.sin(a) * 0.16, math.sin(a) * 0.5));
    }
  }

  void _updateMaterials(double dt, double time) {
    _colors.approach(_targetColors, 1 - math.exp(-dt * 4));
    var glowTarget = _mood.glow;
    if (_padActive) {
      final w = moodWeights;
      glowTarget = 0;
      for (var i = 0; i < 4; i++) {
        glowTarget += w[i] * _corners[i].glow;
      }
    }
    _glow = _approach(_glow, glowTarget, dt * 2.5);
    final glow = _glow * glowScale;

    soft.update(dt);
    _rideHat();
    final ambC = Vector4(ambientColor.x, ambientColor.y, ambientColor.z, 0);
    final ambD = Vector4(ambientDirection.x, ambientDirection.y, ambientDirection.z, 0);
    for (final m in [_skin, _bodySkin, _face, _ember, ?_accent]) {
      m.parameters
        ..setVec4('ambient_color', ambC)
        ..setVec4('ambient_dir', ambD);
    }
    if (!friend.isLantern) {
      final k = 1 - math.exp(-dt * 4);
      final pal = _palette;
      _applyToy(_skin, pal.head, k, glow);
      _applyToy(_bodySkin, pal.body, k, glow);
      _applyToy(_ember, pal.hands, k, glow);
      if (pal.accent case final a?) _applyToy(_accent!, a, k, glow);
      final blinking = _blinkLeft > 0;
      final frame = blinking ? LanternFace.blink.cell : (_faceOverride?.cell ?? _faceFrame);
      final fc = ToyLook(base: pal.face, shade: pal.face).turned(_hueShift).base;
      _face.parameters
        ..setFloat('frame', frame)
        ..setFloat('prev_frame', blinking ? frame : _prevFaceFrame)
        ..setFloat('frame_mix', blinking || _faceOverride != null ? 1.0 : _faceMix)
        ..setVec2('look', Vector2(_eyes.x * 0.05 * kFaceZ, -_eyes.y * 0.035))
        ..setFloat('tint', friend.faceTint)
        ..setVec4('face_color', Vector4(fc.$1, fc.$2, fc.$3, 1))
        ..setFloat('glow', glow);
      _sparkAmbient.parameters
        ..setVec4('ember_color', Vector4(fc.$1, fc.$2, fc.$3, 1))
        ..setFloat('intensity', 2.2 * math.max(glow, 0.5));
      return;
    }
    for (final m in [_skin, _bodySkin]) {
      m.parameters
        ..setVec4('base_color', _colors.skin)
        ..setVec4('rim_color', _colors.rim)
        ..setVec4('inner_color', _colors.inner)
        ..setFloat('translucency', _colors.translucency)
        ..setFloat('glow', glow)
        ..setFloat('time', time);
    }

    final blinking = _blinkLeft > 0;
    final frame = blinking
        ? LanternFace.blink.cell
        : (_faceOverride?.cell ?? _faceFrame);
    _face.parameters
      ..setFloat('frame', frame)
      ..setFloat('prev_frame', blinking ? frame : _prevFaceFrame)
      ..setFloat('frame_mix', blinking || _faceOverride != null ? 1.0 : _faceMix)
      ..setVec2('look', Vector2(_eyes.x * 0.05 * kFaceZ, -_eyes.y * 0.035))
      ..setFloat('glow', glow);

    final emberPulse = 1 + 0.08 * math.sin(time * 5.3);
    _ember.parameters
      ..setVec4('ember_color', _colors.ember)
      ..setFloat('intensity', 2.3 * glow * emberPulse);
    _sparkAmbient.parameters
      ..setVec4('ember_color', _colors.ember)
      ..setFloat('intensity', 2.6 * math.max(glow, 0.5));
  }

  static double _approach(double v, double target, double k) =>
      v + (target - v) * math.min(1, k);

  static double _smooth(double x) => x * x * (3 - 2 * x);

  static double _easeOutBack(double t) {
    const c1 = 1.70158, c3 = c1 + 1;
    final x = t.clamp(0.0, 1.0) - 1;
    return 1 + c3 * x * x * x + c1 * x * x;
  }
}

/// A damped spring toward [target].
class _Spring {
  _Spring({required this.stiffness, required this.damping});
  final double stiffness;
  final double damping;
  double position = 0;
  double velocity = 0;
  double target = 0;

  void step(double dt) {
    final a = (target - position) * stiffness - velocity * damping;
    velocity += a * dt;
    position += velocity * dt;
  }
}


/// A dangling accessory part (a pom-pom, a scarf tail) that lags behind the
/// head and wobbles back.
class _Sway {
  _Sway(this.owner, this.node, this.amount) : rest = node.localTransform.clone();

  /// The accessory this part belongs to.
  final Node owner;
  final Node node;
  final double amount;
  final Matrix4 rest;
  final Vector3 _pos = Vector3.zero();
  final Vector3 _vel = Vector3.zero();

  void step(double dt, Vector3 headVelocity) {
    if (dt <= 0) return;
    final target = headVelocity * (-0.045 * amount);
    final a = (target - _pos) * 90.0 - _vel * 7.0;
    _vel.addScaled(a, dt);
    _pos.addScaled(_vel, dt);
    node.localTransform = Matrix4.translation(_pos) * rest;
  }
}


/// A toy material's colors, eased toward a target so color changes blend.
class _ToyState {
  _ToyState.from(ToyLook t) : base = _v(t.base), shade = _v(t.shade), rim = _v(t.rim);

  final Vector4 base, shade, rim;

  void approach(ToyLook t, double k) {
    base.add((_v(t.base) - base)..scale(k));
    shade.add((_v(t.shade) - shade)..scale(k));
    rim.add((_v(t.rim) - rim)..scale(k));
  }

  static Vector4 _v(V3 c) => Vector4(c.$1, c.$2, c.$3, 1);
}

/// One foot's hold on the ground while walking (see the friend's gait).
class _Footing {
  final Vector3 plant = Vector3.zero();
  final Vector3 from = Vector3.zero();
  final Vector3 to = Vector3.zero();
  bool planted = false;

  /// Progress through a step, 0 to 1, or -1 while planted.
  double step = -1;
  double duration = 0.2;
}

/// Blends two transforms by [t]: their positions, rotations, and scales.
Matrix4 _mixTransforms(Matrix4 a, Matrix4 b, double t) {
  final pa = Vector3.zero(), pb = Vector3.zero(), sa = Vector3.zero(), sb = Vector3.zero();
  final qa = Quaternion.identity(), qb = Quaternion.identity();
  a.decompose(pa, qa, sa);
  b.decompose(pb, qb, sb);
  if (qa.dot(qb) < 0) qb.scale(-1);
  final q = Quaternion(qa.x + (qb.x - qa.x) * t, qa.y + (qb.y - qa.y) * t, qa.z + (qb.z - qa.z) * t, qa.w + (qb.w - qa.w) * t)..normalize();
  return Matrix4.compose(pa + (pb - pa) * t, q, sa + (sb - sa) * t);
}
