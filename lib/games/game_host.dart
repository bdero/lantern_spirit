import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../app/scene_clock.dart';
import '../app/profile.dart';
import '../app/profile_scope.dart';
import '../app/sfx.dart';
import '../lantern/character.dart';
import '../lantern/friends.dart';
import '../lantern/themes.dart';

/// One mini-game: its own scene, input, and score, played by Lumi.
abstract class MiniGame {
  String get title;

  /// Short instructions shown at the start and in the HUD.
  String get hint;

  /// Round length in seconds, or null when the round ends some other way.
  double? get roundLength;

  Scene get scene;
  Camera get camera;

  /// Builds the scene, with [lumi] already added to it.
  Future<void> load(LanternCharacter lumi);

  /// Advances the game; [playing] is false during the countdown and results.
  void update(double dt, double time, {required bool playing});

  /// The finger moved to [x] across the screen, from -1 (left) to 1 (right).
  void steer(double x) {}

  /// A tap anywhere on the play field.
  void tap() {}

  /// A finger went down at [x] (-1 to 1) during play, and came back up.
  /// By default a press steers there and counts as a tap.
  void press(double x) {
    steer(x);
    tap();
  }

  void release() {}

  /// Stops anything the game left running (looping sounds).
  void dispose() {}

  /// Whether a finger is down on the play field right now.
  bool held = false;

  // ---------------------------------------------------------------- juice
  /// Floating text in the world ("+25", "BOING"), drawn over the scene.
  final List<Popup> popups = [];

  void popup(vm.Vector3 at, String text, {Color color = const Color(0xFFFFE3A6), double size = 26, double life = 0.9}) {
    popups.add(Popup(at.clone(), text, color, size, life));
    if (popups.length > 24) popups.removeAt(0);
  }

  /// A big title across the screen (a new zone, a finished constellation).
  String? bannerTitle;
  String? bannerSub;
  Color bannerColor = const Color(0xFFFFE3A6);
  double bannerAge = 99;

  void banner(String title, {String? sub, Color color = const Color(0xFFFFE3A6), String sound = 'banner'}) {
    Sfx.sound(sound);
    bannerTitle = title;
    bannerSub = sub;
    bannerColor = color;
    bannerAge = 0;
  }

  /// A full-screen flash of light, fading over a few frames.
  Color flashColor = const Color(0xFFFFFFFF);
  double flashAmount = 0;

  void screenFlash(Color color, [double amount = 0.6]) {
    flashColor = color;
    flashAmount = math.max(flashAmount, amount);
  }

  /// Freezes the action for a beat on a big hit.
  double hitstop = 0;

  void stop(double seconds) => hitstop = math.max(hitstop, seconds);

  /// Advances the juice; called by the host every frame.
  void tickJuice(double dt) {
    for (final p in popups) {
      p.age += dt;
    }
    popups.removeWhere((p) => p.age >= p.life);
    bannerAge += dt;
    flashAmount = math.max(0, flashAmount - dt * 3.2);
  }

  int get score;

  /// Text for the HUD's left and right pills, and a callout in the middle.
  String get leftPill;
  String get rightPill;
  String? get callout => null;

  /// A 0..1 gauge shown beside the right pill, or null for none.
  double? get meter => null;

  /// A line under the score on the results card.
  String? get resultLine => null;

  /// Whether the round is over before its time runs out.
  bool get finished => false;

  /// Stars earned for a final [score], paid into the profile.
  int starsFor(int score);

  /// Records the score in the profile (best scores).
  void record(Profile profile, int score);
}

/// Text floating up from a point in the world.
class Popup {
  Popup(this.at, this.text, this.color, this.size, this.life);
  final vm.Vector3 at;
  final String text;
  final Color color;
  final double size;
  final double life;
  double age = 0;
}

/// Hosts a [MiniGame]: countdown, HUD, pause, and results.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.create});

  final MiniGame Function() create;

  @override
  State<GameScreen> createState() => GameScreenState();
}

enum GamePhase { loading, countdown, playing, paused, results }

