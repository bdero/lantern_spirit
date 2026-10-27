// A sweep over everything with a friend other than Lumi, plus a bot that
// plays Sky Lift for a while to catch dead ends. Reports PNGs, which
// test_driver/integration_test.dart writes to build/captures/, and the
// bot's altitude in the log.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/sweep_capture_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lantern_spirit/app/profile.dart';
import 'package:lantern_spirit/games/game_host.dart';
import 'package:lantern_spirit/games/sky_lift.dart';
import 'package:lantern_spirit/main.dart';
import 'package:lantern_spirit/show/show_screen.dart';
import 'package:lantern_spirit/ui/park_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final captures = <String, String>{};

  Future<void> settle(WidgetTester tester, Duration d, {void Function()? each}) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      each?.call();
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    await tester.pump();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    captures['$name.png'] = base64Encode(bytes!.buffer.asUint8List());
  }

  testWidgets('sweep', (tester) async {
    final key = GlobalKey();
    final profile = Profile.memory();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LanternSpiritApp(profile: profile)));
    ParkScreenState park() => tester.state<ParkScreenState>(find.byType(ParkScreen));
    await until(tester, () => park().character != null);
    profile.chooseFriend('mochi');
    await until(tester, () => !park().swapping && park().character!.friend.id == 'mochi');
    park().character!.wake();
    await settle(tester, const Duration(milliseconds: 1200));

    // Mochi's errand.
    park().sendLumiForTest();
    for (final (at, name) in const [(2.6, 's_errand_peek'), (5.1, 's_errand_press'), (6.4, 's_errand_home')]) {
      await until(tester, () => park().errandTime >= at);
      await capture(tester, key, name);
    }
    await until(tester, () => !park().errandActive);
    await settle(tester, const Duration(milliseconds: 800));

    // Mochi's room.
    await park().openRoomForTest();
    await settle(tester, const Duration(milliseconds: 1500));
    await capture(tester, key, 's_room');
    park().closeRoomForTest();
    await settle(tester, const Duration(milliseconds: 1300));

    // Juju at the show: the pier, the close-up, the finale.
    profile.chooseFriend('juju');
    await until(tester, () => !park().swapping && park().character!.friend.id == 'juju');
    await settle(tester, const Duration(milliseconds: 800));
    park().openShowForTest();
    await until(tester, () => find.byType(ShowScreen).evaluate().isNotEmpty);
    await settle(tester, const Duration(milliseconds: 3000));
    final show = tester.state<ShowScreenState>(find.byType(ShowScreen));
    for (final (t, name) in const [(8.0, 's_show_break'), (18.0, 's_show_closeup'), (44.0, 's_show_finale')]) {
      show.director!.seek(t);
      await settle(tester, const Duration(milliseconds: 900));
      await capture(tester, key, name);
    }
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester, const Duration(milliseconds: 1500));

    // A bot plays Sky Lift: holds while it has glow, lets go to recharge,
    // and steers toward whatever pickup is above.
    profile.chooseFriend('nova');
    await until(tester, () => !park().swapping && park().character!.friend.id == 'nova');
    park().openGameForTest(true);
    await settle(tester, const Duration(milliseconds: 600));
    GameScreenState game() => tester.state<GameScreenState>(find.byType(GameScreen));
    await until(tester, () => game().phase == GamePhase.playing);
    final g = game().game as SkyLift;
    var holding = true;
    var shots = 0;
    final start = DateTime.now();
    await settle(tester, const Duration(seconds: 40), each: () {
      if (game().phase != GamePhase.playing) return;
      if (holding && g.meter < 0.08) holding = false;
      if (!holding && g.meter > 0.6) holding = true;
      g.thrustForTest = holding;
      g.steer(g.botSteer());
    });
    debugPrint('SKYLIFT BOT: ${g.meters.floor()} m after ${DateTime.now().difference(start).inSeconds}s, phase ${game().phase}');
    await capture(tester, key, 's_lift_bot_${shots++}');

    binding.reportData = <String, dynamic>{...captures};
  });
}
