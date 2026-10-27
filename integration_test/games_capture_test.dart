// Plays both mini-games with scripted input and reports PNGs mid-round, which
// test_driver/integration_test.dart writes to build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/games_capture_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lantern_spirit/app/profile.dart';
import 'package:lantern_spirit/games/game_host.dart';
import 'package:lantern_spirit/games/sky_lift.dart';
import 'package:lantern_spirit/games/star_catch.dart';
import 'package:lantern_spirit/main.dart';
import 'package:lantern_spirit/ui/park_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final captures = <String, String>{};

  Future<void> settle(WidgetTester tester, Duration d, {void Function(double t)? each}) async {
    final start = DateTime.now();
    final end = start.add(d);
    while (DateTime.now().isBefore(end)) {
      each?.call(DateTime.now().difference(start).inMilliseconds / 1000);
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    await tester.pump();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    captures['$name.png'] = base64Encode(bytes!.buffer.asUint8List());
  }

  testWidgets('capture games', (tester) async {
    final key = GlobalKey();
    final profile = Profile.memory();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LanternSpiritApp(profile: profile)));
    ParkScreenState park() => tester.state<ParkScreenState>(find.byType(ParkScreen));
    for (var i = 0; i < 400 && park().character == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    await settle(tester, const Duration(milliseconds: 600));
    await capture(tester, key, 'g0_park');

    for (final lift in [false, true]) {
      // Play as different friends.
      profile.chooseFriend(lift ? 'nova' : 'juju');
      await settle(tester, const Duration(milliseconds: 1500));
      park().openGameForTest(lift);
      GameScreenState game() => tester.state<GameScreenState>(find.byType(GameScreen));
      await settle(tester, const Duration(milliseconds: 600));
      for (var i = 0; i < 400 && game().phase == GamePhase.loading; i++) {
        await settle(tester, const Duration(milliseconds: 50));
      }
      await settle(tester, const Duration(milliseconds: 700));
      await capture(tester, key, lift ? 'g1_lift_countdown' : 'g1_catch_countdown');
      await settle(tester, const Duration(milliseconds: 3200));
      if (lift) {
        final g = game().game as SkyLift;
        // Hold for a few seconds, steering, then let go and drift.
        g.thrustForTest = true;
        await settle(tester, const Duration(seconds: 3), each: (t) => g.steer(math.sin(t * 1.3) * 0.8));
        await capture(tester, key, 'g2_lift_play');
        g.thrustForTest = false;
        await settle(tester, const Duration(milliseconds: 900));
        await capture(tester, key, 'g2_lift_drift');
        for (final (y, name) in const [(15.4, 'g4_lift_cloudsea'), (24.0, 'g5_lift_above'), (46.0, 'g6_lift_night'), (72.0, 'g7_lift_aurora'), (94.0, 'g8_lift_moon')]) {
          g.jumpForTest(y);
          g.thrustForTest = true;
          await settle(tester, const Duration(milliseconds: 1500));
          await capture(tester, key, name);
        }
        g.thrustForTest = true;
        await settle(tester, const Duration(milliseconds: 2500));
        g.thrustForTest = false;
      } else {
        final g = game().game as StarCatch;
        await settle(tester, const Duration(seconds: 4), each: (t) => g.steer(math.sin(t * 1.3) * 0.8));
        await capture(tester, key, 'g2_catch_play');
        // Fill a constellation: catch every star that appears for a while.
        var shot = false;
        await settle(tester, const Duration(seconds: 9), each: (t) {
          g.catchForTest(1);
          g.steer(math.sin(t * 0.9) * 0.6);
        });
        await capture(tester, key, 'g2b_catch_shower');
        if (!shot) shot = true;
        await settle(tester, const Duration(milliseconds: 2500), each: (t) => g.steer(math.sin(t * 1.1) * 0.8));
        await capture(tester, key, 'g2c_catch_next');
      }
      if (game().phase != GamePhase.results) game().finishForTest();
      await settle(tester, const Duration(milliseconds: 1500));
      await capture(tester, key, lift ? 'g3_lift_results' : 'g3_catch_results');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await settle(tester, const Duration(milliseconds: 1200));
    }
    binding.reportData = <String, dynamic>{...captures};
  });
}
