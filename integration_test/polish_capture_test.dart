// Frame-by-frame checks for the motion polish: a notification caught and
// delivered, the spark chase (with the reaching hand's largest jump between
// frames printed, to catch any snapping), the peek's climb back over the
// card, the status line changing, and the walk to Tidal Twist around the
// carousel. Reports PNGs, which test_driver/integration_test.dart writes to
// build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/polish_capture_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lantern_spirit/app/profile.dart';
import 'package:lantern_spirit/main.dart';
import 'package:lantern_spirit/map/park_map_screen.dart';
import 'package:lantern_spirit/ui/park_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final captures = <String, String>{};

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    await tester.pump();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    captures['$name.png'] = base64Encode(bytes!.buffer.asUint8List());
  }

  testWidgets('capture polish', (tester) async {
    addTearDown(() => binding.reportData = <String, dynamic>{...captures});
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LanternSpiritApp(profile: Profile.memory()..addKey())));
    ParkScreenState park() => tester.state<ParkScreenState>(find.byType(ParkScreen));

    // Pumps frames for [d]; tracks the reaching hand's biggest jump between
    // frames, in world units.
    var maxJump = 0.0;
    Future<void> settle(Duration d) async {
      final end = DateTime.now().add(d);
      while (DateTime.now().isBefore(end)) {
        final c = park().character;
        final before = c?.handWorld;
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 16));
        final after = park().character?.handWorld;
        if (before != null && after != null) maxJump = math.max(maxJump, (after - before).length);
      }
    }

    Future<void> frames(String name, int count, int everyMs) async {
      for (var i = 0; i < count; i++) {
        await settle(Duration(milliseconds: everyMs));
        await capture(tester, key, '${name}_${i.toString().padLeft(2, '0')}');
      }
    }

    for (var i = 0; i < 400 && park().character == null; i++) {
      await settle(const Duration(milliseconds: 50));
    }
    park().autoSurprises = false;
    park().character!.wake();
    await settle(const Duration(milliseconds: 1500));

    // The notification: caught, read, thrown onto its card.
    maxJump = 0;
    park().notify();
    await frames('p_toast', 18, 250);
    debugPrint('POLISH toast hand max jump ${maxJump.toStringAsFixed(3)}');
    await settle(const Duration(milliseconds: 1500));
    // Again without captures, which stall frames and exaggerate the jumps.
    maxJump = 0;
    park().notify();
    await settle(const Duration(milliseconds: 4800));
    debugPrint('POLISH toast hand max jump, uncaptured ${maxJump.toStringAsFixed(3)}');
    await settle(const Duration(milliseconds: 800));

    // The spark chase.
    maxJump = 0;
    park().startChase();
    await frames('p_chase', 10, 340);
    debugPrint('POLISH chase hand max jump ${maxJump.toStringAsFixed(3)}');
    await settle(const Duration(milliseconds: 1200));

    // The status line as it changes: typing makes the friend follow along.
    await tester.enterText(find.byType(TextField), 'mo');
    await frames('p_caption', 5, 45);
    await settle(const Duration(milliseconds: 1600));
    // The search scrolled down to its match; back up to clear it (jumping,
    // since a long drag sends the friend riding the scrollbar).
    tester.state<ScrollableState>(find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first).position.jumpTo(0);
    await settle(const Duration(milliseconds: 1200));
    await tester.enterText(find.byType(TextField), '');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(const Duration(milliseconds: 1500));

    // The peek, and especially the climb back up over the card.
    park().peekForTest();
    await settle(const Duration(milliseconds: 3800));
    await frames('p_peek', 12, 100);
    await settle(const Duration(milliseconds: 1200));

    // The walk to Tidal Twist, which used to pass through the carousel.
    park().openMapForTest();
    for (var i = 0; i < 400 && (find.byType(ParkMapScreen).evaluate().isEmpty || tester.state<ParkMapScreenState>(find.byType(ParkMapScreen)).lumi == null); i++) {
      await settle(const Duration(milliseconds: 50));
    }
    await settle(const Duration(milliseconds: 1500));
    final map = tester.state<ParkMapScreenState>(find.byType(ParkMapScreen));
    // Every trip crosses the plaza; none may pass through the fountain.
    var nearest = double.infinity;
    Future<void> walkTo(String name) async {
      map.goTo(map.rides.firstWhere((r) => r.name == name));
      for (var i = 0; i < 600 && map.travelling; i++) {
        await settle(const Duration(milliseconds: 30));
        final p = map.positionForTest;
        nearest = math.min(nearest, math.sqrt((p.x - 0) * (p.x - 0) + (p.z + 1.1) * (p.z + 1.1)));
      }
    }

    map.goTo(map.rides.firstWhere((r) => r.name == 'Tidal Twist'));
    await frames('p_walk', 14, 400);
    for (var i = 0; i < 400 && map.travelling; i++) {
      await settle(const Duration(milliseconds: 30));
    }
    for (final name in const ['Star Swing', 'River Run', 'Moon Drop', 'Sky Coaster', 'Comet Carousel']) {
      await walkTo(name);
    }
    debugPrint('POLISH fountain nearest ${nearest.toStringAsFixed(2)} (basin radius 0.42)');
    binding.reportData = <String, dynamic>{...captures};
  });
}
