import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import '../app/scene_clock.dart';
import '../app/clock.dart';
import '../app/profile_scope.dart';
import '../app/sfx.dart';
import '../lantern/character.dart';
import '../lantern/friends.dart';
import '../lantern/themes.dart';
import '../vfx/shadow.dart';
import 'fireworks.dart';
import 'lagoon_set.dart';
import 'show_director.dart';
import 'show_script.dart';

/// Fireworks over the lagoon, watched from the pier with Lumi.
class ShowScreen extends StatefulWidget {
  const ShowScreen({super.key, this.theme, this.startAt = 0, this.autoExit = true});

  final LanternTheme? theme;

  /// Show time to start from (the scrubber and render checks use this).
  final double startAt;

  /// Close the screen on its own when the show ends.
  final bool autoExit;

  @override
  State<ShowScreen> createState() => ShowScreenState();
}

class ShowScreenState extends State<ShowScreen> {
  final Scene scene = Scene();
  ShowDirector? director;
  Object? _error;
  late final Sfx _sfx = Sfx(scene);

  bool _controls = false;
  Timer? _hideControls;
  bool _exiting = false;

  // Quality probe: frame times over the first seconds of the show.
  final List<double> _frameTimes = [];
  String tier = 'High';

  @override
  void initState() {
    super.initState();
    // The fireworks mesh is rebuilt every frame; the debug coplanar-face scan
    // walks meshes across several frames and trips over that.
    scene.debugCheckCoplanarOverlaps = false;
    scene.toneMapping = ToneMappingMode.pbrNeutral;
    scene.environmentIntensity = 0.05;
    scene.postProcess.bloom
      ..enabled = true
      ..threshold = 0.9
      ..intensity = 0.42
      ..scatter = 0.78;
    _load();
  }

