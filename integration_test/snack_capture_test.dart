// A notification eaten: caught, three bites cut out of the slab with crumbs
// flying, the rest gulped, and a belly rub. Also the fixes around it: the
// spark chase's escape, the snowman appearing, and the start of a peek
// (no leftover particles), and closing the map and a game back onto their
// cards. Reports PNGs, which
// test_driver/integration_test.dart writes to build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/snack_capture_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lantern_spirit/app/profile.dart';
import 'package:lantern_spirit/games/game_host.dart';
import 'package:lantern_spirit/main.dart';
import 'package:lantern_spirit/map/park_map_screen.dart';
import 'package:lantern_spirit/ui/park_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final captures = <String, String>{};

  Future<void> settle(WidgetTester tester, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    await tester.pump();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    captures['$name.png'] = base64Encode(bytes!.buffer.asUint8List());
  }

  Future<void> frames(WidgetTester tester, GlobalKey key, String name, int count, int everyMs) async {
    for (var i = 0; i < count; i++) {
      await settle(tester, Duration(milliseconds: everyMs));
      await capture(tester, key, '${name}_${i.toString().padLeft(2, '0')}');
    }
  }

  testWidgets('capture snack', (tester) async {
    addTearDown(() => binding.reportData = <String, dynamic>{...captures});
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LanternSpiritApp(profile: Profile.memory())));
    ParkScreenState park() => tester.state<ParkScreenState>(find.byType(ParkScreen));
    for (var i = 0; i < 400 && park().character == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    park().autoSurprises = false;
    park().character!.wake();
    await settle(tester, const Duration(milliseconds: 1500));

    // The snack, beat by beat.
    park().eatNotification();
    await frames(tester, key, 'e_snack', 30, 200);
    await settle(tester, const Duration(milliseconds: 1500));

    // The chase, ending in the escape.
    park().startChase();
    await settle(tester, const Duration(milliseconds: 2600));
    await frames(tester, key, 'e_chase', 8, 60);
    await settle(tester, const Duration(milliseconds: 1200));

    // The snowman's first frames.
    park().buildSnowman();
    await frames(tester, key, 'e_snow', 4, 0);
    await settle(tester, const Duration(milliseconds: 3000));

    // Two peeks in a row: the second must start clean.
    park().peekForTest();
    await settle(tester, const Duration(milliseconds: 5800));
    park().peekForTest();
    await frames(tester, key, 'e_peek', 6, 0);
    await settle(tester, const Duration(milliseconds: 5500));

    // Closing the map and a game: the window shrinks back onto its card and
    // dissolves into the card's still.
    park().openMapForTest();
    await settle(tester, const Duration(milliseconds: 4000));
    Navigator.of(tester.element(find.byType(ParkMapScreen))).pop();
    await frames(tester, key, 'e_close_map', 10, 70);
    await settle(tester, const Duration(milliseconds: 800));
    park().openGameForTest(false);
    await settle(tester, const Duration(milliseconds: 3000));
    Navigator.of(tester.element(find.byType(GameScreen))).pop();
    await frames(tester, key, 'e_close_game', 10, 70);
    await settle(tester, const Duration(milliseconds: 800));
  });
}
