import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/audio.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_soloud/flutter_scene_soloud.dart';
import 'package:vector_math/vector_math.dart';

import 'clock.dart';

/// Whether the app plays any audio. Haptics are unaffected either way.
const bool kAudioEnabled = true;

/// Speed of sound in world units per second (the world is in meters).
const double kSpeedOfSound = 343.0;

/// Sound effects for one scene, plus haptics.
///
/// Each experience owns one, attached to its scene root, so its sounds stop
/// when it unmounts. Clips load once per instance from `assets/sfx/`.
class Sfx {
  Sfx(Scene scene) {
    if (!kAudioEnabled) return;
    final engine = SoloudAudioEngine(bufferSize: 1024);
    scene.root.addComponent(engine);
    _engine = engine;
    _bus = engine.createBus('sfx');
  }

  // A small mix buffer keeps impacts tight to what is on screen. Null when
  // audio is off.
  SoloudAudioEngine? _engine;
  AudioBus? _bus;
  final Map<String, Future<AudioClip?>> _clips = {};
  final List<Timer> _pending = [];

  /// Mutes everything this instance plays.
  bool muted = false;

  Future<AudioClip?> _clip(String name) => _clips.putIfAbsent(name, () async {
    final engine = _engine;
    if (engine == null) return null;
    try {
      return await engine.loadClip('assets/sfx/$name.wav');
    } catch (e) {
      // Audio is optional; a missing device or backend should never break
      // the experience.
      return null;
    }
  });

  /// Starts loading [names] so their first play has no gap.
  void preload(Iterable<String> names) {
    for (final n in names) {
      _clip(n);
    }
  }

  /// Plays [name] once, flat (no position), optionally after [delay].
  void play(String name, {double volume = 1, double pitch = 1, Duration delay = Duration.zero}) {
    if (muted || (_engine == null && onRecord == null)) return;
    void go() async {
      final record = onRecord;
      if (record != null) {
        if (!muted) record({'sound': name, 'volume': volume, 'pitch': pitch});
        return;
      }
      final clip = await _clip(name);
      if (clip == null || muted) return;
      try {
        _engine?.playOneShot(clip, volume: volume, pitch: pitch, bus: _bus);
      } catch (_) {}
    }

    if (delay <= Duration.zero) {
      go();
    } else {
      _pending.add(AppClock.timer(delay, go));
    }
  }

  /// Plays [name] as heard from [listener] when it happens at [source]: it
  /// arrives after the sound's travel time and quieter with distance.
  void playFrom(
    String name, {
    required Vector3 source,
    required Vector3 listener,
    double volume = 1,
    double pitch = 1,
    double rolloff = 120,
    void Function()? onArrive,
  }) {
    // The arrival still drives haptics and reactions when audio is off.
    final d = source.distanceTo(listener);
    final delay = Duration(microseconds: (d / kSpeedOfSound * 1e6).round());
    final v = volume * (rolloff / (rolloff + d)).clamp(0.05, 1.0);
    play(name, volume: v, pitch: pitch, delay: delay);
    if (onArrive != null) _pending.add(AppClock.timer(delay, onArrive));
  }

  /// Starts a looping sound and returns a handle to stop it.
  Future<SfxLoop?> loop(String name, {double volume = 1}) async {
    final record = onRecord;
    if (record != null) {
      if (muted) return null;
      final id = _loopIds++;
      record({'loop': id, 'sound': name, 'volume': volume});
      _recordedLoops[id] = {'sound': name, 'volume': volume};
      return SfxLoop._(null, id, volume);
    }
    final clip = await _clip(name);
    final engine = _engine;
    if (clip == null || engine == null || muted) return null;
    try {
      final voice = engine.createVoice(clip)
        ..volume = volume
        ..looping = true
        ..setBus(_bus)
        ..setPositional(false);
      voice.start();
      return SfxLoop._(voice, null, volume);
    } catch (_) {
      return null;
    }
  }

  /// Cancels sounds still waiting on their travel delay.
  void cancelPending() {
    for (final t in _pending) {
      t.cancel();
    }
    _pending.clear();
  }

  void dispose() => cancelPending();

  /// While set, sounds are handed here (with what [play] and [loop] were
  /// given) instead of played, so a recording can mix them offline.
  static void Function(Map<String, Object?> event)? onRecord;
  static int _loopIds = 0;
  static final Map<int, Map<String, Object?>> _recordedLoops = {};

