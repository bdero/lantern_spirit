import 'dart:math' as math;

import 'package:flutter_scene/kit.dart' show CameraShake;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../app/sfx.dart';
import '../lantern/character.dart';
import '../lantern/moods.dart';
import 'fireworks.dart';
import 'lagoon_set.dart';
import 'show_script.dart';

/// Runs the show: advances show time, places the camera, drives the set,
/// the fireworks, their light on everything, Lumi's acting, and the sound.
///
/// Everything visual is a function of show time, so [seek] can jump anywhere
/// and the frame is exactly what playing to that moment would have shown.
class ShowDirector {
  ShowDirector({
    required this.scene,
    required this.set,
    required this.fireworks,
    required this.lumi,
    required this.sfx,
    required this.script,
  }) {
    for (var i = 0; i < 6; i++) {
      final light = PointLight(color: Vector3.all(1), intensity: 0, range: 0);
      final node = Node(name: 'BurstLight$i')..addComponent(PointLightComponent(light));
      scene.add(node);
      _pool.add((node, light));
    }
    // Friends with feet stand on the deck; Lumi floats just over it.
    final stand = lumi.friend.foot == null ? 0.0 : lumi.restFeet - 0.02;
    lumi.place(kPierEnd - Vector3(0, stand, 0), math.pi);
    _head = kPierEnd + Vector3(0, lumi.restHead.y - stand, 0);
    lumi.restMood = LanternMood.watch;
    lumi.canDoze = false;
    lumi.setMood(LanternMood.watch);
  }

  final Scene scene;
  final LagoonSet set;
  final FireworkRenderer fireworks;
  final LanternCharacter lumi;
  final Sfx sfx;
  final ShowScript script;

  /// Where the friend's head rests on the pier, for framing close-ups.
  late final Vector3 _head;

  final PerspectiveCamera camera = PerspectiveCamera(position: Vector3(0.3, 3.4, -9.5), target: Vector3(0, 26, 140));
  final CameraShake _shake = CameraShake();
  final List<(Node, PointLight)> _pool = [];

  double time = 0;
  bool playing = true;
  double _prev = 0;
  int _nextBeat = 0;
  Launch? _gaze;
  double _gazeUntil = 0;

  /// Scales how strongly burst light reaches the set and Lumi.
  double lightScale = 1.0;

  /// Jumps to [t] without sounds, as if the show had played to it.
  void seek(double t) {
    time = t.clamp(0.0, ShowScript.length);
    _prev = time;
    sfx.cancelPending();
    _nextBeat = script.lumi.indexWhere((b) => b.time > time);
    if (_nextBeat < 0) _nextBeat = script.lumi.length;
    lumi.restMood = script.restingMoodAt(time);
    lumi.setMood(lumi.restMood);
    lumi.settle();
  }

  void update(double dt) {
    if (playing) time = math.min(ShowScript.length, time + dt);
    final forward = playing && time > _prev;

    _placeCamera(time, dt);
    fireworks.evaluate(script.launches, time, camera.position);
    _applyLight();
    set.update(time);
    set.townLights = time > ShowScript.finale && time < ShowScript.afterglow + 2 ? 0.65 : 1.0;

    if (forward) _events(_prev, time);
    _gazeAt(time);
    lumi.update(playing ? dt : 0, time);
    _prev = time;
  }

  // ---------------------------------------------------------------- events
  void _events(double from, double to) {
    while (_nextBeat < script.lumi.length && script.lumi[_nextBeat].time <= to) {
      final beat = script.lumi[_nextBeat++];
      if (beat.rest != null) lumi.restMood = beat.rest!;
      lumi.setMood(beat.mood);
    }
    for (final l in script.launches) {
      // Launch and burst are separate sounds on separate events. The shells
      // go up far across the lagoon, so a launch is only a faint mortar
      // thump (and only for the main shells); the bursts carry the show,
      // each heard after its own travel time.
      if (l.time > from && l.time <= to && l.main) {
        sfx.playFrom('mortar', source: l.pad, listener: camera.position, volume: 0.35, pitch: 0.9 + ((l.seed >> 3) % 20) / 100, rolloff: 220);
      }
      if (l.breakTime > from && l.breakTime <= to) {
        final big = l.main || l.size >= 1.2;
        sfx.playFrom(
          big ? 'burst_big_${1 + l.seed % 3}' : 'burst_small_${1 + l.seed % 2}',
          source: l.breakAt,
          listener: camera.position,
          volume: big ? 1.0 : 0.7,
          pitch: 0.94 + ((l.seed >> 5) % 12) / 100,
          rolloff: 220,
          onArrive: () {
            if (big) {
              Sfx.heavy();
              if (l.main) _shake.addTrauma(0.28);
            } else {
              Sfx.light();
            }
            lumi.jolt(big ? 0.6 : 0.3);
          },
        );
        if (l.kind == BurstKind.crackle || l.kind == BurstKind.willow) {
          sfx.playFrom('crackle', source: l.breakAt, listener: camera.position, volume: 0.6, rolloff: 220);
        }
        // New light pulls Lumi's gaze for a moment.
        _gaze = l;
        _gazeUntil = to + 1.4;
      }
    }
  }

  void _gazeAt(double t) {
    final g = _gaze;
    if (g != null && t < _gazeUntil && t >= g.breakTime) {
      lumi.lookAtWorld(g.breakAt);
    } else {
      lumi.lookAtWorld(null);
    }
  }

