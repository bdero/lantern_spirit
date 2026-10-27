// The wardrobe sheet opening and closing over the header (Lumi must not
// move), and leaving a game mid-round. Reports PNGs, which
// test_driver/integration_test.dart writes to build/captures/.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/fixes_capture_test.dart \
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
    final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    captures['$name.png'] = base64Encode(bytes!.buffer.asUint8List());
  }

  testWidgets('capture fixes', (tester) async {
    final key = GlobalKey();
    final profile = Profile.memory();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LanternSpiritApp(profile: profile)));
    ParkScreenState park() => tester.state<ParkScreenState>(find.byType(ParkScreen));
    for (var i = 0; i < 400 && park().character == null; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    park().character!.wake();
    await settle(tester, const Duration(milliseconds: 1500));
    await capture(tester, key, 'f0_before');

    await tester.tap(find.byTooltip('Wardrobe'));
    await settle(tester, const Duration(milliseconds: 200));
    await capture(tester, key, 'f1_opening');
    await settle(tester, const Duration(milliseconds: 600));
    await capture(tester, key, 'f2_open');
    profile.wear(hat: 'beanie');
    await settle(tester, const Duration(milliseconds: 800));
    await capture(tester, key, 'f3_beanie');
    await tester.tap(find.byTooltip('Close').last);
    await settle(tester, const Duration(milliseconds: 150));
    await capture(tester, key, 'f4_closing');
    await settle(tester, const Duration(milliseconds: 600));
    await capture(tester, key, 'f5_closed');

    park().openGameForTest(false);
    await settle(tester, const Duration(milliseconds: 1500));
    for (var i = 0; i < 400 && tester.state<GameScreenState>(find.byType(GameScreen)).phase != GamePhase.playing; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    await settle(tester, const Duration(milliseconds: 1000));
    await capture(tester, key, 'f6_playing');
    await tester.tap(find.byTooltip('Pause'));
    await settle(tester, const Duration(milliseconds: 300));
    await capture(tester, key, 'f7_paused');
    await tester.tap(find.text('Leave game'));
    await settle(tester, const Duration(milliseconds: 1300));
    expect(find.byType(GameScreen), findsNothing);
    await capture(tester, key, 'f8_left');

    binding.reportData = <String, dynamic>{...captures};
  });
}