  /// Loops started while recording that are still going, by id.
  static Map<int, Map<String, Object?>> get recordedLoops => _recordedLoops;

  // ------------------------------------------------------------- app-wide
  /// The app's own sounds (UI, the friend, the park, the games), played
  /// through the park's scene, which stays mounted under every screen pushed
  /// over it. The fireworks show keeps its own.
  static Sfx? ui;

  /// Mutes [ui] (the creative panel's Sound switch).
  static final mute = ValueNotifier<bool>(false);

  static final Map<String, DateTime> _lastPlayed = {};

  /// How loud each app sound sits in the mix. The friend's own voice and
  /// body (chirps, squishes, sneezes, chewing) and other living things (the
  /// butterfly) stay soft and subtle, under the UI and the games.
  static const Map<String, double> _levels = {
    // The friend's voice.
    'chirp_happy': 0.28, 'chirp_curious': 0.28, 'chirp_sad': 0.28, 'giggle': 0.3, 'yawn': 0.25, 'snore': 0.18,
    'sneeze_in': 0.25, 'sneeze_out': 0.32, 'shy': 0.25, 'wake': 0.3, 'dizzy': 0.3, 'burp': 0.25,
    // The friend's body.
    'poke': 0.35, 'squish': 0.3, 'stretch': 0.28, 'snap_back': 0.32, 'hop': 0.3, 'land': 0.3, 'tumble': 0.32,
    'hat_pop': 0.35, 'hat_land': 0.3, 'map_step': 0.22,
    // Eating.
    'bite_1': 0.4, 'bite_2': 0.4, 'bite_3': 0.4, 'gulp': 0.32, 'belly_rub': 0.25, 'catch': 0.4,
    // Living things and small magic around the friend.
    'butterfly': 0.18, 'spark_zip': 0.25, 'spark_escape': 0.25, 'snow_build': 0.3, 'snow_melt': 0.25,
    'trick_bubble': 0.4, 'trick_split': 0.4, 'trick_bloom': 0.4, 'trick_holo': 0.4, 'pop': 0.35,
    'rain_loop': 0.6, 'scroll_ride': 0.35, 'swap': 0.5,
    // Petting.
    'pet_stroke': 0.35, 'heart': 0.3,
    // Pickups in the games come thick and fast, so they stay light.
    'star_catch': 0.28, 'glow_pickup': 0.4, 'star_miss': 0.35, 'combo': 0.6,
  };

  /// Plays an app sound by name through [ui]. A sound asked for again within
  /// [gap] of its last play is skipped, so bursts of events never pile up.
  static void sound(String name, {double volume = 1, double pitch = 1, Duration gap = const Duration(milliseconds: 70), Duration delay = Duration.zero}) {
    final sfx = ui;
    if (sfx == null || mute.value) return;
    final now = AppClock.now;
    final last = _lastPlayed[name];
    if (last != null && now.difference(last) < gap) return;
    _lastPlayed[name] = now;
    sfx.play(name, volume: volume * (_levels[name] ?? 1), pitch: pitch, delay: delay);
  }

  /// Starts a looping app sound; returns a handle to stop it.
  static Future<SfxLoop?> soundLoop(String name, {double volume = 1}) async {
    final sfx = ui;
    if (sfx == null || mute.value) return null;
    return sfx.loop(name, volume: volume * (_levels[name] ?? 1));
  }

  static void light() => HapticFeedback.lightImpact();
  static void medium() => HapticFeedback.mediumImpact();
  static void heavy() => HapticFeedback.heavyImpact();
  static void tick() => HapticFeedback.selectionClick();
}

/// A looping sound that is playing (or, while recording, being logged).
class SfxLoop {
  SfxLoop._(this._voice, this._id, this._volume);
  final AudioVoice? _voice;
  final int? _id;
  double _volume;

  set volume(double v) {
    if (v == _volume) return;
    _volume = v;
    _voice?.volume = v;
    if (_id != null) {
      Sfx._recordedLoops[_id]?['volume'] = v;
      Sfx.onRecord?.call({'loop': _id, 'volume': v});
    }
  }

  void stop() {
    _voice?.stop();
    if (_id != null) {
      Sfx._recordedLoops.remove(_id);
      Sfx.onRecord?.call({'loop': _id, 'stop': true});
    }
  }
}
