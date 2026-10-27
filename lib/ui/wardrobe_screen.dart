import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/material.dart' as m show Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../app/scene_clock.dart';
import '../app/profile.dart';
import '../app/sfx.dart';
import '../app/profile_scope.dart';
import '../lantern/character.dart';
import '../lantern/friends.dart';
import '../lantern/moods.dart';
import '../lantern/themes.dart';
import '../lantern/wardrobe.dart';
import 'palette.dart';

/// Lumi's wardrobe: a live preview to turn and poke, and the hats, colors,
/// and glow to choose from. Choices save to the guest's profile, so Lumi
/// wears them everywhere in the app.
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key, this.headerHeight, this.initialTab = 0});

  /// The friend tiles, for clips that tap them.
  static final friendTiles = {for (final f in Friends.all) f.id: GlobalKey()};

  /// Which tab opens first: 0 hats, 1 colors, 2 glow, 3 friends.
  final int initialTab;

  /// When set, the wardrobe is only a sheet below a header of this height,
  /// and the header's own Lumi (still on screen above it) is the preview.
  final double? headerHeight;

  @override
  State<WardrobeScreen> createState() => WardrobeScreenState();
}

class WardrobeScreenState extends State<WardrobeScreen> {
  final Scene scene = Scene();
  LanternCharacter? lumi;
  final PerspectiveCamera camera = PerspectiveCamera(
    fovRadiansY: 27 * vm.degrees2Radians,
    position: vm.Vector3(0, 1.95, -7.2),
    target: vm.Vector3(0, 1.72, 0),
  );
  double _yaw = 0;
  double _spin = 0;
  late int _tab = widget.initialTab;
  Size _viewSize = Size.zero;

  @override
  void initState() {
    super.initState();
    scene.postProcess.bloom
      ..enabled = true
      ..threshold = 1.0
      ..intensity = 0.3;
    scene.environmentIntensity = 0.8;
    if (widget.headerHeight == null) _load();
  }

  Future<void> _load() async {
    final p = ProfileScope.read(context);
    final c = await LanternCharacter.load(scene, friend: Friends.byId(p.friend));
    if (!mounted) return;
    c
      ..canDoze = false
      ..setMood(LanternMood.awake)
      ..settle()
      ..glowScale = p.glow
      ..hueShift = p.hueShift;
    c.setTheme(_themeNamed(p.theme));
    await c.wear(hat: p.hat, scarf: p.scarf);
    if (mounted) setState(() => lumi = c);
  }

  static LanternTheme _themeNamed(String name) => LanternTheme.all.firstWhere(
    (t) => t.name == name,
    orElse: () => LanternTheme.aurora,
  );

  @override
  void dispose() {
    scene.removeAll();
    super.dispose();
  }

  void _apply(Profile p) {
    final c = lumi;
    if (c == null) return;
    c
      ..glowScale = p.glow
      ..hueShift = p.hueShift;
    if (c.theme.name != p.theme) c.setTheme(_themeNamed(p.theme));
    c.wear(hat: p.hat, scarf: p.scarf);
  }

  void _celebrate() {
    lumi?.setMood(LanternMood.delighted);
  }

  @override
  Widget build(BuildContext context) {
    final p = ProfileScope.of(context);
    _apply(p);
    final pad = MediaQuery.of(context).padding;
    final headerHeight = widget.headerHeight;
    if (headerHeight != null) {
      return Column(
        children: [
          // The header stays visible above; a tap there closes the sheet.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: SizedBox(height: headerHeight, width: double.infinity),
          ),
          Expanded(child: _sheet(p, pad, title: true)),
        ],
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B1433),
      body: Column(
        children: [
          Expanded(
            flex: 11,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -0.1),
                        radius: 0.9,
                        colors: [
                          Color(0xFF26346B),
                          Color(0xFF141E45),
                          Color(0xFF0B1433),
                        ],
                        stops: [0, 0.55, 1],
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _viewSize = constraints.biggest;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          // Drag sideways to turn Lumi; tap the head to poke.
                          onHorizontalDragUpdate: (d) =>
                              _spin += d.delta.dx * 0.012,
                          onTapUp: (d) {
                            final c = lumi;
                            if (c == null) return;
                            c.poke(
                              scene,
                              camera.screenPointToRay(
                                d.localPosition,
                                _viewSize,
                              ),
                            );
                          },
                          child: lumi == null
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Park.glow,
                                  ),
                                )
                              : appSceneView(
                                  scene,
                                  camera: camera,
                                  onTick: (elapsed, dt) {
                                    final c = lumi!;
                                    // Drag spin carries momentum, then eases back to front.
                                    _yaw += _spin;
                                    _spin *= math.exp(-dt * 4);
                                    _yaw *= math.exp(
                                      -dt * (_spin.abs() < 0.002 ? 1.5 : 0),
                                    );
                                    c.place(vm.Vector3.zero(), _yaw);
                                    c.update(dt, elapsed.inMicroseconds / 1e6);
                                  },
                                ),
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: pad.top + 6,
                  left: 8,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
                Positioned(
                  top: pad.top + 16,
                  left: 0,
                  right: 0,
                  child: const IgnorePointer(
                    child: Text(
                      'Wardrobe',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 14,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Text(
                      '${p.keys} keys  ·  ${p.stars} stars',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFB4C1E6),
                        fontSize: 13,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(flex: 12, child: _sheet(p, pad)),
        ],
      ),
    );
  }