  Future<void> _load() async {
    try {
      final friend = Friends.byId(ProfileScope.read(context).friend);
      final results = await Future.wait([
        LagoonSet.build(),
        LanternCharacter.load(scene, friend: friend),
        loadFmatMaterial('assets/show/firework.fmat'),
        loadFmatMaterial('assets/show/smoke.fmat'),
      ]);
      if (!mounted) return;
      final set = results[0] as LagoonSet;
      final lumi = results[1] as LanternCharacter;
      if (widget.theme != null) lumi.setTheme(widget.theme!);
      // Lumi comes to the show dressed as the guest left it.
      if (!mounted) return;
      final profile = ProfileScope.read(context);
      lumi
        ..glowScale = profile.glow
        ..hueShift = profile.hueShift;
      await lumi.wear(hat: profile.hat, scarf: profile.scarf);
      if (!mounted) return;
      final fireworks = FireworkRenderer(
        lightMaterial: results[2] as PreprocessedMaterial,
        smokeMaterial: results[3] as PreprocessedMaterial,
      );
      scene.skybox = Skybox(set.sky);
      scene.add(set.root);
      scene.add(fireworks.smokeNode);
      scene.add(fireworks.lightNode);
      final d = ShowDirector(
        scene: scene,
        set: set,
        fireworks: fireworks,
        lumi: lumi,
        sfx: _sfx,
        script: ShowScript(),
      );
      // A soft shadow on the deck under the friend.
      final shadow = await ContactShadow.create(scene, opacity: 0.5);
      shadow.place(kPierEnd + Vector3(0, 0.01, 0), radius: lumi.friend.foot == null ? 0.42 : 0.5, height: lumi.friend.foot == null ? 0.4 : 0);
      d.seek(widget.startAt);
      d.update(0);
      // Compile every pipeline before the first visible frame.
      await scene.warmUp([RenderView(camera: d.camera)], includeOffscreen: true);
      if (!mounted) return;
      _sfx.preload(const ['mortar', 'burst_big_1', 'burst_big_2', 'burst_big_3', 'burst_small_1', 'burst_small_2', 'crackle']);
      setState(() => director = d);
    } catch (e, st) {
      debugPrint('The lagoon failed to load: $e\n$st');
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _hideControls?.cancel();
    _sfx.dispose();
    scene.removeAll();
    super.dispose();
  }

  void _tick(Duration elapsed, double dt) {
    final d = director;
    if (d == null) return;
    d.update(dt);
    _probe(dt);
    if (_controls) setState(() {});
    if (widget.autoExit && !_exiting && d.time >= ShowScript.length - 1.3) {
      _exit();
    }
  }

  void _probe(double dt) {
    final d = director!;
    if (d.time < 1.5 || d.time > 4.5 || tier == 'Low') return;
    _frameTimes.add(dt);
    if (_frameTimes.length < 90) return;
    final sorted = _frameTimes.toList()..sort();
    final p75 = sorted[(sorted.length * 0.75).floor()];
    _frameTimes.clear();
    if (p75 > 1 / 32) {
      tier = 'Low';
      d.set.reflector?.resolutionScale = 0.25;
      d.fireworks.trailSamples = 5;
    } else if (p75 > 1 / 48 && tier == 'High') {
      tier = 'Medium';
      d.set.reflector?.resolutionScale = 0.35;
      d.fireworks.trailSamples = 6;
    }
  }

  void _exit() {
    if (_exiting) return;
    _exiting = true;
    final profile = ProfileScope.read(context);
    profile.markFireworksWatched();
    Navigator.of(context).maybePop();
  }

  /// Shows the controls, as a tap on the show does (for scripted clips).
  void revealControls() => _showControls();

  /// Seeks to [t], as dragging the timeline does (for scripted clips).
  void scrubTo(double t) {
    director?.seek(t);
    _showControls();
  }

  void _showControls() {
    setState(() => _controls = true);
    _hideControls?.cancel();
    _hideControls = AppClock.timer(const Duration(seconds: 3), () {
      if (mounted && (director?.playing ?? true)) setState(() => _controls = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = director;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_error != null)
              Center(child: Text('Could not load the show.\n$_error', style: const TextStyle(color: Colors.white70)))
            else if (d != null)
              appSceneView(scene, camera: d.camera, onTick: _tick),
            // Until the lagoon is ready, keep showing the card's picture, so
            // the window opens onto the same view and then comes alive.
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: d == null ? 1 : 0,
                duration: const Duration(milliseconds: 600),
                child: Image.asset('assets/ui/tonight.jpg', fit: BoxFit.cover, alignment: const Alignment(0, -0.2)),
              ),
            ),
            if (d != null)
              IgnorePointer(
                ignoring: !_controls,
                child: AnimatedOpacity(
                  opacity: _controls ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: _ShowControls(
                    director: d,
                    tier: tier,
                    onClose: _exit,
                    onPlayPause: () {
                      setState(() => d.playing = !d.playing);
                      _showControls();
                    },
                    onSeek: (t) {
                      d.seek(t);
                      _showControls();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShowControls extends StatelessWidget {
  const _ShowControls({
    required this.director,
    required this.tier,
    required this.onClose,
    required this.onPlayPause,
    required this.onSeek,
  });

  final ShowDirector director;
  final String tier;
  final VoidCallback onClose;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeek;

  static const _marks = [
    (ShowScript.firstBreak, 'first break'),
    (ShowScript.closeUp, 'close-up'),
    (ShowScript.build, 'build'),
    (ShowScript.finale, 'finale'),
    (ShowScript.afterglow, 'afterglow'),
  ];

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final t = director.time;
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 140,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.5), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: pad.top + 8,
          left: 12,
          child: IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ),
        Positioned(
          top: pad.top + 18,
          right: 20,
          child: Text(
            'Fireworks over the lagoon · $tier',
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: pad.bottom + 18,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 16, 10),
            decoration: BoxDecoration(
              color: const Color(0xCC0C122C),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2A3566)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: director.playing ? 'Pause' : 'Play',
                      onPressed: onPlayPause,
                      icon: Icon(director.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) => Stack(
                          alignment: Alignment.center,
                          children: [
                            for (final (mt, _) in _marks)
                              Positioned(
                                left: 24 + (c.maxWidth - 48) * mt / ShowScript.length - 1,
                                top: 8,
                                bottom: 8,
                                child: Container(width: 2, color: const Color(0x66FFB35C)),
                              ),
                            SliderTheme(
                              data: const SliderThemeData(
                                activeTrackColor: Color(0xFF8FD3FF),
                                inactiveTrackColor: Color(0xFF1A2450),
                                thumbColor: Color(0xFF8FD3FF),
                                trackHeight: 3,
                              ),
                              child: Slider(value: t.clamp(0, ShowScript.length), max: ShowScript.length, onChanged: onSeek),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 46,
                      child: Text(
                        '${t.floor()}s',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final (mt, label) in _marks)
                      ActionChip(
                        label: Text(label),
                        onPressed: () => onSeek(math.max(0, mt - 0.6)),
                        labelStyle: const TextStyle(fontSize: 12, color: Colors.white),
                        backgroundColor: const Color(0xFF1A2450),
                        side: const BorderSide(color: Color(0xFF2A3566)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