  // ---------------------------------------------------------------- light
  void _applyLight() {
    final lights = fireworks.lights.toList()..sort((a, b) => b.intensity.compareTo(a.intensity));
    var total = 0.0;
    final mix = Vector3.zero();
    for (final l in lights) {
      total += l.intensity;
      mix.addScaled(l.color, l.intensity);
    }
    for (var i = 0; i < _pool.length; i++) {
      final (node, light) = _pool[i];
      if (i < lights.length) {
        final l = lights[i];
        node.localTransform = Matrix4.translation(l.position);
        light.color = l.color;
        light.intensity = l.intensity * 9000 * lightScale;
      } else {
        light.intensity = 0;
      }
    }
    final strength = math.min(1.4, total * 0.4);
    if (lights.isNotEmpty) {
      final top = lights.first;
      final dir = (top.position - camera.position)..normalize();
      final c = mix / math.max(total, 1e-4);
      set.setFlash(dir, c, strength);
      // Lumi takes the same light, from the direction of the brightest.
      lumi.ambientColor.setFrom(c * (math.min(1.6, total * 0.5) * lightScale));
      lumi.ambientDirection.setFrom((top.position - lumi.headCenter)..normalize());
    } else {
      set.setFlash(Vector3(0, 0.4, 1), Vector3.zero(), 0);
      lumi.ambientColor.setZero();
    }
    // Exposure breathes with the show without ever clipping to white.
    scene.exposure = 1.0 / (1.0 + 0.07 * math.min(5.0, total));
  }

  // ---------------------------------------------------------------- camera
  static double _ease(double x) {
    x = x.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  static Vector3 _lerp(Vector3 a, Vector3 b, double t) => a + (b - a) * t;

  void _placeCamera(double t, double dt) {
    final head = _head;
    final dof = scene.depthOfField;
    dof.enabled = false;
    Vector3 pos;
    Vector3 target;
    double fov;
    if (t < ShowScript.firstBreak) {
      // Settle in: a slow push toward the pier.
      final k = _ease(t / ShowScript.firstBreak);
      pos = _lerp(Vector3(0.3, 3.4, -9.5), Vector3(0.3, 3.0, -7.0), k);
      target = _lerp(Vector3(0, 26, 140), Vector3(0, 32, 140), k);
      fov = 50 - 4 * k;
    } else if (t < ShowScript.closeUp) {
      // Over the shoulder, drifting toward the action.
      final k = _ease((t - ShowScript.firstBreak) / (ShowScript.closeUp - ShowScript.firstBreak));
      pos = _lerp(Vector3(0.3, 3.0, -7.0), Vector3(0.15, 2.8, -6.0), k);
      target = Vector3(0, 34, 140);
      fov = 46;
    } else if (t < ShowScript.build) {
      // Reaction close-up from the water side: Lumi's face lit by the show,
      // the lights behind the audience melting into bokeh.
      final k = _ease((t - ShowScript.closeUp) / (ShowScript.build - ShowScript.closeUp));
      final offset = _lerp(Vector3(0.9, 0.1, 7.6), Vector3(0.7, 0.0, 6.8), k);
      pos = head + offset;
      target = head + Vector3(0, -0.15, 0);
      fov = 30;
      dof
        ..enabled = true
        ..focusDistance = offset.length
        ..fStop = 1.0;
    } else if (t < ShowScript.finale) {
      // The build: a slow crane up and back.
      final k = _ease((t - ShowScript.build) / (ShowScript.finale - ShowScript.build));
      pos = _lerp(Vector3(-0.8, 2.8, -6.5), Vector3(-3.5, 9.0, -14.0), k);
      target = Vector3(0, 40, 140);
      fov = 46 + 6 * k;
    } else if (t < ShowScript.afterglow) {
      // The finale: wide and low behind Lumi.
      final k = _ease((t - ShowScript.finale) / (ShowScript.afterglow - ShowScript.finale));
      pos = _lerp(Vector3(0.3, 3.0, -6.8), Vector3(0.3, 2.9, -5.9), k);
      target = Vector3(0, 44, 140);
      fov = 60;
    } else if (t < ShowScript.returnAt) {
      // Afterglow: beside Lumi, the last willow drifting into the water.
      final k = _ease((t - ShowScript.afterglow) / (ShowScript.returnAt - ShowScript.afterglow));
      pos = _lerp(Vector3(3.6, 3.2, -7.5), Vector3(3.2, 3.0, -6.5), k);
      target = Vector3(-2.6, 8, 34);
      fov = 40;
    } else {
      // Back up and away, toward the card.
      final k = _ease((t - ShowScript.returnAt) / (ShowScript.length - ShowScript.returnAt));
      pos = _lerp(Vector3(3.2, 3.0, -6.5), Vector3(0.3, 14, -22), k);
      target = _lerp(Vector3(-2.6, 8, 34), Vector3(0, 30, 140), k);
      fov = 40 + 14 * k;
    }
    final shake = _shake.update(playing ? dt : 0);
    final jitter = shake.toMatrix4().getTranslation();
    camera
      ..position = pos + jitter
      ..target = target + jitter * 6
      ..fovRadiansY = fov * degrees2Radians;
  }
}