  Widget _sheet(Profile p, EdgeInsets pad, {bool title = false}) {
    return m.Material(
      color: Park.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, pad.bottom + 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Text(
                      'Wardrobe',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Park.ink,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${p.keys} keys · ${p.stars} stars',
                      style: const TextStyle(
                        color: Park.inkMuted,
                        fontSize: 13,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded, color: Park.ink),
                    ),
                  ],
                ),
              ),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 3, label: Text('Friends')),
                ButtonSegment(value: 0, label: Text('Hats')),
                ButtonSegment(value: 1, label: Text('Colors')),
                ButtonSegment(value: 2, label: Text('Glow')),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: switch (_tab) {
                0 => _hats(p),
                3 => _friends(p),
                1 => _colors(p),
                _ => _glow(p),
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Who lives in the app. Picking one swaps the friend in the header.
  Widget _friends(Profile p) {
    return GridView.count(
      padding: EdgeInsets.zero,
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.08,
      children: [
        for (final f in Friends.all)
          Semantics(
            key: WardrobeScreen.friendTiles[f.id],
            button: true,
            selected: p.friend == f.id,
            label: '${f.name}, ${f.kind}',
            child: GestureDetector(
              onTap: () => p.chooseFriend(f.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: Park.raised,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: p.friend == f.id ? Park.glow : Park.line,
                    width: p.friend == f.id ? 2.5 : 1,
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox.expand(child: Image.asset(f.thumbnail, fit: BoxFit.cover)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(f.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Park.ink)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            f.kind.toUpperCase(),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Park.inkMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                          ),
                        ),
                      ],
                    ),

                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _hats(Profile p) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.82,
          children: [
            _tile(
              selected: p.hat == null,
              locked: false,
              title: 'None',
              image: null,
              onTap: () {
                Sfx.sound('tap');
                p.wear(clearHat: true);
              },
            ),
            for (final a in Wardrobe.hats)
              _tile(
                selected: p.hat == a.id,
                locked: !a.unlocked(p),
                title: a.name,
                subtitle: a.unlocked(p) ? null : a.unlockText,
                image: 'assets/ui/wear_${a.id}.png',
                onTap: () {
                  Sfx.sound('hat_equip');
                  p.wear(hat: a.id);
                  _celebrate();
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          value: p.scarf,
          onChanged: (v) {
            Sfx.sound('toggle');
            p.wear(scarf: v);
          },
          title: const Text('Scarf', style: Park.title),
          subtitle: Text(
            Wardrobe.scarf.blurb,
            style: const TextStyle(color: Park.inkMuted, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _tile({
    required bool selected,
    required bool locked,
    required String title,
    String? subtitle,
    required String? image,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: locked ? '$title, locked. ${subtitle ?? ''}' : title,
      child: GestureDetector(
        onTap: locked ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: locked ? const Color(0xFF0E1328) : Park.raised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? Park.glow : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x111B2340),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const RadialGradient(
                      colors: [Color(0xFF26346B), Color(0xFF111A3D)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (image != null)
                        Opacity(
                          opacity: locked ? 0.35 : 1,
                          child: Image.asset(image, fit: BoxFit.cover),
                        )
                      else
                        const Center(
                          child: Icon(
                            Icons.block_rounded,
                            color: Color(0xFF6D7AA3),
                          ),
                        ),
                      if (locked)
                        const Center(
                          child: Icon(
                            Icons.lock_rounded,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Park.ink,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: Park.inkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colors(Profile p) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const Text('THEME', style: Park.eyebrow),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final t in LanternTheme.all)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      Sfx.sound('tap');
                      p.setLook(theme: t.name);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Park.raised,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: p.theme == t.name ? Park.ink : Park.line,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: t.swatch,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Park.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Text('HUE', style: Park.eyebrow),
            const Spacer(),
            Text('${p.hueShift.round()}°', style: Park.tabular),
          ],
        ),
        Container(
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              colors: [
                for (var h = -180; h <= 180; h += 45)
                  HSVColor.fromAHSV(1, (h + 205) % 360, 0.55, 1).toColor(),
              ],
            ),
          ),
        ),
        Slider(
          value: p.hueShift,
          min: -180,
          max: 180,
          onChanged: (v) => p.setLook(hueShift: v),
        ),
        TextButton(
          onPressed: () => p.setLook(hueShift: 0),
          child: const Text('Reset hue'),
        ),
      ],
    );
  }

  Widget _glow(Profile p) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Row(
          children: [
            const Text('GLOW', style: Park.eyebrow),
            const Spacer(),
            Text(p.glow.toStringAsFixed(2), style: Park.tabular),
          ],
        ),
        Slider(
          value: p.glow,
          min: 0.5,
          max: 1.6,
          onChanged: (v) => p.setLook(glow: v),
        ),
        const SizedBox(height: 6),
        Text(
          'How brightly ${Friends.byId(p.friend).name} glows everywhere in the app. A softer glow suits daytime screens; a brighter one shines at night.',
          style: TextStyle(color: Park.inkMuted, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }
}