class GameScreenState extends State<GameScreen> {
  late MiniGame game = widget.create();
  LanternCharacter? lumi;
  GamePhase phase = GamePhase.loading;
  double _countdown = 3;
  double _played = 0;
  int _stars = 0;
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    game.scene.debugCheckCoplanarOverlaps = false;
    final p = ProfileScope.read(context);
    final c = await LanternCharacter.load(game.scene, friend: Friends.byId(p.friend));
    if (!mounted) return;
    c
      ..canDoze = false
      ..idleAntics = false
      ..glowScale = p.glow
      ..hueShift = p.hueShift;
    c.setTheme(LanternTheme.all.firstWhere((t) => t.name == p.theme, orElse: () => LanternTheme.aurora));
    c.wake();
    await c.wear(hat: p.hat, scarf: p.scarf);
    await game.load(c);
    await game.scene.warmUp([RenderView(camera: game.camera)], includeOffscreen: true);
    if (!mounted) return;
    setState(() {
      lumi = c;
      phase = GamePhase.countdown;
    });
  }

  @override
  void dispose() {
    game.dispose();
    game.scene.removeAll();
    super.dispose();
  }

  void _tick(Duration elapsed, double dt) {
    final c = lumi;
    if (c == null) return;
    final paused = phase == GamePhase.paused;
    if (!paused) _time += dt;
    switch (phase) {
      case GamePhase.countdown:
        final before = _countdown.ceil();
        _countdown -= dt;
        if (_countdown.ceil() != before) {
          Sfx.tick();
          if (_countdown > 0) Sfx.sound('countdown');
        }
        if (_countdown <= 0) {
          phase = GamePhase.playing;
          Sfx.medium();
          Sfx.sound('countdown_go');
        }
      case GamePhase.playing:
        _played += dt;
        final limit = game.roundLength;
        if ((limit != null && _played >= limit) || game.finished) _finish();
      default:
        break;
    }
    // A hitstop freezes the world for a beat; the juice keeps animating.
    var step = paused ? 0.0 : dt;
    if (game.hitstop > 0) {
      game.hitstop -= dt;
      step *= 0.06;
    }
    game.tickJuice(paused ? 0 : dt);
    game.update(step, _time, playing: phase == GamePhase.playing);
    c.update(step, _time);
    setState(() {});
  }

  void _finish() {
    phase = GamePhase.results;
    final p = ProfileScope.read(context);
    _stars = game.starsFor(game.score);
    game.record(p, game.score);
    if (_stars > 0) p.addStars(_stars);
    lumi?.celebrate();
    Sfx.heavy();
    Sfx.sound('results');
  }

  void _again() {
    final old = game;
    setState(() {
      phase = GamePhase.loading;
      lumi = null;
      _countdown = 3;
      _played = 0;
      _time = 0;
      game = widget.create();
    });
    old.scene.removeAll();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final c = lumi;
    return Scaffold(
      backgroundColor: const Color(0xFF070B1C),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null)
            LayoutBuilder(
              // Raw pointers, not gestures: a game needs the press the moment
              // it lands and every move after, with no tap-versus-drag wait.
              builder: (context, constraints) {
                double x(PointerEvent e) => (e.localPosition.dx / constraints.maxWidth * 2 - 1).clamp(-1.0, 1.0);
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    game.held = true;
                    if (phase == GamePhase.playing) {
                      game.press(x(e));
                    } else {
                      game.steer(x(e));
                    }
                  },
                  onPointerMove: (e) => game.steer(x(e)),
                  onPointerUp: (_) {
                    game.held = false;
                    game.release();
                  },
                  onPointerCancel: (_) {
                    game.held = false;
                    game.release();
                  },
                  child: appSceneView(game.scene, camera: game.camera, onTick: _tick),
                );
              },
            )
          else
            const Center(child: CircularProgressIndicator(color: Color(0xFF8FD3FF))),
          if (c != null) ..._juice(context),
          // HUD.
          if (phase == GamePhase.playing || phase == GamePhase.paused)
            Positioned(
              top: pad.top + 10,
              left: 56,
              right: 16,
              child: Row(
                children: [
                  _pill(game.leftPill),
                  const Spacer(),
                  _pill(game.rightPill),
                  if (game.meter case final m?) ...[const SizedBox(width: 8), _meter(m)],
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: phase == GamePhase.paused ? 'Resume' : 'Pause',
                    onPressed: () => setState(() => phase = phase == GamePhase.paused ? GamePhase.playing : GamePhase.paused),
                    icon: Icon(phase == GamePhase.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                  ),
                ],
              ),
            ),
          if (phase == GamePhase.playing && game.callout != null)
            Positioned(
              top: pad.top + 76,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Text(
                  game.callout!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFE3A6),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: Color(0xCCFFBE5A), blurRadius: 18)],
                  ),
                ),
              ),
            ),
          if (phase == GamePhase.countdown)
            Center(
              child: IgnorePointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_countdown.ceil().clamp(1, 3)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 96,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(color: Color(0x990A1024), blurRadius: 24)],
                      ),
                    ),
                    Text(
                      game.hint,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Color(0x990A1024), blurRadius: 10)],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (phase == GamePhase.paused)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Paused', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => setState(() => phase = GamePhase.playing),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8FD3FF), foregroundColor: const Color(0xFF0A1024)),
                    child: const Text('Resume'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Leave game'),
                  ),
                ],
              ),
            ),
          if (phase == GamePhase.results) _results(context),
          Positioned(
            top: pad.top + 10,
            left: 8,
            child: IconButton(
                    tooltip: 'Leave game',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
          ),
        ],
      ),
    );
  }

  @visibleForTesting
  void finishForTest() => setState(_finish);

  /// Popups, the banner, and the screen flash.
  List<Widget> _juice(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final out = <Widget>[];
    for (final p in game.popups) {
      final s = game.camera.worldToScreen(p.at, size);
      if (s == null) continue;
      final t = p.age / p.life;
      final pop = t < 0.15 ? Curves.easeOutBack.transform(t / 0.15) : 1.0;
      out.add(
        Positioned(
          left: s.dx - 120,
          top: s.dy - 40 - 60 * Curves.easeOut.transform(t),
          width: 240,
          child: IgnorePointer(
            child: Opacity(
              opacity: (1 - t * t).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.4 + 0.6 * pop,
                child: Text(
                  p.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: p.color,
                    fontSize: p.size,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    shadows: [Shadow(color: p.color.withValues(alpha: 0.8), blurRadius: 16), const Shadow(color: Color(0x99000000), blurRadius: 4, offset: Offset(0, 2))],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final title = game.bannerTitle;
    const bannerLife = 2.2;
    if (title != null && game.bannerAge < bannerLife) {
      final t = game.bannerAge / bannerLife;
      final inT = Curves.easeOutBack.transform((game.bannerAge / 0.35).clamp(0.0, 1.0));
      final fade = t > 0.75 ? 1 - (t - 0.75) / 0.25 : 1.0;
      out.add(
        Positioned(
          left: 24,
          right: 24,
          top: size.height * 0.3,
          child: IgnorePointer(
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.6 + 0.4 * inT + 0.05 * t,
                child: Column(
                  children: [
                    Text(
                      title.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: title.length > 16 ? 28 : 34,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.5,
                        shadows: [
                          const Shadow(color: Color(0xAA000000), blurRadius: 14),
                          Shadow(color: game.bannerColor, blurRadius: 24),
                          Shadow(color: game.bannerColor, blurRadius: 8),
                        ],
                      ),
                    ),
                    if (game.bannerSub case final sub?)
                      Text(
                        sub,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: game.bannerColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 10)],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (game.flashAmount > 0.01) {
      out.add(Positioned.fill(child: IgnorePointer(child: ColoredBox(color: game.flashColor.withValues(alpha: game.flashAmount.clamp(0.0, 1.0) * 0.55)))));
    }
    return out;
  }

  Widget _meter(double value) => Container(
    width: 64,
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0x8C0A1024),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0x332A3566)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 8,
        backgroundColor: const Color(0x332A3566),
        color: value < 0.12 ? const Color(0xFF6A7396) : const Color(0xFFFFC98A),
      ),
    ),
  );

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0x8C0A1024),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0x332A3566)),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
    ),
  );

  Widget _results(BuildContext context) {
    return Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.of(context).padding.bottom + 28,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          color: const Color(0xF20C122C),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF2A3566)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(game.title, style: const TextStyle(color: Color(0xFF95A2C8), fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              '${game.score}',
              style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w800),
            ),
            if (game.resultLine case final line?)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            Text(
              _stars > 0 ? '+$_stars ${_stars == 1 ? 'star' : 'stars'} for the wardrobe' : 'No stars this time',
              style: const TextStyle(color: Color(0xFFFFC98A), fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0xFF2A3566))),
                    child: const Text('Done'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _again,
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8FD3FF), foregroundColor: const Color(0xFF0A1024)),
                    child: const Text('Play again'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
