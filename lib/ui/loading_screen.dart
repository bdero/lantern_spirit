import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/preload.dart';
import '../app/profile_scope.dart';
import 'palette.dart';
import 'park_screen.dart';

/// Shows a glowing lantern and a progress bar while [Preload] loads and
/// compiles every screen, then crossfades into the park.
///
/// The web page shows the same lantern (web/index.html) while Flutter itself
/// downloads, so the two read as one loading screen.
class Boot extends StatefulWidget {
  const Boot({super.key});

  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();
  double _progress = 0;
  bool _ready = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _run();
  }

  Future<void> _run() async {
    final images = [
      for (final name in const [
        'friend_juju.jpg',
        'friend_lumi.jpg',
        'friend_mochi.jpg',
        'friend_nova.jpg',
        'game_catch.jpg',
        'game_lift.jpg',
        'park_map.jpg',
        'tonight.jpg',
      ])
        'assets/ui/$name',
    ];
    await Future.wait([
      Preload.run(
        ProfileScope.read(context),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      ),
      for (final i in images) precacheImage(AssetImage(i), context),
    ]);
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: _ready ? const ParkScreen() : _loading(),
    );
  }

  Widget _loading() {
    return Material(
      key: const ValueKey('loading'),
      color: Park.bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = 0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi);
                return Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [
                        Color(0xFFDDF3FF),
                        Color(0xFF8FD3FF),
                        Color(0x008FD3FF),
                      ],
                      stops: [0, 0.45, 1],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFF8FD3FF,
                        ).withValues(alpha: 0.35 + 0.25 * t),
                        blurRadius: 30 + 20 * t,
                        spreadRadius: 4 + 6 * t,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 36),
            const Text(
              'Lantern Spirit',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF8FD3FF)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
